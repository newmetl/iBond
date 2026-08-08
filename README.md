# Laser Taser

A 2D twin-stick stealth shooter for iOS. Rebuilt from a 2011 idea ("iBond" —
hence the repo name) with Swift, SwiftUI + SpriteKit, and a custom pure-Swift
physics/raycast engine. See `docs/superpowers/specs/` for design docs and
`CLAUDE.md` for development notes.

## The game

You are the cyan circle. Eliminate every enemy on a 3×3-screen scrolling map:

- **Shooters (red)** hide behind rocks. If one is on screen with a clear line
  to you, a green aim line locks on for 1.5s — then a green laser kills you.
- **Runners (purple)** wait until they first appear on screen, then chase you;
  a touch kills you.
- Your **laser battery** holds 2 seconds of firing. Spares lie on the map and
  drop from some shooters; collecting one refills you. An empty battery isn't
  game over — but you can't shoot until you find a spare.
- **Rocks** block movement and lasers. **Mirrors** block movement but reflect
  lasers — bank shots kill enemies behind cover, and a beam reflected into
  yourself kills you.

## Controls

- **Left stick** (lower-left): move; direction + deflection = velocity. Your
  facing (and therefore your aim) follows your movement.
- **Fire button** (lower-right): tap for a burst, hold for continuous fire.
  The beam fires along your current facing.

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

## Running on a device

Automatic signing is configured (`project.yml`). Build with
`-allowProvisioningUpdates` for a `platform=iOS` destination, then install and
launch with `xcrun devicectl` — exact commands in `CLAUDE.md`. With a free
Apple ID the install expires after ~7 days; rebuild and reinstall to renew.
