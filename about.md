# Poki

Poki is a tiny, iOS-only app for letting someone know you are thinking of them without starting a conversation. A poke sends a push notification to an accepted friend, optionally containing a very short message.

The product should feel immediate, personal, and quiet: choose a person, tap, and carry on with your day.

## Product direction

- One core function: poke another person.
- A very minimal interface, with as few screens and steps as possible.
- Short messages are optional; users should never need to think of something to write before sending a poke.
- Friend connections require acceptance so knowing a username alone does not allow unsolicited pokes.
- No pressure to reply, maintain a streak, or open a conversation.
- iOS only for the initial product.

## Main screen and visual reference

The supplied September 26, 2026 reference sketch defines the visual direction:

- A plain white background with generous empty space.
- A vertical list of light-gray, rounded friend containers near the top.
- A circular profile image on the left of each container. The black circles in the sketch represent friend profile photos or avatar placeholders.
- A minimal text-entry field beside each profile image.
- A small, black, pill-shaped navigation bar near the bottom, within the device's safe area.
- A star button on the left of the bottom bar and the user's own circular profile image on the right, separated by a thin vertical divider.

The three friend rows in the sketch are illustrative, not a three-friend limit. Additional friends can appear in a scrolling list. Keep the bottom bar available without covering the list or keyboard.

Avoid introducing a feed, dashboard, large headings, decorative cards, or a permanent message history. The friend list and bottom bar are the main experience.

## Friend rows and sending a poke

Each row represents one accepted Poki friend and contains their avatar and a short message field.

1. The user optionally enters a message next to the friend's avatar.
2. Tapping the row's non-editing area sends that person a poke with the entered message.
3. If the field is empty, send a default message such as "Thinking of you".
4. Give a small haptic and brief visual acknowledgement when the server accepts the poke.
5. Clear the draft after a successful send. Preserve it if sending fails.

The intended interaction is that the whole container acts as the poke target. The text field must remain an editing exception: tapping, selecting, or typing in it must never send a poke. Tapping the avatar or surrounding container area sends the poke, including while a draft is being edited. This resolves the overlap between an editable field and a tappable row without adding a large send button.

Show a compact friend name or username where needed to make recipients distinguishable, especially when profile images are missing or similar. The precise placement can be decided during design while preserving the reference's minimal appearance.

### Message length

The request describes a very short message, approximately 10 words or 30 characters. These are different limits; the working specification uses **30 visible characters maximum, including spaces and punctuation**, rather than a separate word limit.

- Apply the same limit to row messages and saved favorite messages.
- Count visible characters so emoji and combined characters behave sensibly.
- Keep messages on a single line and treat whitespace-only input as empty.
- Show a subtle remaining-character count only while editing if needed.
- Do not silently truncate pasted text or send text that differs from what the user sees.
- Validate the limit on both the app and server.

Example messages: "Thinking of you", "Miss you", "Coffee later?", and "You crossed my mind".

## Favorite person: the star button

The star is a customizable one-tap poke button, not a separate favorites screen in normal use.

### First-time setup

1. Tap the unconfigured star.
2. Choose one accepted friend as the favorite person.
3. Enter and save a required preset message of up to 30 characters.
4. Confirm the selected person and message during setup.

### Everyday use

- Tapping the configured star immediately pokes the saved person with the saved message.
- No typing, recipient selection, or confirmation dialog is required for each poke.
- Give the same subtle send feedback used for friend rows.
- Provide favorite configuration in the profile/settings area so the user can change the person or message, or clear the favorite.
- If the connection is removed or blocked, stop allowing sends and prompt the user to configure a valid favorite on the next tap.

The star's accessible label should identify the recipient and action, for example, "Poke Sam".

## Own profile and secondary screens

The right-hand circle in the bottom navigation bar opens the current user's profile. This is the entry point for everything outside the main poke interaction:

- Profile photo, display name, and unique username.
- Finding people by username and sharing an invite link.
- Incoming friend requests, outgoing requests, and accepted friends.
- Accepting or declining requests and removing friends.
- Favorite person and preset-message configuration.
- Notification preferences and muted or blocked people.
- Account settings, sign out, and account deletion.
- Help and privacy information.

Keep these functions grouped inside the profile area so the main screen stays sparse.

## Onboarding and friend connections

1. Create an account using Sign in with Apple and choose a unique username; see the implementation plan below.
2. Add an optional profile photo and display name.
3. Explain why notifications matter and request notification permission in context.
4. Find a registered user by username or share an invite link.
5. Send a friend request; pokes become available after acceptance.
6. Optionally configure the star and add a Home Screen widget.

The first-run empty state should offer one clear action to add a friend. A pending request is not an active poke target. If notifications are disabled, explain how to enable them without repeatedly interrupting the user.

## Recipient notification

A poke notification identifies the sender and includes the short message:

> **Alex poked you**
>
> Thinking of you

- Use the custom row message, the favorite's saved message, or the default message as appropriate.
- Offer a "Poke back" notification action using a default reply, without requiring a conversation or typed response.
- Opening the notification should lead to the relevant friend in the app.
- Respect iOS notification permissions, Focus settings, and preview preferences.
- Server acceptance does not prove the recipient saw or received a visible notification. Do not label a poke as read or promise immediate delivery.

## iOS interaction constraints

The original idea included tapping the app icon to send a poke without opening the app, or opening a Dynamic Island-style form. The implementation direction is:

- A normal app-icon tap opens the minimal main screen. Do not send a poke automatically merely because the app launches.
- An interactive Home Screen widget can offer a direct poke action without navigating into the app, using an App Intent. A widget for the configured favorite person is the natural first extension.
- Dynamic Island is not a general-purpose username-and-message input form. Do not make that interaction a requirement or use a persistent Live Activity solely as an app launcher.
- If desired later, a brief pill-shaped confirmation can appear inside the app, visually inspired by the reference's minimal style.
- The app must work on supported iPhones without Dynamic Island.

Apple references:

- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

## Small safeguards and accessibility

- Require an accepted connection before sending; enforce this on the server.
- Include mute, block, and unfriend controls in the profile area.
- Use a short send cooldown and server-side rate limits to prevent repeated accidental taps or spam. Exact limits remain to be chosen.
- Prevent duplicate sends while a request is in flight; retries must not create duplicate pokes.
- If offline, show a brief failure and allow an explicit retry. Avoid silently delivering an old poke much later.
- Use sufficiently large tap targets, VoiceOver labels, readable contrast, and Dynamic Type support.
- Never rely on avatar appearance, color, or haptics alone to communicate recipient identity or sending state.

## Initial scope

The first usable release includes accounts, accepted friend connections, the minimal friend list, optional short messages, notification delivery, the configurable star, profile/settings, and basic mute/block and rate limiting. Include notification poke-back and a favorite-person widget when the core send flow is reliable; they support the same single purpose.

Do not add chat threads, a social feed, read receipts, online status, typing indicators, streaks, leaderboards, media attachments, or group conversations to the initial release.

## Engineering direction and project status

**Implementation baseline: September 26, 2026.** A local SwiftUI prototype now covers the friend list, safe message editing, simulated poke feedback, favorite configuration, and the profile shell. The service remains simulated; authentication, friend synchronization, APNs delivery, account management, and the widget are not implemented yet. Preserve the product behavior above while building in small, testable increments.

Build a native iOS app backed by one small backend codebase and managed infrastructure. The main technical risks are accidental sends, authorization between friends, duplicate requests, and unreliable notification delivery. Prove those flows before polishing secondary screens.

### Languages and frameworks

| Area | Planned choice | Reason |
| --- | --- | --- |
| iOS language | Swift 6, with strict concurrency checking | Native Apple integration and explicit handling of asynchronous work. |
| UI | SwiftUI, Observation, and structured concurrency (`async`/`await`) | A small interface with predictable screen state and little infrastructure. |
| Minimum OS | iOS 17, provisionally | Supports the planned interactive widget; test on both the minimum and current supported iOS releases. |
| Authentication | AuthenticationServices for native Sign in with Apple; Supabase Auth with its Swift SDK | Avoid building password management and keep an authenticated identity across devices. |
| App networking | URLSession with Codable request/response models | A straightforward typed client for the Poki API. |
| Backend | TypeScript in strict mode, Node.js LTS, Fastify | One maintainable service for authorization, validation, database transactions, and push delivery. |
| Database | Supabase-managed PostgreSQL, SQL migrations, and the `pg` Node driver | Friendship rules, uniqueness, and idempotency benefit from relational constraints and transactions. |
| Avatar storage | Supabase Storage in a private bucket | Keep image files outside the database and control who can access them. |
| Push delivery | UserNotifications on iOS; direct APNs HTTP/2 requests from the backend | Native notifications without another push broker. |
| Widget | WidgetKit and App Intents | A small favorite-person action sharing the app's send client. |
| Dependencies | Swift Package Manager for iOS; npm with a committed lockfile for the backend | Reproducible dependency resolution with few tools. |
| Verification | XCTest/XCUITest for iOS; Node's test runner and Fastify injection for the API; real PostgreSQL integration tests | Cover interaction mistakes and permission failures at their actual boundaries. |
| Automation | GitHub Actions, with macOS jobs for iOS and Linux jobs for the backend | Build, type-check, and verify changes consistently. |

These are project recommendations, not a claim that tooling is installed or accounts are configured. Pin compatible stable toolchain and dependency versions during setup. The deployment target and the Xcode/SDK required to submit the app are separate choices; verify current submission requirements before release.

SwiftUI is the preferred fit because the initial product is entirely iOS-specific, including widgets, notification actions, accessibility, and haptics. PostgreSQL keeps permission rules explicit. Supabase supplies authentication, storage, and database hosting; custom behavior lives in the small Node service. The API and push worker share one codebase and database. A dedicated worker process is needed to dispatch queued pushes reliably; it is not a separate business service.

Supporting documentation: [Supabase's Swift integration](https://supabase.com/docs/guides/getting-started/tutorials/with-swift), [native Sign in with Apple](https://supabase.com/docs/guides/auth/social-login/auth-apple), [Fastify with TypeScript](https://fastify.dev/docs/latest/Reference/TypeScript/), and [Apple's interactive widget model](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).

## Planned project structure

Keep the app, backend, database migrations, and contracts together in one repository:

```text
poki/
├── about.md                         # Product specification and delivery plan
├── ios/
│   ├── Poki.xcodeproj/               # App, widget, and test targets
│   ├── Poki/
│   │   ├── App/                     # Entry point, dependencies, navigation
│   │   ├── Features/
│   │   │   ├── Onboarding/          # Apple sign-in, username, permissions
│   │   │   ├── Friends/             # Main list, row drafts, send feedback
│   │   │   ├── Connections/         # Lookup and request management
│   │   │   ├── Favorite/            # Star setup and editing
│   │   │   └── Profile/             # Settings, privacy controls, deletion
│   │   ├── UI/                      # Shared controls, spacing, accessibility
│   │   └── Resources/               # Assets and localized strings
│   ├── Packages/PokiCore/           # Shared models, validation, API/session client
│   ├── PokiWidget/                  # Favorite widget and App Intent
│   ├── PokiTests/                   # State and domain tests
│   └── PokiUITests/                 # Sending versus editing interaction tests
├── backend/
│   ├── src/
│   │   ├── app.ts                   # Fastify composition without starting a port
│   │   ├── server.ts                # API process entry point
│   │   ├── worker.ts                # Push dispatch and scheduled cleanup
│   │   ├── modules/                 # Profiles, connections, favorites, pokes, devices
│   │   ├── auth/                    # JWT verification and caller identity
│   │   ├── db/                      # Parameterized queries and transactions
│   │   └── push/                    # APNs transport, token lifecycle, retries
│   ├── tests/                       # API, permissions, transaction integration tests
│   ├── package.json
│   └── tsconfig.json
├── supabase/
│   ├── config.toml                  # Local service configuration
│   ├── migrations/                  # Schema, constraints, grants, policies
│   └── seed.sql                     # Synthetic development data only
├── contracts/
│   ├── openapi.yaml                 # HTTP schemas, errors, authentication
│   └── message-fixtures.json        # Shared Unicode validation examples
├── docs/
│   ├── decisions/                  # Short records of significant tradeoffs
│   └── operations.md               # Environments, secrets, deployment, recovery
└── .github/workflows/               # Build and verification automation
```

This tree is an outline; create each directory when its first implementation exists. Do not add empty layers merely to match the diagram.

### App boundaries and state

Use feature-oriented SwiftUI views with small observable, main-actor-isolated state models. Views render state and forward actions; the shared API client handles transport, session refresh, and error decoding. Inject dependencies so previews and tests can use deterministic substitutes.

A friend row has explicit idle, editing, sending, accepted, and failed states. Keep drafts in memory per friend. Disable repeated submission while sending, and clear a draft only after server acceptance. Avoid gesture handlers wrapping the editable field; make the avatar and non-editing surface accessible buttons with shared send behavior.

Keep session credentials in Keychain. Use an App Group for a minimal widget snapshot and a shared Keychain access group for authorized session access. Validate session refresh and device-lock behavior on hardware before shipping the widget. Never put credentials in widget timelines or ordinary preferences. Local caches are disposable; the backend remains authoritative for permissions and favorites.

## Backend design and data ownership

### Request and notification flow

```text
SwiftUI app / notification action / widget
    → HTTPS Poki API with authenticated user and idempotency key
    → PostgreSQL transaction: permissions + limits + poke + outbox record
    → API acknowledges server acceptance
    → worker checks current permissions and expiration
    → APNs → recipient's registered iPhone(s)
```

The app authenticates through Supabase Auth. All social reads and writes go through the Poki API so username lookup, authorization, and abuse controls have one boundary. The API verifies JWT signatures against the configured issuer's keys, including expiration, issuer, and audience; it derives the acting user from the token, never from a caller-supplied sender ID.

Keep application tables in a schema excluded from the public Supabase Data API. Grant the backend a restricted database role and enable deny-by-default row-level security for any client-exposed tables. Privileged service credentials bypass normal client protections, so backend authorization must be explicit and tested. Avatar uploads use narrowly scoped signed upload access; reads are authorized for the owner and accepted friends. Apply size/type limits and re-encode uploads to strip metadata before making them available.

### Core tables

| Table | Responsibility and constraints |
| --- | --- |
| `profiles` | Auth user ID, unique normalized username, optional display name/avatar reference. Start with lowercase ASCII usernames of 3–20 letters, digits, or underscores. |
| `connections` | One row per unordered pair, with requester, pending/accepted status, and timestamps. Reject self-connections; only the recipient can accept. Decline or removal deletes the relationship. |
| `blocks` | Directional owner/blocked-user pair. A block in either direction prevents requests and sends; blocking removes the connection and invalidates associated favorites. Unblocking does not restore friendship. |
| `mutes` | Directional recipient/sender pair. Suppresses pushes without revealing the mute to the sender. |
| `favorites` | One record per owner, containing an accepted friend's ID and required preset message. Invalidate when the relationship ends. |
| `devices` | Owner, installation ID, APNs token, topic/environment, enabled state, and last registration time. Refresh on token changes; remove on sign-out or permanent token rejection. |
| `pokes` | Server ID, sender, recipient, temporary message payload, creation/expiration time, and submission status. Not a user-visible history. |
| `idempotency_keys` | Unique sender/key pair, request digest, original response, and expiration. Reject the same key with different content. |
| `push_jobs` | Transactional outbox entries with device, poke ID, attempts, lease, next attempt, and terminal state. Unique per poke/device. |
| `rate_limit_buckets` | Atomic counters shared across API instances; do not rely on process memory. |

Use database uniqueness and transactional locks for connection transitions, limits, and idempotency. Simultaneous requests must not create duplicate friendships or exceed send limits. Use a consistent lock order for friendship/block/send operations. Recheck connection and device ownership before dispatch; a push already handed to APNs cannot be recalled.

### Initial API outline

All routes use `/v1`. Except for health endpoints and the limited invite landing page, requests require a valid session.

| Area | Routes and behavior |
| --- | --- |
| Profile | `GET/PATCH /me`; `DELETE /me` starts account deletion after recent authentication. |
| Discovery | `GET /users/lookup?username=...` for exact matches; return minimal identity information and rate-limit enumeration. |
| Invites | `POST /invites`; `POST /invites/:token/redeem` creates a request after explicit user action, never an accepted connection. |
| Connections | `GET /connections`; `POST /friend-requests`; `POST /friend-requests/:id/accept`; `DELETE /friend-requests/:id`; `DELETE /connections/:id`. |
| Controls | `PUT/DELETE /blocks/:userId`; `PUT/DELETE /mutes/:userId`; `PATCH /me/notification-preferences`. |
| Favorite | `GET/PUT/DELETE /me/favorite`; server checks the selected relationship and message. |
| Devices | `PUT /devices/:installationId`; `DELETE /devices/:installationId`, scoped to the authenticated owner. |
| Pokes | `POST /pokes` accepts a recipient and optional message, or a favorite-send mode resolved on the server; requires `Idempotency-Key`. |

Document request/response schemas, stable error codes, and pagination in OpenAPI before building clients. Use consistent errors for invalid messages, unavailable connections, expired sessions, and cooldowns. Include `Retry-After` on rate-limit responses. Return an opaque poke ID and `accepted` state on successful submission; do not return a delivery claim.

Invite links need a configured HTTPS domain, Universal Links association, expiring tokens, and a small fallback page. Use opaque tokens without personal data, store only token hashes, and validate again after sign-in. If installation interrupts the link flow, users can reopen the link or use the displayed username; automatic deferred linking is outside the initial scope.

### Message validation and send reliability

- Treat messages as Unicode extended grapheme clusters: use Swift `String.count` and JavaScript `Intl.Segmenter` with grapheme granularity. Share fixtures for emoji, flags, skin tones, combining marks, and boundary lengths; different runtime Unicode versions must be tested for agreement.
- Reject line breaks and disallowed control characters. Preserve visible text; whitespace-only row input selects the default. Favorite messages must contain non-whitespace text. Validate again on the server without silent truncation.
- Assign one UUID idempotency key to each deliberate send. Retry an uncertain request using that same key and payload; an edited or deliberately new send gets a new key.
- Atomically record acceptance and push work before responding. If the response is lost, repeating the request returns its existing acceptance without enqueueing another poke.
- Start with a 5-second sender/recipient cooldown, 20 pokes per sender per minute, and 200 per day, subject to beta tuning. Apply separate request and lookup limits. Enforce counters transactionally using server time.
- Expire pending push work after 60 seconds and set a matching APNs expiration. Retry transient failures with bounded backoff only within that window; do not resurrect an expired poke. APNs expiration is best effort, not a strict delivery-time guarantee. [Apple APNs request documentation](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)
- API idempotency prevents duplicate submissions. It does not guarantee exactly-once visible notification delivery: a worker can lose acknowledgment after APNs accepts a request. Track attempts and choose conservative retry behavior for ambiguous outcomes during the notification spike.
- When offline, retain the draft and offer an explicit retry. Do not persist a client send queue. A muted recipient still produces the same generic acceptance response, with no push job.

### Privacy and operational defaults

Proposed retention: remove message payloads when dispatch reaches a terminal outcome, with a hard cleanup target of 24 hours; retain content-free submission/idempotency metadata for 7 days, and sanitized operational logs for 14 days. Clients must not replay queued requests; expire old submission attempts in the API contract so a retry outside the retention window cannot become a new send. Store no message bodies, auth tokens, or APNs tokens in logs. Backups and provider retention must be reconciled with the published deletion policy before launch.

Account deletion immediately disables the account and device delivery, then removes profile/avatar, relationships, favorites, active poke content, and authentication identity through a retryable server workflow. Verify Apple authorization revocation and recent-authentication requirements during implementation. Include a support/reporting route for unwanted user content before the public beta.

Use separate development, staging, and production configurations. Keep APNs keys, database credentials, and service credentials in server secret storage. Start with one containerized API process and one worker process near the database; select the hosting vendor after confirming budget and region. Track acceptance latency, expired jobs, APNs errors, and authorization failures using content-free metrics. Document migration recovery and verify a backup restore before launch.

## Project plan

The release target is a **two-week App Store submission candidate**. This assumes one experienced developer, immediate access to Apple/Supabase accounts, a Mac with the current stable Xcode, two test iPhones, and prompt product decisions. App Review happens after submission and is outside the two-week engineering window. Protect the core poke flow and cut optional work when a release-blocking task slips.

| Day | Work | Exit condition |
| --- | --- | --- | --- |
| 1 | Install/select Xcode, generate the project, assign the final bundle ID/team, connect GitHub, run the prototype, and create development/staging Supabase projects. | App runs on a physical iPhone; CI builds the shared package; secrets and identifiers are documented. |
| 2–3 | Implement Sign in with Apple, username setup, profiles, device registration, and the first schema/API migration. | Two device accounts authenticate and retain sessions safely. |
| 4–5 | Implement exact username lookup and request/accept/decline/remove, plus minimum block and report controls. | Only accepted, unblocked friends appear as poke targets. |
| 6–7 | Replace simulated sends with transactional poke/idempotency/outbox endpoints and real APNs delivery. | Two physical devices complete the end-to-end poke flow without duplicate sends. |
| 8 | Connect favorite persistence to the backend and complete notification permission guidance, offline errors, token refresh, and sign-out cleanup. | Normal and favorite sends have honest success/failure behavior across session states. |
| 9 | Add account deletion, privacy/support content, rate limits, data cleanup, accessibility fixes, and required App Store privacy disclosures. | Release compliance and safety checklist passes. |
| 10 | Run regression tests on physical devices, create screenshots/metadata, archive, upload, and distribute a final TestFlight build. | The exact release candidate passes smoke tests and has no critical defects. |

The two-week release excludes the widget, notification poke-back action, invite links, avatar uploads, advanced notification preferences, and broad UI polish unless the release candidate is stable early. Those features move to the first post-launch update. Keep every day demonstrable with a short end-to-end walkthrough.

### Verification priorities

1. **Authorization:** pending, removed, blocked, forged-sender, cross-account device, and direct database/storage requests fail safely; lookup and request endpoints resist enumeration and flooding.
2. **Correctness under races:** simultaneous accepts, block-versus-send, parallel rate-limit checks, repeated idempotency keys, and worker restarts preserve database invariants.
3. **Editing behavior:** field focus, selection, paste, keyboard dismissal, and accessibility actions cannot accidentally send; avatar/container sends target the correct friend.
4. **Reliability:** lost API responses, expired sessions, invalid push tokens, no registered devices, APNs failures, and offline retries produce honest states without stale queued sends.
5. **Text parity:** app and server agree on the 30-character limit, empty input, emoji, and single-line rules using the same fixtures.
6. **Device experience:** test notifications and actions on physical devices across foreground/background/terminated states, Focus, denied permissions, large text, VoiceOver, and signed-out widgets.
7. **Data lifecycle:** verify payload cleanup, mute behavior, unfriend/block invalidation, account deletion retries, and the handling of retained backups.

### First implementation backlog

- [ ] Identify the intended GitHub remote; this folder currently has no Git metadata or configured remote.
- [ ] Confirm the bundle ID, Apple Developer team, app name availability, and two-device test access.
- [x] Create the SwiftUI app and shared Swift package with a mock friend list matching the reference.
- [ ] Create the Fastify service with strict TypeScript configuration and environment validation.
- [ ] Write the initial SQL migration and OpenAPI contract, including connection and idempotency constraints.
- [ ] Add local setup instructions and CI builds/checks.
- [ ] Demonstrate Sign in with Apple and one real staging push before expanding UI scope.
- [ ] Deliver the smallest complete flow: authenticate two users → request → accept → poke → receive notification.

### Decisions still open

The implementation baseline above selects the stack and authentication method. Remaining setup/product decisions are the GitHub repository, bundle ID/team, hosting budget and region, invite domain, avatar limits, and final release distribution. Validate the provisional iOS 17 target, rate limits, retry policy, and retention settings during Phase 0 and beta. Keep the beta free; revisit monetization only after the core interaction is validated. Do not add payments, chat, analytics SDKs, or additional infrastructure without a concrete need.

## Success criteria

- After setup, a favorite poke takes one tap.
- Sending a normal poke requires no text input unless the user wants a custom message.
- Editing a message never accidentally sends it.
- Every send clearly identifies the intended recipient and gives honest success or failure feedback.
- The recipient can understand the gesture from the notification alone.
- The app feels like a small moment of connection, with no obligation to reply.
