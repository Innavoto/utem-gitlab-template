# UTEM GitLab CI/CD Security Scanner

Reusable **GitLab CI/CD Component** that integrates [UTEM](https://utem.innavoto.com) (Unified Threat Exposure Management) security scanning into your pipelines. Scans your code, containers, and infrastructure for vulnerabilities and fails the pipeline when findings exceed your severity threshold.

**Publisher:** Innavoto India Pvt Ltd

**Component:** `utem-scan` (defined in `templates/utem-scan.yml`)

> **Catalog status:** This project is *structurally* ready for the GitLab CI/CD Catalog but is **not yet listed** there. The catalog only indexes projects hosted on **gitlab.com** (or a self-managed GitLab) that are flagged as a CI/CD Catalog resource and released with a semver tag — and this repository currently lives on GitHub. A GitHub-hosted project can never appear in the GitLab catalog. See **[RUNBOOK.md](RUNBOOK.md)** for the exact steps to host it on gitlab.com and publish it.

---

## Quick Start

**1. Set your API key** in GitLab (Settings > CI/CD > Variables):

| Variable | Value | Options |
|----------|-------|---------|
| `UTEM_API_KEY` | Your UTEM API key | Masked, Protected |

`UTEM_API_KEY` is intentionally a runtime CI/CD variable, **not** a component input — a secret must never be baked into interpolated pipeline configuration.

**2a. Add to your `.gitlab-ci.yml` (CI/CD Catalog component — recommended, once published):**

```yaml
include:
  - component: $CI_SERVER_FQDN/<group>/utem-gitlab-template/utem-scan@<version>
    inputs:
      severity_threshold: high
      fail_on_findings: true
```

`$CI_SERVER_FQDN` resolves to your GitLab host (e.g. `gitlab.com`). Pin `<version>` to a released semver tag (e.g. `@1.0.0`).

**2b. Or use the legacy project/file include (backward compatible — uses input defaults):**

```yaml
include:
  - project: 'Innavoto/utem-gitlab-template'
    file: '/templates/utem-scan.yml'
```

That's it. The `utem-code-scan` job runs automatically on merge requests and the default branch.

---

## Component Inputs

When included as a component (`include: component:`), configure behavior with typed `inputs:` (validated at include time). Each input maps to the corresponding `UTEM_*` CI/CD variable the scan script reads.

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `stage` | string | `test` | Pipeline stage the scan jobs run in. |
| `base_url` | string | `https://utem.innavoto.com` | UTEM platform URL (must be HTTPS). |
| `scan_type` | string | `code` | Default scan type for `utem-code-scan`: `code`, `full`, `sbom`, `container`, `infrastructure`. |
| `severity_threshold` | string | `high` | Minimum severity that fails the pipeline: `critical`, `high`, `medium`, `low`, `info`. |
| `fail_on_findings` | boolean | `true` | `false` = report-only, never fails the pipeline. |
| `timeout` | number | `300` | Max seconds to wait for scan completion. |
| `modules` | string | `""` | Comma-separated modules (e.g. `sast,secrets`). Empty = all. |
| `script_ref` | string | *(pinned SHA)* | Git ref of `utem-scan.sh` used by the curl fallback when the script isn't vendored in the consuming repo. |

Legacy `include: project/file:` consumers get these same defaults and can still override the underlying `UTEM_*` variables directly (see the table below).

---

## Available Jobs

| Job | Scan Type | Trigger | Behavior |
|-----|-----------|---------|----------|
| `utem-code-scan` | Code analysis | MR events + default branch | Automatic, blocks on findings |
| `utem-full-scan` | Full assessment | Default branch | Manual, allowed to fail |
| `utem-sbom-scan` | SBOM generation | Default branch | Manual, allowed to fail |
| `utem-scheduled-scan` | Full assessment | Pipeline schedules | Automatic on schedule |

---

## Configuration Variables

All variables can be set at the project, group, or job level.

| Variable | Default | Description |
|----------|---------|-------------|
| `UTEM_API_KEY` | *(required)* | API key for UTEM authentication. Generate at `https://utem.innavoto.com/settings/api-keys`. Set as a **masked** CI/CD variable. |
| `UTEM_BASE_URL` | `https://utem.innavoto.com` | UTEM platform URL. Change for self-hosted deployments. |
| `UTEM_TENANT_ID` | `1` | Tenant ID for multi-tenant deployments. |
| `UTEM_SCAN_TYPE` | `code` | Scan type: `code`, `full`, `sbom`, `container`, `infrastructure`. |
| `UTEM_SEVERITY_THRESHOLD` | `high` | Minimum severity to trigger failure: `critical`, `high`, `medium`, `low`, `info`. |
| `UTEM_FAIL_ON_FINDINGS` | `true` | Set to `false` to report findings without failing the pipeline. |
| `UTEM_TIMEOUT` | `300` | Maximum seconds to wait for scan completion. |
| `UTEM_MODULES` | *(empty)* | Comma-separated list of scan modules to enable (e.g., `sast,sca,secrets`). Empty = all modules. |

---

## Usage Examples

### Basic MR scanning (default)

No extra configuration needed. The included template runs `utem-code-scan` on every merge request:

```yaml
include:
  - project: 'Innavoto/utem-gitlab-template'
    file: '/templates/utem-scan.yml'
```

### Custom severity threshold

Fail only on critical findings:

```yaml
include:
  - project: 'Innavoto/utem-gitlab-template'
    file: '/templates/utem-scan.yml'

variables:
  UTEM_SEVERITY_THRESHOLD: "critical"
```

### Report-only mode (no pipeline failure)

```yaml
include:
  - project: 'Innavoto/utem-gitlab-template'
    file: '/templates/utem-scan.yml'

variables:
  UTEM_FAIL_ON_FINDINGS: "false"
```

### Multiple scan types in a single pipeline

```yaml
include:
  - project: 'Innavoto/utem-gitlab-template'
    file: '/templates/utem-scan.yml'

stages:
  - test
  - security

utem-code-scan:
  stage: security

utem-container-scan:
  extends: .utem-scan
  stage: security
  variables:
    UTEM_SCAN_TYPE: "container"
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

### Scheduled nightly full scan

Set up a pipeline schedule in GitLab (CI/CD > Schedules) and the `utem-scheduled-scan` job runs automatically.

### Specific scan modules

Run only SAST and secret detection:

```yaml
include:
  - project: 'Innavoto/utem-gitlab-template'
    file: '/templates/utem-scan.yml'

variables:
  UTEM_MODULES: "sast,secrets"
```

### Self-hosted UTEM

```yaml
include:
  - project: 'Innavoto/utem-gitlab-template'
    file: '/templates/utem-scan.yml'

variables:
  UTEM_BASE_URL: "https://utem.internal.company.com"
  UTEM_TENANT_ID: "42"
```

---

## JUnit Test Reporting

The scanner generates a JUnit XML report (`utem-results.xml`) that integrates with GitLab's test reporting. Each security finding appears as a test case:

- **Passed test case:** No finding (or below threshold)
- **Failed test case:** Finding at or above the severity threshold

View results in the merge request **Tests** tab or the pipeline **Tests** section.

The report includes:
- Finding title and severity
- File location and line number (when available)
- CVE identifier (when applicable)
- Remediation guidance

---

## Artifacts

Each scan produces three artifacts (retained for 30 days):

| File | Format | Content |
|------|--------|---------|
| `utem-results.json` | JSON | Full scan results from the UTEM API |
| `utem-results.xml` | JUnit XML | GitLab-compatible test report |
| `utem-summary.txt` | Plain text | Human-readable summary table |

---

## Pipeline Badge

Add a UTEM scan status badge to your project README:

```markdown
[![UTEM Scan](https://gitlab.com/YOUR_GROUP/YOUR_PROJECT/badges/main/pipeline.svg)](https://gitlab.com/YOUR_GROUP/YOUR_PROJECT/-/pipelines)
```

---

## Requirements

The scan job uses `alpine:3.20` and installs only:
- `curl` — HTTP requests to UTEM API
- `jq` — JSON processing
- `bash` — Script execution

No Python, Node.js, or other runtimes required.

---

## Troubleshooting

### "UTEM_API_KEY is not set"

Set the variable in GitLab > Settings > CI/CD > Variables. Mark it as **Masked** to prevent it from appearing in logs.

### Scan times out

Increase `UTEM_TIMEOUT` (default 300 seconds). Full scans on large repositories may take longer.

### Pipeline fails but you want to review first

Set `UTEM_FAIL_ON_FINDINGS: "false"` to switch to report-only mode. Findings still appear in the JUnit report and artifacts.

### Self-hosted UTEM instance

Set `UTEM_BASE_URL` to your instance URL. Ensure the GitLab runner can reach it over the network.

---

## Development

### Running the test suite

`scripts/utem-scan.sh` is covered by `tests/test_utem_scan.sh`, a self-contained
bash test suite that exercises every stage of the script — input validation,
scan trigger, status polling, result normalization, JUnit report generation,
and severity-threshold gating — against a **mocked UTEM API**
(`tests/mocks/curl`) so no network access or real UTEM instance is required.

```bash
bash tests/test_utem_scan.sh
```

Requires `bash`, `curl`, `jq`, and `python3` (the same runtimes the scan job
itself needs, plus `python3` for an XML well-formedness check). This also runs
automatically in CI as the `unit-tests` job in `.gitlab-ci.yml` whenever
`scripts/**` or `tests/**` change.

The mock intercepts `curl` via `PATH` and returns canned JSON fixtures keyed
off the request URL (`POST /api/v1/scans` → trigger response, `GET
/api/v1/scans/<id>` → status response, `GET /api/v1/scans/<id>/results` →
findings). See the header comment in `tests/mocks/curl` for the fixture
directory layout if you're adding new test cases.

## Publishing to the GitLab CI/CD Catalog

This project is structured as a catalog-ready component, but **it is not listed in
the GitLab CI/CD Catalog yet** — and it cannot be while it is hosted on GitHub.
The catalog only indexes projects on **gitlab.com** (or a self-managed GitLab)
that are enabled as a "CI/CD Catalog resource" and released with a semver tag.

The `create-catalog-release` job in [`.gitlab-ci.yml`](.gitlab-ci.yml) already
does the release half (it fires only on `^v?\d+\.\d+\.\d+$` tags). The remaining
work is human-owned hosting/config on gitlab.com. See **[RUNBOOK.md](RUNBOOK.md)**
for the exact steps:

1. Host or mirror the project on gitlab.com under a **group**.
2. Make it public and toggle **Settings → CI/CD → CI/CD Catalog resource**.
3. Push a semantic-version tag (e.g. `1.0.0`) to trigger `create-catalog-release`.

Only after those steps will `include: component: .../utem-scan@<version>` resolve
from the catalog.

---

## Support

- **UTEM Dashboard:** https://utem.innavoto.com
- **Documentation:** https://docs.utem.innavoto.com
- **Email:** support@innavoto.com

---

## License

MIT License - Copyright (c) 2026 Innavoto India Pvt Ltd

See [LICENSE](LICENSE) for details.
