#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# UTEM Security Scanner — GitLab CI/CD integration script
# Publisher: Innavoto India Pvt Ltd
# https://utem.innavoto.com
#
# Requirements: bash, curl, jq (all available in alpine:3.20)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

if [ "${CI_DEBUG_TRACE:-false}" = "true" ]; then
    echo "WARNING: CI_DEBUG_TRACE is enabled. UTEM_API_KEY may appear in job logs." >&2
    echo "Disable CI_DEBUG_TRACE before running in production." >&2
fi

# ── Constants ────────────────────────────────────────────────────────────────
readonly VERSION="1.0.0"
readonly POLL_INTERVAL=10
readonly SEVERITY_ORDER="critical high medium low info"

# ── Configuration (from environment) ────────────────────────────────────────
UTEM_API_KEY="${UTEM_API_KEY:-}"
UTEM_BASE_URL="${UTEM_BASE_URL:-https://utem.innavoto.com}"
UTEM_SCAN_TYPE="${UTEM_SCAN_TYPE:-code}"
UTEM_SEVERITY_THRESHOLD="${UTEM_SEVERITY_THRESHOLD:-high}"
UTEM_FAIL_ON_FINDINGS="${UTEM_FAIL_ON_FINDINGS:-true}"
UTEM_TIMEOUT="${UTEM_TIMEOUT:-300}"
UTEM_MODULES="${UTEM_MODULES:-}"

# GitLab-provided variables
CI_PROJECT_PATH="${CI_PROJECT_PATH:-unknown/project}"
CI_PROJECT_URL="${CI_PROJECT_URL:-}"
CI_COMMIT_SHA="${CI_COMMIT_SHA:-}"
CI_COMMIT_REF_NAME="${CI_COMMIT_REF_NAME:-}"
CI_PIPELINE_ID="${CI_PIPELINE_ID:-}"
CI_JOB_URL="${CI_JOB_URL:-}"

# ── Output files ─────────────────────────────────────────────────────────────
RESULTS_JSON="utem-results.json"
RESULTS_XML="utem-results.xml"
SUMMARY_TXT="utem-summary.txt"

# ── Helpers ──────────────────────────────────────────────────────────────────

log() {
    echo "[UTEM] $(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"
}

error() {
    echo "[UTEM] ERROR: $*" >&2
}

separator() {
    echo "────────────────────────────────────────────────────────────────"
}

# Map severity string to numeric rank for threshold comparison.
# Lower rank = higher severity.
severity_rank() {
    case "${1,,}" in
        critical) echo 0 ;;
        high)     echo 1 ;;
        medium)   echo 2 ;;
        low)      echo 3 ;;
        info)     echo 4 ;;
        *)        echo 5 ;;
    esac
}

# Perform an authenticated GET request
api_get() {
    local url="$1"
    local trace_was_on=false
    [[ "$-" == *x* ]] && trace_was_on=true
    { set +x; } 2>/dev/null
    local response
    response=$(curl -fsSL \
        --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 30 \
        --max-redirs 3 \
        -H "Authorization: Bearer ${UTEM_API_KEY}" \
        -H "Content-Type: application/json" \
        "${url}") || { $trace_was_on && set -x; return 1; }
    $trace_was_on && set -x
    echo "${response}"
}

# Perform an authenticated POST request
api_post() {
    local url="$1"
    local data="$2"
    local trace_was_on=false
    [[ "$-" == *x* ]] && trace_was_on=true
    { set +x; } 2>/dev/null
    local response
    response=$(curl -fsSL \
        -X POST \
        --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 30 \
        --max-redirs 3 \
        -H "Authorization: Bearer ${UTEM_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "${data}" \
        "${url}") || { $trace_was_on && set -x; return 1; }
    $trace_was_on && set -x
    echo "${response}"
}

# ── Validation ───────────────────────────────────────────────────────────────

validate_inputs() {
    if [ -z "${UTEM_API_KEY}" ]; then
        error "UTEM_API_KEY is not set."
        error ""
        error "Set it in GitLab -> Settings -> CI/CD -> Variables (masked & protected)."
        error "Generate an API key at: ${UTEM_BASE_URL}/settings/api-keys"
        exit 1
    fi

    # Enforce HTTPS
    if [[ "${UTEM_BASE_URL}" != https://* ]]; then
        error "UTEM_BASE_URL must use HTTPS. Got: '${UTEM_BASE_URL}'"
        exit 1
    fi

    # Validate scan type
    case "${UTEM_SCAN_TYPE}" in
        code|full|sbom|container|infrastructure) ;;
        *)
            error "Invalid UTEM_SCAN_TYPE: '${UTEM_SCAN_TYPE}'"
            error "Allowed values: code, full, sbom, container, infrastructure"
            exit 1
            ;;
    esac

    # Validate severity threshold
    local rank
    rank=$(severity_rank "${UTEM_SEVERITY_THRESHOLD}")
    if [ "${rank}" -gt 4 ]; then
        error "Invalid UTEM_SEVERITY_THRESHOLD: '${UTEM_SEVERITY_THRESHOLD}'"
        error "Allowed values: critical, high, medium, low, info"
        exit 1
    fi

    # Validate timeout is numeric
    if ! echo "${UTEM_TIMEOUT}" | grep -qE '^[0-9]+$'; then
        error "UTEM_TIMEOUT must be a positive integer (seconds). Got: '${UTEM_TIMEOUT}'"
        exit 1
    fi
}

# ── Scan lifecycle ───────────────────────────────────────────────────────────

trigger_scan() {
    log "Triggering ${UTEM_SCAN_TYPE} scan for ${CI_PROJECT_PATH}..."

    local payload
    payload=$(jq -n \
        --arg target "${CI_PROJECT_PATH}" \
        --arg target_url "${CI_PROJECT_URL}" \
        --arg scan_type "${UTEM_SCAN_TYPE}" \
        --arg commit_sha "${CI_COMMIT_SHA}" \
        --arg branch "${CI_COMMIT_REF_NAME}" \
        --arg pipeline_id "${CI_PIPELINE_ID}" \
        --arg modules "${UTEM_MODULES}" \
        '{
            target: $target,
            target_url: $target_url,
            scan_type: $scan_type,
            source: "gitlab-ci",
            metadata: {
                commit_sha: $commit_sha,
                branch: $branch,
                pipeline_id: $pipeline_id,
                ci_job_url: env.CI_JOB_URL
            }
        } + (if $modules != "" then {modules: ($modules | split(","))} else {} end)'
    )

    local response
    response=$(api_post "${UTEM_BASE_URL}/api/v1/scans" "${payload}") || {
        error "Failed to trigger scan. HTTP request failed."
        error "Check UTEM_BASE_URL (${UTEM_BASE_URL}) and UTEM_API_KEY."
        exit 1
    }

    SCAN_ID=$(echo "${response}" | jq -r '.id // .scan_id // empty')
    if [ -z "${SCAN_ID}" ]; then
        local error_detail
        error_detail=$(echo "${response}" | jq -r '.detail // .message // .error // "unknown"' 2>/dev/null || echo "unparseable")
        error "Scan trigger failed: ${error_detail}"
        exit 1
    fi

    if ! echo "${SCAN_ID}" | grep -qE '^[a-zA-Z0-9_-]{1,128}$'; then
        error "Invalid scan ID format: '${SCAN_ID}'"
        exit 1
    fi

    log "Scan triggered successfully. Scan ID: ${SCAN_ID}"
}

poll_scan() {
    log "Polling scan status (timeout: ${UTEM_TIMEOUT}s, interval: ${POLL_INTERVAL}s)..."

    local elapsed=0
    local status=""

    while [ "${elapsed}" -lt "${UTEM_TIMEOUT}" ]; do
        local response
        response=$(api_get "${UTEM_BASE_URL}/api/v1/scans/${SCAN_ID}") || {
            error "Failed to fetch scan status."
            exit 1
        }

        status=$(echo "${response}" | jq -r '.status // "unknown"')

        case "${status}" in
            completed|finished|done)
                log "Scan completed."
                return 0
                ;;
            failed|error|cancelled)
                error "Scan ended with status: ${status}"
                local detail
                detail=$(echo "${response}" | jq -r '.detail // .error // "No details available"')
                error "Detail: ${detail}"
                exit 1
                ;;
            queued|running|in_progress|pending|scanning)
                printf "\r[UTEM] Status: %-15s Elapsed: %ds / %ds" "${status}" "${elapsed}" "${UTEM_TIMEOUT}"
                ;;
            *)
                log "Unknown status: ${status}. Continuing to poll..."
                ;;
        esac

        sleep "${POLL_INTERVAL}"
        elapsed=$((elapsed + POLL_INTERVAL))
    done

    echo ""
    error "Scan timed out after ${UTEM_TIMEOUT}s (last status: ${status})"
    error "Increase UTEM_TIMEOUT or check the UTEM dashboard for scan ${SCAN_ID}."
    exit 1
}

fetch_results() {
    log "Fetching scan results..."

    local response
    response=$(api_get "${UTEM_BASE_URL}/api/v1/scans/${SCAN_ID}/results") || {
        error "Failed to fetch scan results."
        exit 1
    }

    # Normalize: results might be at top level or nested under .findings / .items / .results
    local findings
    findings=$(echo "${response}" | jq '
        if type == "array" then .
        elif .findings then .findings
        elif .items then .items
        elif .results then .results
        else []
        end
    ')

    # Store the full response and normalized findings
    echo "${response}" | jq '.' > "${RESULTS_JSON}"

    # Return findings array for processing
    echo "${findings}"
}

# ── Report generation ────────────────────────────────────────────────────────

count_by_severity() {
    local findings="$1"
    local severity="$2"
    echo "${findings}" | jq --arg sev "${severity}" '
        [.[] | select(
            (.severity // .risk_level // "unknown") |
            ascii_downcase == ($sev | ascii_downcase)
        )] | length
    '
}

generate_junit_xml() {
    local findings="$1"

    local total
    total=$(echo "${findings}" | jq 'length')

    # Count failures: findings at or above the threshold severity
    local threshold_rank
    threshold_rank=$(severity_rank "${UTEM_SEVERITY_THRESHOLD}")

    local failures=0
    for sev in ${SEVERITY_ORDER}; do
        local rank
        rank=$(severity_rank "${sev}")
        if [ "${rank}" -le "${threshold_rank}" ]; then
            local count
            count=$(count_by_severity "${findings}" "${sev}")
            failures=$((failures + count))
        fi
    done

    # Build JUnit XML
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo "<testsuites>"
        echo "  <testsuite name=\"UTEM Security Scan\" tests=\"${total}\" failures=\"${failures}\" errors=\"0\" timestamp=\"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\">"

        if [ "${total}" -eq 0 ]; then
            echo "    <testcase name=\"No findings\" classname=\"utem.${UTEM_SCAN_TYPE}\" />"
        else
            echo "${findings}" | jq -r '
                def xml_escape: gsub("[<>&\"]"; {
                    "<": "&lt;",
                    ">": "&gt;",
                    "&": "&amp;",
                    "\"": "&quot;"
                });
                def cdata_escape: gsub("]]>"; "]]]]><![CDATA[>");
                .[] |
                (.severity // .risk_level // "unknown" | ascii_downcase) as $sev |
                @text "    <testcase name=\"\(.title // .name // .rule_id // "Finding" | xml_escape)\" classname=\"utem.\($sev | xml_escape)\">\n      <failure message=\"\(.description // .detail // "Security finding detected" | xml_escape | .[0:500])\" type=\"\($sev | xml_escape)\"><![CDATA[\nSeverity: \(.severity // .risk_level // "unknown" | cdata_escape)\nRule: \(.rule_id // "N/A" | cdata_escape)\nFile: \(.file // .location // .resource // "N/A" | cdata_escape)\nLine: \(.line // .line_number // "N/A" | tostring | cdata_escape)\nCVE: \(.cve_id // .cve // "N/A" | cdata_escape)\nRemediation: \(.remediation // .fix // "See UTEM dashboard for details" | cdata_escape)\n]]></failure>\n    </testcase>"
            '
        fi

        echo "  </testsuite>"
        echo "</testsuites>"
    } > "${RESULTS_XML}"

    log "JUnit report written to ${RESULTS_XML}"
}

generate_summary() {
    local findings="$1"

    local total
    total=$(echo "${findings}" | jq 'length')

    local critical high medium low info
    critical=$(count_by_severity "${findings}" "critical")
    high=$(count_by_severity "${findings}" "high")
    medium=$(count_by_severity "${findings}" "medium")
    low=$(count_by_severity "${findings}" "low")
    info=$(count_by_severity "${findings}" "info")

    {
        separator
        echo "  UTEM Security Scan Report v${VERSION}"
        separator
        echo ""
        echo "  Project:    ${CI_PROJECT_PATH}"
        echo "  Branch:     ${CI_COMMIT_REF_NAME}"
        echo "  Commit:     ${CI_COMMIT_SHA:0:8}"
        echo "  Scan Type:  ${UTEM_SCAN_TYPE}"
        echo "  Scan ID:    ${SCAN_ID}"
        echo "  Threshold:  ${UTEM_SEVERITY_THRESHOLD}"
        echo "  Fail on:    ${UTEM_FAIL_ON_FINDINGS}"
        echo ""
        separator
        echo "  Findings Summary"
        separator
        echo ""
        printf "  %-12s %s\n" "CRITICAL" "${critical}"
        printf "  %-12s %s\n" "HIGH" "${high}"
        printf "  %-12s %s\n" "MEDIUM" "${medium}"
        printf "  %-12s %s\n" "LOW" "${low}"
        printf "  %-12s %s\n" "INFO" "${info}"
        echo "  ────────────────────"
        printf "  %-12s %s\n" "TOTAL" "${total}"
        echo ""
        separator
    } | tee "${SUMMARY_TXT}"

    # Determine pass/fail
    local threshold_rank
    threshold_rank=$(severity_rank "${UTEM_SEVERITY_THRESHOLD}")

    local blocking=0
    for sev in ${SEVERITY_ORDER}; do
        local rank
        rank=$(severity_rank "${sev}")
        if [ "${rank}" -le "${threshold_rank}" ]; then
            local count
            count=$(count_by_severity "${findings}" "${sev}")
            blocking=$((blocking + count))
        fi
    done

    if [ "${blocking}" -gt 0 ]; then
        log "Found ${blocking} finding(s) at or above '${UTEM_SEVERITY_THRESHOLD}' severity."
        if [ "${UTEM_FAIL_ON_FINDINGS}" = "true" ]; then
            error "Pipeline FAILED — ${blocking} finding(s) exceed threshold."
            error "Review: ${UTEM_BASE_URL}/scans/${SCAN_ID}"
            return 1
        else
            log "UTEM_FAIL_ON_FINDINGS=false — pipeline continues despite findings."
            return 0
        fi
    else
        log "No findings at or above '${UTEM_SEVERITY_THRESHOLD}' severity. Pipeline PASSED."
        return 0
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    echo ""
    separator
    log "UTEM Security Scanner v${VERSION}"
    log "Innavoto India Pvt Ltd — https://utem.innavoto.com"
    separator
    echo ""

    # Step 1: Validate inputs
    validate_inputs

    # Step 2: Trigger scan
    trigger_scan

    # Step 3: Poll until completion
    poll_scan
    echo ""

    # Step 4: Fetch results
    local findings
    findings=$(fetch_results)

    # Step 5: Generate reports
    generate_junit_xml "${findings}"

    # Step 6: Print summary and determine exit code
    generate_summary "${findings}"
}

main "$@"
