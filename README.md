# ftp-backup

Compress, AES-256 encrypt, and upload your files to an FTP server (e.g. an Android phone running an FTP app). Keeps only the N most recent backups on the server.

## Setup

```bash
cp backup.template.conf backup.conf
chmod 600 backup.conf
# Edit backup.conf: set FTP_HOST, FTP_USER, FTP_PASS, ARCHIVE_PASS, SOURCE_DIRS
./install-aliases.sh    # adds `bk` and `rs` aliases to your shell
./uninstall-aliases.sh  # removes them
```

## Usage

```bash
bk    # backup
rs    # restore latest
```

Or directly:

```bash
./ftp-backup.sh
./ftp-restore.sh
```

## Requirements

`tar`, `gzip`, `gpg`, `curl` — all present in a stock Fedora Silverblue image.

## Config

| Variable | Default | Description |
|---|---|---|
| `SOURCE_DIRS` | `~/Documents ~/Pictures` | Folders to back up |
| `KEEP` | `3` | Backups to retain on the server |
| `FTP_HOST` | — | Server IP |
| `PROTO` | `ftpes` | `ftp` / `ftpes` / `ftps` / `sftp` |
| `TLS_VERIFY` | `false` | Set `true` to verify TLS cert (LAN: leave false) |
| `ARCHIVE_PASS` | — | AES-256 passphrase (must be set) |
| `RESTORE_DIR` | `./restored` | Where extracted files land |

Any variable can be overridden at runtime: `KEEP=5 ./ftp-backup.sh`
