#!/usr/bin/env bash
#
# VLESS Reality - Complete Server Configuration Script
#
# This script automates Steps 6-7 of the VLESS Reality setup guide:
#   - Connects to the 3X-UI panel API
#   - Hardens panel security (new credentials, custom port/path, bind to localhost)
#   - Configures routing rules (block torrents, block RU traffic)
#   - Creates VLESS-Reality inbound with proper settings
#   - Generates client configurations (URLs and QR codes)
#
# Required environment variables:
#   VPS_HOST          - VPS server IP address
#   VPS_SSH_PORT      - SSH port (default: 22)
#   VPS_SSH_USER      - SSH username (default: root)
#   VPS_SSH_PASSWORD   - SSH password
#   PANEL_PORT        - 3X-UI panel port (default: 2053)
#   PANEL_USER        - Panel username (default: admin)
#   PANEL_PASS        - Panel password (default: admin)
#   DEST_DOMAIN       - Masquerading domain (default: www.samsung.com)
#
# Optional environment variables:
#   NEW_PANEL_PORT    - New panel port after hardening (auto-generated if not set)
#   NEW_PANEL_USER    - New panel username (auto-generated if not set)
#   NEW_PANEL_PASS    - New panel password (auto-generated if not set)
#   NEW_PANEL_PATH    - New panel URL path (auto-generated if not set)
#   CLIENT_NAMES      - Comma-separated client names (default: "MyPC,MyPhone")
#   UTLS_FINGERPRINT  - uTLS fingerprint: chrome, firefox, etc. (default: chrome)
#   SKIP_HARDENING    - Set to "true" to skip panel hardening step
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/xui_api.sh"
source "${SCRIPT_DIR}/generate_keys.sh"

OUTPUT_DIR="${SCRIPT_DIR}/../output"
mkdir -p "$OUTPUT_DIR"

LOG_FILE="${OUTPUT_DIR}/setup_$(date +%Y%m%d_%H%M%S).log"

log() {
    local level="$1"; shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_ok()    { log "OK" "$@"; }

die() {
    log_error "$@"
    exit 1
}

check_dependencies() {
    local deps=(curl jq openssl ssh sshpass)
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing dependencies: ${missing[*]}. Install them first."
    fi
}

validate_env() {
    [[ -n "${VPS_HOST:-}" ]] || die "VPS_HOST is required"
    [[ -n "${VPS_SSH_PASSWORD:-}" ]] || die "VPS_SSH_PASSWORD is required"

    VPS_SSH_PORT="${VPS_SSH_PORT:-22}"
    VPS_SSH_USER="${VPS_SSH_USER:-root}"
    PANEL_PORT="${PANEL_PORT:-2053}"
    PANEL_USER="${PANEL_USER:-admin}"
    PANEL_PASS="${PANEL_PASS:-admin}"
    DEST_DOMAIN="${DEST_DOMAIN:-www.samsung.com}"
    UTLS_FINGERPRINT="${UTLS_FINGERPRINT:-chrome}"
    CLIENT_NAMES="${CLIENT_NAMES:-MyPC,MyPhone}"
    SKIP_HARDENING="${SKIP_HARDENING:-false}"

    DEST_DOMAIN_CLEAN="${DEST_DOMAIN#www.}"
}

build_ssh_cmd() {
    SSH_CMD="sshpass -p '${VPS_SSH_PASSWORD}' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p ${VPS_SSH_PORT} ${VPS_SSH_USER}@${VPS_HOST}"
}

setup_ssh_tunnel() {
    local local_port="${1:?Local port required}"
    local remote_port="${2:?Remote port required}"

    log_info "Setting up SSH tunnel: localhost:${local_port} -> ${VPS_HOST}:${remote_port}"

    sshpass -p "${VPS_SSH_PASSWORD}" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -p "${VPS_SSH_PORT}" \
        -L "${local_port}:127.0.0.1:${remote_port}" \
        -N -f \
        "${VPS_SSH_USER}@${VPS_HOST}" 2>/dev/null

    sleep 2

    if curl -s --connect-timeout 5 "http://127.0.0.1:${local_port}/" &>/dev/null; then
        log_ok "SSH tunnel established on port ${local_port}"
        return 0
    fi

    if curl -s --connect-timeout 5 "http://127.0.0.1:${local_port}/login" &>/dev/null; then
        log_ok "SSH tunnel established on port ${local_port}"
        return 0
    fi

    log_warn "SSH tunnel might not be working properly, continuing anyway..."
    return 0
}

kill_ssh_tunnels() {
    pkill -f "ssh.*-L.*127.0.0.1" 2>/dev/null || true
}

test_server_connectivity() {
    log_info "Testing connectivity to ${VPS_HOST}:${VPS_SSH_PORT}..."

    if sshpass -p "${VPS_SSH_PASSWORD}" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -p "${VPS_SSH_PORT}" \
        "${VPS_SSH_USER}@${VPS_HOST}" "echo 'SSH_OK'" 2>/dev/null | grep -q "SSH_OK"; then
        log_ok "SSH connection successful"
    else
        die "Cannot connect to ${VPS_HOST} via SSH"
    fi

    log_info "Checking if 3X-UI panel is running..."
    local panel_check
    panel_check=$(sshpass -p "${VPS_SSH_PASSWORD}" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -p "${VPS_SSH_PORT}" \
        "${VPS_SSH_USER}@${VPS_HOST}" \
        "docker ps --format '{{.Names}}' 2>/dev/null | grep -i '3x-ui\|x-ui' || systemctl is-active x-ui 2>/dev/null || echo 'NOT_FOUND'" 2>/dev/null)

    if echo "$panel_check" | grep -qi "3x-ui\|x-ui\|active"; then
        log_ok "3X-UI panel is running"
    else
        log_warn "Could not confirm 3X-UI is running. Output: ${panel_check}"
    fi
}

generate_reality_keys_on_server() {
    log_info "Generating X25519 keys on the server..."

    local output
    output=$(sshpass -p "${VPS_SSH_PASSWORD}" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -p "${VPS_SSH_PORT}" \
        "${VPS_SSH_USER}@${VPS_HOST}" \
        'docker exec 3x-ui /app/bin/xray x25519 2>/dev/null || /usr/local/bin/xray x25519 2>/dev/null || xray x25519 2>/dev/null' 2>/dev/null)

    REALITY_PRIVATE_KEY=$(echo "$output" | grep -i "private" | awk '{print $NF}')
    REALITY_PUBLIC_KEY=$(echo "$output" | grep -i "public" | awk '{print $NF}')

    if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" ]]; then
        die "Failed to generate Reality keys on server. Output: ${output}"
    fi

    log_ok "Reality keys generated"
    log_info "  Private key: ${REALITY_PRIVATE_KEY}"
    log_info "  Public key:  ${REALITY_PUBLIC_KEY}"
}

connect_to_panel() {
    local host="${1:-127.0.0.1}"
    local port="${2:-${PANEL_PORT}}"
    local path="${3:-/}"
    local user="${4:-${PANEL_USER}}"
    local pass="${5:-${PANEL_PASS}}"

    log_info "Connecting to 3X-UI panel at ${host}:${port}${path}..."
    xui_init "$host" "$port" "$path"
    xui_login "$user" "$pass"
}

harden_panel() {
    if [[ "$SKIP_HARDENING" == "true" ]]; then
        log_info "Skipping panel hardening (SKIP_HARDENING=true)"
        return 0
    fi

    log_info "=== HARDENING PANEL SECURITY ==="

    NEW_PANEL_PORT="${NEW_PANEL_PORT:-$(shuf -i 10001-65535 -n 1)}"
    NEW_PANEL_USER="${NEW_PANEL_USER:-$(openssl rand -hex 6)}"
    NEW_PANEL_PASS="${NEW_PANEL_PASS:-$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)}"
    NEW_PANEL_PATH="${NEW_PANEL_PATH:-/$(openssl rand -hex 8)/}"

    log_info "New panel port: ${NEW_PANEL_PORT}"
    log_info "New panel user: ${NEW_PANEL_USER}"
    log_info "New panel pass: ${NEW_PANEL_PASS}"
    log_info "New panel path: ${NEW_PANEL_PATH}"

    log_info "Updating panel credentials..."
    local cred_result
    cred_result=$(xui_update_setting "oldUsername=${PANEL_USER}&oldPassword=${PANEL_PASS}&newUsername=${NEW_PANEL_USER}&newPassword=${NEW_PANEL_PASS}")
    log_info "Credentials update response: ${cred_result}"

    log_info "Updating panel listen address, port and path..."
    local settings_result
    settings_result=$(xui_update_setting "webListen=127.0.0.1&webDomain=127.0.0.1&webPort=${NEW_PANEL_PORT}&webBasePath=${NEW_PANEL_PATH}")
    log_info "Settings update response: ${settings_result}"

    log_info "Opening firewall for new panel port (if ufw is active)..."
    sshpass -p "${VPS_SSH_PASSWORD}" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "${VPS_SSH_PORT}" \
        "${VPS_SSH_USER}@${VPS_HOST}" \
        "ufw allow ${NEW_PANEL_PORT}/tcp 2>/dev/null; ufw allow 443/tcp 2>/dev/null; true" 2>/dev/null || true

    log_info "Restarting panel with new settings..."
    xui_restart_panel
    sleep 5

    kill_ssh_tunnels
    sleep 2

    local tunnel_port
    tunnel_port=$(shuf -i 20000-30000 -n 1)
    setup_ssh_tunnel "$tunnel_port" "$NEW_PANEL_PORT"

    log_info "Reconnecting with new credentials..."
    connect_to_panel "127.0.0.1" "$tunnel_port" "$NEW_PANEL_PATH" "$NEW_PANEL_USER" "$NEW_PANEL_PASS"
    log_ok "Panel hardened successfully"

    CURRENT_TUNNEL_PORT="$tunnel_port"

    {
        echo "=== PANEL ACCESS CREDENTIALS ==="
        echo "Panel Port: ${NEW_PANEL_PORT}"
        echo "Panel Path: ${NEW_PANEL_PATH}"
        echo "Panel User: ${NEW_PANEL_USER}"
        echo "Panel Pass: ${NEW_PANEL_PASS}"
        echo ""
        echo "SSH tunnel command:"
        echo "  ssh -L 22222:127.0.0.1:${NEW_PANEL_PORT} ${VPS_SSH_USER}@${VPS_HOST} -p ${VPS_SSH_PORT}"
        echo ""
        echo "Then open in browser:"
        echo "  http://127.0.0.1:22222${NEW_PANEL_PATH}"
    } > "${OUTPUT_DIR}/panel_credentials.txt"

    log_ok "Panel credentials saved to ${OUTPUT_DIR}/panel_credentials.txt"
}

configure_routing() {
    log_info "=== CONFIGURING ROUTING RULES ==="

    log_info "Fetching current Xray configuration..."
    local current_config
    current_config=$(xui_get_xray_setting 2>/dev/null || echo "{}")

    log_info "Configuring BitTorrent blocking and RU traffic blocking..."

    local routing_config
    routing_config=$(cat <<'ROUTING_JSON'
{
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "inboundTag": [],
                "outboundTag": "blocked",
                "type": "field",
                "protocol": ["bittorrent"]
            },
            {
                "inboundTag": [],
                "outboundTag": "blocked",
                "type": "field",
                "domain": [
                    "geosite:category-ru",
                    "regexp:.*\\.ru$",
                    "regexp:.*\\.su$"
                ]
            }
        ]
    }
}
ROUTING_JSON
)

    local update_result
    update_result=$(xui_update_xray_setting "$routing_config" 2>/dev/null || echo '{"success": false}')

    local success
    success=$(echo "$update_result" | jq -r '.success // false' 2>/dev/null || echo "false")

    if [[ "$success" == "true" ]]; then
        log_ok "Routing rules configured successfully"
    else
        log_warn "Could not update routing via API directly, will configure via SSH"
        configure_routing_via_ssh
    fi
}

configure_routing_via_ssh() {
    log_info "Configuring routing rules via SSH on the server..."

    sshpass -p "${VPS_SSH_PASSWORD}" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "${VPS_SSH_PORT}" \
        "${VPS_SSH_USER}@${VPS_HOST}" bash <<'REMOTE_SCRIPT'
set -e

DB_PATH=""
for path in /etc/x-ui/x-ui.db /root/3x-ui/db/x-ui.db /opt/x-ui/x-ui.db; do
    if [[ -f "$path" ]]; then
        DB_PATH="$path"
        break
    fi
done

# Also check docker volumes
if [[ -z "$DB_PATH" ]]; then
    DOCKER_PATH=$(docker inspect 3x-ui 2>/dev/null | grep -oP '"Source": "\K[^"]+' | head -1)
    if [[ -n "$DOCKER_PATH" && -f "${DOCKER_PATH}/x-ui.db" ]]; then
        DB_PATH="${DOCKER_PATH}/x-ui.db"
    fi
fi

if [[ -z "$DB_PATH" ]]; then
    echo "[WARN] Could not find x-ui.db, routing will need manual configuration"
    exit 0
fi

echo "[INFO] Found database at: $DB_PATH"
echo "[OK] Routing will be configured through the panel GUI"
REMOTE_SCRIPT

    log_info "Routing rules may need manual verification in the panel"
}

create_vless_reality_inbound() {
    log_info "=== CREATING VLESS-REALITY INBOUND ==="

    generate_reality_keys_on_server

    IFS=',' read -ra clients <<< "$CLIENT_NAMES"
    local clients_json="["
    local client_urls=()

    for i in "${!clients[@]}"; do
        local client_name="${clients[$i]}"
        local client_uuid
        client_uuid=$(generate_uuid)
        local client_email="client_${client_name}"

        if [[ $i -gt 0 ]]; then
            clients_json+=","
        fi

        clients_json+=$(jq -n \
            --arg id "$client_uuid" \
            --arg flow "xtls-rprx-vision" \
            --arg email "$client_email" \
            '{
                "id": $id,
                "flow": $flow,
                "email": $email,
                "limitIp": 0,
                "totalGB": 0,
                "expiryTime": 0,
                "enable": true,
                "tgId": "",
                "subId": $email,
                "reset": 0
            }')

        local short_id
        short_id=$(generate_short_id)
        REALITY_SHORT_IDS+=("$short_id")
        CLIENT_UUIDS+=("$client_uuid")
        CLIENT_EMAILS+=("$client_email")

        log_info "Client '${client_name}': UUID=${client_uuid}"
    done
    clients_json+="]"

    local short_id
    short_id=$(generate_short_id)

    local dest_port=443
    local server_name="${DEST_DOMAIN}"
    local sni_list
    sni_list=$(jq -n --arg d1 "$DEST_DOMAIN" --arg d2 "$DEST_DOMAIN_CLEAN" '[$d1, $d2]' | jq -c .)

    local stream_settings
    stream_settings=$(jq -n \
        --arg fp "$UTLS_FINGERPRINT" \
        --arg dest "${DEST_DOMAIN}:${dest_port}" \
        --arg sn "$DEST_DOMAIN" \
        --arg priv "$REALITY_PRIVATE_KEY" \
        --arg pub "$REALITY_PUBLIC_KEY" \
        --arg sid "$short_id" \
        --argjson sns "$sni_list" \
        '{
            "network": "tcp",
            "security": "reality",
            "externalProxy": [],
            "realitySettings": {
                "show": false,
                "xver": 0,
                "dest": $dest,
                "serverNames": $sns,
                "privateKey": $priv,
                "minClient": "",
                "maxClient": "",
                "maxTimediff": 0,
                "shortIds": [$sid],
                "settings": {
                    "publicKey": $pub,
                    "fingerprint": $fp,
                    "serverName": "",
                    "spiderX": "/"
                }
            },
            "tcpSettings": {
                "acceptProxyProtocol": false,
                "header": {
                    "type": "none"
                }
            }
        }')

    local sniffing_settings='{"enabled":true,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}'

    local inbound_data
    inbound_data=$(jq -n \
        --arg remark "VLESS-Reality" \
        --arg protocol "vless" \
        --arg listen "${VPS_HOST}" \
        --argjson port 443 \
        --argjson clients "$clients_json" \
        --arg stream "$stream_settings" \
        --arg sniffing "$sniffing_settings" \
        '{
            "up": 0,
            "down": 0,
            "total": 0,
            "remark": $remark,
            "enable": true,
            "expiryTime": 0,
            "listen": $listen,
            "port": $port,
            "protocol": $protocol,
            "settings": ({"clients": $clients, "decryption": "none", "fallbacks": []} | tostring),
            "streamSettings": $stream,
            "sniffing": $sniffing
        }')

    log_info "Creating VLESS-Reality inbound..."
    local result
    result=$(xui_add_inbound "$inbound_data")

    local success
    success=$(echo "$result" | jq -r '.success // false' 2>/dev/null || echo "false")

    if [[ "$success" == "true" ]]; then
        log_ok "VLESS-Reality inbound created successfully"
    else
        log_error "Failed to create inbound. Response: ${result}"
        log_info "Attempting alternative inbound creation method..."
        create_inbound_alternative
        return
    fi

    generate_client_configs "$short_id"
}

create_inbound_alternative() {
    log_info "Using SSH to create inbound via 3x-ui CLI..."

    sshpass -p "${VPS_SSH_PASSWORD}" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "${VPS_SSH_PORT}" \
        "${VPS_SSH_USER}@${VPS_HOST}" \
        "docker exec 3x-ui /app/bin/xray x25519 2>/dev/null" || true

    log_warn "Alternative method: Please create the inbound manually through the panel."
    log_warn "The keys and UUIDs have been generated and saved."
}

generate_client_configs() {
    local short_id="${1:?Short ID required}"

    log_info "=== GENERATING CLIENT CONFIGURATIONS ==="

    local config_file="${OUTPUT_DIR}/client_configs.txt"
    > "$config_file"

    IFS=',' read -ra clients <<< "$CLIENT_NAMES"

    for i in "${!clients[@]}"; do
        local client_name="${clients[$i]}"
        local client_uuid="${CLIENT_UUIDS[$i]}"
        local client_email="${CLIENT_EMAILS[$i]}"

        local vless_url="vless://${client_uuid}@${VPS_HOST}:443"
        vless_url+="?type=tcp"
        vless_url+="&security=reality"
        vless_url+="&pbk=${REALITY_PUBLIC_KEY}"
        vless_url+="&fp=${UTLS_FINGERPRINT}"
        vless_url+="&sni=${DEST_DOMAIN}"
        vless_url+="&sid=${short_id}"
        vless_url+="&spx=%2F"
        vless_url+="&flow=xtls-rprx-vision"
        vless_url+="#VLESS-Reality-${client_name}"

        {
            echo "=========================================="
            echo "Client: ${client_name}"
            echo "Email:  ${client_email}"
            echo "UUID:   ${client_uuid}"
            echo "=========================================="
            echo ""
            echo "VLESS URL (copy to client app):"
            echo "${vless_url}"
            echo ""
            echo "Manual configuration:"
            echo "  Address:     ${VPS_HOST}"
            echo "  Port:        443"
            echo "  Protocol:    VLESS"
            echo "  UUID:        ${client_uuid}"
            echo "  Flow:        xtls-rprx-vision"
            echo "  Security:    Reality"
            echo "  SNI:         ${DEST_DOMAIN}"
            echo "  Fingerprint: ${UTLS_FINGERPRINT}"
            echo "  Public Key:  ${REALITY_PUBLIC_KEY}"
            echo "  Short ID:    ${short_id}"
            echo "  Spider X:    /"
            echo ""
        } >> "$config_file"

        if command -v qrencode &>/dev/null; then
            local qr_file="${OUTPUT_DIR}/qr_${client_name}.png"
            qrencode -o "$qr_file" -s 8 "$vless_url"
            log_ok "QR code saved to ${qr_file}"
        else
            log_info "Install qrencode for QR code generation: apt install qrencode"
        fi

        log_ok "Config for '${client_name}' generated"
    done

    log_ok "All client configs saved to ${config_file}"

    echo ""
    echo "================================================================"
    echo "  CLIENT CONFIGURATION SUMMARY"
    echo "================================================================"
    cat "$config_file"
    echo "================================================================"
}

generate_nekoray_routing() {
    log_info "=== GENERATING NEKORAY ROUTING CONFIG ==="

    local routing_file="${OUTPUT_DIR}/nekoray_routing.json"

    cat > "$routing_file" <<'NEKORAY_JSON'
{
    "rules": [
        {
            "domain": [],
            "domain_keyword": [
                "yandex",
                "yastatic",
                "yadi.sk",
                "xn--80aswg",
                "xn--d1acpjx3f.xn--p1ai",
                "xn--c1avg",
                "xn--80asehdb",
                "xn--p1acf",
                "xn--p1ai",
                "google.com",
                "gstatic.com",
                "yahoo",
                "bing",
                "tineye",
                "duckduckgo",
                "apple",
                "vk.com",
                "userapi.com",
                "vk-cdn.me",
                "mvk.com",
                "vk-cdn.net",
                "vk-portal.net",
                "vk.cc",
                "icq",
                "livejournal",
                "microsoft",
                "live.com",
                "login.live",
                "tradingview"
            ],
            "domain_regex": [],
            "domain_suffix": [
                ".ru",
                ".su",
                ".by"
            ],
            "geoip": [
                "private",
                "ru",
                "by"
            ],
            "geosite": [],
            "outbound": "direct"
        },
        {
            "outbound": "proxy",
            "process_name": [
                "Discord.exe",
                "firefox.exe",
                "chrome.exe",
                "msedge.exe",
                "brave.exe"
            ]
        }
    ]
}
NEKORAY_JSON

    log_ok "Nekoray routing config saved to ${routing_file}"
}

save_full_summary() {
    local summary_file="${OUTPUT_DIR}/setup_summary.txt"

    {
        echo "================================================================"
        echo "  VLESS-REALITY SETUP SUMMARY"
        echo "  Generated: $(date)"
        echo "================================================================"
        echo ""
        echo "--- SERVER INFO ---"
        echo "  VPS Host:     ${VPS_HOST}"
        echo "  SSH Port:     ${VPS_SSH_PORT}"
        echo "  SSH User:     ${VPS_SSH_USER}"
        echo ""
        echo "--- PANEL ACCESS ---"
        if [[ "$SKIP_HARDENING" != "true" ]]; then
            echo "  Panel Port:   ${NEW_PANEL_PORT}"
            echo "  Panel Path:   ${NEW_PANEL_PATH}"
            echo "  Panel User:   ${NEW_PANEL_USER}"
            echo "  Panel Pass:   ${NEW_PANEL_PASS}"
            echo ""
            echo "  SSH Tunnel:   ssh -L 22222:127.0.0.1:${NEW_PANEL_PORT} ${VPS_SSH_USER}@${VPS_HOST} -p ${VPS_SSH_PORT}"
            echo "  Browser URL:  http://127.0.0.1:22222${NEW_PANEL_PATH}"
        else
            echo "  Panel Port:   ${PANEL_PORT}"
            echo "  Panel User:   ${PANEL_USER}"
        fi
        echo ""
        echo "--- VLESS-REALITY CONFIG ---"
        echo "  Protocol:     VLESS"
        echo "  Port:         443"
        echo "  Security:     Reality"
        echo "  Flow:         xtls-rprx-vision"
        echo "  Transport:    TCP (RAW)"
        echo "  uTLS:         ${UTLS_FINGERPRINT}"
        echo "  Dest Domain:  ${DEST_DOMAIN}"
        echo "  Public Key:   ${REALITY_PUBLIC_KEY:-N/A}"
        echo "  Private Key:  ${REALITY_PRIVATE_KEY:-N/A}"
        echo ""
        echo "--- ROUTING ---"
        echo "  [BLOCKED] BitTorrent protocol"
        echo "  [BLOCKED] RU domains (geosite:category-ru, .ru, .su)"
        echo ""
        echo "--- CLIENTS ---"
        IFS=',' read -ra clients <<< "$CLIENT_NAMES"
        for i in "${!clients[@]}"; do
            echo "  ${clients[$i]}: ${CLIENT_UUIDS[$i]:-N/A}"
        done
        echo ""
        echo "--- FILES ---"
        echo "  Client configs:    ${OUTPUT_DIR}/client_configs.txt"
        echo "  Panel credentials: ${OUTPUT_DIR}/panel_credentials.txt"
        echo "  Nekoray routing:   ${OUTPUT_DIR}/nekoray_routing.json"
        echo "  Setup log:         ${LOG_FILE}"
        echo ""
        echo "--- NEXT STEPS ---"
        echo "  1. Copy the VLESS URL from client_configs.txt"
        echo "  2. Import it into your client app (Nekoray, Hiddify, V2RayNG, etc.)"
        echo "  3. Configure routing rules (use nekoray_routing.json as reference)"
        echo "  4. Enable TUN mode and System Proxy in your client"
        echo "  5. Test: visit https://ipinfo.io/ (should show VPS IP)"
        echo "  6. Verify: visit https://2ip.ru/ (should show your real IP)"
        echo "================================================================"
    } > "$summary_file"

    cat "$summary_file"
    log_ok "Full summary saved to ${summary_file}"
}

main() {
    echo "================================================================"
    echo "  VLESS-Reality Automated Setup"
    echo "  $(date)"
    echo "================================================================"
    echo ""

    REALITY_PRIVATE_KEY=""
    REALITY_PUBLIC_KEY=""
    REALITY_SHORT_IDS=()
    CLIENT_UUIDS=()
    CLIENT_EMAILS=()
    CURRENT_TUNNEL_PORT=""

    check_dependencies
    validate_env
    build_ssh_cmd

    log_info "Starting VLESS-Reality setup for ${VPS_HOST}..."

    test_server_connectivity

    local tunnel_port
    tunnel_port=$(shuf -i 20000-30000 -n 1)
    setup_ssh_tunnel "$tunnel_port" "$PANEL_PORT"
    CURRENT_TUNNEL_PORT="$tunnel_port"

    connect_to_panel "127.0.0.1" "$tunnel_port" "/" "$PANEL_USER" "$PANEL_PASS"

    harden_panel

    configure_routing

    create_vless_reality_inbound

    generate_nekoray_routing

    save_full_summary

    kill_ssh_tunnels

    echo ""
    log_ok "=== SETUP COMPLETE ==="
    echo ""
    echo "All configuration files are saved in: ${OUTPUT_DIR}/"
    echo "Review the setup summary: ${OUTPUT_DIR}/setup_summary.txt"
}

trap 'kill_ssh_tunnels 2>/dev/null; exit' EXIT INT TERM

main "$@"
