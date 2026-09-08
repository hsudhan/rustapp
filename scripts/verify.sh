#!/usr/bin/env bash
set -euo pipefail

export APP__DATABASE__URL="${APP__DATABASE__URL:-postgresql://harir@localhost:5432/bankdb}"

cargo build --workspace

services=(
    "party-service 3001 parties party_id 1000 10 9 109"
    "individual-profile-service 3002 individual-profiles individual_id 800 8 9 109"
    "corporate-profile-service 3003 corporate-profiles corporate_id 200 2 1 101"
    "customer-address-service 3004 customer-addresses address_id 1000 10 9 109"
    "customer-contact-service 3005 customer-contacts contact_id 1000 10 9 109"
    "customer-identification-service 3006 customer-identifications identification_id 1000 10 2 102"
    "customer-employment-service 3007 customer-employment employment_id 800 8 9 109"
    "customer-kyc-service 3008 customer-kyc kyc_id 1000 10 1 101"
)

fail=0
for entry in "${services[@]}"; do
    read -r name port route pk total pages first1 first2 <<< "$entry"
    echo "=== $name (port $port, /$route) ==="
    ./target/debug/"$name" > /tmp/"$name".log 2>&1 &
    pid=$!
    sleep 1

    check() {
        local desc="$1" expected="$2" actual="$3"
        if [[ "$expected" == "$actual" ]]; then
            echo "  PASS: $desc ($actual)"
        else
            echo "  FAIL: $desc (expected $expected, got $actual)"
            fail=1
        fi
    }

    p1=$(curl -s "http://localhost:$port/$route?page=1&page_size=100")
    p2=$(curl -s "http://localhost:$port/$route?page=2&page_size=100")
    check "page 1 row count"        "100"    "$(jq '.data | length' <<< "$p1")"
    check "page 1 metadata"         "$total" "$(jq '.pagination.total_records' <<< "$p1")"
    check "page 1 total pages"      "$pages" "$(jq '.pagination.total_pages' <<< "$p1")"
    check "page 1 first pk"         "$first1" "$(jq ".data[0].$pk" <<< "$p1")"
    check "page 2 first pk"         "$first2" "$(jq ".data[0].$pk" <<< "$p2")"
    check "page 2 row count"        "100"    "$(jq '.data | length' <<< "$p2")"
    check "beyond-last page empty"  "0"      "$(curl -s "http://localhost:$port/$route?page=$((pages + 1))" | jq '.data | length')"
    check "health 200"              "200"    "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/health")"
    check "page=0 rejected"         "400"    "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/$route?page=0")"
    check "page_size=101 rejected"  "400"    "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/$route?page_size=101")"

    kill "$pid"
    wait "$pid" 2>/dev/null || true
done

if [[ $fail -ne 0 ]]; then
    echo "VERIFICATION FAILED"
    exit 1
fi
echo "ALL SERVICES VERIFIED"
