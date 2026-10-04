# Poki — agent handoff (October 4, 2026)

Read `about.md`, `docs/accounts-setup.md`, and the current updates at the top of
`docs/project-status.md`. The older implementation review is historical, not the
current state. Start by checking `git status` and recent commits.

## Current state

- Native SwiftUI app, iOS 17 minimum, generated with XcodeGen from `project.yml`.
  Sign in with Apple accounts, profile creation, exact @username search, accepted
  friendships, requests, in-app pokes, and local favorite configuration exist.
- Social actions call authenticated Supabase RPCs directly. `backend/` is a
  Fastify health-only service; no social API or push worker is hosted.
- **The backend is deployed to the homelab** (commits `c5cc86e`, `1418e03`); see
  `docs/homelab-hosting.md`. Public health URL: https://poki.irrssue.com/v1/health
  (root returns 404 by design). Docker Compose project `poki` runs the `api`
  container (loopback `127.0.0.1:3014`) and a dedicated Cloudflare tunnel `poki`.
  Deploy or roll back with `bash deploy/homelab.sh [commit]` over the existing
  `ssh irrssue@homelab` access; pushes alone do not deploy. Releases live in
  `/home/irrssue/apps/poki/releases/<commit>`, `current` symlinks the live one.
- Hosted Supabase project: `dpxgiogbdbmpqnxxgoph` (Poki, Canada Central).
  The app's URL and public publishable key are in
  `ios/Poki/Resources/AccountConfiguration.plist`. Never commit admin keys,
  database passwords, sessions, or confirmation URLs containing tokens.
- Remove/cancel, block/unblock, account deletion and retention cleanup are
  implemented in `202610040001_safety.sql`.
- Commit `ceaa32f` added `202610040002_mute.sql` and Profile mute/unmute controls.
  Muting privately hides incoming pokes and their badge contribution, preserves
  friendships/sending, and survives removal/blocking. Unmuting restores recent
  pokes with their existing read state. Account deletion cascades mute rows.
- **Sign in with Apple is the only sign-in** (replaced email/password, confirmation
  links, resend and the `com.pokiapp.poki` URL scheme). One "Continue with Apple"
  button: `AccountView` sends Apple a hashed `AppleSignInNonce` (PokiCore), then
  `AccountService.signInWithApple` exchanges the identity token + raw nonce at
  `auth/v1/token?grant_type=id_token`; Supabase creates the account on first use
  and signs in afterwards. Apple's first-time full name prefills profile setup.
  `project.yml` adds the `com.apple.developer.applesignin` entitlement.
- **Team `S9ZZCZZ5BV` is a free Personal team.** Apple will not provision Sign in
  with Apple or Push Notifications for it, so signed device builds fail at
  provisioning. This was already true since the push entitlement landed; the
  pre-Apple-sign-in commit fails identically. Simulator builds with
  `CODE_SIGNING_ALLOWED=NO` still compile and test, but Apple sign-in cannot
  complete without a provisioned App ID.
- **Push foundation is built but not live.** `202610040003_push.sql` adds private
  device registrations, an outbox queued by a trigger in the poke transaction,
  leased worker RPCs and dispatch-time friendship/block/mute rechecks.
  `202610040004_push_rotation.sql` lets the newest account own an APNs token
  (Keychain survives reinstall) and prunes expired devices/push work in cleanup.
  `backend/src/worker.ts` is the APNs HTTP/2 worker (not yet deployed or
  credentialed). iOS: `NotificationController` (permission, token, routing, single
  `PokiAppDelegate`) and `PushRegistration` (serialized Keychain-backed device
  registration; sign-out waits for server removal). Tapping a push opens the inbox
  after checking it belongs to the signed-in account. Debug builds register as
  `sandbox`, Release as `production`; `Poki.entitlements` sets `aps-environment`.
- Two parallel push UIs were committed by mistake on October 4 (`79eed3c`,
  `9d4ccf8`); they were consolidated into the single path above.

## Verification and limits

- All 20 backend tests passed after the mute increment. PGlite applies every SQL
  migration in filename order and exercises authorization and state transitions.
- After the Apple sign-in switch: all 8 shared Swift package tests (including the
  nonce hash/uniqueness tests) and all 13 simulator app tests passed on the booted
  iPhone 18 Pro simulator. Sign in with Apple itself has NOT been exercised end to
  end (blocked on the paid team and Supabase provider setup below).
- An earlier signed device build succeeded before the push entitlement existed;
  signed device builds now fail on the Personal team (see above).
- All 13 simulator app tests (including push registration) and 38 backend tests
  passed after the push consolidation on the booted iPhone 18 Pro simulator.
  GitHub Actions results were not checked. Push delivery has not been tested on
  hardware.
- Full Xcode now exists at `/Applications/Xcode.app`. The default `xcode-select`
  still points to Command Line Tools; use the explicit DEVELOPER_DIR below.
- Verified October 4, 2026: the homelab health URL returned `{"status":"ok"}`
  (HTTP 200), and on the server both `api` (healthy) and `tunnel` were up,
  running release `1418e039e3e1734bb49e0a22ae5ffad6e2d3a7ae` (= `main` at the time).
- **Verified October 4, 2026: the October 4 migrations are NOT applied live**
  (now four: safety, mute, push, push_rotation).
  Probing the hosted Data API with the publishable key returned `PGRST202`
  (function not found) for `poki_block(person_id)` and `poki_mute(person_id)`,
  while `poki_request`/`poki_snapshot` exist (`42501` permission denied for anon).
  Remove/block/delete/mute will fail in the app until both are applied.
- This Mac has no Supabase CLI login, access token, database password, `psql`,
  or installed `supabase` binary (`npx supabase` is available via Node 26).

## Next steps, in order

1. **Make Sign in with Apple work (blocked on owner).** The owner must upgrade to
   the paid Apple Developer Program, and in the Supabase dashboard enable the
   Apple provider with `com.pokiapp.Poki` in Client IDs (no secret needed for
   native). Optionally disable the Email provider. Then build to the iPhone with
   automatic signing (`-allowProvisioningUpdates`), and test first sign-in (account
   creation + name prefill), relaunch persistence, sign-out, signing back in to the
   same account, and Hide My Email. Existing email test accounts are not migrated;
   Supabase links an Apple identity to one only when the verified emails match.
2. **Apply the missing hosted migrations (confirmed absent; blocked on owner
   access).** Ask the owner to run `! npx supabase login` in the session (browser
   approval), then `npx supabase link --project-ref dpxgiogbdbmpqnxxgoph` (may
   prompt for the database password; never commit or log it) and push only
   `202610040001_safety.sql`, then `202610040002_mute.sql`. Alternatively the
   owner pastes each file into the dashboard SQL Editor in that order. Re-probe
   `poki_block`/`poki_mute` afterwards to confirm they exist. Test with two accounts: remove/cancel, block in both
   directions, blocker-only unblock, directional mute/unmute, and inbox/badge
   filtering. Account deletion is destructive; use explicitly disposable test
   accounts with appropriate authorization. Check `cron.job` for `poki-cleanup`
   when pg_cron is available; cleanup scheduling is conditional.
3. **Check CI** for the latest commits.
4. **Make push live (blocked on owner credentials).** Apply the push migrations,
   then deploy `worker.ts` to the homelab next to `api` with `SUPABASE_URL`,
   `SUPABASE_SERVICE_KEY_FILE`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`
   (`com.pokiapp.Poki`) and `APNS_KEY_FILE` supplied as files/secrets outside git.
   Confirm the Push Notifications capability on the App ID for team `S9ZZCZZ5BV`.
   Test on two iPhones: permission, delivery, mute/block suppression, tap routing,
   sign-out removal, and account switch on one phone. Poke-back follows once
   delivery is reliable.

## External prerequisites

- The owner was told (October 4) what each blocked item needs: Supabase CLI
  login for migrations, an SMTP provider and sender domain, an Apple Developer
  APNs `.p8` key, and two iPhones for acceptance testing. The owner has not yet
  decided whether to start the push foundation code; confirm before beginning.
- Custom SMTP is no longer needed for sign-in now that accounts come from Apple.
- A paid Apple Developer Program membership is required for Sign in with Apple,
  push, and installing the current app on a device.
- APNs requires the owner's Apple Developer key, capability/entitlement, and a
  deployed worker with securely stored credentials. No secrets belong in iOS.
- Hosted migration access requires the owner to sign in (see step 2) or provide
  an approved execution path. The Supabase dashboard was accessible in the in-app browser
  during the redirect fix; do not assume that session remains available.

## Later backlog

- Report-user controls and a private reporting/moderation workflow.
- Revoke Apple tokens on account deletion (App Store requirement for Sign in with
  Apple): needs a server-side Sign in with Apple key and the authorization code.
- Match the spec's 30 visible characters (graphemes) on client and server;
  current validation uses 30 Unicode code points. Add shared Unicode fixtures.
- Make all non-editing friend-row areas poke targets, add accepted-send haptics,
  and test keyboard, Dynamic Type, VoiceOver, and accidental-send behavior.
- Private profile-photo storage and a real app icon.
- Favorite-person WidgetKit/App Intents extension after send reliability is proven.
- Optional reproducible Supabase CLI configuration.

## Useful commands

Homelab checks (no secrets needed):

```sh
curl -sS https://poki.irrssue.com/v1/health
ssh irrssue@homelab 'cd /home/irrssue/apps/poki/current && POKI_RELEASE=$(basename "$(readlink -f .)") docker compose -f deploy/compose.yml ps'
```

```sh
cd backend
npm test
npm run typecheck
```

From the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path ios/Packages/PokiCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Poki.xcodeproj -scheme Poki -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO
```

Use an available simulator rather than assuming the example device exists.
Regenerate with `xcodegen generate` after changing `project.yml`; keep the generated
project, `ios/Poki/Resources/Info.plist` and `Poki.entitlements` consistent with it.

## Working conventions

- Social writes use `security definer` RPCs in `public`, deriving the actor from
  `auth.uid()`. Private tables have RLS and no client grants; use an empty search
  path and qualified references. Check the actor even for no-op operations.
- Revoke new public RPC execution from `public, anon`; grant to `authenticated`.
  Revoke private function execution from `public, anon, authenticated`.
- Add timestamped migrations; never rewrite applied migrations. Cover database
  behavior in `backend/tests/social.test.mjs`.
- Follow the user's Git workflow: stage changed files, commit with a readable
  message explaining what and why, then push directly to `main` automatically.
- The user requests execution responses containing only `DONE`, unless they
  explicitly ask for explanations or next steps.
