#!/usr/bin/env bash
#
# ftp-restore.sh  (native tools only — Fedora Silverblue friendly)
# Fetch the LATEST password-protected AES-256 archive from an FTP server
# (e.g. your phone), decrypt it, and extract it into a folder sitting NEXT
# TO THIS SCRIPT.
#
# Usage:   ./ftp-restore.sh
#
# Settings live in backup.conf next to this script (shared with
# ftp-backup.sh). Any can be overridden via env vars, e.g.:
#   FTP_PASS='secret' ARCHIVE_PASS='secret2' ./ftp-restore.sh
#
# Uses only base-image tools: tar, gzip, gpg, curl. Nothing to install.
#
# NOTE: passwords are stored in plaintext in backup.conf. Lock it down:
#   chmod 600 backup.conf

set -euo pipefail

# ===== CONFIG — all settings live in backup.conf (next to this script) ==
# Folder this script lives in — restored files go in a subfolder here.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${CONF:-$SCRIPT_DIR/backup.conf}"
[[ -r "$CONF" ]] || { echo "Config file not found: $CONF" >&2; exit 1; }
# shellcheck source=/dev/null
source "$CONF"
# ========================================================================

# ----- sanity checks -----
for c in tar gzip gpg curl; do
  command -v "$c" >/dev/null || { echo "Missing required tool: $c" >&2; exit 1; }
done
[[ -n "$ARCHIVE_PASS" && "$ARCHIVE_PASS" != "change-me-archive-password" ]] \
  || { echo "Set ARCHIVE_PASS (in-script or env)." >&2; exit 1; }
[[ -n "$FTP_PASS" && "$FTP_PASS" != "change-me-ftp-password" ]] \
  || { echo "Set FTP_PASS (in-script or env)." >&2; exit 1; }

# ----- map PROTO -> curl scheme + TLS options -----
TLS_OPTS=()
case "$PROTO" in
  ftp)   SCHEME="ftp"  ;;
  ftpes) SCHEME="ftp";  TLS_OPTS+=(--ssl-reqd) ;;
  ftps)  SCHEME="ftps" ;;
  sftp)  SCHEME="sftp" ;;
  *) echo "Unknown PROTO: $PROTO (use ftp|ftpes|ftps|sftp)" >&2; exit 1 ;;
esac
[[ "$TLS_VERIFY" == true ]] || TLS_OPTS+=(--insecure)

# credentials fed via -K - (stdin) so they never hit the process list (ps).
# " and \ in credentials are escaped so the curl config line stays valid.
curl_ftp() {
  local u="${FTP_USER//\\/\\\\}"; u="${u//\"/\\\"}"
  local p="${FTP_PASS//\\/\\\\}"; p="${p//\"/\\\"}"
  curl --silent --show-error --connect-timeout 20 "${TLS_OPTS[@]}" -K - "$@" <<EOF
user = "$u:$p"
EOF
}

mkdir -p "$WORK_DIR"

# ----- 1. find the latest archive on the server -----
echo "[1/3] Looking for the latest backup in $SCHEME://$FTP_HOST:$FTP_PORT$REMOTE_DIR/"
# Names are backup-YYYYMMDD-HHMMSS.tar.gz.gpg, so a lexical sort is also
# chronological — the last line is the newest.
LATEST="$(curl_ftp --list-only "$SCHEME://$FTP_HOST:$FTP_PORT$REMOTE_DIR/" 2>/dev/null \
          | awk '{n=$NF; sub(".*/","",n); print n}' \
          | grep '^backup-.*\.tar\.gz\.gpg$' | sort | tail -n 1 || true)"
[[ -n "$LATEST" ]] || { echo "No backups found on server." >&2; exit 1; }
echo "      latest: $LATEST"

LOCAL="$WORK_DIR/$LATEST"
trap 'rm -f "$LOCAL"' EXIT

# Resolve destination now and verify it BEFORE downloading. RESTORE_DIR is
# the PARENT path (defaults to next to the script if empty); the archive is
# extracted into a subfolder named after it. Refuse to proceed if that
# target already has contents (hidden files included).
# Relative RESTORE_DIR is resolved from SCRIPT_DIR, not the caller's CWD.
if [[ -n "${RESTORE_DIR:-}" && "${RESTORE_DIR}" != /* ]]; then
  RESTORE_BASE="$SCRIPT_DIR/$RESTORE_DIR"
else
  RESTORE_BASE="${RESTORE_DIR:-$SCRIPT_DIR}"
fi
DEST="$RESTORE_BASE/${LATEST%.tar.gz.gpg}"
if [[ -d "$DEST" && -n "$(ls -A "$DEST" 2>/dev/null)" ]]; then
  echo "Restore folder exists and is not empty: $DEST" >&2
  echo "Move/remove it or set a different RESTORE_DIR, then re-run." >&2
  exit 1
fi

# ----- 2. download -----
echo "[2/3] Downloading $LATEST"
curl_ftp -o "$LOCAL" "$SCHEME://$FTP_HOST:$FTP_PORT$REMOTE_DIR/$LATEST"
echo "      saved ($(du -h "$LOCAL" | cut -f1))"

# ----- 3. decrypt + extract beside the script -----
mkdir -p "$DEST"
echo "[3/3] Decrypting + extracting into $DEST"
# gpg decrypts (passphrase via fd 3 so it never shows in ps); tar extracts.
gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 3 \
    -d "$LOCAL" 3< <(printf '%s' "$ARCHIVE_PASS") \
  | tar -xz -C "$DEST"
echo "      extracted."

# ----- cleanup local copy -----
if [[ "$DELETE_LOCAL_AFTER_EXTRACT" == true ]]; then
  rm -f "$LOCAL"
  echo "Local copy removed."
else
  trap - EXIT   # keep the download; disable the error-path cleanup trap
fi

echo "Done. Files are in: $DEST"