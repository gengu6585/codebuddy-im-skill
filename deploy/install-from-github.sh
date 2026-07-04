#!/bin/bash
# Clone fork repos from GitHub and run native systemd install.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Run as root inside the Ubuntu container"
    exit 1
fi

SKILL_REPO="${SKILL_REPO:-https://github.com/gengu6585/codebuddy-im-skill.git}"
CORE_REPO="${CORE_REPO:-https://github.com/gengu6585/Claude-to-IM.git}"
BRANCH="${BRANCH:-main}"
CLONE_ROOT="${CLONE_ROOT:-/tmp/codebuddy-im-deploy}"

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
    echo "❌ Set TELEGRAM_BOT_TOKEN"
    exit 1
fi

echo "→ Fetch sources"
rm -rf "$CLONE_ROOT"
mkdir -p "$CLONE_ROOT"
if [ -n "${GITHUB_PAT:-}" ]; then
    SKILL_URL="${SKILL_REPO/https:\/\/github.com/https://gengu6585:${GITHUB_PAT}@github.com}"
    CORE_URL="${CORE_REPO/https:\/\/github.com/https://gengu6585:${GITHUB_PAT}@github.com}"
    git clone --depth 1 --branch "$BRANCH" "$SKILL_URL" "$CLONE_ROOT/codebuddy-im-skill"
    git clone --depth 1 --branch "$BRANCH" "$CORE_URL" "$CLONE_ROOT/Claude-to-IM"
else
    git clone --depth 1 --branch "$BRANCH" "$SKILL_REPO" "$CLONE_ROOT/codebuddy-im-skill"
    git clone --depth 1 --branch "$BRANCH" "$CORE_REPO" "$CLONE_ROOT/Claude-to-IM"
fi

export TELEGRAM_BOT_TOKEN CTI_TG_CHAT_ID CTI_TG_ALLOWED_USERS
bash "$CLONE_ROOT/codebuddy-im-skill/deploy/install-container-native.sh"
