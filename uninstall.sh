#!/usr/bin/env bash
# Removes BitChord Desktop's server, autostart entry and installed files.
set -euo pipefail
case "$(uname -s)" in
  Darwin) APP_HOME="${BITCHORD_HOME:-$HOME/Library/Application Support/BitChord}"
          launchctl bootout "gui/$(id -u)/com.bitchord.desktop" 2>/dev/null || true
          rm -f "$HOME/Library/LaunchAgents/com.bitchord.desktop.plist" ;;
  Linux)  APP_HOME="${BITCHORD_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/bitchord}"
          systemctl --user disable --now bitchord.service 2>/dev/null || true
          rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/bitchord.service" ;;
esac
rm -rf "$APP_HOME"
echo "Removed. Also remove the BitChord extension from chrome://extensions."
