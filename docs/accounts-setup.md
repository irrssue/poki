# Accounts and friend requests

The development Supabase project is `dpxgiogbdbmpqnxxgoph` (Poki, Canada Central).
`ios/Poki/Resources/AccountConfiguration.plist` contains its URL and **public**
publishable key. Never put a secret/service-role key or database password in the app.

Apply `supabase/migrations/202609300001_social.sql` once to a new Supabase database.
The migration has been applied to the development project. The tables live in
`poki_private`, are protected by RLS, and have no client grants. Authenticated
clients call the public RPCs below. Every function derives its actor from
`auth.uid()`; no request body can choose its sender. The Fastify service remains
health-only; social requests use Supabase's authenticated Data API directly.
This avoids requiring a separately hosted API for this development increment.

| RPC | Arguments | Result |
| --- | --- | --- |
| `poki_create_profile` | `username`, `display_name` | Unique lowercase profile |
| `poki_snapshot` | none | Own profile, accepted friends, pending requests, recent received pokes |
| `poki_search` | `username` | Exact username match and relationship, or null |
| `poki_request` | `recipient_id` | Pending request; duplicate/crossed requests do not auto-accept |
| `poki_respond` | `request_id`, `accept` | Only the pending request's recipient may respond |
| `poki_send` | `recipient_id`, `message`, `poke_id` | Durable in-app poke, accepted friends only |
| `poki_read` | `poke_ids` | Marks only the caller's received pokes read |

Clients poll every 10 seconds while active and support pull-to-refresh. The bell
counts incoming requests and unread pokes. Accepting adds the friend to both
accounts. Declining suppresses repeat requests for 24 hours. Request and lookup
rates are limited per account. Pokes have a 3-second sender cooldown, a 20/minute
limit, and durable UUID deduplication. The app reuses an uncertain submission's ID
when retrying the same recipient/message.

Email-code sign-in requires custom SMTP and an OTP email template containing
`{{ .Token }}` for new and existing accounts. Supabase's default mail service is
restricted and its default template is a magic link. Do not claim that arbitrary
users can sign in until mail delivery is configured or the approved development
password flow is enabled. Sessions are stored in the device Keychain, refresh is
serialized, and sign-out clears local account state.

Pokes currently appear **inside the app**, not as APNs lock-screen notifications.
No APNs key, push entitlement, worker, or delivery outbox is configured. The inbox
shows the last 24 hours; database payload cleanup is not yet scheduled. Before a
public release, add retention cleanup, block/remove/report controls, account
deletion, and push delivery. Current messages use a 30 Unicode-code-point budget
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
