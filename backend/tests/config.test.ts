import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadConfig } from '../src/config.ts';

test('defaults bind only to loopback', () => {
  assert.deepEqual(loadConfig({}), { nodeEnv: 'development', host: '127.0.0.1', port: 3000, logLevel: 'info' });
});

test('deployment configuration is explicit', () => {
  assert.deepEqual(loadConfig({ NODE_ENV: 'production', HOST: '0.0.0.0', PORT: '8080', LOG_LEVEL: 'warn' }),
    { nodeEnv: 'production', host: '0.0.0.0', port: 8080, logLevel: 'warn' });
  assert.equal(loadConfig({ HOST: '::1' }).host, '::1');
});

for (const port of ['', '0', '-1', '65536', '3.5', '3000junk', '1e3', ' 3000']) {
  test(`reject invalid port ${JSON.stringify(port)}`, () => {
    assert.throws(() => loadConfig({ PORT: port }), /Invalid PORT/);
  });
}

for (const key of ['NODE_ENV', 'HOST', 'LOG_LEVEL']) {
  test(`reject invalid ${key} without disclosing its value`, () => {
    assert.throws(() => loadConfig({ [key]: 'secret-value' }), (error: unknown) => {
      assert.ok(error instanceof Error);
      assert.ok(error.message.includes(key));
      assert.ok(!error.message.includes('secret-value'));
      return true;
    });
  });
}
