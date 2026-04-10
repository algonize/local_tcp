#!/usr/bin/env node

/**
 * Local TCP - Native Messaging Host
 * Handles raw TCP socket communication for Chrome Extensions
 */

const net = require('net');
const fs = require('fs');

const connections = {}; // id -> Socket

// ─── Native Messaging Protocol Helpers ────────────────────────────────────────

function sendMessage(msg) {
    const buffer = Buffer.from(JSON.stringify(msg));
    const header = Buffer.alloc(4);
    header.writeUInt32LE(buffer.length, 0);
    process.stdout.write(header);
    process.stdout.write(buffer);
}

// ─── Input Handling ──────────────────────────────────────────────────────────

let inputBuffer = Buffer.alloc(0);

process.stdin.on('data', (data) => {
    inputBuffer = Buffer.concat([inputBuffer, data]);
    handleInput();
});

function handleInput() {
    while (inputBuffer.length >= 4) {
        const msgLen = inputBuffer.readUInt32LE(0);
        if (inputBuffer.length >= 4 + msgLen) {
            const content = inputBuffer.slice(4, 4 + msgLen);
            inputBuffer = inputBuffer.slice(4 + msgLen);
            try {
                const message = JSON.parse(content.toString());
                handleMessage(message);
            } catch (err) {
                sendMessage({ success: false, error: 'JSON parse error: ' + err.message });
            }
        } else {
            break;
        }
    }
}

// ─── Business Logic ───────────────────────────────────────────────────────────

async function handleMessage(msg) {
    const { action, host, port, data, connectionId } = msg;

    switch (action) {
        case 'CONNECT': {
            const id = connectionId || `${host}:${port}`;
            
            if (connections[id]) {
                connections[id].destroy();
                delete connections[id];
            }

            const client = new net.Socket();
            client.connect(port, host, () => {
                connections[id] = client;
                sendMessage({ success: true, message: `Connected to ${host}:${port}`, connectionId: id });
            });

            client.on('error', (err) => {
                sendMessage({ success: false, error: `Socket error: ${err.message}`, connectionId: id });
                delete connections[id];
            });

            client.on('close', () => {
                delete connections[id];
            });
            break;
        }

        case 'SEND':
        case 'PRINT': {
            const id = connectionId || `${host}:${port}`;
            let client = connections[id];

            if (!client) {
                // Auto-connect attempt
                client = new net.Socket();
                client.connect(port, host, () => {
                    connections[id] = client;
                    proceedWithSend(client, data);
                });
                client.on('error', (err) => {
                    sendMessage({ success: false, error: `Socket connect failed: ${err.message}` });
                });
            } else {
                proceedWithSend(client, data);
            }
            break;
        }

        case 'DISCONNECT': {
            const id = connectionId || `${host}:${port}`;
            if (connections[id]) {
                connections[id].destroy();
                delete connections[id];
                sendMessage({ success: true, message: 'Disconnected' });
            } else {
                sendMessage({ success: true, message: 'No connection to disconnect' });
            }
            break;
        }

        case 'PING': {
            sendMessage({ success: true, message: 'Pong', version: '1.0.0' });
            break;
        }

        default:
            sendMessage({ success: false, error: 'Unknown action: ' + action });
    }
}

function proceedWithSend(client, data) {
    if (!data || !Array.isArray(data)) {
        return sendMessage({ success: false, error: 'Invalid data format' });
    }
    
    const buffer = Buffer.from(data);
    client.write(buffer, (err) => {
        if (err) {
            sendMessage({ success: false, error: 'Write failed: ' + err.message });
        } else {
            sendMessage({ success: true, bytesSent: buffer.length });
        }
    });
}

// Error handling to prevent host from crashing
process.on('uncaughtException', (err) => {
    sendMessage({ success: false, error: 'Uncaught Exception: ' + err.message });
});
