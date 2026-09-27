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
