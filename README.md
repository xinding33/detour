# Detour

Turns Tailscale off while chosen apps are open and back on when they quit.

<!-- One paragraph: what it does, and why you'd want it. -->

## Install

```sh
brew install --cask xinding33/tap/detour
```

Or download `Detour-x.y.z.zip` from the [latest release](https://github.com/xinding33/detour/releases/latest),
unzip it and move `Detour.app` to Applications. It needs macOS 14 or later.

<!-- Permissions: name each one, why it's needed, and what happens without it. -->

### Updating

Detour checks for a new release once a day and installs it. Turn that off with
**Install Updates Automatically** in its menu, or use **Check for Updates…**. `brew upgrade`
leaves it alone, because it updates itself.

## Use

<!-- The menu, shortcuts, settings. -->

## How it works

<!-- The system APIs it relies on, and anything that isn't a documented API. -->

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

<!-- What it doesn't do, and what can break across macOS versions. -->

## Development

Detour was developed with AI assistance.

## License

Copyright 2026 Xin Ding. Licensed under the [Apache License, Version 2.0](LICENSE).
