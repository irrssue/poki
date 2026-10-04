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
push outbox) and `202610040004_push_rotation.sql` (token takeover, expiry cleanup) in that order.
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

Clients poll every 10 seconds while active and support pull-to-refresh. The bell
counts incoming requests and unread pokes. Accepting adds the friend to both
accounts. Declining suppresses repeat requests for 24 hours. Request and lookup
rates are limited per account. Pokes have a 3-second sender cooldown, a 20/minute
limit, and durable UUID deduplication. The app reuses an uncertain submission's ID
when retrying the same recipient/message.

The app uses email/password signup and sign-in. Confirmation remains enabled on
the development project until explicitly approved otherwise. Supabase's default
mail service restricts recipients; custom SMTP is required for verified signup
by arbitrary users. A development-only alternative is disabling confirmation
with the project owner's approval; those accounts do not prove email ownership.
The hosted Auth Site URL and exact allowed redirect are now
`com.pokiapp.poki://auth/confirm`, replacing the default localhost destination.
Signup explicitly requests that redirect. iOS registers the scheme and handles
signup callbacks, exchanges the refresh token with this project's Auth server,
then saves the session in Keychain and loads profile setup. Callback URLs must
never be logged because they contain credentials. Expired/invalid links show a
safe error. The sign-in screen offers Resend confirmation email. Install the
updated app before opening a new link on the iPhone; older emails may still
contain localhost, and already-used links require sign-in or a fresh email.
See [Supabase mobile deep linking](https://supabase.com/docs/guides/auth/native-mobile-deep-linking?platform=swift).

The app handles either configuration and never treats an unconfirmed signup as a
signed-in session. Sessions are stored in the device Keychain, refresh is
serialized, and sign-out clears local account state.

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
Before a public release, add reporting and verify push delivery on hardware. Current messages use a 30 Unicode-code-point budget
on both client and database; compound emoji consume multiple units. Full
30-grapheme support remains a follow-up requiring a matching server validator.

## Verification

`cd backend && npm test` runs health/config tests plus the real PostgreSQL
migration using PGlite with separate authenticated identities. It covers private
table access, recipient-only acceptance, duplicate and crossed requests, denied
pending/declined pokes, deduplication, and recipient-only unread updates.

Run `swift test --package-path ios/Packages/PokiCore` and the `Poki` Xcode test
scheme for validation and account/send-state tests. Real-device acceptance test:
create two accounts, choose usernames, search/add, verify no poke target exists
before acceptance, accept from the second account's bell, then send a poke and
refresh the second account's inbox. Repeat after signing out and signing back in.
