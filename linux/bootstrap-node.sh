#!/usr/bin/env bash
# Bootstrap a fresh Debian/Ubuntu node as a GitHub Actions self-hosted runner
# for the Altosec LoadBalancer. Installs Docker (to build + deploy the image),
# downloads and registers the runner, and runs it as a systemd service
# (starts on boot, auto-restarts). Safe to re-run (re-registers with --replace).
#
# Run ON the node as root:
#   sudo ./bootstrap-node.sh --token <registration-token> --runner-name proxy-node-01
#
# Or one-liner (token: GitHub -> repo Settings -> Actions -> Runners ->
# "New self-hosted runner", valid ~1 hour):
#   curl -fsSL \
#     https://raw.githubusercontent.com/altosecteam-org/AltoSec-Nginx-Server-Script/main/linux/bootstrap-node.sh \
#     | sudo bash -s -- --token <registration-token> --runner-name proxy-node-01
set -euo pipefail

# Repo whose Actions this runner executes (NOT where this script is hosted).
REPO_URL="https://github.com/altosecteam-org/Altosec-nginx-manager"
RUNNER_TOKEN=""
RUNNER_NAME=""
RUNNER_LABELS=""
RUNNER_USER="gha-runner"
RUNNER_VERSION=""   # empty → resolve latest from the GitHub API

log() { echo ">>> $*"; }
err() { echo "ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    -t|--token)        RUNNER_TOKEN="${2:-}"; shift 2;;
    -n|--runner-name)  RUNNER_NAME="${2:-}"; shift 2;;
    -u|--url)          REPO_URL="${2:-}"; shift 2;;
    -l|--labels)       RUNNER_LABELS="${2:-}"; shift 2;;
    --user)            RUNNER_USER="${2:-}"; shift 2;;
    --version)         RUNNER_VERSION="${2:-}"; shift 2;;
    -h|--help)         awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$0"; exit 0;;
    *) err "Unknown option: $1 (use --help)";;
  esac
done

[ "$(id -u)" -eq 0 ] || err "Run as root (use sudo)."
[ -n "$RUNNER_TOKEN" ] || err "--token is required."
[ -n "$RUNNER_NAME" ]  || err "--runner-name is required."

case "$(uname -m)" in
  x86_64|amd64)  ARCH="x64";;
  aarch64|arm64) ARCH="arm64";;
  *) err "Unsupported architecture: $(uname -m)";;
esac

command -v apt-get >/dev/null 2>&1 || \
  err "This bootstrap targets Debian/Ubuntu (apt). Install curl/tar/docker manually on other distros."

log "Installing base packages (curl, tar, sudo, ca-certificates) …"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends curl ca-certificates tar sudo

if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker Engine + compose plugin …"
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker 2>/dev/null || true

if ! id "$RUNNER_USER" >/dev/null 2>&1; then
  log "Creating runner user '$RUNNER_USER' …"
  useradd -m -s /bin/bash "$RUNNER_USER"
fi
# The runner builds/deploys with Docker, so it needs docker-group access.
usermod -aG docker "$RUNNER_USER"

if [ -z "$RUNNER_VERSION" ]; then
  log "Resolving latest runner version …"
  RUNNER_VERSION="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest \
    | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$RUNNER_VERSION" ] || err "Could not resolve latest version; pass --version X.Y.Z"
fi
log "Runner v$RUNNER_VERSION ($ARCH)"

RUNNER_HOME="/home/$RUNNER_USER/actions-runner"
TARBALL="actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz"
DL_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${TARBALL}"

# Cleanly retire an existing service before re-registering.
if [ -f "$RUNNER_HOME/svc.sh" ]; then
  log "Existing runner found — stopping and uninstalling its service …"
  ( cd "$RUNNER_HOME" && ./svc.sh stop 2>/dev/null || true; ./svc.sh uninstall 2>/dev/null || true )
fi

mkdir -p "$RUNNER_HOME"
log "Downloading $TARBALL …"
curl -fsSL -o "/tmp/$TARBALL" "$DL_URL"
tar xzf "/tmp/$TARBALL" -C "$RUNNER_HOME"
rm -f "/tmp/$TARBALL"
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME"

log "Installing runner OS dependencies …"
"$RUNNER_HOME/bin/installdependencies.sh"

log "Registering runner '$RUNNER_NAME' with $REPO_URL …"
label_arg=""
[ -n "$RUNNER_LABELS" ] && label_arg="--labels $RUNNER_LABELS"
sudo -u "$RUNNER_USER" bash -c "cd '$RUNNER_HOME' && ./config.sh \
  --url '$REPO_URL' --token '$RUNNER_TOKEN' \
  --name '$RUNNER_NAME' $label_arg \
  --work '_work' --unattended --replace"

log "Installing + starting systemd service …"
( cd "$RUNNER_HOME" && ./svc.sh install "$RUNNER_USER" && ./svc.sh start )

log "Done. Runner '$RUNNER_NAME' is online and starts on boot."
log "Verify: ${REPO_URL}/settings/actions/runners"
