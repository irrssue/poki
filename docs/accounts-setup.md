# Accounts and friend requests

The development Supabase project is `dpxgiogbdbmpqnxxgoph` (Poki, Canada Central).
`ios/Poki/Resources/AccountConfiguration.plist` contains its URL and **public**
publishable key. Never put a secret/service-role key or database password in the app.

Apply the SQL files in `supabase/migrations/` in filename order to a new Supabase database.
The first two migrations have been applied to the development project.
`202610040001_safety.sql` (remove, block, account deletion, retention cleanup) is
**not yet applied**: paste it into the project's SQL Editor, or run
`supabase db push` after `supabase link --project-ref dpxgiogbdbmpqnxxgoph`. Then apply
`202610040002_mute.sql` (mute), `202610040003_push.sql` (device registration and
push outbox), `202610040004_push_rotation.sql` (token takeover, expiry cleanup) and
`202610070001_reports.sql` (private reports and moderation) in that order.
The app
tolerates the older schema, but remove/block/delete fail until it is applied. The tables live in
`poki_private`, are protected by RLS, and have no client grants. Authenticated
clients call the public RPCs below. Every function derives its actor from
`auth.uid()`; no request body can choose its sender. The Fastify service remains
health-only; social requests use Supabase's authenticated Data API directly.
This avoids requiring a separately hosted API for this development increment.

| RPC | Arguments | Result |
| --- | --- | --- |
| `poki_create_profile` | `username`, `display_name` | Unique lowercase profile |
| `poki_snapshot` | none | Own profile, accepted friends, pending requests, recent received pokes, blocked and muted people |
| `poki_search` | `username` | Exact username match and relationship, or null |
| `poki_request` | `recipient_id` | Pending request; duplicate/crossed requests do not auto-accept |
| `poki_respond` | `request_id`, `accept` | Only the pending request's recipient may respond |
| `poki_send` | `recipient_id`, `message`, `poke_id` | Durable in-app poke, accepted friends only |
| `poki_read` | `poke_ids` | Marks only the caller's received pokes read |
| `poki_remove` | `person_id` | Ends a friendship or cancels/dismisses a pending request |
| `poki_block` | `person_id` | Blocks and removes any connection; hides both people from each other's search and requests |
| `poki_unblock` | `person_id` | Only the blocker can lift a block |
| `poki_mute` | `person_id` | Mutes an accepted friend for the caller only |
| `poki_unmute` | `person_id` | Removes only the caller’s mute preference, even after removal/blocking |
| `poki_delete_account` | none | Deletes the auth user; profile, connections, pokes and blocks cascade |
| `poki_report` | `person_id`, `reason`, optional `poke_id`, `details`, `also_block` | Private report with copied evidence; optionally blocks in the same transaction |

Clients poll every 10 seconds while active and support pull-to-refresh. The bell
counts incoming requests and unread pokes. Accepting adds the friend to both
accounts. Declining suppresses repeat requests for 24 hours. Request and lookup
rates are limited per account. Pokes have a 3-second sender cooldown, a 20/minute
limit, and durable UUID deduplication. The app reuses an uncertain submission's ID
when retrying the same recipient/message.

Sign in with Apple is the only way into the app. One "Continue with Apple" button
covers both cases: Supabase creates the account the first time an Apple ID signs in
and returns the existing account afterwards. The app sends Apple a SHA-256 hashed
single-use nonce, then exchanges the identity token and raw nonce at
`auth/v1/token?grant_type=id_token` (provider `apple`); Supabase verifies both, so
no tokens arrive by URL and the old `com.pokiapp.poki://auth/confirm` scheme is gone.
Apple shares the user's name only on the first authorization; the app uses it to
prefill profile setup. The email (possibly an Apple private relay address) stays
private; friends find people by username.

Required setup, none of which is in git:

1. **Paid Apple Developer Program membership.** Team `S9ZZCZZ5BV` is currently a
   free Personal team. Apple refuses to provision Sign in with Apple (and Push
   Notifications) for Personal teams, so device builds fail at signing until the
   team is upgraded. The entitlement (`com.apple.developer.applesignin`) is in
   `project.yml`; automatic signing then enables the capability on the App ID.
2. **Supabase Apple provider.** Dashboard → Authentication → Sign In / Providers →
   Apple: enable it and add `com.pokiapp.Poki` to Client IDs. Native sign-in does
   not need the secret key/Services ID fields. Optionally disable the Email
   provider so accounts can only be created through Apple.
3. Before App Store release, account deletion must also revoke the user's Apple
   tokens through Apple's REST API (server-side, needs a Sign in with Apple key).

Sessions are stored in the device Keychain, refresh is serialized, and sign-out
clears local account state.

Pokes always appear **inside the app**. Lock-screen delivery is implemented but
not yet live: the app requests permission from Profile, registers its APNs token
through `poki_register_device`, and removes it before sign-out. Each poke atomically
queues deliveries that `backend/src/worker.ts` sends over APNs HTTP/2 after rechecking
friendship, blocks and mutes. Going live needs the push migrations applied, an Apple
`.p8` key, and a deployed worker with a service-role key; none is configured yet.
An APNs token belongs to the most recent account that registered it, so a reinstalled
or shared phone moves to the newly signed-in account. The inbox
shows the last 24 hours. An hourly `pg_cron` job (`poki-cleanup`) deletes pokes
older than 7 days, stale rate-limit rows, expired device registrations and old push work. Blocking hides the blocked person's
recent pokes from the blocker's inbox. Muting hides a person's pokes from the
caller's inbox and unread badge without changing friendship, search, or sending.
Unmuting restores recent pokes with their existing read state. Mutes survive
removal/blocking, remain manageable in Profile, and cascade on account deletion.
The sender cannot see whether they are muted, and muted pokes are never pushed.
Before a public release, verify push delivery on hardware. Current messages use a 30 Unicode-code-point budget
on both client and database; compound emoji consume multiple units. Full
30-grapheme support remains a follow-up requiring a matching server validator.

## Reporting and moderation

People can report a friend (Profile → ⋯ → Report), a blocked person (swipe in
Profile's Blocked list), a received poke or friend request (swipe or long-press in
the inbox), and a username search result. They choose a reason (harassment,
inappropriate, spam, impersonation, other), may add one line of up to 300
characters, and can block in the same step (on by default). Reports are private:
the reported person is never told, and reports never appear in any snapshot.

Because pokes are purged after 7 days, `poki_report` copies evidence into the
report: the reported poke's message, or the reported person's last five pokes to the
reporter. Retrying an open report for the same person and poke is a no-op. Reports
are limited to 5 per minute per account. Reports outlive either account (ids become
null; the reported username is kept) and are deleted 90 days after resolution.

Moderation is private and has no client access. The two RPCs are granted only to
`service_role`; run them from the Supabase dashboard SQL Editor:

```sql
select jsonb_pretty(poki_list_reports());              -- open reports, oldest first
select jsonb_pretty(poki_list_reports('actioned', 20)); -- or 'dismissed'
select poki_resolve_report('<report id>', 'dismissed');
select poki_resolve_report('<report id>', 'actioned');       -- handled elsewhere
select poki_resolve_report('<report id>', 'actioned', true); -- remove the account
```

Each listed report shows the reason, details, copied evidence, reporter id, and how
many open reports name the same person. Removing an account resolves every open
report against that person as actioned and deletes their auth user, so their profile,
friendships, pokes and devices cascade away. They can still sign in with Apple again
as a new account; a durable ban is not implemented. Check the queue at least daily
once the app is public. App Review also expects published contact details for
reporting; add a support address or page before submission.

## Verification

`cd backend && npm test` runs health/config tests plus the real PostgreSQL
migration using PGlite with separate authenticated identities. It covers private
table access, recipient-only acceptance, duplicate and crossed requests, denied
pending/declined pokes, deduplication, and recipient-only unread updates.

Run `swift test --package-path ios/Packages/PokiCore` and the `Poki` Xcode test
scheme for validation and account/send-state tests. Real-device acceptance test:
create two accounts with different Apple IDs, choose usernames, search/add, verify
no poke target exists before acceptance, accept from the second account's bell, then send a poke and
refresh the second account's inbox. Repeat after signing out and signing back in.
