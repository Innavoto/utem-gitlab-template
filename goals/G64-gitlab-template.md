# G64 — GitLab CI/CD security-scan template: test coverage + report-integrity fixes

- **Module(s):** utem-gitlab-template
- **Gap:** P2 #36
- **Kind:** correctness | integration
- **Blast radius:** single-repo
- **Attempts:** 1

## Goal
/goal the template defines a working scan job that (against a mocked UTEM API) triggers a
      scan, parses findings, emits a GitLab report artifact, and fails on findings above
      threshold.
      checked by the template YAML is valid (parse-check); a test of the invoke script
      against a mocked UTEM API asserting scan-trigger + report-artifact shape + threshold
      exit; README documents include usage.
      stop after 30 turns

## Evidence the gap exists (from audit)

Audited the repo before writing any code (`utem-gitlab-template`, 2 prior commits:
`dd39237` initial release, `752ef07` security hardening). Contrary to the assumed premise
("stub job" / "missing invoke script" / "no GitLab-native artifact" / "no docs"), the
template was **already substantially complete**:

- `templates/utem-scan.yml` — real `.utem-scan` hidden job + 4 concrete jobs
  (`utem-code-scan`, `utem-full-scan`, `utem-sbom-scan`, `utem-scheduled-scan`), with a
  GitLab-native `artifacts.reports.junit: utem-results.xml` (GitLab's JUnit report format
  is a first-class "report artifact" type, same tier as `sast`/`codequality`).
- `scripts/utem-scan.sh` (443 lines) — full lifecycle: `validate_inputs` →
  `trigger_scan` (POST `/api/v1/scans`) → `poll_scan` (GET `/api/v1/scans/<id>`) →
  `fetch_results` (GET `.../results`, normalizes array/`.findings`/`.items`/`.results`
  shapes) → `generate_junit_xml` → `generate_summary` (severity-threshold gate, honors
  `UTEM_FAIL_ON_FINDINGS`).
- `README.md` — already documents `include:` usage, all 8 config variables, 6 usage
  examples, artifact table, troubleshooting.
- `.gitlab-ci.yml` — a real self-test pipeline (YAML lint, shellcheck, structure check,
  dry-run), but **zero tests of the script's actual logic** — nothing exercised
  `trigger_scan`/`poll_scan`/`fetch_results`/`generate_junit_xml`/`generate_summary`
  against any API response, mocked or otherwise.

**Highest-value missing piece, matching the goal's own `checked by` clause verbatim**
("a test of the invoke script against a mocked UTEM API asserting scan-trigger +
report-artifact shape + threshold exit"): there were no such tests. Writing them
surfaced two real, previously-undetected production bugs in `scripts/utem-scan.sh`
(see DOER evidence log) — this justified treating "add tests" as correctness work,
not busywork.

## Integration contract to satisfy

N/A — this is a standalone customer-facing CI template repo (no `utem-*` platform
service to register in `service_registry.py`, no APM graph sync, no SOAR event, no UI
surface). The "integration" here is the template's contract with the customer's GitLab
pipeline and with the (external, real) UTEM API — validated by mocking that API.

## DOER evidence log

**Made the script testable (2 small, behavior-preserving changes):**
- `scripts/utem-scan.sh`: `POLL_INTERVAL` is now `${UTEM_POLL_INTERVAL:-10}` (was a
  hardcoded `readonly 10`) so tests can poll fast; default behavior unchanged.
- `scripts/utem-scan.sh`: `main "$@"` now runs only when the script is executed
  directly (`[[ "${BASH_SOURCE[0]}" == "${0}" ]]`), not unconditionally at import time —
  so `tests/test_utem_scan.sh` can `source` the script and call individual functions
  (`severity_rank`, `validate_inputs`, `generate_junit_xml`, ...) without triggering a
  real scan or requiring `UTEM_API_KEY`.

**Built the mock UTEM API + test suite:**
- `tests/mocks/curl` — a mock `curl` selected via `PATH` (scripts/utem-scan.sh always
  passes the request URL as curl's last argument; the mock relies on that convention).
  Returns canned JSON fixtures from `$MOCK_RESPONSES_DIR`, keyed by URL shape:
  `POST .../api/v1/scans` (trigger), `GET .../api/v1/scans/<id>` (status — supports both
  a fixed `status.json` and a `status_sequence.txt` for multi-poll scenarios), `GET
  .../api/v1/scans/<id>/results` (findings). Also supports `MOCK_CURL_FAIL` /
  `MOCK_CURL_HTTP_FAIL` to simulate transport/HTTP failures.
- `tests/test_utem_scan.sh` — 28 test functions / 42 assertions, run sequentially each
  in its own subshell + fresh tmp cwd + fresh `MOCK_RESPONSES_DIR` (isolated, no shared
  state). Covers: `severity_rank`, `count_by_severity`, all 5 `validate_inputs` failure
  paths + the success path, `trigger_scan` (success / missing id / malformed id /
  network failure), `poll_scan` (completed immediately / failed / queued→running→
  completed / timeout), `fetch_results` normalization of all 4 response shapes,
  `generate_junit_xml` (empty + XML-escaping + failure-count-vs-threshold), all 3
  `generate_summary` modes (pass / fail / report-only), and 3 full end-to-end `main()`
  runs against the mock (pass / fail-above-threshold / report-only-never-fails) —
  asserting exit code, and the shape of all 3 artifacts (`utem-results.json/.xml/.txt`).

**Bugs found and fixed by the test suite (both pre-existing, both real):**
1. **`fetch_results()` corrupted its own return value.** `log()` wrote to stdout; on
   the very first test that called `fetch_results` via `findings=$(fetch_results)`
   (matching how `main()` calls it), the `log "Fetching scan results..."` line leaked
   into `$findings`, and every downstream `jq` parse (JUnit XML gen, severity counting,
   threshold gate) broke with `jq: parse error: Invalid numeric literal...`. This bug
   was live in production before this change — any real invocation against the real
   UTEM API would have silently miscounted findings and/or emitted a broken report.
   Fix: `log()` now writes to stderr (matching `error()`'s existing convention).
2. **JUnit XML escaping was a complete no-op.** `xml_escape` used
   `gsub("[<>&\"]"; {object})` — jq does not evaluate a bare object as a per-match
   replacement map for `gsub`; it silently returns the input unescaped. Any finding
   title/description containing `<`, `>`, `&`, or `"` (routine for security findings —
   XSS/SQLi titles are the obvious case) would produce invalid, unescaped XML that
   GitLab's JUnit report parser would reject, silently breaking the report artifact
   this template exists to produce. Fix: rewrote as jq's named-capture `gsub`
   form — `gsub("(?<c>[<>&\"])"; {...}[.c])` — verified manually
   (`echo '"<tag> & \"q\" > end"' | jq -r 'gsub(...)'` → correctly escapes all four
   characters in one pass) and via the new `test_generate_junit_xml_counts_and_escapes`
   test.

**Wiring + docs:**
- `.gitlab-ci.yml` — new `test` stage + `unit-tests` job (alpine:3.20, installs
  `bash curl jq python3`, runs `bash tests/test_utem_scan.sh`) on MR / default-branch /
  `scripts,tests` changes. Added `tests/test_utem_scan.sh` to `verify-structure`'s
  required-file list.
- `README.md` — new "Development" section: how to run the suite, what it mocks, runtime
  requirements. (The pre-existing `include:`/variables docs were already thorough and
  needed no changes.)
- `CHANGELOG.md` — `[Unreleased]` entry documenting the test suite and both bug fixes.

**Local pre-checks run (all from repo root, on bash 5.3 / macOS — same
bash/curl/jq/python3 versions the alpine:3.20 CI image provides at the interface level
this suite depends on):**
```
$ shellcheck -s bash -S warning scripts/utem-scan.sh tests/test_utem_scan.sh tests/mocks/curl
(clean, zero warnings)

$ bash -n scripts/utem-scan.sh tests/test_utem_scan.sh tests/mocks/curl
(clean)

$ python3 -c "import yaml; [yaml.safe_load(open(f)) for f in
  ['templates/utem-scan.yml', '.gitlab-ci.yml']]"
templates/utem-scan.yml: valid YAML
.gitlab-ci.yml: valid YAML

$ bash tests/test_utem_scan.sh
Assertions: 42  passed: 42  failed: 0
RESULT: PASS
```

Not run (no access in this environment / out of scope for a DOER): an actual GitLab
runner executing `.gitlab-ci.yml`'s `unit-tests` job inside `alpine:3.20` — the CHECKER
or a real GitLab pipeline run is the next rung for that. `apk` package availability for
`bash curl jq python3` on `alpine:3.20` was not independently re-verified here (all four
are extremely common Alpine packages already used elsewhere in this same
`.gitlab-ci.yml` file's other jobs, so this mirrors existing, working precedent rather
than introducing a new dependency).

## CHECKER verdict
<to be appended by the CHECKER>
