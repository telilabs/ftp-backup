#!/usr/bin/env bash
#
# uninstall-aliases.sh
# Removes the managed alias block that install-aliases.sh added to your
# shell's rc file. Safe to run multiple times.
#
# Usage:   ./uninstall-aliases.sh
#
# Override the rc file with RC=...:
#   RC=~/.bashrc ./uninstall-aliases.sh

set -euo pipefail

# pick rc file: honor $RC, else match the login shell, else ~/.bashrc
if [[ -n "${RC:-}" ]]; then
  : # use as given
elif [[ "${SHELL:-}" == */zsh ]]; then
  RC="$HOME/.zshrc"
else
  RC="$HOME/.bashrc"
fi

MARK_BEGIN="# >>> ftp-backup aliases >>>"
MARK_END="# <<< ftp-backup aliases <<<"

if [[ ! -f "$RC" ]]; then
  echo "RC file not found: $RC — nothing to do."
  exit 0
fi

if ! grep -qF "$MARK_BEGIN" "$RC"; then
  echo "No ftp-backup alias block found in $RC — nothing to do."
  exit 0
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
sed "/^${MARK_BEGIN}$/,/^${MARK_END}$/d" "$RC" > "$tmp"
mv "$tmp" "$RC"

echo "Removed ftp-backup alias block from $RC."
echo "Activate now with:  source \"$RC\"   (or open a new terminal)"
