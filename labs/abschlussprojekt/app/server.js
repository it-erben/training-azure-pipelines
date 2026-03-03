const http = require('http');
const fs = require('fs');
const path = require('path');

const port = process.env.PORT || 8080;

// --- Hilfsfunktionen (exportiert für Unit Tests) ---

function getHealthResponse() {
    return {
        status: 'healthy',
        version: process.env.APP_VERSION || 'local',
        environment: process.env.ENVIRONMENT || 'development',
        timestamp: new Date().toISOString()
    };
}

function getInfoResponse() {
    return {
        name: 'team-dashboard',
        version: process.env.APP_VERSION || 'local',
        uptime: process.uptime()
    };
}

// --- HTTP-Server ---

const server = http.createServer((req, res) => {
    if (req.url === '/health') {
        res.writeHead(200, {'Content-Type': 'application/json'});
        res.end(JSON.stringify(getHealthResponse()));
        return;
    }

    if (req.url === '/api/info') {
        res.writeHead(200, {'Content-Type': 'application/json'});
        res.end(JSON.stringify(getInfoResponse()));
        return;
    }

    if (req.url === '/style.css') {
        const cssPath = path.join(__dirname, 'public', 'style.css');
        if (fs.existsSync(cssPath)) {
            res.writeHead(200, {'Content-Type': 'text/css'});
            res.end(fs.readFileSync(cssPath));
        } else {
            res.writeHead(404);
            res.end('Not found');
        }
        return;
    }

    // Default: index.html
    const indexPath = path.join(__dirname, 'public', 'index.html');
    if (fs.existsSync(indexPath)) {
        res.writeHead(200, {'Content-Type': 'text/html'});
        res.end(fs.readFileSync(indexPath));
    } else {
        res.writeHead(200, {'Content-Type': 'text/html'});
        res.end('<h1>Team Status Dashboard</h1>');
    }
});

// Server nur starten, wenn direkt ausgeführt (nicht bei require in Tests)
if (require.main === module) {
    server.listen(port, () => {
        console.log(`Server running`);
    });
}

module.exports = {getHealthResponse, getInfoResponse, server};
