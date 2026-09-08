#!/usr/bin/env bash
set -euo pipefail

pids=()
cleanup() { for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null || true; done; }; trap cleanup EXIT

export APP__DATABASE__URL="${APP__DATABASE__URL:-postgresql://harir@localhost:5432/bankdb}"

cargo build --workspace

services=(
    "party-service 3001 parties party_id 1000 10"
    "individual-profile-service 3002 individual-profiles individual_id 800 8"
    "corporate-profile-service 3003 corporate-profiles corporate_id 200 2"
    "customer-address-service 3004 customer-addresses address_id 1000 10"
    "customer-contact-service 3005 customer-contacts contact_id 1000 10"
    "customer-identification-service 3006 customer-identifications identification_id 1000 10"
    "customer-employment-service 3007 customer-employment employment_id 800 8"
    "customer-kyc-service 3008 customer-kyc kyc_id 1000 10"
)

fail=0
for entry in "${services[@]}"; do
    read -r name port route pk total pages <<< "$entry"
    echo "=== $name (port $port, /$route) ==="
    ./target/debug/"$name" > /tmp/"$name".log 2>&1 &
    pid=$!
    pids+=("$pid")
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

    p1=$(curl -s --retry-connrefused --retry 5 "http://localhost:$port/$route?page=1&page_size=100")
    p2=$(curl -s --retry-connrefused --retry 5 "http://localhost:$port/$route?page=2&page_size=100")
    check "page 1 row count"              "100"    "$(jq '.data | length' <<< "$p1")"
    check "page 1 metadata"               "$total" "$(jq '.pagination.total_records' <<< "$p1")"
    check "page 1 total pages"            "$pages" "$(jq '.pagination.total_pages' <<< "$p1")"
    check "page 1 first pk is numeric"    "true"   "$(jq ".data[0].$pk | type == \"number\"" <<< "$p1")"
    p1_last=$(jq ".data[-1].$pk" <<< "$p1")
    p2_first=$(jq ".data[0].$pk" <<< "$p2")
    check "page 2 starts after page 1 ends" "true" "$([[ "$p2_first" -gt "$p1_last" ]] && echo true || echo false)"
    check "page 2 row count"              "100"    "$(jq '.data | length' <<< "$p2")"
    check "beyond-last page empty"        "0"      "$(curl -s --retry-connrefused --retry 5 "http://localhost:$port/$route?page=$((pages + 1))" | jq '.data | length')"
    check "health 200"                    "200"    "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/health")"
    check "page=0 rejected"               "400"    "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/$route?page=0")"
    check "page_size=101 rejected"        "400"    "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/$route?page_size=101")"

    enum_filter=""
    case "$name" in
        party-service)
            enum_filter='([.data[].party_type] | all(. == "IN" or . == "CORP")) and ([.data[].customer_segment] | all(. == "RETAIL" or . == "WEALTH" or . == "SME" or . == "CORPORATE" or . == "INSTITUTIONAL")) and ([.data[].customer_status] | all(. == "PENDING" or . == "ACTIVE" or . == "INACTIVE" or . == "DORMANT" or . == "SUSPENDED" or . == "CLOSED"))'
            ;;
        customer-address-service)
            enum_filter='[.data[].address_type] | all(. == "RESIDENTIAL" or . == "MAILING" or . == "REGISTERED" or . == "OFFICE" or . == "BILLING")'
            ;;
        customer-contact-service)
            enum_filter='[.data[].contact_type] | all(. == "MOBILE" or . == "LANDLINE" or . == "WORK_PHONE" or . == "EMAIL" or . == "FAX")'
            ;;
        customer-identification-service)
            enum_filter='[.data[].id_type] | all(. == "PASSPORT" or . == "NATIONAL_ID" or . == "DRIVERS_LICENSE" or . == "TAX_ID" or . == "SSN")'
            ;;
        customer-employment-service)
            enum_filter='[.data[].employment_status] | all(. == "EMPLOYED" or . == "SELF_EMPLOYED" or . == "UNEMPLOYED" or . == "RETIRED" or . == "STUDENT")'
            ;;
        customer-kyc-service)
            enum_filter='([.data[].kyc_status] | all(. == "PENDING" or . == "APPROVED" or . == "REJECTED" or . == "RE_KYC_REQUIRED")) and ([.data[].risk_rating] | all(. == "LOW" or . == "MEDIUM" or . == "HIGH" or . == "PROHIBITED"))'
            ;;
    esac
    if [[ -n "$enum_filter" ]]; then
        check "enum values valid" "true" "$(jq -e "$enum_filter" <<< "$p1" > /dev/null && echo true || echo false)"
    fi

    kill "$pid"
    wait "$pid" 2>/dev/null || true
done

if [[ $fail -ne 0 ]]; then
    echo "VERIFICATION FAILED"
    exit 1
fi
echo "ALL SERVICES VERIFIED"
