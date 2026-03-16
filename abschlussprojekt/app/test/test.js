const {getHealthResponse, getInfoResponse} = require('../server');

let passed = 0;
let failed = 0;

function assert(condition, message) {
    if (condition) {
        console.log(`  PASS: ${message}`);
        passed++;
    } else {
        console.log(`  FAIL: ${message}`);
        failed++;
    }
}

console.log('Running tests...\n');

// Health Response Tests
const health = getHealthResponse();
assert(health.status === 'healthy', 'Health status is "healthy"');
assert(typeof health.timestamp === 'string', 'Health response has timestamp');
assert(health.version !== undefined, 'Health response has version');
assert(health.environment !== undefined, 'Health response has environment');

// Info Response Tests
const info = getInfoResponse();
assert(info.name === 'team-dashboard', 'Info name is "team-dashboard"');
assert(info.version !== undefined, 'Info response has version');
assert(typeof info.uptime === 'number', 'Info response has numeric uptime');

console.log(`\nResults: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
