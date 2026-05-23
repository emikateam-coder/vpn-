#!/usr/bin/env bash
#
# Generate X25519 key pair for VLESS Reality
# Outputs JSON with privateKey and publicKey
#

set -euo pipefail

generate_x25519_keys() {
    local private_key public_key

    private_key=$(openssl genpkey -algorithm X25519 2>/dev/null | openssl pkey -text -noout 2>/dev/null | grep -A5 "priv:" | tail -4 | tr -d ' :\n' | xxd -r -p | base64 | tr '/+' '_-' | tr -d '=')
    public_key=$(openssl genpkey -algorithm X25519 2>/dev/null | openssl pkey -text -noout 2>/dev/null | grep -A5 "pub:" | tail -4 | tr -d ' :\n' | xxd -r -p | base64 | tr '/+' '_-' | tr -d '=')

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        echo "[ERROR] Failed to generate X25519 keys via openssl, falling back to xray binary" >&2
        return 1
    fi

    jq -n --arg priv "$private_key" --arg pub "$public_key" \
        '{"privateKey": $priv, "publicKey": $pub}'
}

generate_x25519_via_xray() {
    local ssh_cmd="${1:?SSH command required}"
    local output
    output=$($ssh_cmd "docker exec 3x-ui /app/bin/xray x25519 2>/dev/null || /usr/local/bin/xray x25519 2>/dev/null || xray x25519 2>/dev/null" 2>/dev/null)

    local private_key public_key
    private_key=$(echo "$output" | grep -i "private" | awk '{print $NF}')
    public_key=$(echo "$output" | grep -i "public" | awk '{print $NF}')

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        echo "[ERROR] Failed to generate keys via xray binary" >&2
        return 1
    fi

    jq -n --arg priv "$private_key" --arg pub "$public_key" \
        '{"privateKey": $priv, "publicKey": $pub}'
}

generate_short_id() {
    openssl rand -hex 8
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "=== X25519 Key Pair ==="
    generate_x25519_keys || echo "[WARN] Local generation failed"
    echo ""
    echo "=== Short ID ==="
    generate_short_id
    echo ""
    echo "=== UUID ==="
    generate_uuid
fi
