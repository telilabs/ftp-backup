#!/usr/bin/env bash
#
# ftp-backup.sh  (native tools only — Fedora Silverblue friendly)
# Compress one or more folders into a single password-protected AES-256
# archive, upload it to an FTP server (e.g. your phone), and keep only the N
# most recent backups ON THE SERVER.
#
# Usage:   ./ftp-backup.sh
# All settings (server, passwords, SOURCE_DIRS, KEEP, ...) live in
# backup.conf next to this script. Any can be overridden at runtime via an
# environment variable of the same name, e.g.:
#   FTP_PASS='secret' ARCHIVE_PASS='secret2' KEEP=5 ./ftp-backup.sh
#
# Uses only base-image tools: tar, gzip, gpg, curl. Nothing to install.
#
# NOTE: passwords are stored in plaintext in backup.conf. Lock it down:
#   chmod 600 backup.conf

set -euo pipefail

# ===== CONFIG — all settings live in backup.conf (next to this script) ==
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
(( ${#SOURCE_DIRS[@]} > 0 )) || { echo "No source directories given." >&2; exit 1; }
for d in "${SOURCE_DIRS[@]}"; do
  [[ -d "$d" ]] || { echo "Source folder not found: $d" >&2; exit 1; }
done
[[ -n "$ARCHIVE_PASS" && "$ARCHIVE_PASS" != "change-me-archive-password" ]] \
  || { echo "Set ARCHIVE_PASS (in-script or env)." >&2; exit 1; }
[[ -n "$FTP_PASS" && "$FTP_PASS" != "change-me-ftp-password" ]] \
  || { echo "Set FTP_PASS (in-script or env)." >&2; exit 1; }

# ----- map PROTO -> curl scheme + TLS options -----
TLS_OPTS=()
case "$PROTO" in
  ftp)   SCHEME="ftp"  ;;                                  # no encryption
  ftpes) SCHEME="ftp";  TLS_OPTS+=(--ssl-reqd) ;;          # explicit FTPS (AUTH TLS)
  ftps)  SCHEME="ftps" ;;                                  # implicit FTPS
  sftp)  SCHEME="sftp" ;;                                  # SSH
  *) echo "Unknown PROTO: $PROTO (use ftp|ftpes|ftps|sftp)" >&2; exit 1 ;;
esac
[[ "$TLS_VERIFY" == true ]] || TLS_OPTS+=(--insecure)      # accept self-signed / skip host key

# curl helper: credentials fed via -K - (stdin) so they never hit the
# process list (ps). TLS options and per-call args are passed as arguments.
# " and \ in credentials are escaped so the curl config line stays valid.
curl_ftp() {
  local u="${FTP_USER//\\/\\\\}"; u="${u//\"/\\\"}"
  local p="${FTP_PASS//\\/\\\\}"; p="${p//\"/\\\"}"
  curl --silent --show-error --connect-timeout 20 "${TLS_OPTS[@]}" -K - "$@" <<EOF
user = "$u:$p"
EOF
}

mkdir -p "$WORK_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
BASENAME="backup-$STAMP.tar.gz.gpg"
ARCHIVE="$WORK_DIR/$BASENAME"
trap 'rm -f "$ARCHIVE"' EXIT

# Build tar arguments: one "-C <parent> <basename>" pair per source dir, so
# each folder is stored under just its own name at the top of the archive.
# NOTE: if two sources share the same basename (e.g. two different "docs"
# folders) they'll collide in the archive — rename one or adjust if needed.
TAR_ARGS=()
for d in "${SOURCE_DIRS[@]}"; do
  TAR_ARGS+=( -C "$(dirname "$d")" "$(basename "$d")" )
done

# ----- 1. compress + encrypt -----
echo "[1/3] Compressing + encrypting ${#SOURCE_DIRS[@]} folder(s) -> $BASENAME"
printf '        - %s\n' "${SOURCE_DIRS[@]}"
# tar compresses (gzip); gpg encrypts with AES-256. The passphrase is read
# from fd 3 (process substitution) so it never appears in argv or ps.
tar -czf - "${TAR_ARGS[@]}" \
  | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
        --symmetric --cipher-algo AES256 --compress-algo none \
        -o "$ARCHIVE" 3< <(printf '%s' "$ARCHIVE_PASS")

echo "      verifying archive..."
gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 3 \
    -d "$ARCHIVE" 3< <(printf '%s' "$ARCHIVE_PASS") | tar -tz >/dev/null
echo "      OK ($(du -h "$ARCHIVE" | cut -f1))"

# ----- 2. upload -----
echo "[2/3] Uploading via $PROTO to $SCHEME://$FTP_HOST:$FTP_PORT$REMOTE_DIR/"
curl_ftp --ftp-create-dirs -T "$ARCHIVE" \
  "$SCHEME://$FTP_HOST:$FTP_PORT$REMOTE_DIR/$BASENAME"
echo "      uploaded."

# ----- 3. retention: keep newest $KEEP on the server -----
echo "[3/3] Pruning remote backups (keeping $KEEP)"
REMOTE_LIST="$(curl_ftp --list-only "$SCHEME://$FTP_HOST:$FTP_PORT$REMOTE_DIR/" 2>/dev/null \
              | awk '{n=$NF; sub(".*/","",n); print n}' \
              | grep '^backup-.*\.tar\.gz\.gpg$' | sort || true)"
TOTAL="$(printf '%s\n' "$REMOTE_LIST" | grep -c . || true)"

if (( TOTAL > KEEP )); then
  DELETE_COUNT=$(( TOTAL - KEEP ))
  echo "      $TOTAL backups on server, removing $DELETE_COUNT oldest"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    echo "      deleting $f"
    curl_ftp -o /dev/null -Q "CWD $REMOTE_DIR" -Q "DELE $f" \
      "$SCHEME://$FTP_HOST:$FTP_PORT/" || echo "      (could not delete $f)"
  done < <(printf '%s\n' "$REMOTE_LIST" | head -n "$DELETE_COUNT")
else
  echo "      $TOTAL backup(s) on server, nothing to prune"
fi

# ----- cleanup local copy -----
if [[ "$DELETE_LOCAL_AFTER_UPLOAD" == true ]]; then
  rm -f "$ARCHIVE"
  echo "Local copy removed."
else
  trap - EXIT   # keep the archive; disable the error-path cleanup trap
fi

echo "Done."