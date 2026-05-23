#!/usr/bin/env bash
#
# 3X-UI Panel API library
# Provides functions to interact with the 3X-UI panel REST API
# Supports both HTTP and HTTPS panels with CSRF token handling
#

set -euo pipefail

XUI_COOKIE_JAR="/tmp/xui_cookies.txt"
XUI_BASE_URL=""
XUI_CSRF_TOKEN=""
XUI_USE_HTTPS="false"

xui_init() {
    local host="${1:?Host required}"
    local port="${2:-2053}"
    local path="${3:-/}"

    [[ "$path" == "/" ]] || path="/${path#/}"
    [[ "$path" == */ ]] || path="${path}/"

    rm -f "$XUI_COOKIE_JAR"
    XUI_CSRF_TOKEN=""
    XUI_USE_HTTPS="false"

    local https_code
    https_code=$(curl -sk --connect-timeout 5 --max-time 10 "https://${host}:${port}${path}" -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")

    if echo "$https_code" | grep -qE "^(200|301|302|403)$"; then
        XUI_USE_HTTPS="true"
        XUI_BASE_URL="https://${host}:${port}${path}"
    else
        XUI_BASE_URL="http://${host}:${port}${path}"
    fi

    _xui_fetch_csrf
}

_xui_fetch_csrf() {
    local html token=""

    for page in "" "panel/"; do
        html=$(curl -sk --connect-timeout 10 --max-time 15 -b "$XUI_COOKIE_JAR" -c "$XUI_COOKIE_JAR" "${XUI_BASE_URL}${page}" 2>/dev/null || true)
        token=$(echo "$html" | grep -oP 'csrf-token"\s+content="\K[^"]+' 2>/dev/null || true)
        if [[ -n "$token" ]]; then
            break
        fi
    done

    XUI_CSRF_TOKEN="$token"
}

_xui_build_curl_cmd() {
    XUI_CURL_CMD=(curl -s --connect-timeout 10 --max-time 30 -b "$XUI_COOKIE_JAR" -c "$XUI_COOKIE_JAR")
    if [[ "$XUI_USE_HTTPS" == "true" ]]; then
        XUI_CURL_CMD+=(-k)
    fi
    if [[ -n "$XUI_CSRF_TOKEN" ]]; then
        XUI_CURL_CMD+=(-H "X-CSRF-Token: ${XUI_CSRF_TOKEN}")
    fi
}

xui_login() {
    local username="${1:?Username required}"
    local password="${2:?Password required}"

    if [[ -z "$XUI_CSRF_TOKEN" ]]; then
        _xui_fetch_csrf
    fi

    _xui_build_curl_cmd

    local response
    response=$("${XUI_CURL_CMD[@]}" \
        -w "\n%{http_code}" \
        -X POST "${XUI_BASE_URL}login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${username}&password=${password}")

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

    _xui_fetch_csrf

    echo "[OK] Successfully logged in to 3X-UI panel"
}

xui_api_call() {
    local method="${1:?Method required}"
    local endpoint="${2:?Endpoint required}"
    local data="${3:-}"

    endpoint="${endpoint#/}"
    local url="${XUI_BASE_URL}panel/api/${endpoint}"

    _xui_build_curl_cmd
    XUI_CURL_CMD+=(-w "\n%{http_code}" -X "$method")

    if [[ -n "$data" ]]; then
        XUI_CURL_CMD+=(-H "Content-Type: application/json" -d "$data")
    fi

    local response
    response=$("${XUI_CURL_CMD[@]}" "$url")

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

    _xui_build_curl_cmd

    local response
    response=$("${XUI_CURL_CMD[@]}" \
        -w "\n%{http_code}" \
        -X POST "$url" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "$data")

    local http_code body
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)

    if [[ "$http_code" != "200" ]]; then
        echo "[ERROR] Setting update failed: HTTP $http_code" >&2
        return 1
    fi

    echo "$body"
}

xui_update_user() {
    local old_user="${1:?Old username required}"
    local old_pass="${2:?Old password required}"
    local new_user="${3:?New username required}"
    local new_pass="${4:?New password required}"

    local url="${XUI_BASE_URL}panel/setting/updateUser"

    _xui_build_curl_cmd

    local response
    response=$("${XUI_CURL_CMD[@]}" \
        -w "\n%{http_code}" \
        -X POST "$url" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "oldUsername=${old_user}&oldPassword=${old_pass}&newUsername=${new_user}&newPassword=${new_pass}")

    local http_code body
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)

    if [[ "$http_code" != "200" ]]; then
        echo "[ERROR] User update failed: HTTP $http_code" >&2
        return 1
    fi

    echo "$body"
}

xui_restart_panel() {
    local url="${XUI_BASE_URL}panel/setting/restartPanel"

    _xui_build_curl_cmd

    "${XUI_CURL_CMD[@]}" -X POST "$url" || true
    echo "[OK] Panel restart requested"
}

xui_update_xray_setting() {
    local data="${1:?Xray settings data required}"
    local url="${XUI_BASE_URL}panel/xray"

    _xui_build_curl_cmd

    local response
    response=$("${XUI_CURL_CMD[@]}" \
        -w "\n%{http_code}" \
        -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "$data")

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

    _xui_build_curl_cmd

    "${XUI_CURL_CMD[@]}" "$url"
}
