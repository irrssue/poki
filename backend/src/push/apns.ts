import { createPrivateKey, sign } from 'node:crypto';
import { connect } from 'node:http2';
import type { ClientHttp2Session } from 'node:http2';

export interface PushPayload {
  id: string;
  token: string;
  environment: 'sandbox' | 'production';
  recipient_id: string;
  sender_id: string;
  sender_name: string;
  message: string;
  expires_at: number;
  attempts: number;
}
export interface APNsResponse { status: number; reason?: string; timestamp?: number }
export interface DeliveryResult { outcome: 'sent' | 'retry' | 'drop' | 'invalid'; invalidatedAt?: number }
export function classify(response: APNsResponse): DeliveryResult {
  if (response.status === 200) return { outcome: 'sent' };
  if (response.status === 410 && Number.isFinite(response.timestamp)) {
    return { outcome: 'invalid', invalidatedAt: response.timestamp! };
  }
  if (response.status === 400 && ['BadDeviceToken', 'DeviceTokenNotForTopic'].includes(response.reason ?? '')) {
    return { outcome: 'invalid' };
  }
  if ([429, 500, 503].includes(response.status)) return { outcome: 'retry' };
  // Authentication/configuration errors must stop dispatch, not drain the queue.
  if (response.status === 403 || response.reason === 'BadTopic' || response.reason === 'TopicDisallowed') {
    throw new Error('APNs configuration rejected. Check the worker credentials and topic.');
  }
  return { outcome: 'drop' };
}

export function notificationBody(payload: PushPayload) {
  return JSON.stringify({
    aps: { alert: { title: `${payload.sender_name} poked you`, body: payload.message }, sound: 'default' },
    recipient_id: payload.recipient_id, sender_id: payload.sender_id,
  });
}

export function providerToken(privateKey: string, keyID: string, teamID: string, now: number): string {
  const key = createPrivateKey(privateKey);
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
    throw new Error('APNs requires a P-256 signing key.');
  }
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: keyID })).toString('base64url');
  const body = Buffer.from(JSON.stringify({ iss: teamID, iat: Math.floor(now / 1000) })).toString('base64url');
  const signature = sign('sha256', Buffer.from(`${header}.${body}`), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  return `${header}.${body}.${signature}`;
}

export class APNsClient {
  private connections = new Map<string, ClientHttp2Session>();
  private jwt: string;
  private issuedAt = Date.now();
  constructor(private readonly key: string, private readonly keyID: string, private readonly teamID: string, private readonly topic: string) {
    this.jwt = providerToken(key, keyID, teamID, this.issuedAt);
  }
  async send(payload: PushPayload): Promise<APNsResponse> {
    if (Date.now() - this.issuedAt > 50 * 60_000) {
      this.issuedAt = Date.now();
      this.jwt = providerToken(this.key, this.keyID, this.teamID, this.issuedAt);
    }
    const host = payload.environment === 'sandbox' ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com';
    let session = this.connections.get(host);
    if (!session || session.closed || session.destroyed) {
      session = connect(host);
      session.on('error', () => { session?.destroy(); });
      session.on('goaway', () => { session?.close(); });
      this.connections.set(host, session);
    }
    const connection = session;
    return await new Promise<APNsResponse>((resolve, reject) => {
      let settled = false;
      const stream = connection.request({
        ':method': 'POST', ':path': `/3/device/${payload.token}`,
        authorization: `bearer ${this.jwt}`, 'apns-topic': this.topic,
        'apns-push-type': 'alert', 'apns-priority': '10',
        // Do not store an old poke at APNs while a recipient is offline.
        'apns-expiration': '0', 'apns-id': payload.id, 'apns-collapse-id': payload.id,
      });
      const fail = () => {
        if (settled) return;
        settled = true; clearTimeout(timer); stream.close(); reject(new Error('APNs transport unavailable.'));
      };
      const timer = setTimeout(fail, 10_000);
      let status = 0;
      let body = '';
      stream.setEncoding('utf8');
      stream.on('response', headers => { status = Number(headers[':status']); });
      stream.on('data', (chunk: string) => { body += chunk; if (body.length > 4096) fail(); });
      stream.on('error', fail);
      stream.on('close', () => { if (!settled) fail(); });
      stream.on('end', () => {
        if (settled) return;
        settled = true; clearTimeout(timer);
        let detail: { reason?: string; timestamp?: number } = {};
        try { detail = JSON.parse(body || '{}') as typeof detail; } catch { /* status remains authoritative */ }
        resolve({ status, ...detail });
      });
      stream.end(notificationBody(payload));
    });
  }
  close() { for (const session of this.connections.values()) session.destroy(); }
}
