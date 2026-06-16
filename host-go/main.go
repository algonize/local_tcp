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
	"net"
	"os"
	"strings"
	"sync"
	"time"
)

const version = "2.0.0"

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

// dialWithRetry opens a TCP connection, retrying transient failures.
// Wi-Fi network printers sleep their radio to save power; the first connect
// then fails with "no route to host" / "connection timed out" because ARP
// can't resolve the (asleep) device yet. A short retry wakes it and succeeds,
// so users never see a spurious failure on the first print after idle.
func dialWithRetry(addr string, timeout time.Duration) (net.Conn, error) {
	const maxAttempts = 3
	var err error
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		var c net.Conn
		c, err = net.DialTimeout("tcp", addr, timeout)
		if err == nil {
			return c, nil
		}
		if attempt < maxAttempts && isTransientDialErr(err) {
			time.Sleep(time.Duration(attempt) * 300 * time.Millisecond)
			continue
		}
		break
	}
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

	switch req.Action {

	case "PING":
		sendMessage(Response{ReqID: req.ReqID, Success: true, Message: "Pong", Version: version})

	case "CONNECT":
		id := connID(req)
		lock := lockFor(id)
		lock.Lock()
		defer lock.Unlock()

		addr := fmt.Sprintf("%s:%d", req.Host, req.Port)
		c, err := dialWithRetry(addr, dialTimeout(req))
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
			nc, err := dialWithRetry(addr, dialTimeout(req))
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
	defer func() {
		if r := recover(); r != nil {
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
