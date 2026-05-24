# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
