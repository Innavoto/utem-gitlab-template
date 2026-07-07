#!/usr/bin/env python3
"""Validate the UTEM GitLab CI/CD Component contract.

A catalog component must:
  1. be a two-document YAML file (spec header  ---  config body),
  2. declare a non-empty `spec.inputs` map,
  3. give every input a `default` (so a bare include works with no inputs),
  4. only interpolate inputs (`$[[ inputs.<name> ]]`) that are declared.

This runs without a live GitLab runner, so it can gate every pipeline and
every local commit. Exit non-zero on any violation.
"""
import re
import sys

import yaml

COMPONENT = "templates/utem-scan.yml"
REQUIRED = {
    "stage",
    "base_url",
    "scan_type",
    "severity_threshold",
    "fail_on_findings",
    "timeout",
    "modules",
    "script_ref",
}
# Matches $[[ inputs.<name> ]] with optional surrounding spaces.
REF_RE = re.compile(r"\$\[\[\s*inputs\.([a-zA-Z0-9_]+)\s*\]\]")


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    body = open(COMPONENT).read()
    docs = list(yaml.safe_load_all(body))

    if len(docs) < 2:
        fail("component file must have a spec header AND a config document (2 YAML docs)")

    inputs = ((docs[0] or {}).get("spec") or {}).get("inputs")
    if not isinstance(inputs, dict) or not inputs:
        fail("spec.inputs missing or empty")

    missing = REQUIRED - set(inputs)
    if missing:
        fail(f"missing declared inputs: {sorted(missing)}")

    for name, cfg in inputs.items():
        if "default" not in (cfg or {}):
            fail(f"input {name!r} has no default (would force every consumer to supply it)")

    refs = set(REF_RE.findall(body))
    undeclared = refs - set(inputs)
    if undeclared:
        fail(f"config interpolates undeclared inputs: {sorted(undeclared)}")

    print(
        f"OK: {len(inputs)} inputs declared, all with defaults; "
        f"interpolation refs {sorted(refs)} all declared."
    )


if __name__ == "__main__":
    main()
