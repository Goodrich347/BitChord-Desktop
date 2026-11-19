#!/usr/bin/env bash
# BitChord Desktop installer: builds the BitChord web player + its browser
# extension from the upstream repo (pinned), applies this repo's patches and
# serves it locally on http://localhost:5173 (the origin the extension trusts).
# macOS and Linux. Re-run any time to update/rebuild.
set -euo pipefail

UPSTREAM="${BITCHORD_UPSTREAM:-https://github.com/kushagrasinghx/BitChord.git}"
COMMIT="${BITCHORD_COMMIT:-acf219a7e4a7f52f026d4336d5c7ac5cf7bfafcc}"   # upstream main, v1.9.1
PNPM_VERSION="12.11.2"
PORT=5173
PARTY_URL="${VITE_PARTY_SERVER_URL:-https://api.bitchord.kushagrasingh.in}"

HERE="$(cd "$(dirname "$0")" && pwd)"
case "$(uname -s)" in
  Darwin) OS=mac;   DEFAULT_HOME="$HOME/Library/Application Support/BitChord" ;;
  Linux)  OS=linux; DEFAULT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/bitchord" ;;
  *) echo "Unsupported OS. On Windows use WSL, or follow the manual steps in README." >&2; exit 1 ;;
esac
APP_HOME="${BITCHORD_HOME:-$DEFAULT_HOME}"
# Our own temp dir is removed whole; a user-given BITCHORD_BUILD_DIR only loses what we put in it.
if [ -n "${BITCHORD_BUILD_DIR:-}" ]; then BUILD="$BITCHORD_BUILD_DIR"; OWN_BUILD=; else BUILD="$(mktemp -d "${TMPDIR:-/tmp}/bitchord-build.XXXXXX")"; OWN_BUILD=1; fi
say() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }
cleanup() {
  [ -z "${BITCHORD_KEEP_BUILD:-}" ] || return 0
  if [ -n "$OWN_BUILD" ]; then rm -rf "$BUILD"; else rm -rf "$BUILD/src"; fi
}
trap cleanup EXIT

# 1. Requirements
command -v git >/dev/null || die "git is required."
command -v node >/dev/null || die "Node.js 22+ is required (https://nodejs.org or: brew install node)."
command -v python3 >/dev/null || die "python3 is required (it runs the tiny local server)."
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 22 ] || die "Node.js 22+ is required (found $(node -v))."
PNPM=(npx --yes "pnpm@$PNPM_VERSION")

# 2. Source
say "Fetching BitChord ($COMMIT) into $BUILD"
mkdir -p "$BUILD"
rm -rf "$BUILD/src"
git -C "$BUILD" init -q src
git -C "$BUILD/src" remote add origin "$UPSTREAM"
git -C "$BUILD/src" fetch -q --depth 1 --filter=blob:limit=5m origin "$COMMIT"
git -C "$BUILD/src" sparse-checkout set web
git -C "$BUILD/src" checkout -q FETCH_HEAD

# 3. Patches
for p in "$HERE"/patches/*.patch; do
  say "Applying $(basename "$p")"
  git -C "$BUILD/src" apply --whitespace=nowarn "$p" || die "Patch $(basename "$p") does not apply to $COMMIT."
done

# 4. Build
say "Installing dependencies (~560 MB, build-time only)"
"${PNPM[@]}" --dir "$BUILD/src/web" install --frozen-lockfile
WEB="$BUILD/src/web"
say "Building the extension"
( cd "$WEB/extension" && PATH="$PWD/node_modules/.bin:$PATH" \
  BITCHORD_SITE_ORIGINS="http://localhost:$PORT,https://bitchord.in,https://bitchord-8bw.pages.dev" wxt build )
say "Building the site"
printf 'VITE_PARTY_SERVER_URL=%s\n' "$PARTY_URL" > "$WEB/app/.env.local"
( cd "$WEB/app" && PATH="$PWD/node_modules/.bin:$PATH" && tsc -p . && vite build )

# 5. Install (only outputs, ~50 MB)
say "Installing to $APP_HOME"
mkdir -p "$APP_HOME"
rm -rf "$APP_HOME/site.new" "$APP_HOME/extension.new"
cp -R "$WEB/app/dist" "$APP_HOME/site.new"
cp -R "$WEB/extension/.output/chrome-mv3" "$APP_HOME/extension.new"
rm -rf "$APP_HOME/site" "$APP_HOME/extension"
mv "$APP_HOME/site.new" "$APP_HOME/site"
mv "$APP_HOME/extension.new" "$APP_HOME/extension"
cp "$HERE/scripts/server.py" "$APP_HOME/server.py"

# 6. Autostart server
if [ -n "${BITCHORD_NO_SERVICE:-}" ]; then
  say "Skipping autostart (BITCHORD_NO_SERVICE). Run: python3 \"$APP_HOME/server.py\""
elif [ "$OS" = mac ]; then
  PLIST="$HOME/Library/LaunchAgents/com.bitchord.desktop.plist"
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.bitchord.desktop</string>
<key>ProgramArguments</key><array><string>/usr/bin/python3</string><string>$APP_HOME/server.py</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
</dict></plist>
EOF
  launchctl bootout "gui/$(id -u)/com.bitchord.desktop" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
else
  UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/bitchord.service"
  mkdir -p "$(dirname "$UNIT")"
  cat > "$UNIT" <<EOF
[Unit]
Description=BitChord local web player
[Service]
ExecStart=$(command -v python3) "$APP_HOME/server.py"
Restart=always
[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload && systemctl --user enable --now bitchord.service
  systemctl --user restart bitchord.service
fi

cat <<EOF

BitChord is installed.  Site: http://localhost:$PORT

One-time browser setup (Chrome / Edge / Brave):
  1. Open chrome://extensions and turn on Developer mode
  2. Load unpacked -> $APP_HOME/extension
  3. Open http://localhost:$PORT, then menu -> Cast, save and share -> Install page as app
After updating, press Reload on the extension card.
EOF
