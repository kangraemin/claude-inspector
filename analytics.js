const https = require('node:https');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');

const MEASUREMENT_ID = process.env.GA4_MEASUREMENT_ID || 'G-Q72NP8CB65';
const API_SECRET     = process.env.GA4_API_SECRET     || 'ZfvhJ6CeTbuUZIfecLo4JA';

let _clientId = null;
let _userDataPath = '';
let _sessionId = null;

function init(userDataPath) {
  _userDataPath = userDataPath;
  _sessionId = Date.now().toString();
}

function getClientId() {
  if (_clientId) return _clientId;
  const file = path.join(_userDataPath, 'analytics.json');
  try {
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (data.clientId) { _clientId = data.clientId; return _clientId; }
  } catch {}
  _clientId = randomUUID();
  try { fs.writeFileSync(file, JSON.stringify({ clientId: _clientId })); } catch {}
  return _clientId;
}

function trackEvent(eventName, params = {}) {
  if (!MEASUREMENT_ID || !API_SECRET) return;
  const body = JSON.stringify({
    client_id: getClientId(),
    events: [{ name: eventName, params: { ...params, session_id: _sessionId, engagement_time_msec: 100, app_version: require('./package.json').version } }],
  });
  const req = https.request({
    hostname: 'www.google-analytics.com',
    path: `/mp/collect?measurement_id=${MEASUREMENT_ID}&api_secret=${API_SECRET}`,
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
  });
  req.on('error', () => {}); // silent fail
  req.write(body);
  req.end();
}

module.exports = { init, trackEvent };
