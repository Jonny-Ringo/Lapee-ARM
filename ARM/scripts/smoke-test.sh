#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${LAPEE_BASE_URL:-http://127.0.0.1:8734}"

request() {
    label="$1"
    method="$2"
    path="$3"
    tmp="$(mktemp)"
    status="$(
        curl -sS -o "$tmp" -w '%{http_code}' \
            -X "$method" \
            -H 'accept: application/json' \
            -H 'accept-bundle: true' \
            "$BASE_URL$path"
    )"
    if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
        echo "FAIL $label: HTTP $status $method $path" >&2
        sed -n '1,20p' "$tmp" >&2
        rm -f "$tmp"
        return 1
    fi
    bytes="$(wc -c < "$tmp" | tr -d ' ')"
    rm -f "$tmp"
    echo "OK   $label: HTTP $status, ${bytes} bytes"
}

request "http server" OPTIONS "/~meta@1.0/info"
request "device dispatch" GET "/~system@1.0/info"
request "system report" GET "/~system@1.0/all"

echo "Smoke test passed for $BASE_URL"
