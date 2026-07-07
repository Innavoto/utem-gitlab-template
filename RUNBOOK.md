# RUNBOOK — Publishing `utem-scan` to the GitLab CI/CD Catalog

This repository is **structurally catalog-ready**: it contains a valid CI/CD
Component (`templates/utem-scan.yml` with a `spec:inputs` header), a top-level
`README.md`, and a `.gitlab-ci.yml` whose `create-catalog-release` job publishes
a new catalog version on every semantic-version tag.

It is **NOT yet published**, and it **cannot be published from where it lives now.**

## The hard external constraint (do not work around it)

The GitLab CI/CD Catalog only lists components from projects that are:

1. **hosted on `gitlab.com`** (or a self-managed GitLab instance with the
   catalog enabled), and
2. flagged as a **"CI/CD Catalog resource"** in the project settings, and
3. released with a **semantic-version Git tag** that triggers a GitLab
   release.

This repository currently lives on **GitHub** (`github.com/Innavoto/utem-gitlab-template`).
**A GitHub-hosted project can never appear in the GitLab CI/CD Catalog** — GitHub
has no such catalog, and GitLab only indexes projects on a GitLab instance.
Mirroring/relocating the project to gitlab.com is therefore a mandatory,
human-owned prerequisite. Everything below must be done by a human with Owner
/ Maintainer rights on a gitlab.com group. **Do not automate account or project
creation on gitlab.com.**

## Remaining human steps

### 1. Put the project on gitlab.com under a group

The catalog does not accept components from a personal namespace — the project
must live under a **group**.

- Create (or reuse) a gitlab.com group, e.g. `gitlab.com/innavoto`.
- Create the project under it: `gitlab.com/innavoto/utem-gitlab-template`.
- Push this repository's contents there. Either:
  - **One-time push:**
    ```bash
    git remote add gitlab git@gitlab.com:innavoto/utem-gitlab-template.git
    git push gitlab main
    ```
  - **Or a pull mirror** (Settings → Repository → Mirroring repositories) so
    the GitHub repo stays the source of truth and gitlab.com mirrors it.
    Note: releases/tags must still land on the gitlab.com side to trigger the
    catalog release job.

### 2. Enable the project as a CI/CD Catalog resource

On the gitlab.com project:

- **Settings → General → Visibility, project features, permissions** — ensure
  the project is **public** (public components are discoverable by everyone;
  internal/private components are only visible to members).
- **Settings → CI/CD → Catalog resource** (also surfaced as a toggle on the
  project's **Settings → General**) — turn on **"CI/CD Catalog resource."**
  A top-level `README.md` and a component under `templates/` are required for
  this toggle to succeed; both are already present.

### 3. Confirm the component is detected

- Open **Deploy → ... → CI/CD Catalog** (or `gitlab.com/explore/catalog`) and
  confirm the project shows up (it will show "no releases yet" until step 4).
- The component's fully-qualified path is:
  `gitlab.com/innavoto/utem-gitlab-template/utem-scan`
  (project path + component name, where the component name = the template
  filename without extension).

### 4. Push a semantic-version tag to publish a version

The `create-catalog-release` job in `.gitlab-ci.yml` runs **only** on tags that
match `^v?\d+\.\d+\.\d+$` and uses `release-cli` to create a GitLab release.
For a catalog resource, that release **publishes the component version** to the
catalog.

```bash
# from the gitlab.com clone / mirror, on the commit you want to release
git tag 1.0.0
git push gitlab 1.0.0        # or: git push origin 1.0.0 if origin == gitlab.com
```

- Watch the pipeline for that tag: the `create-catalog-release` job must go
  green. Branch, MR, and schedule pipelines will **not** run this job.
- After it succeeds, the version `1.0.0` appears in the catalog entry and
  becomes usable as `@1.0.0`.

### 5. (Optional) verify as a consumer

In any other gitlab.com project:

```yaml
include:
  - component: $CI_SERVER_FQDN/innavoto/utem-gitlab-template/utem-scan@1.0.0
    inputs:
      severity_threshold: high
```

Set `UTEM_API_KEY` as a masked CI/CD variable, run a pipeline, and confirm the
`utem-code-scan` job appears and produces the JUnit report.

## What is already done for you (no human action needed)

- `templates/utem-scan.yml` — valid component with `spec:inputs` (8 inputs, all
  with defaults) and 4 jobs.
- `.gitlab-ci.yml` — validates the component, unit-tests the scan script against
  a mocked UTEM API, and releases on semver tags only.
- `README.md` — documents both the `include: component:` (catalog) usage and the
  legacy `include: project/file:` usage.
- `CHANGELOG.md` — versioned per semver.

## Versioning convention

- Tags are semantic versions: `MAJOR.MINOR.PATCH` (a leading `v` is accepted).
- Bump `CHANGELOG.md` `[Unreleased]` → a dated version section before tagging.
- The catalog shows the latest release plus full version history; consumers pin
  with `@<version>` (recommended) or track a branch/SHA (`@main`, `@<sha>`).
