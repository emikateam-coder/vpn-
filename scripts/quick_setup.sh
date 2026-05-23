#!/usr/bin/env bash
#
# Quick setup wrapper - interactive prompt for required parameters
# Use this if environment variables are not set
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================================"
echo "  VLESS-Reality Quick Setup"
echo "================================================================"
echo ""

if [[ -z "${VPS_HOST:-}" ]]; then
    read -rp "VPS IP address: " VPS_HOST
    export VPS_HOST
fi

if [[ -z "${VPS_SSH_PORT:-}" ]]; then
    read -rp "SSH port [22]: " VPS_SSH_PORT
    export VPS_SSH_PORT="${VPS_SSH_PORT:-22}"
fi

if [[ -z "${VPS_SSH_USER:-}" ]]; then
    read -rp "SSH user [root]: " VPS_SSH_USER
    export VPS_SSH_USER="${VPS_SSH_USER:-root}"
fi

if [[ -z "${VPS_SSH_PASSWORD:-}" ]]; then
    read -rsp "SSH password: " VPS_SSH_PASSWORD
    echo ""
    export VPS_SSH_PASSWORD
fi

if [[ -z "${PANEL_PORT:-}" ]]; then
    read -rp "3X-UI panel port [2053]: " PANEL_PORT
    export PANEL_PORT="${PANEL_PORT:-2053}"
fi

if [[ -z "${PANEL_USER:-}" ]]; then
    read -rp "Panel username [admin]: " PANEL_USER
    export PANEL_USER="${PANEL_USER:-admin}"
fi

if [[ -z "${PANEL_PASS:-}" ]]; then
    read -rsp "Panel password [admin]: " PANEL_PASS
    echo ""
    export PANEL_PASS="${PANEL_PASS:-admin}"
fi

if [[ -z "${DEST_DOMAIN:-}" ]]; then
    read -rp "Masquerading domain [www.samsung.com]: " DEST_DOMAIN
    export DEST_DOMAIN="${DEST_DOMAIN:-www.samsung.com}"
fi

if [[ -z "${CLIENT_NAMES:-}" ]]; then
    read -rp "Client names (comma-separated) [MyPC,MyPhone]: " CLIENT_NAMES
    export CLIENT_NAMES="${CLIENT_NAMES:-MyPC,MyPhone}"
fi

echo ""
echo "Starting setup with:"
echo "  VPS:     ${VPS_HOST}:${VPS_SSH_PORT}"
echo "  Panel:   port ${PANEL_PORT}, user ${PANEL_USER}"
echo "  Domain:  ${DEST_DOMAIN}"
echo "  Clients: ${CLIENT_NAMES}"
echo ""

read -rp "Proceed? [Y/n]: " confirm
if [[ "${confirm,,}" == "n" ]]; then
    echo "Aborted."
    exit 0
fi

exec bash "${SCRIPT_DIR}/setup_vless_reality.sh"
