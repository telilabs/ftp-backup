#!/usr/bin/env bash
#
# install-aliases.sh
# Adds short aliases for the backup/restore scripts that sit next to this
# file, writing them into your shell's rc file. Idempotent — re-running
# updates the block instead of duplicating it.
#
# Usage:   ./install-aliases.sh [BACKUP_ALIAS] [RESTORE_ALIAS]
# Example: ./install-aliases.sh bk rs        (defaults shown)
#
# Pick the rc file with RC=... (defaults: ~/.zshrc if you use zsh, else ~/.bashrc):
#   RC=~/.bashrc ./install-aliases.sh

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BK_ALIAS="${1:-bk}"
RS_ALIAS="${2:-rs}"
BK_SCRIPT="$DIR/ftp-backup.sh"
RS_SCRIPT="$DIR/ftp-restore.sh"

# pick rc file: honor $RC, else match the login shell, else ~/.bashrc
if [[ -n "${RC:-}" ]]; then
  : # use as given
elif [[ "${SHELL:-}" == */zsh ]]; then
  RC="$HOME/.zshrc"
else
  RC="$HOME/.bashrc"
fi

# sanity
for s in "$BK_SCRIPT" "$RS_SCRIPT"; do
  [[ -f "$s" ]] || { echo "Script not found next to installer: $s" >&2; exit 1; }
  chmod +x "$s"
done

MARK_BEGIN="# >>> ftp-backup aliases >>>"
MARK_END="# <<< ftp-backup aliases <<<"

touch "$RC"
# strip any previous managed block, then append a fresh one;
# write to a temp file first and mv into place atomically to avoid
# truncating $RC if the process is interrupted mid-write.
tmp="$(mktemp)"
tmp2="$(mktemp)"
trap 'rm -f "$tmp" "$tmp2"' EXIT
sed "/^${MARK_BEGIN}$/,/^${MARK_END}$/d" "$RC" > "$tmp"
{
  cat "$tmp"
  printf '%s\n' "$MARK_BEGIN"
  printf "alias %s='%q'\n" "$BK_ALIAS" "$BK_SCRIPT"
  printf "alias %s='%q'\n" "$RS_ALIAS" "$RS_SCRIPT"
  printf '%s\n' "$MARK_END"
} > "$tmp2"
mv "$tmp2" "$RC"
rm -f "$tmp"

echo "Added to $RC:"
echo "  $BK_ALIAS -> $BK_SCRIPT"
echo "  $RS_ALIAS -> $RS_SCRIPT"
echo
echo "Activate now with:  source \"$RC\"   (or open a new terminal)"