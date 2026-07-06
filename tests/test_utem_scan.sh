#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Test suite for scripts/utem-scan.sh.
#
# Exercises the script's logic — input validation, scan trigger, status
# polling, result normalization, JUnit report generation, and severity-
# threshold gating — against a mocked UTEM API (tests/mocks/curl), so no
# network access or real UTEM instance is required.
#
# Run:  bash tests/test_utem_scan.sh
# Exit: 0 if every assertion passed, 1 otherwise (prints a FAIL line per
#       failing assertion plus a final summary).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCAN_SCRIPT="${REPO_ROOT}/scripts/utem-scan.sh"
MOCK_CURL_DIR="${SCRIPT_DIR}/mocks"

RESULTS_LOG="$(mktemp)"
trap 'rm -f "${RESULTS_LOG}"' EXIT

CURRENT_TEST=""

record_pass() { echo "PASS ${CURRENT_TEST}" >> "${RESULTS_LOG}"; }
record_fail() { echo "FAIL ${CURRENT_TEST} :: $*" >> "${RESULTS_LOG}"; }

assert_eq() {
    local actual="$1" expected="$2" msg="${3:-}"
    if [[ "${actual}" == "${expected}" ]]; then
        record_pass
    else
        record_fail "expected [${expected}] got [${actual}] ${msg}"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        record_pass
    else
        record_fail "expected output to contain [${needle}] ${msg} -- got: ${haystack:0:300}"
    fi
}

assert_file_exists() {
    local path="$1"
    if [[ -f "${path}" ]]; then
        record_pass
    else
        record_fail "expected file to exist: ${path}"
    fi
}

# Build a fresh mock-responses directory populated with the given fixture
# files (name=content pairs) and echo its path.
make_mock_dir() {
    local dir
    dir="$(mktemp -d)"
    while [[ $# -gt 0 ]]; do
        printf '%s' "$2" > "${dir}/$1"
        shift 2
    done
    echo "${dir}"
}

# Runs $2 (a function name) as an isolated test: fresh cwd, fresh env,
# PATH pointed at the mock curl. Body is expected to call assert_* helpers
# and/or set CURRENT_TEST-scoped globals; failures/passes are appended to
# RESULTS_LOG so counts survive the subshell boundary.
run_test() {
    local name="$1" fn="$2"
    CURRENT_TEST="${name}"
    echo "test: ${name}"
    (
        set -uo pipefail
        cd "$(mktemp -d)" || exit 1
        export PATH="${MOCK_CURL_DIR}:${PATH}"
        unset MOCK_CURL_FAIL MOCK_CURL_HTTP_FAIL SCAN_ID
        "${fn}"
    )
}

# ── Unit tests: pure functions ──────────────────────────────────────────────

test_severity_rank() {
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    assert_eq "$(severity_rank critical)" "0"
    assert_eq "$(severity_rank HIGH)" "1"
    assert_eq "$(severity_rank Medium)" "2"
    assert_eq "$(severity_rank low)" "3"
    assert_eq "$(severity_rank info)" "4"
    assert_eq "$(severity_rank bogus)" "5"
}

test_count_by_severity() {
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local findings='[{"severity":"High"},{"risk_level":"high"},{"severity":"low"}]'
    assert_eq "$(count_by_severity "${findings}" high)" "2"
    assert_eq "$(count_by_severity "${findings}" low)" "1"
    assert_eq "$(count_by_severity "${findings}" critical)" "0"
}

# ── Unit tests: validate_inputs ─────────────────────────────────────────────

test_validate_inputs_missing_api_key() {
    export UTEM_API_KEY=""
    export UTEM_BASE_URL="https://utem.test"
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local out rc
    out=$(validate_inputs 2>&1); rc=$?
    assert_eq "${rc}" "1" "missing API key must exit 1"
    assert_contains "${out}" "UTEM_API_KEY is not set"
}

test_validate_inputs_rejects_http() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="http://utem.test"
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local out rc
    out=$(validate_inputs 2>&1); rc=$?
    assert_eq "${rc}" "1" "non-https base url must exit 1"
    assert_contains "${out}" "must use HTTPS"
}

test_validate_inputs_rejects_bad_scan_type() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export UTEM_SCAN_TYPE="bogus"
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local out rc
    out=$(validate_inputs 2>&1); rc=$?
    assert_eq "${rc}" "1" "invalid scan type must exit 1"
    assert_contains "${out}" "Invalid UTEM_SCAN_TYPE"
}

test_validate_inputs_rejects_bad_severity() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export UTEM_SEVERITY_THRESHOLD="apocalyptic"
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local out rc
    out=$(validate_inputs 2>&1); rc=$?
    assert_eq "${rc}" "1" "invalid severity threshold must exit 1"
    assert_contains "${out}" "Invalid UTEM_SEVERITY_THRESHOLD"
}

test_validate_inputs_rejects_non_numeric_timeout() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export UTEM_TIMEOUT="soon"
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local out rc
    out=$(validate_inputs 2>&1); rc=$?
    assert_eq "${rc}" "1" "non-numeric timeout must exit 1"
    assert_contains "${out}" "must be a positive integer"
}

test_validate_inputs_accepts_valid_config() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export UTEM_SCAN_TYPE="code"
    export UTEM_SEVERITY_THRESHOLD="high"
    export UTEM_TIMEOUT="300"
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local rc
    ( validate_inputs ) >/dev/null 2>&1; rc=$?
    assert_eq "${rc}" "0" "valid config must not exit non-zero"
}

# ── Unit tests: trigger_scan (mocked POST /api/v1/scans) ───────────────────

test_trigger_scan_success() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export CI_PROJECT_PATH="acme/widgets"
    export CI_PROJECT_URL="https://gitlab.example.com/acme/widgets"
    export CI_JOB_URL="https://gitlab.example.com/acme/widgets/-/jobs/1"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir trigger.json '{"id":"scan-abc123","status":"queued"}')
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    trigger_scan >/dev/null 2>&1
    assert_eq "${SCAN_ID}" "scan-abc123"
}

test_trigger_scan_missing_id_fails() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export CI_PROJECT_PATH="acme/widgets"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir trigger.json '{"detail":"tenant not found"}')
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local out rc
    out=$(trigger_scan 2>&1); rc=$?
    assert_eq "${rc}" "1" "missing scan id must exit 1"
    assert_contains "${out}" "Scan trigger failed"
}

test_trigger_scan_rejects_malformed_id() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export CI_PROJECT_PATH="acme/widgets"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir trigger.json '{"id":"not a valid id!"}')
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local out rc
    out=$(trigger_scan 2>&1); rc=$?
    assert_eq "${rc}" "1" "malformed scan id must exit 1"
    assert_contains "${out}" "Invalid scan ID format"
}

test_trigger_scan_network_failure() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export CI_PROJECT_PATH="acme/widgets"
    export MOCK_CURL_FAIL="1"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir trigger.json '{"id":"scan-abc123"}')
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local out rc
    out=$(trigger_scan 2>&1); rc=$?
    assert_eq "${rc}" "1" "network failure must exit 1"
    assert_contains "${out}" "Failed to trigger scan"
}

# ── Unit tests: poll_scan (mocked GET /api/v1/scans/<id>) ──────────────────

test_poll_scan_completed_immediately() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export SCAN_ID="scan-abc123"
    export UTEM_TIMEOUT="30"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir status.json '{"status":"completed"}')
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local rc
    ( poll_scan ) >/dev/null 2>&1; rc=$?
    assert_eq "${rc}" "0" "completed status must return 0"
}

test_poll_scan_failed_status() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export SCAN_ID="scan-abc123"
    export UTEM_TIMEOUT="30"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir status.json '{"status":"failed","detail":"engine crashed"}')
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local out rc
    out=$(poll_scan 2>&1); rc=$?
    assert_eq "${rc}" "1" "failed status must exit 1"
    assert_contains "${out}" "engine crashed"
}

test_poll_scan_eventually_completes() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export SCAN_ID="scan-abc123"
    # Bounded and non-zero so a regression in the mock's sequence-advance
    # logic (or the real poll loop) fails fast within a few seconds instead
    # of spinning/blocking forever.
    export UTEM_TIMEOUT="5"
    export UTEM_POLL_INTERVAL="1"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir status_sequence.txt $'{"status":"queued"}\n{"status":"running"}\n{"status":"completed"}')
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local rc
    ( poll_scan ) >/dev/null 2>&1; rc=$?
    assert_eq "${rc}" "0" "must eventually return 0 once status flips to completed"
}

test_poll_scan_times_out() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export SCAN_ID="scan-abc123"
    export UTEM_TIMEOUT="1"
    export UTEM_POLL_INTERVAL="1"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir status.json '{"status":"queued"}')
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local out rc
    out=$(poll_scan 2>&1); rc=$?
    assert_eq "${rc}" "1" "must exit 1 on timeout"
    assert_contains "${out}" "timed out"
}

# ── Unit tests: fetch_results normalization (mocked GET .../results) ───────

test_fetch_results_array_form() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export SCAN_ID="scan-abc123"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir results.json '[{"severity":"high"},{"severity":"low"}]')
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local findings
    findings=$(fetch_results)
    assert_eq "$(echo "${findings}" | jq 'length')" "2"
    assert_file_exists "utem-results.json"
}

test_fetch_results_findings_key_form() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export SCAN_ID="scan-abc123"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir results.json '{"findings":[{"severity":"critical"},{"severity":"low"},{"severity":"info"}]}')
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local findings
    findings=$(fetch_results)
    assert_eq "$(echo "${findings}" | jq 'length')" "3"
}

test_fetch_results_items_key_form() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export SCAN_ID="scan-abc123"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir results.json '{"items":[{"severity":"medium"}]}')
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local findings
    findings=$(fetch_results)
    assert_eq "$(echo "${findings}" | jq 'length')" "1"
}

test_fetch_results_unrecognized_shape_yields_empty() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export SCAN_ID="scan-abc123"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir results.json '{"unexpected":"shape"}')
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local findings
    findings=$(fetch_results)
    assert_eq "$(echo "${findings}" | jq 'length')" "0"
}

# ── Unit tests: report generation ───────────────────────────────────────────

test_generate_junit_xml_no_findings() {
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    generate_junit_xml "[]" >/dev/null
    assert_file_exists "utem-results.xml"
    local xml
    xml=$(cat utem-results.xml)
    assert_contains "${xml}" 'tests="0"'
    assert_contains "${xml}" 'failures="0"'
    assert_contains "${xml}" '<testcase name="No findings"'
}

test_generate_junit_xml_counts_and_escapes() {
    export UTEM_SEVERITY_THRESHOLD="high"
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local findings='[
        {"title":"<script>alert(1)</script> & \"XSS\"","severity":"critical"},
        {"title":"stale dep","severity":"low"}
    ]'
    generate_junit_xml "${findings}" >/dev/null
    assert_file_exists "utem-results.xml"
    local xml
    xml=$(cat utem-results.xml)
    assert_contains "${xml}" 'tests="2"'
    # only the critical finding is >= "high" threshold
    assert_contains "${xml}" 'failures="1"'
    assert_contains "${xml}" "&lt;script&gt;"
    # The XML must be well-formed. This report is entirely self-generated
    # (jq output over our own fixtures, not attacker-controlled input), so
    # XXE is not a real threat model here -- but we reject any DOCTYPE/ENTITY
    # outright before parsing anyway (belt-and-suspenders; a well-formed
    # JUnit report should never contain one) rather than pull in an extra
    # XML toolchain dependency just to check well-formedness.
    if python3 -c "
import sys
content = open('utem-results.xml').read()
if '<!DOCTYPE' in content or '<!ENTITY' in content:
    print('rejected: DOCTYPE/ENTITY not allowed in a generated JUnit report', file=sys.stderr)
    sys.exit(1)
import xml.etree.ElementTree as ET
ET.fromstring(content)
" 2>xml_check_err.log; then
        record_pass
    else
        record_fail "utem-results.xml is not well-formed XML: $(cat xml_check_err.log 2>/dev/null)"
    fi
}

test_generate_summary_pass_below_threshold() {
    export UTEM_SEVERITY_THRESHOLD="high"
    export UTEM_FAIL_ON_FINDINGS="true"
    export SCAN_ID="scan-abc123"
    export UTEM_BASE_URL="https://utem.test"
    export CI_PROJECT_PATH="acme/widgets"
    export CI_COMMIT_REF_NAME="main"
    export CI_COMMIT_SHA="deadbeefdeadbeef"
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local rc
    ( generate_summary '[{"severity":"low"},{"severity":"info"}]' ) >/dev/null 2>&1; rc=$?
    assert_eq "${rc}" "0" "below-threshold findings must not fail the pipeline"
    assert_file_exists "utem-summary.txt"
}

test_generate_summary_fails_at_or_above_threshold() {
    export UTEM_SEVERITY_THRESHOLD="high"
    export UTEM_FAIL_ON_FINDINGS="true"
    export SCAN_ID="scan-abc123"
    export UTEM_BASE_URL="https://utem.test"
    export CI_PROJECT_PATH="acme/widgets"
    export CI_COMMIT_REF_NAME="main"
    export CI_COMMIT_SHA="deadbeefdeadbeef"
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local out rc
    out=$(generate_summary '[{"severity":"critical"},{"severity":"low"}]' 2>&1); rc=$?
    assert_eq "${rc}" "1" "at/above-threshold findings must fail the pipeline"
    assert_contains "${out}" "FAILED"
}

test_generate_summary_report_only_mode_never_fails() {
    export UTEM_SEVERITY_THRESHOLD="high"
    export UTEM_FAIL_ON_FINDINGS="false"
    export SCAN_ID="scan-abc123"
    export UTEM_BASE_URL="https://utem.test"
    export CI_PROJECT_PATH="acme/widgets"
    export CI_COMMIT_REF_NAME="main"
    export CI_COMMIT_SHA="deadbeefdeadbeef"
    # shellcheck source=/dev/null
    source "${SCAN_SCRIPT}"
    local rc
    ( generate_summary '[{"severity":"critical"}]' ) >/dev/null 2>&1; rc=$?
    assert_eq "${rc}" "0" "UTEM_FAIL_ON_FINDINGS=false must never fail the pipeline"
}

# ── End-to-end: full main() run against the mocked API ─────────────────────

test_end_to_end_pass_no_blocking_findings() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export UTEM_SEVERITY_THRESHOLD="high"
    export UTEM_TIMEOUT="10"
    export UTEM_POLL_INTERVAL="0"
    export CI_PROJECT_PATH="acme/widgets"
    export CI_PROJECT_URL="https://gitlab.example.com/acme/widgets"
    export CI_COMMIT_SHA="deadbeefdeadbeef"
    export CI_COMMIT_REF_NAME="main"
    export CI_PIPELINE_ID="42"
    export CI_JOB_URL="https://gitlab.example.com/acme/widgets/-/jobs/1"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir \
        trigger.json '{"id":"scan-e2e-pass"}' \
        status.json '{"status":"completed"}' \
        results.json '{"findings":[{"title":"outdated lodash","severity":"low"}]}')

    local rc
    bash "${SCAN_SCRIPT}" >/dev/null 2>&1; rc=$?

    assert_eq "${rc}" "0" "scan with only low findings (threshold=high) must pass"
    assert_file_exists "utem-results.json"
    assert_file_exists "utem-results.xml"
    assert_file_exists "utem-summary.txt"
    # results.json is the raw /results response (our fixture has no "id"
    # field), not the /scans trigger response -- jq -r on a missing key
    # prints the literal string "null".
    assert_eq "$(jq -r '.id' utem-results.json 2>/dev/null || true)" "null" \
        "results.json must be the raw /results response, not the trigger response"
    assert_contains "$(cat utem-results.xml)" 'tests="1"'
    assert_contains "$(cat utem-results.xml)" 'failures="0"'
}

test_end_to_end_fails_above_threshold() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export UTEM_SEVERITY_THRESHOLD="high"
    export UTEM_TIMEOUT="10"
    export UTEM_POLL_INTERVAL="0"
    export CI_PROJECT_PATH="acme/widgets"
    export CI_PROJECT_URL="https://gitlab.example.com/acme/widgets"
    export CI_COMMIT_SHA="deadbeefdeadbeef"
    export CI_COMMIT_REF_NAME="main"
    export CI_PIPELINE_ID="42"
    export CI_JOB_URL="https://gitlab.example.com/acme/widgets/-/jobs/1"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir \
        trigger.json '{"id":"scan-e2e-fail"}' \
        status.json '{"status":"completed"}' \
        results.json '{"findings":[{"title":"SQL injection","severity":"critical"},{"title":"stale dep","severity":"low"}]}')

    local rc
    bash "${SCAN_SCRIPT}" >/dev/null 2>&1; rc=$?

    assert_eq "${rc}" "1" "a critical finding above threshold=high must fail the pipeline"
    assert_file_exists "utem-results.xml"
    assert_contains "$(cat utem-results.xml)" 'tests="2"'
    assert_contains "$(cat utem-results.xml)" 'failures="1"'
}

test_end_to_end_report_only_mode() {
    export UTEM_API_KEY="test-key"
    export UTEM_BASE_URL="https://utem.test"
    export UTEM_SEVERITY_THRESHOLD="high"
    export UTEM_FAIL_ON_FINDINGS="false"
    export UTEM_TIMEOUT="10"
    export UTEM_POLL_INTERVAL="0"
    export CI_PROJECT_PATH="acme/widgets"
    export CI_PROJECT_URL="https://gitlab.example.com/acme/widgets"
    export CI_COMMIT_SHA="deadbeefdeadbeef"
    export CI_COMMIT_REF_NAME="main"
    export CI_PIPELINE_ID="42"
    export CI_JOB_URL="https://gitlab.example.com/acme/widgets/-/jobs/1"
    export MOCK_RESPONSES_DIR
    MOCK_RESPONSES_DIR=$(make_mock_dir \
        trigger.json '{"id":"scan-e2e-report-only"}' \
        status.json '{"status":"completed"}' \
        results.json '{"findings":[{"title":"SQL injection","severity":"critical"}]}')

    local rc
    bash "${SCAN_SCRIPT}" >/dev/null 2>&1; rc=$?

    assert_eq "${rc}" "0" "UTEM_FAIL_ON_FINDINGS=false must pass even with critical findings"
}

# ── Runner ───────────────────────────────────────────────────────────────────

main() {
    echo "Running utem-scan.sh test suite..."
    echo ""

    local tests=(
        test_severity_rank
        test_count_by_severity
        test_validate_inputs_missing_api_key
        test_validate_inputs_rejects_http
        test_validate_inputs_rejects_bad_scan_type
        test_validate_inputs_rejects_bad_severity
        test_validate_inputs_rejects_non_numeric_timeout
        test_validate_inputs_accepts_valid_config
        test_trigger_scan_success
        test_trigger_scan_missing_id_fails
        test_trigger_scan_rejects_malformed_id
        test_trigger_scan_network_failure
        test_poll_scan_completed_immediately
        test_poll_scan_failed_status
        test_poll_scan_eventually_completes
        test_poll_scan_times_out
        test_fetch_results_array_form
        test_fetch_results_findings_key_form
        test_fetch_results_items_key_form
        test_fetch_results_unrecognized_shape_yields_empty
        test_generate_junit_xml_no_findings
        test_generate_junit_xml_counts_and_escapes
        test_generate_summary_pass_below_threshold
        test_generate_summary_fails_at_or_above_threshold
        test_generate_summary_report_only_mode_never_fails
        test_end_to_end_pass_no_blocking_findings
        test_end_to_end_fails_above_threshold
        test_end_to_end_report_only_mode
    )

    for t in "${tests[@]}"; do
        run_test "${t}" "${t}"
    done

    echo ""
    echo "────────────────────────────────────────────────────────────"
    local total pass_count fail_count
    total=$(wc -l < "${RESULTS_LOG}" | tr -d ' ')
    pass_count=$(grep -c '^PASS' "${RESULTS_LOG}" || true)
    fail_count=$(grep -c '^FAIL' "${RESULTS_LOG}" || true)

    grep '^FAIL' "${RESULTS_LOG}" || true

    echo "Assertions: ${total}  passed: ${pass_count}  failed: ${fail_count}"
    echo "────────────────────────────────────────────────────────────"

    if [[ "${fail_count}" -gt 0 ]]; then
        echo "RESULT: FAIL"
        exit 1
    else
        echo "RESULT: PASS"
        exit 0
    fi
}

main "$@"
