import { readFile } from 'node:fs/promises';
import { setTimeout } from 'node:timers/promises';
import { APNsClient } from './push/apns.ts';
import { dispatchOne } from './push/dispatch.ts';
import type { WorkerRPC } from './push/dispatch.ts';

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error('Missing worker configuration.');
  return value;
}

async function main() {
  const base = new URL(required('SUPABASE_URL'));
  if (base.protocol !== 'https:' || !/^[a-z0-9]+\.supabase\.co$/.test(base.hostname) || base.username || base.password) {
    throw new Error('Invalid worker database URL.');
  }
  const secret = (await readFile(required('SUPABASE_SERVICE_KEY_FILE'), 'utf8')).trim();
  if (!secret) throw new Error('Missing worker credentials.');
  const keyID = required('APNS_KEY_ID');
  const teamID = required('APNS_TEAM_ID');
  const topic = required('APNS_TOPIC');
  if (!/^[A-Z0-9]{10}$/.test(keyID) || !/^[A-Z0-9]{10}$/.test(teamID) || !/^[A-Za-z0-9.-]+$/.test(topic)) {
    throw new Error('Invalid APNs configuration.');
  }
  const apns = new APNsClient(await readFile(required('APNS_KEY_FILE'), 'utf8'), keyID, teamID, topic);
  const controller = new AbortController();
  for (const signal of ['SIGINT', 'SIGTERM'] as const) process.once(signal, () => controller.abort());
  const rpc: WorkerRPC = {
    async call<T>(name: string, body: Record<string, unknown> = {}): Promise<T> {
      const response = await fetch(new URL(`/rest/v1/rpc/${name}`, base), {
        method: 'POST', headers: { apikey: secret, Authorization: `Bearer ${secret}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(body), signal: AbortSignal.timeout(10_000),
      });
      if (!response.ok) throw new Error('Worker database request failed.');
      const text = await response.text();
      return (text ? JSON.parse(text) : null) as T;
    },
  };
  try {
    while (!controller.signal.aborted) {
      const worked = await dispatchOne(rpc, apns);
      if (!worked) await setTimeout(2000, undefined, { signal: controller.signal }).catch(() => {});
    }
  } finally { apns.close(); }
}
main().catch(() => {
  // Never log raw errors, tokens, message payloads, keys or request URLs.
  console.error('Push worker stopped. Check credentials, migrations, and service availability.');
  process.exitCode = 1;
});
