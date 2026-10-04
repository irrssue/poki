# Poki — agent handoff (October 4, 2026)

Read `about.md`, `docs/accounts-setup.md`, and the current updates at the top of
`docs/project-status.md`. The older implementation review is historical, not the
current state. Start by checking `git status` and recent commits.

## Current state

- Native SwiftUI app, iOS 17 minimum, generated with XcodeGen from `project.yml`.
  Email/password accounts, profile creation, exact @username search, accepted
  friendships, requests, in-app pokes, and local favorite configuration exist.
- Social actions call authenticated Supabase RPCs directly. `backend/` is a
  Fastify health-only service; no social API or push worker is hosted.
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
- Commit `7db8c18` fixed signup confirmation redirects. Hosted Auth Site URL and
  its exact allowed redirect were saved as `com.pokiapp.poki://auth/confirm`.
  The app registers that scheme, explicitly requests it at signup, validates
  signup callbacks and exchanges refresh tokens with the configured Auth server
  before saving the session in Keychain. Sign-in includes confirmation resend.
- Email confirmation remains enabled. No custom SMTP or APNs delivery has been
  configured in this work. Pokes currently appear only inside Poki.

## Verification and limits

- All 20 backend tests passed after the mute increment. PGlite applies every SQL
  migration in filename order and exercises authorization and state transitions.
- All seven shared Swift package tests passed after the redirect fix, including
  rejection of foreign/malformed/expired callbacks and duplicate refresh tokens.
- Simulator app compilation and signed physical-device build succeeded. The
  updated app was installed and launched on the connected iPhone.
- Simulator app tests stalled before starting and were interrupted; do not claim
  the full app test suite passed. GitHub Actions results were not checked.
- Full Xcode now exists at `/Applications/Xcode.app`. The default `xcode-select`
  still points to Command Line Tools; use the explicit DEVELOPER_DIR below.
- The fresh email-link round trip has NOT been verified. Older emails may retain
  localhost; an already-used link may have confirmed the address before redirecting.
- Only the first two September 30 migrations were previously verified live.
  Neither October 4 migration was applied during these changes. Inspect hosted
  state before assuming remove/block/delete/mute are available there.

## Next steps, in order

1. **Finish confirmation acceptance testing.** On the updated iPhone app, try
   signing in if the earlier link was clicked. Otherwise use Resend confirmation
   email and open the newest link on the same phone. Check return to Poki,
   authenticated profile setup, relaunch persistence, and sign-out. Check expired
   links show a safe error. Coordinate inbox/password interaction with the owner;
   never log real callback URLs or tokens. Do not disable email confirmation as
   a shortcut.
2. **Inspect and deploy missing hosted migrations.** Check whether the safety and
   mute migrations are already present. If absent, apply
   `202610040001_safety.sql`, then `202610040002_mute.sql` using the SQL Editor or
   linked Supabase CLI. Test with two accounts: remove/cancel, block in both
   directions, blocker-only unblock, directional mute/unmute, and inbox/badge
   filtering. Account deletion is destructive; use explicitly disposable test
   accounts with appropriate authorization. Check `cron.job` for `poki-cleanup`
   when pg_cron is available; cleanup scheduling is conditional.
3. **Recover simulator app tests and check CI.** Resolve the simulator boot/test
   launch stall, then run the Poki test scheme. Do not reinstall tools or change
   global Xcode selection unnecessarily. Preserve existing signing/team settings.
4. **Next substantial engineering increment: durable push foundation.** Add a
   private device-registration table and authenticated RPC with token ownership,
   APNs environment, rotation, and sign-out lifecycle. Add an outbox atomically
   with poke insertion, preserving idempotency. Test no duplicate dispatch jobs,
   rollback on failures, and private-table/actor boundaries. Then implement the
   APNs HTTP/2 worker with bounded retries, expiration, token invalidation, and
   current friendship/block/mute checks before dispatch. Configure credentials
   and hosting separately; do not claim visible push delivery until tested on
   hardware. Add contextual permission UI and notification routing. Poke-back
   follows once delivery is reliable.

## External prerequisites

- Custom SMTP is still needed for verified signup by arbitrary users; the built-in
  mailer's restrictions remain. The owner received a confirmation email, which
  does not establish unrestricted delivery. Keep confirmation enabled.
- APNs requires the owner's Apple Developer key, capability/entitlement, and a
  deployed worker with securely stored credentials. No secrets belong in iOS.
- Hosted migration access may require the owner to sign in or provide an approved
  execution path. The Supabase dashboard was accessible in the in-app browser
  during the redirect fix; do not assume that session remains available.

## Later backlog

- Report-user controls and a private reporting/moderation workflow.
- Match the spec's 30 visible characters (graphemes) on client and server;
  current validation uses 30 Unicode code points. Add shared Unicode fixtures.
- Make all non-editing friend-row areas poke targets, add accepted-send haptics,
  and test keyboard, Dynamic Type, VoiceOver, and accidental-send behavior.
- Private profile-photo storage and a real app icon.
- Favorite-person WidgetKit/App Intents extension after send reliability is proven.
- Optional reproducible Supabase CLI configuration.

## Useful commands

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
project and `ios/Poki/Resources/Info.plist` consistent with URL-scheme registration.

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
