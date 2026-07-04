#!/bin/bash
# Native systemd install for Droidspaces Ubuntu — Claude-to-IM-skill + CodeBuddy runtime.
set -euo pipefail

INSTALL_ROOT="/opt/tinkerlab"
SKILL_DIR="$INSTALL_ROOT/codebuddy-im-skill"
CORE_DIR="$INSTALL_ROOT/Claude-to-IM"
WORKSPACE="/workspace/tinkerlab"
CTI_HOME="/root/.claude-to-im"
SERVICE_NAME="codebuddy-im-skill.service"
OLD_SERVICE="codebuddy-telegram-bot-native.service"

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Run as root inside the Ubuntu container"
    exit 1
fi

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
    echo "❌ Set TELEGRAM_BOT_TOKEN"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_SKILL="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_CORE="$(cd "$SRC_SKILL/../Claude-to-IM" 2>/dev/null && pwd || true)"

echo "→ Stop legacy Python telegram-bot-bridge (if present)"
systemctl stop "$OLD_SERVICE" 2>/dev/null || true
systemctl disable "$OLD_SERVICE" 2>/dev/null || true

echo "→ Install packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl rsync

if ! command -v node >/dev/null 2>&1; then
    echo "❌ Node.js >= 20 required"
    exit 1
fi

if ! command -v codebuddy >/dev/null 2>&1; then
    echo "❌ codebuddy CLI required (already expected on this container)"
    exit 1
fi

mkdir -p "$INSTALL_ROOT" "$WORKSPACE" "$CTI_HOME"/{data,logs,runtime,data/messages}

echo "→ Sync skill source to $SKILL_DIR"
mkdir -p "$SKILL_DIR"
rsync -a --delete \
    --exclude node_modules --exclude '.git' --exclude 'dist' \
    "$SRC_SKILL/" "$SKILL_DIR/"

echo "→ Sync claude-to-im core to $CORE_DIR"
mkdir -p "$CORE_DIR"
if [ -n "$SRC_CORE" ] && [ -d "$SRC_CORE" ]; then
    rsync -a --delete \
        --exclude node_modules --exclude '.git' \
        "$SRC_CORE/" "$CORE_DIR/"
else
    echo "❌ Missing sibling Claude-to-IM checkout at $INSTALL_ROOT/Claude-to-IM"
    exit 1
fi

echo "→ npm install + build"
cd "$SKILL_DIR"
npm ci
npm run build

echo "→ Write CTI config"
cat > "$CTI_HOME/config.env" <<EOF
CTI_RUNTIME=codebuddy
CTI_ENABLED_CHANNELS=telegram
CTI_DEFAULT_WORKDIR=$WORKSPACE
CTI_DEFAULT_MODE=code
CTI_TG_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
CTI_AUTO_APPROVE=true
EOF

if [ -n "${CTI_TG_CHAT_ID:-}" ]; then
    echo "CTI_TG_CHAT_ID=${CTI_TG_CHAT_ID}" >> "$CTI_HOME/config.env"
fi
if [ -n "${CTI_TG_ALLOWED_USERS:-}" ]; then
    echo "CTI_TG_ALLOWED_USERS=${CTI_TG_ALLOWED_USERS}" >> "$CTI_HOME/config.env"
fi

chmod 600 "$CTI_HOME/config.env"

echo "→ systemd unit"
install -m 644 "$SKILL_DIR/deploy/$SERVICE_NAME" "/etc/systemd/system/$SERVICE_NAME"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

sleep 4
systemctl --no-pager status "$SERVICE_NAME" || true
bash "$SKILL_DIR/scripts/daemon.sh" status || true
echo "✅ Claude-to-IM-skill (CodeBuddy) deployed. Logs: journalctl -u $SERVICE_NAME -f"
