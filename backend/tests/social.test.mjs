import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFile, readdir } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

const alice = '11111111-1111-4111-8111-111111111111';
const bob = '22222222-2222-4222-8222-222222222222';
const eve = '33333333-3333-4333-8333-333333333333';

const migrations = new URL('../../supabase/migrations/', import.meta.url);

// Applies every migration in filename order, as Supabase does, with stub auth roles.
async function database(t) {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`create role anon; create role authenticated; create schema auth;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql as
      $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    insert into auth.users values ('${alice}'),('${bob}'),('${eve}');`);
  for (const file of (await readdir(migrations)).filter(name => name.endsWith('.sql')).sort()) {
    await db.exec(await readFile(new URL(file, migrations), 'utf8'));
  }
  const actor = async (id) => {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [id]);
    await db.exec('set role authenticated');
  };
  const snapshot = async () => (await db.query('select public.poki_snapshot() as value')).rows[0].value;
  return { db, actor, snapshot };
}

test('real PostgreSQL enforces account and friendship boundaries', async t => {
  const { db, actor, snapshot } = await database(t);
  await actor(alice);
  await db.query('select public.poki_create_profile($1,$2)', ['@Irrssue','Alice']);
  await actor(bob);
  await assert.rejects(db.query('select public.poki_create_profile($1,$2)', ['irrssue','Duplicate']), /username is taken/);
  await db.query('select public.poki_create_profile($1,$2)', ['bob','Bob']);
  await actor(eve);
  await db.query('select public.poki_create_profile($1,$2)', ['eve','Eve']);
  await actor(alice);
  const match = await db.query('select public.poki_search($1) as value', ['@BOB']);
  assert.equal(match.rows[0].value.person.id, bob);
  assert.equal(match.rows[0].value.relationship, 'none');
  assert.equal((await db.query('select public.poki_search($1) as value', ['missing'])).rows[0].value, null);
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

test('real PostgreSQL enforces removal, blocking, deletion, and cleanup', async t => {
  const { db, actor, snapshot } = await database(t);
  for (const [id, handle] of [[alice,'alice'],[bob,'bob'],[eve,'eve']]) {
    await actor(id);
    await db.query('select public.poki_create_profile($1,$2)', [handle, handle]);
  }
  const befriend = async (from, to) => {
    await actor(from);
    await db.query('select public.poki_request($1)', [to]);
    await actor(to);
    const request = (await snapshot()).requests.find(r => r.incoming && r.person.id === from);
    await db.query('select public.poki_respond($1,true)', [request.id]);
  };
  await befriend(alice, bob);
  await actor(alice);
  await db.query('select public.poki_remove($1)', [bob]);
  assert.equal((await snapshot()).friends.length, 0);
  await actor(bob);
  assert.equal((await snapshot()).friends.length, 0);
  await assert.rejects(db.query('select public.poki_send($1,$2,$3)', [alice,'Hi','66666666-6666-4666-8666-666666666666']), /only poke accepted friends/);
  // A sender can cancel an outgoing request.
  await db.query('select public.poki_request($1)', [alice]);
  await db.query('select public.poki_remove($1)', [alice]);
  assert.equal((await snapshot()).requests.length, 0);

  await befriend(alice, bob);
  await actor(bob);
  await db.query('select public.poki_send($1,$2,$3)', [alice,'Before block','77777777-7777-4777-8777-777777777777']);
  await actor(alice);
  await assert.rejects(db.query('select public.poki_block($1)', [alice]), /cannot block yourself/);
  await db.query('select public.poki_block($1)', [bob]);
  await db.query('select public.poki_block($1)', [bob]);
  let a = await snapshot();
  assert.equal(a.friends.length, 0);
  assert.equal(a.pokes.length, 0);
  assert.deepEqual(a.blocked.map(p => p.id), [bob]);
  assert.equal((await db.query('select public.poki_search($1) as value', ['bob'])).rows[0].value, null);
  await assert.rejects(db.query('select public.poki_request($1)', [bob]), /not available/);
  await actor(bob);
  assert.equal((await snapshot()).blocked.length, 0);
  assert.equal((await db.query('select public.poki_search($1) as value', ['alice'])).rows[0].value, null);
  await assert.rejects(db.query('select public.poki_request($1)', [alice]), /not available/);
  await assert.rejects(db.query('select public.poki_send($1,$2,$3)', [alice,'Hi','88888888-8888-4888-8888-888888888888']), /only poke accepted friends/);
  // Only the blocker can lift a block.
  await db.query('select public.poki_unblock($1)', [alice]);
  await actor(alice);
  assert.equal((await snapshot()).blocked.length, 1);
  await db.query('select public.poki_unblock($1)', [bob]);
  a = await snapshot();
  assert.equal(a.blocked.length, 0);
  assert.equal(a.pokes.length, 1);
  assert.equal((await db.query('select public.poki_search($1) as value', ['bob'])).rows[0].value.relationship, 'none');

  await befriend(eve, alice);
  await actor(eve);
  await db.query('select public.poki_delete_account()');
  await assert.rejects(db.query('select public.poki_create_profile($1,$2)', ['eve','Eve']), /foreign key|violates/);
  await actor(alice);
  a = await snapshot();
  assert.equal(a.friends.length, 0);
  assert.equal((await db.query('select public.poki_search($1) as value', ['eve'])).rows[0].value, null);

  await assert.rejects(db.query('select poki_private.cleanup()'), /permission denied/);
  await db.exec(`reset role;
    update poki_private.pokes set created_at = now() - interval '8 days';
    select poki_private.cleanup();`);
  assert.equal((await db.query('select count(*)::int as n from poki_private.pokes')).rows[0].n, 0);
  await db.exec('set role anon');
  for (const call of ['poki_remove($1)', 'poki_block($1)', 'poki_unblock($1)']) {
    await assert.rejects(db.query(`select public.${call}`, [bob]), /permission denied/);
  }
  await assert.rejects(db.query('select public.poki_delete_account()'), /permission denied/);
});
