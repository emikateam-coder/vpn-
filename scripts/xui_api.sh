#!/usr/bin/env bash
#
# 3X-UI Panel API library
# Provides functions to interact with the 3X-UI panel REST API
#

set -euo pipefail

XUI_COOKIE_JAR="/tmp/xui_cookies.txt"
XUI_BASE_URL=""

xui_init() {
    local host="${1:?Host required}"
    local port="${2:-2053}"
    local path="${3:-/}"

    [[ "$path" == "/" ]] || path="/${path#/}"
    [[ "$path" == */ ]] || path="${path}/"

    XUI_BASE_URL="http://${host}:${port}${path}"
    rm -f "$XUI_COOKIE_JAR"
}

xui_login() {
    local username="${1:?Username required}"
    local password="${2:?Password required}"

    local response
    response=$(curl -s -w "\n%{http_code}" \
        -c "$XUI_COOKIE_JAR" \
        -X POST "${XUI_BASE_URL}login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${username}&password=${password}" \
        --connect-timeout 10 \
        --max-time 30)

    local http_code body
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)

    if [[ "$http_code" != "200" ]]; then
        echo "[ERROR] Login failed with HTTP $http_code" >&2
        echo "$body" >&2
        return 1
    fi

    local success
    success=$(echo "$body" | jq -r '.success // false')
    if [[ "$success" != "true" ]]; then
        echo "[ERROR] Login failed: $(echo "$body" | jq -r '.msg // "unknown error"')" >&2
        return 1
    fi

    echo "[OK] Successfully logged in to 3X-UI panel"
}

xui_api_call() {
    local method="${1:?Method required}"
    local endpoint="${2:?Endpoint required}"
    local data="${3:-}"

    endpoint="${endpoint#/}"
    local url="${XUI_BASE_URL}panel/api/${endpoint}"

    local curl_args=(-s -w "\n%{http_code}" -b "$XUI_COOKIE_JAR" -X "$method" --connect-timeout 10 --max-time 30)

    if [[ -n "$data" ]]; then
        curl_args+=(-H "Content-Type: application/json" -d "$data")
    fi

    local response
    response=$(curl "${curl_args[@]}" "$url")

    local http_code body
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)

    if [[ "$http_code" != "200" ]]; then
        echo "[ERROR] API call failed: $method $endpoint => HTTP $http_code" >&2
        echo "$body" >&2
        return 1
    fi

    echo "$body"
}

xui_get_inbounds() {
    xui_api_call GET "inbounds/list"
}

xui_add_inbound() {
    local data="${1:?Inbound JSON data required}"
    xui_api_call POST "inbounds/add" "$data"
}

xui_get_inbound() {
    local id="${1:?Inbound ID required}"
    xui_api_call GET "inbounds/get/${id}"
}

xui_update_inbound() {
    local id="${1:?Inbound ID required}"
    local data="${2:?Update data required}"
    xui_api_call POST "inbounds/update/${id}" "$data"
}

xui_delete_inbound() {
    local id="${1:?Inbound ID required}"
    xui_api_call POST "inbounds/del/${id}"
}

xui_update_setting() {
    local data="${1:?Settings data required}"

    local url="${XUI_BASE_URL}panel/setting/update"
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -b "$XUI_COOKIE_JAR" \
        -X POST "$url" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "$data" \
        --connect-timeout 10 \
        --max-time 30)

    local http_code body
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)

    if [[ "$http_code" != "200" ]]; then
        echo "[ERROR] Setting update failed: HTTP $http_code" >&2
        return 1
    fi

    echo "$body"
}

xui_restart_panel() {
    local url="${XUI_BASE_URL}panel/setting/restartPanel"
    curl -s -b "$XUI_COOKIE_JAR" -X POST "$url" \
        --connect-timeout 10 --max-time 30 || true
    echo "[OK] Panel restart requested"
}

xui_update_xray_setting() {
    local data="${1:?Xray settings data required}"

    local url="${XUI_BASE_URL}panel/xray"
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -b "$XUI_COOKIE_JAR" \
        -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$data" \
        --connect-timeout 10 \
        --max-time 30)

    local http_code body
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)

    if [[ "$http_code" != "200" ]]; then
        echo "[ERROR] Xray setting update failed: HTTP $http_code" >&2
        return 1
    fi

    echo "$body"
}

xui_get_xray_setting() {
    local url="${XUI_BASE_URL}panel/xray"
    curl -s -b "$XUI_COOKIE_JAR" "$url" --connect-timeout 10 --max-time 30
}
