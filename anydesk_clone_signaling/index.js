const http = require('http');
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

const PORT = 8080;
const STATIC_DIR = path.join(__dirname, '..', 'anydesk_clone', 'build', 'web');

// Mime types for serving static files
const MIME_TYPES = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.wasm': 'application/wasm',
};

// Create HTTP server that serves static files
const server = http.createServer((req, res) => {
  let filePath = path.join(STATIC_DIR, req.url === '/' ? 'index.html' : req.url);
  
  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, data) => {
    if (err) {
      // Fallback to index.html for SPA routing
      fs.readFile(path.join(STATIC_DIR, 'index.html'), (err2, data2) => {
        if (err2) {
          res.writeHead(404);
          res.end('Not Found');
          return;
        }
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(data2);
      });
      return;
    }
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(data);
  });
});

// Attach WebSocket server to the same HTTP server
const wss = new WebSocket.Server({ server });

// Map of connectionId -> WebSocket
const clients = new Map();

wss.on('connection', (ws) => {
  let currentId = null;

  ws.on('message', (messageAsString) => {
    let message;
    try {
      message = JSON.parse(messageAsString);
    } catch (e) {
      console.error('Invalid JSON:', messageAsString);
      return;
    }

    switch (message.type) {
      case 'register':
        currentId = message.id;
        clients.set(currentId, ws);
        console.log(`Client registered: ${currentId}`);
        break;

      case 'offer':
      case 'answer':
      case 'candidate':
      case 'end':
        const targetWs = clients.get(message.target);
        if (targetWs && targetWs.readyState === WebSocket.OPEN) {
          console.log(`Forwarding ${message.type} from ${currentId} to ${message.target}`);
          targetWs.send(JSON.stringify({
            type: message.type,
            sender: currentId,
            data: message.data
          }));
        } else {
          console.log(`Target ${message.target} not found or disconnected`);
          ws.send(JSON.stringify({
            type: 'error',
            message: 'Target device not found or offline.'
          }));
        }
        break;

      default:
        console.warn('Unknown message type:', message.type);
    }
  });

  ws.on('close', () => {
    if (currentId) {
      clients.delete(currentId);
      console.log(`Client disconnected: ${currentId}`);
    }
  });
});

server.listen(PORT, () => {
  console.log(`Combined server (HTTP + WebSocket) listening on port ${PORT}`);
  console.log(`Serving Flutter web build from: ${STATIC_DIR}`);
});
