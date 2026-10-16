# Detour

Turns Tailscale off while chosen apps are open and back on when they quit.

Some apps want the shortest path to the internet. GeForce NOW streams games, and a VPN in the way
adds latency. Detour sits in the menu bar, turns Tailscale off while any app you choose is open,
and turns it back on a few seconds after the last one quits. It only undoes what it did: if
Tailscale was already off, it stays off, and if you turn it back on mid-game, Detour leaves it
alone.

## Install

```sh
brew install --cask xinding33/tap/detour
```

Or download `Detour-x.y.z.zip` from the [latest release](https://github.com/xinding33/detour/releases/latest),
unzip it and move `Detour.app` to Applications. It needs macOS 14 or later.

Detour needs no permissions. It needs the standalone Tailscale app from
[tailscale.com](https://tailscale.com/download/mac), logged in.

### Updating

Detour checks for a new release once a day and installs it. Turn that off with
**Install updates automatically** in Settings, or use **Check for Updates** there. `brew upgrade`
leaves it alone, because it updates itself.

## Use

The menu bar icon shows what Detour is doing:

| Icon | Meaning |
|---|---|
| Straight arrow | Watching. Tailscale is left alone. |
| Bent arrow | Tailscale is off because a watched app is open, or is about to come back on. |
| Dimmed arrow with pause bars | Paused. |
| Dimmed arrow with "!" | Detour can't control Tailscale (not installed, not running or logged out). |

The menu says what's happening and offers **Pause Detour** (for an hour, or until you resume).
Pausing while Tailscale is off because of Detour turns it back on. Quitting Detour does too.

**Settings…** has the list of apps (matched by bundle identifier), how long to wait after the
last one quits before turning Tailscale back on (10 seconds by default, so a relaunch doesn't make
it flap), Open at Login, and updates. The Add Apps sheet suggests installed games and streaming
apps and lists the apps open now.

## How it works

- NSWorkspace's launch and quit notifications say when a watched app opens or quits. An app
  counts as open while it's running, even idle in the background.
- Tailscale's own CLI, inside the app bundle, does the rest: `tailscale status --json` every few
  seconds, `tailscale down` to turn it off and a bare `tailscale up` to turn it back on. A bare
  `up` only flips Tailscale's on switch, so exit nodes, routes and DNS settings stay as they were.
- Before turning Tailscale off, Detour records that it did in
  `~/Library/Application Support/Detour/session.json`. After a crash, logout or restart it turns
  Tailscale back on at launch if no watched app is open.

`Detour --diagnose` prints Tailscale's state, the watched apps and the saved session.
`Detour --snapshot DIR` renders the icons, menu text and Settings to PNGs without touching
Tailscale.

## Build

```sh
swift test
bash scripts/build.sh   # dist/Detour.app
```

`build.sh` signs with this Mac's Developer ID certificate if it has one, so permissions you grant
survive rebuilds. Otherwise it signs ad hoc, and macOS asks again after each build. Builds from
source never update themselves.

### Release

Push a `v` tag, e.g. `git tag v0.1.0 && git push origin v0.1.0`. The release workflow tests, signs,
notarizes and publishes `Detour-0.1.0.zip`, then updates the cask in
[xinding33/homebrew-tap](https://github.com/xinding33/homebrew-tap). To make a release on this Mac
instead, run `scripts/release.sh`.

## Limitations

- Only the standalone Tailscale app is supported, not the Mac App Store build.
- Only native apps. GeForce NOW in a browser tab isn't detected.
- Tailscale is turned off entirely, not just bypassed for one app.

## Development

Detour was developed with AI assistance.

## License

Copyright 2026 Xin Ding. Licensed under the [Apache License, Version 2.0](LICENSE).
