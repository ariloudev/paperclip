#!/usr/bin/env bash
# Deploy Paperclip to the Mini (Colima) via Docker context "mini".
#
# What it does:
#   1. Gracefully stops the running instance on the mini
#   2. Builds the Docker image locally
#   3. Transfers the image to the mini via docker save/load
#   4. Syncs ~/.paperclip to the mini (one-time seed of local data)
#   5. Prepares deploy directory and .env on the mini
#   6. Deploys via docker compose on the mini over SSH
#
# Prerequisites:
#   - Docker context "mini" exists (docker context create mini --docker "host=ssh://openclaw@mini")
#   - SSH access to openclaw@mini
#
# Environment variables (optional):
#   MINI_SSH        SSH destination          (default: openclaw@mini)
#   REMOTE_DATA     Data dir on the mini     (default: ~/.paperclip)
#   REMOTE_DEPLOY   Deploy dir on the mini   (default: ~/paperclip-deploy)
#   SKIP_BUILD      Set to 1 to skip image build (reuse existing)
#   SYNC            Set to 1 to sync ~/.paperclip to the mini
#   ANTHROPIC_API_KEY, OPENAI_API_KEY — forwarded to the container if set

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DOCKER_CTX="mini"
MINI_SSH="${MINI_SSH:-openclaw@mini}"
REMOTE_DATA="${REMOTE_DATA:-~/.paperclip}"
REMOTE_DEPLOY="${REMOTE_DEPLOY:-~/paperclip-deploy}"
IMAGE_NAME="paperclip"

# ── 1. Stop running instance ────────────────────────────────────────────────
echo "==> Stopping running instance on mini (if any)..."
ssh "$MINI_SSH" bash <<'REMOTE_STOP'
if [ -f ~/paperclip-deploy/docker-compose.yml ]; then
  cd ~/paperclip-deploy
  docker compose down --timeout 30 2>/dev/null && echo "   Stopped." || echo "   Nothing running."
else
  echo "   No prior deployment found."
fi
REMOTE_STOP

# ── 2. Build ────────────────────────────────────────────────────────────────
if [[ "${SKIP_BUILD:-}" != "1" ]]; then
  echo "==> Building Docker image locally..."
  docker build -t "$IMAGE_NAME" "$PROJECT_DIR"
else
  echo "==> Skipping build (SKIP_BUILD=1)"
fi

# ── 3. Transfer image ──────────────────────────────────────────────────────
echo "==> Transferring image to mini..."
docker save "$IMAGE_NAME" | docker --context "$DOCKER_CTX" load

# ── 4. Sync data ───────────────────────────────────────────────────────────
if [[ "${SYNC:-}" == "1" ]]; then
  echo "==> Syncing ~/.paperclip → $MINI_SSH:$REMOTE_DATA ..."
  rsync -az --exclude '.DS_Store' "$HOME/.paperclip/" "$MINI_SSH:$REMOTE_DATA/"

  # Rewrite hardcoded local paths in config.json so they resolve inside the
  # container where PAPERCLIP_HOME=/paperclip (mounted from REMOTE_DATA).
  # e.g. /Users/admin/.paperclip/instances/... → /paperclip/instances/...
  LOCAL_PAPERCLIP_HOME="$HOME/.paperclip"
  CONTAINER_PAPERCLIP_HOME="/paperclip"
  echo "==> Rewriting paths in remote config.json..."
  echo "    ${LOCAL_PAPERCLIP_HOME} → ${CONTAINER_PAPERCLIP_HOME}"
  ssh "$MINI_SSH" "sed -i.bak 's|${LOCAL_PAPERCLIP_HOME}|${CONTAINER_PAPERCLIP_HOME}|g' ${REMOTE_DATA}/instances/default/config.json && rm -f ${REMOTE_DATA}/instances/default/config.json.bak"
else
  echo "==> Skipping data sync (use SYNC=1 to sync)"
fi

# ── 5. Prepare remote deploy directory ──────────────────────────────────────
echo "==> Setting up deploy directory on mini..."

# Generate BETTER_AUTH_SECRET on first deploy; preserve on subsequent ones
ssh "$MINI_SSH" bash <<'REMOTE_INIT'
mkdir -p ~/paperclip-deploy
if [ ! -f ~/paperclip-deploy/.env ]; then
  echo "BETTER_AUTH_SECRET=$(openssl rand -hex 32)" > ~/paperclip-deploy/.env
  echo "   Created .env with new BETTER_AUTH_SECRET"
else
  echo "   .env already exists, keeping existing secret"
fi
REMOTE_INIT

# Append/update API keys in .env if set locally
ENV_UPDATES=""
[[ -n "${ANTHROPIC_API_KEY:-}" ]] && ENV_UPDATES+="ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}"$'\n'
[[ -n "${OPENAI_API_KEY:-}" ]]    && ENV_UPDATES+="OPENAI_API_KEY=${OPENAI_API_KEY}"$'\n'

if [[ -n "$ENV_UPDATES" ]]; then
  echo "==> Forwarding API keys to mini .env..."
  ssh "$MINI_SSH" bash <<REMOTE_ENV
cd ~/paperclip-deploy
# Remove old key lines, then append fresh ones
sed -i.bak '/^ANTHROPIC_API_KEY=/d;/^OPENAI_API_KEY=/d' .env 2>/dev/null || true
cat >> .env <<'KEYS'
${ENV_UPDATES}KEYS
rm -f .env.bak
REMOTE_ENV
fi

# Copy compose file to mini
scp -q "$PROJECT_DIR/docker-compose.deploy.yml" "$MINI_SSH:$REMOTE_DEPLOY/docker-compose.yml"

# ── 6. Deploy ──────────────────────────────────────────────────────────────
echo "==> Starting Paperclip on mini..."
ssh "$MINI_SSH" bash <<REMOTE_UP
cd ~/paperclip-deploy
export \$(grep -v '^#' .env | xargs)
export PAPERCLIP_DATA_DIR="$REMOTE_DATA"
docker compose up -d --remove-orphans
REMOTE_UP

echo ""
echo "==> Done! Paperclip is running on the mini."
echo "    URL: http://mini:3100"
echo "    Data: $MINI_SSH:$REMOTE_DATA"
echo ""
echo "    Manage remotely:"
echo "      docker --context mini ps"
echo "      docker --context mini logs -f paperclip-deploy-paperclip-1"
echo "      ssh $MINI_SSH 'cd ~/paperclip-deploy && docker compose down'"
