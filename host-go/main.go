// Local TCP Bridge — Native Messaging Host (Go)
// Drop-in replacement for the Node.js host. Compiles to a single static
// binary, so end users do NOT need Node.js installed.
//
// Protocol: Chrome Native Messaging (4-byte little-endian length prefix + JSON)
// Actions:  PING | CONNECT | SEND | PRINT | DISCONNECT
// Every response echoes back the `reqId` sent by the extension so the
// background script can correlate concurrent requests safely.

package main

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

// version is injected at build time from manifest.json via:
//   -ldflags "-X main.version=<v>"
// The fallback below is only used for ad-hoc `go run` / `go build` without flags.
var version = "0.0.0-dev"

// ─── Diagnostic Logging ──────────────────────────────────────────────────────
//
// The host speaks only over Chrome's native-messaging pipe, so when it hangs in
// net.DialTimeout it is otherwise a black box. This appends a timestamped trace
// to a log file so a single failing print tells us EXACTLY what happened: which
// address was dialed, whether the dial returned instantly or hung the full
// timeout, and whether ping-wake fired. The path is reported in PING responses
// (see logPath) so the user can find it. Logging never affects the protocol;
// any file error is silently ignored and the host runs normally.
var (
	dbg     *log.Logger
	dbgPath string
)

func initLog() {
	// os.TempDir() is always writable and does NOT depend on the inherited PATH
	// (Chrome spawns hosts with a minimal environment), so the log always lands.
	dbgPath = filepath.Join(os.TempDir(), "localtcp-host.log")
	f, err := os.OpenFile(dbgPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return // logging is best-effort; never block the host on it
	}
	dbg = log.New(f, "", log.LstdFlags|log.Lmicroseconds)
	dbg.Printf("──── host start  version=%s  pid=%d  os=%s ────", version, os.Getpid(), runtime.GOOS)
}

// logf is a safe no-op if the log file could not be opened. log.Logger is
// goroutine-safe, so concurrent request handlers can call this freely.
func logf(format string, a ...interface{}) {
	if dbg != nil {
		dbg.Printf(format, a...)
	}
}

// ─── Message Types ───────────────────────────────────────────────────────────

type Request struct {
	ReqID         string `json:"reqId,omitempty"`
	Action        string `json:"action"`
	Host          string `json:"host,omitempty"`
	Port          int    `json:"port,omitempty"`
	Data          []byte `json:"-"` // populated from rawData
	RawData       []int  `json:"data,omitempty"`
	ConnectionID  string `json:"connectionId,omitempty"`
	TimeoutMs     int    `json:"timeoutMs,omitempty"`
	ReadTimeoutMs int    `json:"readTimeoutMs,omitempty"` // >0 → read back a reply after writing
}

type Response struct {
	ReqID        string `json:"reqId,omitempty"`
	Success      bool   `json:"success"`
	Message      string `json:"message,omitempty"`
	Error        string `json:"error,omitempty"`
	ConnectionID string `json:"connectionId,omitempty"`
	BytesSent    int    `json:"bytesSent,omitempty"`
	Data         []int  `json:"data,omitempty"` // bytes read back from the device (status replies, etc.)
	Version      string `json:"version,omitempty"`
}

// ─── Connection Pool ─────────────────────────────────────────────────────────

var (
	connMu      sync.Mutex
	connections = map[string]net.Conn{}
	connLocks   = map[string]*sync.Mutex{} // per-connection write lock (prevents byte-stream interleaving)
	stdoutMu    sync.Mutex
)

func getConn(id string) net.Conn {
	connMu.Lock()
	defer connMu.Unlock()
	return connections[id]
}

// lockFor returns a stable per-connection mutex so all CONNECT/SEND/PRINT/DISCONNECT
// operations on the same device are serialized. Without this, two concurrent print
// jobs to the same socket could interleave their ESC/POS byte streams and corrupt output.
func lockFor(id string) *sync.Mutex {
	connMu.Lock()
	defer connMu.Unlock()
	l, ok := connLocks[id]
	if !ok {
		l = &sync.Mutex{}
		connLocks[id] = l
	}
	return l
}

func setConn(id string, c net.Conn) {
	connMu.Lock()
	defer connMu.Unlock()
	if old, ok := connections[id]; ok {
		old.Close()
	}
	connections[id] = c
}

func dropConn(id string) {
	connMu.Lock()
	defer connMu.Unlock()
	if c, ok := connections[id]; ok {
		c.Close()
		delete(connections, id)
	}
}

// ─── Native Messaging I/O ────────────────────────────────────────────────────

func sendMessage(r Response) {
	payload, err := json.Marshal(r)
	if err != nil {
		return
	}
	header := make([]byte, 4)
	binary.LittleEndian.PutUint32(header, uint32(len(payload)))
	stdoutMu.Lock()
	defer stdoutMu.Unlock()
	os.Stdout.Write(header)
	os.Stdout.Write(payload)
}

func readMessage(r io.Reader) (*Request, error) {
	header := make([]byte, 4)
	if _, err := io.ReadFull(r, header); err != nil {
		return nil, err
	}
	length := binary.LittleEndian.Uint32(header)
	if length == 0 || length > 64*1024*1024 {
		return nil, fmt.Errorf("invalid message length: %d", length)
	}
	body := make([]byte, length)
	if _, err := io.ReadFull(r, body); err != nil {
		return nil, err
	}
	var req Request
	if err := json.Unmarshal(body, &req); err != nil {
		return nil, fmt.Errorf("JSON parse error: %v", err)
	}
	// Convert []int (JSON numbers) into raw bytes
	if len(req.RawData) > 0 {
		req.Data = make([]byte, len(req.RawData))
		for i, v := range req.RawData {
			req.Data[i] = byte(v & 0xFF)
		}
	}
	return &req, nil
}

// ─── Business Logic ──────────────────────────────────────────────────────────

func connID(req *Request) string {
	if req.ConnectionID != "" {
		return req.ConnectionID
	}
	return fmt.Sprintf("%s:%d", req.Host, req.Port)
}

func dialTimeout(req *Request) time.Duration {
	if req.TimeoutMs > 0 {
		return time.Duration(req.TimeoutMs) * time.Millisecond
	}
	return 5 * time.Second
}

// wakePrinter best-effort sends a couple of ICMP echoes to coax a deep-sleeping
// Wi-Fi printer's radio awake. This is the step that actually rouses it: a bare
// TCP connect often won't — after the first miss macOS caches a *negative* ARP
// entry and stops broadcasting ARP, so the printer never sees any traffic — but
// an ICMP ping forces a fresh ARP resolution and the device wakes, exactly as it
// does when you ping it by hand. Errors are ignored; it's only a nudge before we
// (re)try the real TCP connect. Blocks up to ~2s when the printer is asleep.
func wakePrinter(host string) {
	// Send a small burst (3 echoes) rather than a single packet: a deeply-asleep
	// radio may miss the first ARP/echo, and a 3-packet ping is exactly what was
	// observed to reliably wake this class of printer by hand.
	var args []string
	switch runtime.GOOS {
	case "windows":
		args = []string{"-n", "3", "-w", "1000", host}
	case "darwin":
		args = []string{"-c", "3", "-t", "3", host} // -t: overall timeout (seconds)
	default: // linux & others
		args = []string{"-c", "3", "-W", "2", host} // -W: per-reply timeout (seconds)
	}
	_ = exec.Command(pingPath(), args...).Run()
}

// pingPath resolves an ABSOLUTE path to the system ping binary. This is critical:
// Chrome spawns native messaging hosts with a minimal PATH (typically without
// /sbin), so a bare exec.Command("ping") fails with "executable file not found"
// — the wake silently never fires and a sleeping printer stays unreachable. By
// resolving the absolute path we don't depend on the inherited PATH at all.
func pingPath() string {
	if runtime.GOOS == "windows" {
		if sysRoot := os.Getenv("SystemRoot"); sysRoot != "" {
			return sysRoot + `\System32\PING.EXE`
		}
		return "ping"
	}
	for _, p := range []string{"/sbin/ping", "/bin/ping", "/usr/bin/ping", "/usr/sbin/ping"} {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return "ping" // last resort — rely on PATH
}

// dialWithRetry opens a TCP connection, waking a deep-sleeping Wi-Fi printer
// first if necessary.
//
// Wi-Fi network printers deep-sleep their radio to save power; the ARP entry
// expires, so the first connect returns EHOSTUNREACH ("no route to host")
// *instantly* and — crucially — repeated TCP connects do NOT wake the device
// (macOS caches a negative ARP entry and stops broadcasting). The old Node host
// appeared to work via its long timeout-less connect, but for radios this deep
// only an ICMP ping reliably wakes them. So: try once (fast path for an awake
// printer), and on a transient miss, ping-to-wake then retry the connect, until
// the wake budget — kept under the extension's REQUEST_TIMEOUT_MS — runs out.
func dialWithRetry(host, addr string, timeout time.Duration) (net.Conn, error) {
	const wakeBudget = 28 * time.Second // total budget — stays under the extension's 30s request timeout
	const maxAttemptTimeout = 4 * time.Second // cap EACH dial attempt so the host always returns a real error before the extension's 30s fires
	if timeout <= 0 {
		timeout = 5 * time.Second
	}
	// CRITICAL: never let a single dial attempt consume the whole request window.
	// If the caller passes timeoutMs=30000, an unreachable printer would block the
	// first dial for the full 30s — exactly the extension's timeout — so the
	// extension reports the opaque "Bridge timeout: no response" while the host is
	// still stuck in that first dial and never sends its real "no route to host"
	// error. Capping per-attempt guarantees the host answers first, with a useful
	// message, and still gets multiple wake+retry passes within the budget.
	if timeout > maxAttemptTimeout {
		timeout = maxAttemptTimeout
	}
	deadline := time.Now().Add(wakeBudget)
	logf("dial START addr=%s perAttemptTimeout=%s wakeBudget=%s", addr, timeout, wakeBudget)

	// Fast path: an awake printer connects immediately.
	t0 := time.Now()
	c, err := net.DialTimeout("tcp", addr, timeout)
	if err == nil {
		logf("dial OK addr=%s via=fast-path took=%s", addr, time.Since(t0))
		return c, nil
	}
	logf("dial MISS addr=%s via=fast-path took=%s transient=%v err=%v", addr, time.Since(t0), isTransientDialErr(err), err)
	if !isTransientDialErr(err) {
		return nil, err // hard error (e.g. connection refused) — fail fast
	}

	// Slow path: printer is likely asleep. Ping to wake its radio, then retry
	// the connect; each ping forces a fresh ARP so the device keeps getting
	// nudged until it answers or we exhaust the budget.
	for attempt := 1; time.Now().Before(deadline); attempt++ {
		wt := time.Now()
		wakePrinter(host)
		dt := time.Now()
		c, err = net.DialTimeout("tcp", addr, timeout)
		if err == nil {
			logf("dial OK addr=%s via=wake-retry attempt=%d wake=%s dial=%s", addr, attempt, dt.Sub(wt), time.Since(dt))
			return c, nil
		}
		logf("dial MISS addr=%s via=wake-retry attempt=%d wake=%s dial=%s transient=%v err=%v", addr, attempt, dt.Sub(wt), time.Since(dt), isTransientDialErr(err), err)
		if !isTransientDialErr(err) {
			return nil, err
		}
	}
	logf("dial GIVE-UP addr=%s totalElapsed=%s lastErr=%v", addr, time.Since(t0), err)
	return nil, err
}

// isTransientDialErr reports whether a dial error is the kind that typically
// clears on retry (host asleep / not yet ARP-resolved / momentary timeout)
// rather than a hard config error like connection refused.
func isTransientDialErr(err error) bool {
	if ne, ok := err.(net.Error); ok && ne.Timeout() {
		return true
	}
	msg := err.Error()
	return strings.Contains(msg, "no route to host") ||
		strings.Contains(msg, "host is down") ||
		strings.Contains(msg, "network is unreachable")
}

func handle(req *Request) {
	// A panic here must never take down the whole host (it would drop every
	// connection and kill in-flight jobs). Recover per-request and report it.
	defer func() {
		if r := recover(); r != nil {
			sendMessage(Response{ReqID: req.ReqID, Success: false, Error: fmt.Sprintf("Host error: %v", r)})
		}
	}()

	logf("REQ action=%s host=%s port=%d connId=%s reqId=%s", req.Action, req.Host, req.Port, req.ConnectionID, req.ReqID)

	switch req.Action {

	case "PING":
		// Report the diagnostic log path so the user can find the trace file.
		sendMessage(Response{ReqID: req.ReqID, Success: true, Message: "Pong; log=" + dbgPath, Version: version})

	case "CONNECT":
		id := connID(req)
		lock := lockFor(id)
		lock.Lock()
		defer lock.Unlock()

		addr := fmt.Sprintf("%s:%d", req.Host, req.Port)
		c, err := dialWithRetry(req.Host, addr, dialTimeout(req))
		if err != nil {
			sendMessage(Response{ReqID: req.ReqID, Success: false, Error: "Socket error: " + err.Error(), ConnectionID: id})
			return
		}
		setConn(id, c)
		sendMessage(Response{ReqID: req.ReqID, Success: true, Message: "Connected to " + addr, ConnectionID: id})

	case "SEND", "PRINT":
		id := connID(req)
		if req.Data == nil {
			sendMessage(Response{ReqID: req.ReqID, Success: false, Error: "Invalid data format"})
			return
		}

		// Serialize all writes to this device so concurrent jobs can't interleave bytes.
		lock := lockFor(id)
		lock.Lock()
		defer lock.Unlock()

		c := getConn(id)
		if c == nil {
			addr := fmt.Sprintf("%s:%d", req.Host, req.Port)
			nc, err := dialWithRetry(req.Host, addr, dialTimeout(req))
			if err != nil {
				sendMessage(Response{ReqID: req.ReqID, Success: false, Error: "Socket connect failed: " + err.Error()})
				return
			}
			setConn(id, nc)
			c = nc
		}
		c.SetWriteDeadline(time.Now().Add(10 * time.Second))
		n, err := c.Write(req.Data)
		if err != nil {
			dropConn(id) // stale socket — drop so next attempt re-dials
			sendMessage(Response{ReqID: req.ReqID, Success: false, Error: "Write failed: " + err.Error()})
			return
		}

		resp := Response{ReqID: req.ReqID, Success: true, BytesSent: n, ConnectionID: id}

		// Optional read-back: ESC/POS status queries (e.g. DLE EOT) reply with bytes.
		// When the caller asks for it, wait briefly for a response and return it.
		if req.ReadTimeoutMs > 0 {
			c.SetReadDeadline(time.Now().Add(time.Duration(req.ReadTimeoutMs) * time.Millisecond))
			buf := make([]byte, 512)
			rn, rerr := c.Read(buf)
			if rn > 0 {
				resp.Data = make([]int, rn)
				for i := 0; i < rn; i++ {
					resp.Data[i] = int(buf[i])
				}
			}
			// A timeout with no data is NOT a failure — many devices stay silent.
			if rerr != nil && rn == 0 {
				if ne, ok := rerr.(net.Error); ok && ne.Timeout() {
					resp.Message = "Written; no status reply within readTimeoutMs"
				} else {
					// A non-timeout read error means the socket is bad — drop it.
					dropConn(id)
					resp.Message = "Written; read failed: " + rerr.Error()
				}
			}
		}
		sendMessage(resp)

	case "DISCONNECT":
		id := connID(req)
		lock := lockFor(id)
		lock.Lock()
		defer lock.Unlock()

		if getConn(id) != nil {
			dropConn(id)
			sendMessage(Response{ReqID: req.ReqID, Success: true, Message: "Disconnected"})
		} else {
			sendMessage(Response{ReqID: req.ReqID, Success: true, Message: "No connection to disconnect"})
		}

	default:
		sendMessage(Response{ReqID: req.ReqID, Success: false, Error: "Unknown action: " + req.Action})
	}
}

// ─── Main Loop ───────────────────────────────────────────────────────────────

func main() {
	initLog()
	defer func() {
		if r := recover(); r != nil {
			logf("FATAL host panic: %v", r)
			sendMessage(Response{Success: false, Error: fmt.Sprintf("Host panic: %v", r)})
		}
	}()

	for {
		req, err := readMessage(os.Stdin)
		if err != nil {
			if err == io.EOF || err == io.ErrUnexpectedEOF {
				return // Chrome closed the port — exit cleanly
			}
			sendMessage(Response{Success: false, Error: err.Error()})
			continue
		}
		// Handle each request in its own goroutine so a slow printer
		// never blocks PING/health checks or other connections.
		go handle(req)
	}
}
