#!/bin/bash
# Writes the detour cask for a release into a homebrew-tap checkout. The release workflow runs
# this, and it rewrites the whole file, so change the cask here rather than in the tap.
# Usage: scripts/update-cask.sh TAP_DIR VERSION SHA256
#
# Detour updates itself, so the cask says `auto_updates true` and `brew upgrade` leaves it alone.
# Keep it that way from the first release: adding it later strands installs that can't update.
set -euo pipefail
TAP="$1" VERSION="$2" SHA="$3"
mkdir -p "$TAP/Casks"
cat > "$TAP/Casks/detour.rb" <<CASK
cask "detour" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/xinding33/detour/releases/download/v#{version}/Detour-#{version}.zip"
  name "Detour"
  desc "Turns Tailscale off while chosen apps are open and back on when they quit"
  homepage "https://github.com/xinding33/detour"

  auto_updates true
  depends_on macos: :sonoma

  app "Detour.app"

  uninstall launchctl: "io.github.xinding33.detour",
            quit:      "io.github.xinding33.detour"

  zap trash: [
    "~/Library/Application Support/Detour",
    "~/Library/LaunchAgents/io.github.xinding33.detour.plist",
    "~/Library/Logs/Detour",
    "~/Library/Preferences/io.github.xinding33.detour.plist",
  ]
end
CASK
