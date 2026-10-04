import assert from 'node:assert/strict';
import { test } from 'node:test';
import { generateKeyPairSync, verify } from 'node:crypto';
import { classify, notificationBody, providerToken } from '../src/push/apns.ts';
import type { PushPayload } from '../src/push/apns.ts';
import { dispatchOne } from '../src/push/dispatch.ts';
import type { WorkerRPC } from '../src/push/dispatch.ts';

const payload: PushPayload = { id: 'job', token: 'secret', environment: 'sandbox', recipient_id: 'bob', sender_id: 'alice', sender_name: 'Alice', message: 'Hello', expires_at: 200, attempts: 1 };
test('APNs outcomes distinguish transient, invalid token and provider failures', () => {
  assert.deepEqual(classify({status:200}),{outcome:'sent'});
  for(const status of [429,500,503]) assert.equal(classify({status}).outcome,'retry');
  assert.deepEqual(classify({status:410,timestamp:123}),{outcome:'invalid',invalidatedAt:123});
  assert.equal(classify({status:410}).outcome,'drop');
  assert.equal(classify({status:400,reason:'BadDeviceToken'}).outcome,'invalid');
  assert.equal(classify({status:413}).outcome,'drop');
  assert.throws(()=>classify({status:403}),/configuration/);
});
test('provider token uses verifiable ES256 and notification routes to its account', () => {
  const {privateKey,publicKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
  const pem=privateKey.export({type:'pkcs8',format:'pem'}).toString();
  const jwt=providerToken(pem,'KEY','TEAM',123000);
  const [header,body,signature]=jwt.split('.') as [string,string,string];
  assert.deepEqual(JSON.parse(Buffer.from(body,'base64url').toString()),{iss:'TEAM',iat:123});
  assert.equal(verify('sha256',Buffer.from(`${header}.${body}`),{key:publicKey,dsaEncoding:'ieee-p1363'},Buffer.from(signature,'base64url')),true);
  const notification=JSON.parse(notificationBody(payload));
  assert.equal(notification.recipient_id,'bob');
  assert.equal(notification.aps.alert.title,'Alice poked you');
  assert.equal(notificationBody(payload).includes('secret'),false);
});
for(const scenario of ['sent','transport','expired','suppressed','provider'] as const) {
  test(`worker handles ${scenario} without losing the lease boundary`,async()=>{
    const calls: Array<{name:string;body:Record<string,unknown>}> = [];
    const rpc: WorkerRPC={async call<T>(name:string, body:Record<string,unknown>={}) {
      calls.push({name,body});
      if(name==='poki_claim_push') return {id:'job',lease_id:'lease'} as T;
      if(name==='poki_push_payload') return (scenario==='suppressed'?null:payload) as T;
      return null as T;
    }};
    let sends=0;
    const apns={async send(){ sends++; if(scenario==='transport') throw Error('private transport detail'); return {status:scenario==='provider'?403:200}; }};
    const run=dispatchOne(rpc,apns,()=>scenario==='expired'?300000:100000);
    if(scenario==='provider') await assert.rejects(run,/configuration/); else await run;
    assert.equal(sends, ['expired','suppressed'].includes(scenario)?0:1);
    if(!['suppressed','provider'].includes(scenario)) {
      const finish=calls.at(-1)!;
      assert.equal(finish.name,'poki_finish_push');
      assert.equal(finish.body.claim_id,'lease');
      assert.equal(finish.body.outcome,scenario==='sent'?'sent':scenario==='transport'?'retry':'drop');
    }
  });
}
