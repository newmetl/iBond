# iBond

A 2D laser shooter for iOS, rebuilt from a 2011 idea with Swift + SpriteKit and a
custom physics engine. See `docs/superpowers/specs/` for the design.

## Controls
- **First finger** — tap to send the player circle somewhere; hold to make it follow.
- **Second finger** (while the first is down) — fires the laser from the player
  through your fingertip; move it to sweep the beam.

## Building
The Xcode project is generated, not checked in:

    brew install xcodegen   # once
    xcodegen                # writes iBond.xcodeproj
    open iBond.xcodeproj

Or build from the command line (requires iOS 17+ simulator):

    xcodebuild -project iBond.xcodeproj -scheme iBond \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

Engine unit tests (no simulator needed):

    swift test --package-path Packages/GameEngine
