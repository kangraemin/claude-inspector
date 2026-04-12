const https = require('node:https');
const { randomUUID } = require('node:crypto');

const MEASUREMENT_ID = process.env.GA4_MEASUREMENT_ID || 'G-Q72NP8CB65';
const API_SECRET     = process.env.GA4_API_SECRET     || 'ZfvhJ6CeTbuUZIfecLo4JA';

let _sessionId = null;

function init() {
  // 세션마다 새 UUID — 파일 저장 없음, 유저 추적 불가
  _sessionId = randomUUID();
}

function trackEvent(eventName, params = {}) {
  if (!MEASUREMENT_ID || !API_SECRET) return;
  const body = JSON.stringify({
    client_id: _sessionId, // 세션 단위 임시 ID, 영구 저장 안 함
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
