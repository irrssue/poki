# Poki

Poki is an iOS app for sending a small “thinking of you” notification to an accepted friend without starting a conversation.

## Current prototype

The current app is a local SwiftUI prototype. It includes a friend list, safe tap-to-poke controls, 30-character message drafts, a configurable favorite person, send feedback, and basic profile/settings screens. Sends use a simulated service until the API and APNs integration are connected.

## Local setup

1. Install the current stable Xcode release and select it with `xcode-select`.
2. Install XcodeGen: `brew install xcodegen`.
3. Run `xcodegen generate` from the repository root.
4. Open `Poki.xcodeproj`, select an Apple development team, and run the `Poki` scheme on an iOS 17 or newer simulator or device.

The shared domain package can be compiled with the command-line tools:

```sh
cd ios/Packages/PokiCore
swift build
```

Run unit tests from the generated Xcode project after Xcode is installed; Apple's command-line tools alone do not include the XCTest runtime on this machine.

The bundle identifier in `project.yml` is provisional and must be replaced before signing or App Store submission.

## Backend foundation

The Fastify service currently exposes only `GET /v1/health`. It reports process
liveness, not database readiness or push delivery. The iOS app still uses simulated
sends. No social endpoint accepts unauthenticated or simulated production writes.

Use Node **24.21.0**, pinned in `backend/.node-version`, then:

```sh
cd backend
npm ci
cp .env.example .env
npm run dev
```

Check the running service with `curl http://127.0.0.1:3000/v1/health`.
It returns `{"status":"ok"}`. For a compiled run, use `npm run build` followed by
`npm start`. Both entry points load an optional `.env`; existing environment
variables take precedence. Stop with Ctrl-C or SIGTERM.

Configuration is validated before opening a port:

| Variable | Default | Values |
| --- | --- | --- |
| `NODE_ENV` | `development` | `development`, `test`, `production` |
| `HOST` | `127.0.0.1` | IP address or `localhost`; use `0.0.0.0` in a container |
| `PORT` | `3000` | Integer from 1 to 65535 |
| `LOG_LEVEL` | `info` | `fatal`, `error`, `warn`, `info`, `debug`, `trace`, `silent` |

Do not commit `.env` files. No Supabase, database, or APNs secrets are required for
this foundation. Add validation for those settings alongside their integrations.
Request URLs, headers, bodies, and raw errors are excluded from service request
logs. Startup errors intentionally omit raw details; check the configuration
above and whether the port is already occupied.

```sh
npm run typecheck
npm test
```

Tests use Node's test runner and Fastify injection without external services.
GitHub Actions runs backend checks and shared Swift package/app tests on macOS.
The API contract lives in `contracts/openapi.yaml`; the full implementation review
and next boundary are in [docs/project-status.md](docs/project-status.md).

Runtime references: [Fastify TypeScript](https://fastify.dev/docs/latest/Reference/TypeScript/)
and [Node release schedule](https://github.com/nodejs/Release).
