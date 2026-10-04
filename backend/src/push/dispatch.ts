import { classify } from './apns.ts';
import type { APNsResponse, PushPayload } from './apns.ts';

export interface WorkerRPC { call<T>(name: string, body?: Record<string, unknown>): Promise<T> }
export interface Transport { send(payload: PushPayload): Promise<APNsResponse> }
export async function dispatchOne(rpc: WorkerRPC, apns: Transport, now = Date.now): Promise<boolean> {
  const claim = await rpc.call<{ id: string; lease_id: string } | null>('poki_claim_push');
  if (!claim) return false;
  const identity = { delivery_id: claim.id, claim_id: claim.lease_id };
  const payload = await rpc.call<PushPayload | null>('poki_push_payload', identity);
  if (!payload) return true;
  if (payload.expires_at * 1000 <= now()) {
    await rpc.call('poki_finish_push', { ...identity, outcome: 'drop' });
    return true;
  }
  const sentAt = now();
  let response: APNsResponse;
  try { response = await apns.send(payload); }
  catch {
    await rpc.call('poki_finish_push', { ...identity, outcome: 'retry' });
    return true;
  }
  const result = classify(response);
  await rpc.call('poki_finish_push', {
    ...identity, outcome: result.outcome,
    invalidated_at: result.outcome === 'invalid' ? result.invalidatedAt ?? sentAt : null,
  });
  return true;
}
