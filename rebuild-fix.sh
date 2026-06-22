#!/usr/bin/env bash
#
# rebuild-fix.sh — track the latest exelban/stats, rebase the combined-click fix,
# then rebuild and install.
#
# Flow: fetch upstream -> rebase fix -> (after confirm) force-push to fork
#       -> build -> install to /Applications -> relaunch
#
# Background: the upstream PR was declined, so this fix lives on this fork's master:
#   master = upstream master + this fork's extra commits (the click fix + these docs/script).
# Whenever upstream releases a new version, run this script to rebase those extra
# commits onto the latest code and use it.
#
# Usage:
#   ./rebuild-fix.sh              # full flow; asks before force-push
#   ./rebuild-fix.sh -y           # skip all confirmations, fully automatic
#   ./rebuild-fix.sh --no-push    # rebase + build + install only, leave fork untouched
#   ./rebuild-fix.sh --no-install # rebase + build + push, don't replace /Applications/Stats.app
#
set -euo pipefail

# ---- config ----
FIX_BRANCH="master"             # the branch on this fork carrying the extra fixes
UPSTREAM_REMOTE="origin"        # exelban/stats
UPSTREAM_BRANCH="master"
FORK_REMOTE="fork"              # LouYu2015/stats
BUILD_DIR="/tmp/stats_build"
APP_DEST="/Applications/Stats.app"

# ---- options ----
ASSUME_YES=0
DO_PUSH=1
DO_INSTALL=1
for arg in "$@"; do
  case "$arg" in
    -y|--yes)      ASSUME_YES=1 ;;
    --no-push)     DO_PUSH=0 ;;
    --no-install)  DO_INSTALL=0 ;;
    -h|--help)     grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $arg (use --help)" >&2; exit 2 ;;
  esac
done

# always operate inside the repo the script lives in
cd "$(dirname "$0")"

say()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
err()  { printf '\n\033[1;31mError:\033[0m %s\n' "$*" >&2; }

confirm() {
  [ "$ASSUME_YES" = 1 ] && return 0
  printf '%s [y/N] ' "$1"
  read -r ans </dev/tty
  [[ "$ans" =~ ^[Yy]$ ]]
}

# ---- preflight checks ----
current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$current_branch" != "$FIX_BRANCH" ]; then
  err "On branch '$current_branch'; switch to '$FIX_BRANCH' before running."
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  err "Working tree has uncommitted changes; commit or stash them first to keep rebase safe."
  git status --short
  exit 1
fi

# ---- 1. fetch upstream ----
say "Fetching upstream $UPSTREAM_REMOTE/$UPSTREAM_BRANCH ..."
git fetch "$UPSTREAM_REMOTE" --tags

behind="$(git rev-list --count "HEAD..$UPSTREAM_REMOTE/$UPSTREAM_BRANCH")"
say "Behind upstream by $behind commit(s)."

# ---- 2. rebase ----
if [ "$behind" -eq 0 ]; then
  say "Already on top of latest upstream; skipping rebase."
else
  say "Rebasing the fix onto $UPSTREAM_REMOTE/$UPSTREAM_BRANCH ..."
  if ! git rebase "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"; then
    err "Rebase hit conflicts; restored original state (rebase --abort). Resolve manually, then rerun."
    git rebase --abort || true
    exit 1
  fi
  say "Rebase done: $(git log --oneline -1)"
fi

# ---- 3. force-push to fork ----
if [ "$DO_PUSH" = 1 ]; then
  # only push if the remote actually differs
  if git diff --quiet "$FORK_REMOTE/$FIX_BRANCH" HEAD 2>/dev/null; then
    say "Fork branch already matches local; skipping push."
  elif confirm "Force-push (--force-with-lease) to $FORK_REMOTE/$FIX_BRANCH? This rewrites remote history."; then
    say "Pushing ..."
    git push --force-with-lease "$FORK_REMOTE" "$FIX_BRANCH"
    say "Updated $FORK_REMOTE/$FIX_BRANCH."
  else
    say "Skipping push."
  fi
fi

# ---- 4. build ----
say "Cleaning and building (Debug, unsigned) ..."
rm -rf "$BUILD_DIR"
xcodebuild -project Stats.xcodeproj -scheme Stats -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  | tail -3

built_app="$BUILD_DIR/Build/Products/Debug/Stats.app"
[ -d "$built_app" ] || { err "Build product not found: $built_app"; exit 1; }
say "Build succeeded: $built_app"

# ---- 5. install and relaunch ----
if [ "$DO_INSTALL" = 1 ]; then
  say "Quitting the running Stats ..."
  osascript -e 'quit app "Stats"' 2>/dev/null || true
  sleep 1
  pkill -f "Stats.app/Contents/MacOS/Stats" 2>/dev/null || true
  sleep 1

  say "Installing to $APP_DEST and relaunching ..."
  rm -rf "$APP_DEST"
  cp -R "$built_app" "$APP_DEST"
  open "$APP_DEST"
  sleep 2
  if pgrep -f "$APP_DEST/Contents/MacOS/Stats" >/dev/null; then
    say "Done. Stats relaunched (latest upstream + your fix)."
  else
    err "Installed, but it doesn't seem to be running. Try: open '$APP_DEST'"
  fi
else
  say "Skipped install. Build product is at $built_app"
fi
