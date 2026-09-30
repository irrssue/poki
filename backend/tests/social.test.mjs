import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

const alice = '11111111-1111-4111-8111-111111111111';
const bob = '22222222-2222-4222-8222-222222222222';
const eve = '33333333-3333-4333-8333-333333333333';

test('real PostgreSQL enforces account and friendship boundaries', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`create role anon; create role authenticated; create schema auth;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql as
      $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    insert into auth.users values ('${alice}'),('${bob}'),('${eve}');`);
  await db.exec(await readFile(new URL('../../supabase/migrations/202609300001_social.sql', import.meta.url), 'utf8'));
  const actor = async (id) => {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [id]);
    await db.exec('set role authenticated');
  };
  const snapshot = async () => (await db.query('select public.poki_snapshot() as value')).rows[0].value;
  await actor(alice);
  await db.query('select public.poki_create_profile($1,$2)', ['@Irrssue','Alice']);
  await actor(bob);
  await assert.rejects(db.query('select public.poki_create_profile($1,$2)', ['irrssue','Duplicate']), /username is taken/);
  await db.query('select public.poki_create_profile($1,$2)', ['bob','Bob']);
  await actor(eve);
  await db.query('select public.poki_create_profile($1,$2)', ['eve','Eve']);
  await actor(alice);
  await assert.rejects(db.query('select * from poki_private.profiles'), /permission denied/);
  await assert.rejects(db.query('select public.poki_request($1)', [alice]), /cannot add yourself/);
  await db.query('select public.poki_request($1)', [bob]);
  await db.query('select public.poki_request($1)', [bob]);
  let a = await snapshot();
  assert.equal(a.requests.length, 1);
  assert.equal(a.friends.length, 0);
  const request = a.requests[0].id;
  await assert.rejects(db.query('select public.poki_respond($1,true)', [request]), /no longer available/);
  const poke = '44444444-4444-4444-8444-444444444444';
  await assert.rejects(db.query('select public.poki_send($1,$2,$3)', [bob,'Hi',poke]), /only poke accepted friends/);
  await actor(eve);
  assert.equal((await snapshot()).requests.length, 0);
  await assert.rejects(db.query('select public.poki_respond($1,true)', [request]), /no longer available/);
  await actor(bob);
  // A crossed request must not silently accept the first one.
  await db.query('select public.poki_request($1)', [alice]);
  assert.equal((await snapshot()).friends.length, 0);
  await db.query('select public.poki_respond($1,true)', [request]);
  assert.equal((await snapshot()).friends.length, 1);
  await actor(alice);
  a = await snapshot();
  assert.equal(a.friends.length, 1);
  assert.equal(a.requests.length, 0);
  for (const invalid of ['x'.repeat(31), 'Hi\nBob', '   ']) {
    await assert.rejects(db.query('select public.poki_send($1,$2,$3)', [bob,invalid,poke]), /Invalid poke message/);
  }
  await db.query('select public.poki_send($1,$2,$3)', [bob,'Thinking of you',poke]);
  await db.query('select public.poki_send($1,$2,$3)', [bob,'Thinking of you',poke]);
  await actor(eve);
  await db.query('select public.poki_read($1)', [[poke]]);
  await actor(bob);
  assert.equal((await snapshot()).pokes.length,1);
  assert.equal((await snapshot()).pokes[0].unread,true);
  await db.query('select public.poki_read($1)', [[poke]]);
  assert.equal((await snapshot()).pokes[0].unread,false);
  await actor(eve);
  await db.query('select public.poki_request($1)', [bob]);
  await actor(bob);
  const incoming = (await snapshot()).requests[0];
  await db.query('select public.poki_respond($1,false)', [incoming.id]);
  await actor(eve);
  await assert.rejects(db.query('select public.poki_request($1)', [bob]), /wait before sending another/);
  await assert.rejects(db.query('select public.poki_send($1,$2,$3)', [bob,'Hi','55555555-5555-4555-8555-555555555555']), /only poke accepted friends/);
  await db.exec('reset role; set role anon');
  await assert.rejects(db.query('select public.poki_snapshot()'), /permission denied/);
  await actor('');
  await assert.rejects(db.query('select public.poki_snapshot()'), /Sign in/);
});
