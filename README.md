# UTEM GitLab CI/CD Security Scanner

Reusable GitLab CI component that integrates [UTEM](https://utem.innavoto.com) (Unified Threat Exposure Management) security scanning into your pipelines. Scans your code, containers, and infrastructure for vulnerabilities and fails the pipeline when findings exceed your severity threshold.

**Publisher:** Innavoto India Pvt Ltd

---

## Quick Start

**1. Set your API key** in GitLab (Settings > CI/CD > Variables):

| Variable | Value | Options |
|----------|-------|---------|
| `UTEM_API_KEY` | Your UTEM API key | Masked, Protected |

**2. Add to your `.gitlab-ci.yml`:**

```yaml
include:
  - project: 'Innavoto/utem-gitlab-template'
    file: '/templates/utem-scan.yml'
```

That's it. The `utem-code-scan` job runs automatically on merge requests and the default branch.

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

## Support

- **UTEM Dashboard:** https://utem.innavoto.com
- **Documentation:** https://docs.utem.innavoto.com
- **Email:** support@innavoto.com

---

## License

MIT License - Copyright (c) 2026 Innavoto India Pvt Ltd

See [LICENSE](LICENSE) for details.
