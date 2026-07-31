#!/bin/bash
# Claude Pet installer.
#
#   ./install.sh
#
# Copies the pet into ~/.hammerspoon, the hook into ~/.claude/hooks, and wires
# the hook into ~/.claude/settings.json without disturbing hooks already there.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HS_DIR="$HOME/.hammerspoon"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "==> Checking Hammerspoon"
if [ ! -d "/Applications/Hammerspoon.app" ]; then
  echo "    Hammerspoon not found. Installing via Homebrew..."
  brew install --cask hammerspoon
else
  echo "    already installed"
fi

echo "==> Installing pet into $HS_DIR"
mkdir -p "$HS_DIR/claudepet/assets"
cp "$REPO"/hammerspoon/claudepet/*.lua "$HS_DIR/claudepet/"
cp "$REPO"/hammerspoon/claudepet/assets/pet.png "$HS_DIR/claudepet/assets/"

if [ -f "$HS_DIR/init.lua" ] && ! grep -q 'require("claudepet")' "$HS_DIR/init.lua"; then
  echo "    appending to your existing init.lua"
  {
    echo ""
    echo "-- Claude Pet"
    echo 'claudepet = require("claudepet")'
    echo "hs.allowAppleScript(true)"
  } >> "$HS_DIR/init.lua"
elif [ ! -f "$HS_DIR/init.lua" ]; then
  cp "$REPO/hammerspoon/init.lua" "$HS_DIR/init.lua"
fi

echo "==> Installing hook into $CLAUDE_DIR/hooks"
mkdir -p "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/pet"
cp "$REPO/hooks/claude-pet.sh" "$CLAUDE_DIR/hooks/"
chmod +x "$CLAUDE_DIR/hooks/claude-pet.sh"

echo "==> Wiring hooks into settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"

python3 - "$SETTINGS" <<'PY'
import json, sys

path = sys.argv[1]
with open(path) as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})
WIRING = [
    ("Stop", None, "done"),
    ("SessionEnd", "*", "end"),
    ("Notification", "idle_prompt", "idle"),
]

for event, matcher, kind in WIRING:
    command = 'bash "$HOME/.claude/hooks/claude-pet.sh" %s' % kind
    groups = hooks.setdefault(event, [])

    already = any(
        "claude-pet.sh" in hook.get("command", "")
        for group in groups
        for hook in group.get("hooks", [])
    )
    if already:
        print("    %s: already wired" % event)
        continue

    target = None
    for group in groups:
        if matcher is None or group.get("matcher") in (matcher, "*", None):
            target = group
            break

    if target is None:
        target = {"hooks": []}
        if matcher:
            target["matcher"] = matcher
        groups.append(target)

    target.setdefault("hooks", []).append({"type": "command", "command": command})
    print("    %s: wired" % event)

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PY

echo "==> Launching Hammerspoon"
open -a Hammerspoon

echo "==> Setting Hammerspoon preferences"
# The config enables the AppleScript bridge on load, so wait for it to come up.
for _ in $(seq 1 15); do
  if osascript -e 'tell application "Hammerspoon" to execute lua code "return 1"' >/dev/null 2>&1; then
    osascript -e 'tell application "Hammerspoon" to execute lua code "
      hs.autoLaunch(true)      -- survive reboots
      hs.dockIcon(false)       -- lives in the menu bar, not the dock
      hs.menuIcon(true)        -- keep the hammer icon reachable
      hs.consoleOnTop(false)
      return 1
    "' >/dev/null 2>&1
    echo "    launch at login: on, dock icon: off"
    break
  fi
  sleep 1
done

cat <<'DONE'

Installed.

  • The pet is on the right edge of your screen — drag it anywhere.
  • Click him for the menu: personality, bubble detail, themes, hide, quit.
  • Menu bar icon (top right) or ⌃⌥⌘P to hide/show.
  • Next time any Claude Code session finishes, he speaks.

Launch-at-login is on, so he comes back after a reboot.
No macOS permissions are required — ignore Hammerspoon's Accessibility warning.
DONE
