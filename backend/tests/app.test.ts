import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildApp } from '../src/app.ts';
import { loadConfig } from '../src/config.ts';

const config = loadConfig({ NODE_ENV: 'test', LOG_LEVEL: 'silent' });

test('health is public, uncached, and reports only liveness', async t => {
  const app = buildApp(config);
  t.after(() => app.close());
  const response = await app.inject({ method: 'GET', url: '/v1/health' });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), { status: 'ok' });
  assert.equal(response.headers['cache-control'], 'no-store');
});

test('unimplemented social endpoints cannot accept a poke or disclose profiles', async t => {
  const app = buildApp(config);
  t.after(() => app.close());
  for (const url of ['/v1/pokes', '/v1/me', '/v1/connections']) {
    for (const method of ['GET', 'POST'] as const) {
      const response = await app.inject({ method, url, headers: { authorization: 'Bearer forged-token' } });
      assert.equal(response.statusCode, 404);
      assert.deepEqual(response.json(), { error: { code: 'NOT_FOUND', message: 'Route not found' } });
    }
  }
});

test('internal errors do not disclose implementation details', async t => {
  const app = buildApp(config);
  t.after(() => app.close());
  app.get('/test-error', async () => { throw new Error('secret database credentials'); });
  const response = await app.inject('/test-error');
  assert.equal(response.statusCode, 500);
  assert.deepEqual(response.json(), { error: { code: 'INTERNAL_ERROR', message: 'Something went wrong' } });
});

test('malformed and oversized bodies are rejected without echoing content', async t => {
  const app = buildApp(config);
  t.after(() => app.close());
  app.post('/test-body', async () => ({ ok: true }));
  for (const [payload, status] of [['{"secret":', 400], [JSON.stringify({ secret: 'x'.repeat(17_000) }), 413]] as const) {
    const response = await app.inject({ method: 'POST', url: '/test-body', headers: { 'content-type': 'application/json' }, payload });
    assert.equal(response.statusCode, status);
    assert.deepEqual(response.json(), { error: { code: 'INVALID_REQUEST', message: 'Invalid request' } });
  }
});
