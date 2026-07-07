# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **GitLab CI/CD Component structure.** `templates/utem-scan.yml` now carries a
  `spec:inputs` header (8 typed inputs, all with defaults), making it a valid
  CI/CD Catalog component named `utem-scan`. Consumers can include it via
  `include: component: $CI_SERVER_FQDN/<group>/utem-gitlab-template/utem-scan@<version>`
  with `inputs:`. The legacy `include: project/file:` path still works and
  resolves the same input defaults, so existing consumers are unaffected.
- **Catalog release automation.** `.gitlab-ci.yml` gains a `release` stage with
  a `create-catalog-release` job (`release-cli`) that publishes a new catalog
  version on semantic-version tags only (`^v?\d+\.\d+\.\d+$`). Branch, MR, and
  schedule pipelines never release.
- **`validate-component-spec` CI job** + `tests/validate_component_spec.py` —
  asserts the two-document component shape, that every input has a default, and
  that every `$[[ inputs.* ]]` interpolation references a declared input.
- **`RUNBOOK.md`** — the exact remaining human steps to actually list the
  component in the GitLab CI/CD Catalog (host/mirror on gitlab.com under a group,
  enable the "CI/CD Catalog resource" toggle, push a semver tag). Documents the
  hard constraint that a GitHub-hosted project can never appear in the catalog.

- `tests/test_utem_scan.sh` — bash test suite (42 assertions) covering
  `scripts/utem-scan.sh` end to end, against a mocked UTEM API
  (`tests/mocks/curl`): input validation, scan trigger, status polling
  (completed/failed/queued-then-completed/timeout), result normalization
  (array / `.findings` / `.items` / `.results` response shapes), JUnit XML
  generation, and severity-threshold gating (fail / pass / report-only).
- `unit-tests` CI job (`.gitlab-ci.yml`) runs the suite in `alpine:3.20` on
  every MR, default-branch push, and change under `scripts/**` or `tests/**`.
- README "Development" section documenting how to run and extend the tests.

### Fixed

- **JUnit XML escaping was a no-op.** `xml_escape` used
  `gsub(regex; {object})`, which jq does not evaluate as a per-match
  replacement map — it silently returned the *unescaped* input. Any finding
  title/description containing `<`, `>`, `&`, or `"` (routine for security
  findings, e.g. XSS/SQLi payloads) produced invalid, unescaped XML that
  GitLab's JUnit report parser would reject. Fixed to use jq's named-capture
  `gsub` form, which evaluates the replacement per match.
- **`fetch_results()` corrupted its own return value.** `log()` wrote to
  stdout, and `fetch_results()` called `log "Fetching scan results..."`
  before its final `echo` of the findings JSON. Since `main()` captures
  `fetch_results` via `findings=$(fetch_results)`, the log line was prepended
  to the findings JSON, breaking every downstream `jq` parse (JUnit report,
  severity counts, threshold gating) with a leaked log line prefix. Fixed
  `log()` to write to stderr (matching `error()`), so only real return values
  travel over stdout.
- `POLL_INTERVAL` is now `${UTEM_POLL_INTERVAL:-10}` instead of a hardcoded
  `readonly 10`, and `main` only runs when the script is executed directly
  (`[[ "${BASH_SOURCE[0]}" == "${0}" ]]`) rather than unconditionally at the
  bottom of the file — both changes exist solely to make the script testable
  (fast polling in tests; sourceable without triggering a real scan) and do
  not change production behavior (default poll interval is still 10s).

## [1.0.0] - 2026-05-24

### Added

- Initial release of UTEM GitLab CI/CD security scanning template.
- Reusable `.utem-scan` hidden job for custom pipeline configurations.
- Pre-configured jobs: `utem-code-scan`, `utem-full-scan`, `utem-sbom-scan`, `utem-scheduled-scan`.
- Self-contained `scripts/utem-scan.sh` requiring only `bash`, `curl`, and `jq`.
- Configurable severity threshold with pipeline gating (`UTEM_FAIL_ON_FINDINGS`).
- JUnit XML report generation for GitLab test reporting integration.
- JSON results artifact for programmatic consumption.
- Human-readable summary table printed to job log.
- Support for scan types: `code`, `full`, `sbom`, `container`, `infrastructure`.
- Module selection via `UTEM_MODULES` variable.
- Self-test pipeline (`.gitlab-ci.yml`) with YAML validation, shellcheck linting, structure verification, and dry-run.
- Comprehensive README with quick start, configuration reference, and usage examples.
- MIT license (Innavoto India Pvt Ltd).
