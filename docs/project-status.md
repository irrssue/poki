# Current update — September 30, 2026

Account onboarding, shared profiles, username search, request acceptance, and
in-app pokes are now implemented against the hosted Supabase project. See
[accounts setup](accounts-setup.md) for deployment, verification, and remaining
email delivery/APNs prerequisites. 

October 4, 2026: added `supabase/migrations/202610040001_safety.sql` with remove
friend, cancel request, block/unblock, account deletion, and scheduled retention
cleanup, covered by PGlite integration tests and wired into the profile and inbox
screens. It must still be applied to the hosted project. Remaining external setup:
custom SMTP (or approved disabling of email confirmation) and APNs credentials
for push delivery.

October 4, 2026: added `202610040002_mute.sql` and Profile mute/unmute controls.
Mute preferences are private and directional; the snapshot excludes muted senders
before the inbox limit, so their pokes do not contribute to the badge. Friendships
and outgoing pokes remain available. Muted people stay listed after removal/blocking
so preferences can be undone. Integration tests cover ownership, reversibility,
friendship preservation, sending, auth denial, and deletion cascade. Both October 4
migrations still need hosted deployment. Reporting and APNs remain pending.

The older review below describes the prior
prototype and is retained as historical context.

# Implementation review — September 28, 2026

## What exists

The repository contains a native SwiftUI iOS 17 prototype, a local Swift 6 package,
a checked-in Xcode project generated from `project.yml`, and a small unit test
suite. `AppModel` owns draft, favorite, sending, and navigation state. `PokeService`
is injectable, but its only implementation sleeps and succeeds. `FavoriteStore`
uses UserDefaults. There is no session, database, network client, entitlement for
push delivery, APNs worker, or widget.

The main screen renders mock friends, editable drafts, avatar/send buttons, and
a star/profile bar. Favorites can be configured and saved locally. Profile
identity is placeholder text; add-friend and request buttons are no-ops, and
settings rows are placeholders. The asset catalog has no actual app icon image.

## Next increment delivered

The next unblocked backend backlog item is now implemented: a strict TypeScript
Fastify service with validated runtime configuration, a separately composed app,
a public liveness route, bounded requests, sanitized errors, graceful shutdown,
pinned dependencies, and a lockfile. Injection tests cover configuration,
liveness, unknown social routes, malformed/oversized input, and error disclosure.
The initial OpenAPI document describes only the implemented health route.

CI now covers backend compilation/tests, shared Swift tests, and iOS simulator
app tests. The Xcode generator now enables Info.plist generation for both targets;
the checked-in project previously had neither plist files nor generation enabled. The backend can be developed without external credentials. It does not
claim authentication, friendship authorization, persistence, or push delivery.
This follows the specification's first backend backlog item before connecting
production clients.

## Gaps found in the existing prototype

- Preview friends get fresh UUIDs each launch, so a saved favorite can lose its
  recipient after relaunch.
- Message normalization trims visible spaces. Validation rejects newlines and
  excess length but allows other control characters. Pasted invalid input is
  silently ignored. App/server Unicode fixture parity is still absent.
- Sending bypasses validation if state is changed directly; it does not check
  current accepted-friend membership. Production authorization must be enforced
  independently by the backend.
- A successful in-flight send clears a draft even if the user edited it while
  waiting. There is no cooldown, idempotency key, or uncertain-response retry state.
- The row's surrounding container is not a poke target; there is an extra arrow
  button. Feedback has no haptic, and its dismissal task is not keyed by send.
- The bottom bar overlays content with fixed bottom padding. Keyboard, large text,
  VoiceOver, and accidental-send interaction behavior need device/UI tests.
- Existing tests cover only basic message validation and happy-path state changes.
  App tests use the simulated delay and default persistent favorite store.

## Verification and remaining boundary

All 17 backend tests and strict type checking pass under the pinned Node 24.21.0
runtime. Both source and compiled servers pass an HTTP smoke check and graceful
SIGTERM shutdown; invalid startup configuration exits without exposing its value.
Local shared Swift compilation succeeds. This Mac currently selects only Apple's
Command Line Tools: XCTest and iOS simulator tooling are unavailable. CI provides
the full-Xcode test path; its remote result must be checked after pushing.

Next implement the profile/connection database migration and authenticated API
contract, then Supabase JWT verification and profile setup. Application tables
must be inaccessible to direct client writes. Test ownership and connection
transitions against PostgreSQL before adding poke transactions, idempotency, and
the APNs outbox. No endpoint should acknowledge a poke until it durably records
both acceptance and dispatch work.

Apple team/bundle identity, Supabase projects, hosting region/budget, and physical
test devices remain external setup decisions. The GitHub remote is configured as
`irrssue/poki`; the old specification note about missing Git metadata was stale.
