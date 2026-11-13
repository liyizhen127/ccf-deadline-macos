#!/usr/bin/env python3
"""Fail if a source tree, app bundle or ZIP contains local paths or credentials.

This is a release hygiene check, not a guarantee of complete secret detection.
It prints paths and categories only, never matching secret values.
"""
import argparse
from pathlib import Path
import re
import sys
import zipfile

PATTERNS = {
    "absolute macOS home path": re.compile(rb"/Users/[A-Za-z0-9_. -]+/"),
    "absolute Linux home path": re.compile(rb"/home/[A-Za-z0-9_. -]+/"),
    "absolute Windows home path": re.compile(rb"[A-Za-z]:\\Users\\[^\\\x00\s]+\\"),
    "GitHub access token": re.compile(rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})"),
    "private key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "AWS access key": re.compile(rb"(?:AKIA|ASIA)[A-Z0-9]{16}"),
    "OpenAI-style secret": re.compile(rb"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}"),
}
SKIP_DIRS = {".git", ".build", ".swiftpm", "__pycache__"}
FORBIDDEN_NAMES = {".DS_Store", ".env", "preferences.json", "conferences.json", "hosts.yml"}


def inspect(name, data):
    issues = [label for label, pattern in PATTERNS.items() if pattern.search(data)]
    if Path(name).name in FORBIDDEN_NAMES:
        issues.append("local configuration or metadata")
    if Path(name).suffix.lower() in {".p12", ".pem", ".mobileprovision"}:
        issues.append("signing material")
    return [(name, issue) for issue in issues]


def scan(path):
    findings = []
    if path.is_dir():
        for entry in sorted(path.rglob("*")):
            if entry.is_file() and not set(entry.relative_to(path).parts).intersection(SKIP_DIRS):
                findings.extend(inspect(str(entry.relative_to(path)), entry.read_bytes()))
    elif zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            for name in archive.namelist():
                if not name.endswith("/"):
                    findings.extend(inspect(name, archive.read(name)))
    else:
        findings.extend(inspect(path.name, path.read_bytes()))
    return findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", type=Path, nargs="+")
    args = parser.parse_args()
    findings = [entry for path in args.paths for entry in scan(path)]
    for name, issue in findings:
        print(f"FAIL: {name}: {issue}", file=sys.stderr)
    if findings:
        return 1
    print(f"Release privacy audit passed for {len(args.paths)} target(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
