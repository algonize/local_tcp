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
	"sync"
	"time"
)

const version = "2.0.0"

// ─── Message Types ───────────────────────────────────────────────────────────

type Request struct {
	ReqID        string  `json:"reqId,omitempty"`
	Action       string  `json:"action"`
	Host         string  `json:"host,omitempty"`
	Port         int     `json:"port,omitempty"`
	Data         []byte  `json:"-"` // populated from rawData
	RawData      []int   `json:"data,omitempty"`
	ConnectionID string  `json:"connectionId,omitempty"`
	TimeoutMs    int     `json:"timeoutMs,omitempty"`
}

type Response struct {
	ReqID        string `json:"reqId,omitempty"`
	Success      bool   `json:"success"`
	Message      string `json:"message,omitempty"`
	Error        string `json:"error,omitempty"`
	ConnectionID string `json:"connectionId,omitempty"`
	BytesSent    int    `json:"bytesSent,omitempty"`
	Version      string `json:"version,omitempty"`
}

// ─── Connection Pool ─────────────────────────────────────────────────────────

var (
	connMu      sync.Mutex
	connections = map[string]net.Conn{}
	stdoutMu    sync.Mutex
)

func getConn(id string) net.Conn {
	connMu.Lock()
	defer connMu.Unlock()
	return connections[id]
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

func handle(req *Request) {
	switch req.Action {

	case "PING":
		sendMessage(Response{ReqID: req.ReqID, Success: true, Message: "Pong", Version: version})

	case "CONNECT":
		id := connID(req)
		addr := fmt.Sprintf("%s:%d", req.Host, req.Port)
		c, err := net.DialTimeout("tcp", addr, dialTimeout(req))
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
		c := getConn(id)
		if c == nil {
			addr := fmt.Sprintf("%s:%d", req.Host, req.Port)
			nc, err := net.DialTimeout("tcp", addr, dialTimeout(req))
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
		sendMessage(Response{ReqID: req.ReqID, Success: true, BytesSent: n})

	case "DISCONNECT":
		id := connID(req)
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
