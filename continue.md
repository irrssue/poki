# Continue here — handoff (October 4, 2026)

Read `about.md` (product spec), `docs/accounts-setup.md` (Supabase setup and RPCs),
and `docs/project-status.md` (history) before starting.

## Current state

**Hosted Supabase project:** `dpxgiogbdbmpqnxxgoph` (Poki, Canada Central). The app's
URL and **public** publishable key are in `ios/Poki/Resources/AccountConfiguration.plist`.
Never put a secret/service-role key or database password in the app or repo.

Verified live on October 4, 2026:
- Migrations `202609300001_social.sql` and `202609300002_search_parameter.sql` are applied.
  Calling an RPC without signing in returns `permission denied`, which is correct.
- Email/password auth is enabled. Email confirmation is **required**
  (`mailer_autoconfirm: false`). No custom SMTP is configured.
- Accounts, exact @username search, friend requests and in-app pokes work end to end.

**Backend (`backend/`):** a Fastify service with only `GET /v1/health`. Social features
use Supabase RPCs directly; there is no separately hosted API. `npm test` runs the
health/config tests plus real-PostgreSQL (PGlite) tests that apply **every** file
in `supabase/migrations/` in filename order. All 20 backend tests pass.

**iOS (`ios/`):** SwiftUI app, iOS 17, generated with XcodeGen from `project.yml`.

## Added in commit `75f5777`

- `supabase/migrations/202610040001_safety.sql`:
  - `poki_remove(person_id)`: ends a friendship, or cancels/dismisses a pending
    request. Declined rows keep their 24-hour cooldown.
  - `poki_block(person_id)` / `poki_unblock(person_id)`: blocking deletes the connection
    and hides both people from each other's search and requests. It also hides the
    blocked person's pokes from the blocker's inbox. Only the blocker can unblock.
  - `poki_delete_account()`: deletes the `auth.users` row; the profile, connections,
    pokes, blocks and rate limits cascade.
  - `poki_snapshot` now also returns `blocked` (the people the caller blocked).
  - `poki_private.cleanup()`: an hourly `pg_cron` job (`poki-cleanup`, at minute 17)
    deletes pokes older than 7 days and stale rate-limit rows. It is only scheduled
    when `pg_cron` is available.
- `backend/tests/social.test.mjs`: a new test covering removal, cancelling, blocking in
  both directions, blocker-only unblock, account-deletion cascade, cleanup and anon denial.
- iOS:
  - `ProfileView` lists friends with Remove and Block (both confirmed), shows a
    blocked list with Unblock, and offers a confirmed Delete account.
  - `NotificationsView` has a Cancel button on outgoing requests.
  - `AppModel` has `removeFriend`, `block`, `unblock` and `deleteAccount`.
  - `SocialSnapshot.blocked` is optional, so the app still works on the old schema.
- Docs updated.

## Next increment delivered: mute controls

- `202610040002_mute.sql` adds private directional mute preferences and authenticated
  `poki_mute(person_id)` / `poki_unmute(person_id)` RPCs. Only accepted friends can
  be newly muted. Unmute works after removal/blocking. Account deletion cascades.
- Snapshot includes optional `muted` and excludes those senders before its inbox
  limit; inbox and unread badge hide their pokes. Unmuting restores recent pokes.
- Profile has friend-menu Mute/Unmute and a separate Muted list. Friendship, search,
  and sends remain available; senders cannot read the recipient's preference.
- PostgreSQL integration coverage verifies auth, isolation, deduplication,
  reversibility, continued sends, removal/blocking, and deletion. Swift tests cover
  decoding older snapshots and clearing mute state on sign-out.
- Backend suite and shared Swift build pass; changed Swift sources pass syntax
  parsing. Full iOS build/tests still need Xcode. No APNs delivery is implemented.

## Not verified

- This Mac has only Apple's Command Line Tools (no full Xcode), so the iOS app was
  **not built or run**. The new Swift code was only typechecked against the macOS SDK,
  with stubs for iOS-only APIs. Build and test in Xcode or CI, and on a real device.
- GitHub Actions results were not checked (`gh` is not authenticated on this machine).

## What still needs doing

### Needs the project owner (external setup)
1. **Apply the new migration to the hosted project.** Paste
   `supabase/migrations/202610040001_safety.sql` and then
   `supabase/migrations/202610040002_mute.sql` into the Supabase SQL Editor, or run
   `supabase link --project-ref dpxgiogbdbmpqnxxgoph && supabase db push`.
   Remove, block, delete and mute controls fail in the app until this is done.
   Afterwards, check that `poki-cleanup` appears in `cron.job`.
2. **Email confirmation.** Supabase's built-in mailer only delivers to a limited set
   of addresses, so arbitrary users can't verify signups. Either configure custom
   SMTP, or (with the owner's approval, development only) disable confirmation.
3. **Push notifications (APNs).** Needs an APNs auth key from the Apple Developer
   account and the Push Notifications capability/entitlement. Pokes currently show
   only inside the app.

### Engineering backlog
- **Push delivery:** device token registration RPC/table, a delivery outbox written in
  the same transaction as `poki_send`, a worker in `backend/` that sends via APNs
  HTTP/2, and a "Poke back" notification action. The worker must check current
  recipient mute and block preferences before dispatch. Never acknowledge a poke without
  durably recording the dispatch work.
- **Report user** (spec: profile area). Mute is now implemented.
- **Favorite-person widget:** WidgetKit + App Intents, sharing the send client.
- **Profile photos** (private Supabase Storage bucket) and a real app icon (the asset
  catalog has no image).
- **Message length:** currently a 30 Unicode-code-point limit on both app and
  database. The spec wants 30 visible characters (graphemes), which requires a
  matching validator on the server.
- **Friend-list behavior gaps** from `docs/project-status.md`: the whole row container
  should be the poke target, haptic feedback, and keyboard/Dynamic Type/VoiceOver
  testing.
- **Optional:** add `supabase/config.toml` (`supabase init`) so the CLI workflow
  is reproducible.

## Conventions
- Every social write goes through a `security definer` RPC in `public` that derives
  the user from `auth.uid()`. Tables live in `poki_private` with RLS enabled and no
  client grants.
- New public RPCs: `revoke ... from public, anon` and `grant ... to authenticated`.
  New `poki_private` functions: revoke from `public, anon, authenticated`.
- Add each schema change as a new, timestamp-named migration file. Never edit applied
  migrations. Cover the change in `backend/tests/social.test.mjs`.
- After each change: commit with a descriptive message and push to `main`.
