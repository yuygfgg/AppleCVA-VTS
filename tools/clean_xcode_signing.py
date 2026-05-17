#!/usr/bin/env python3
"""Strip local Xcode signing identifiers from project files."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PROJECT_FILE_PATTERN = "*.xcodeproj/project.pbxproj"

LINE_PATTERNS = [
    re.compile(r"^\s*DEVELOPMENT_TEAM(?:\[[^\]]+\])?\s*=\s*[^;]*;\n?"),
    re.compile(r"^\s*CODE_SIGN_IDENTITY(?:\[[^\]]+\])?\s*=\s*[^;]*;\n?"),
    re.compile(r"^\s*PROVISIONING_PROFILE(?:\[[^\]]+\])?\s*=\s*[^;]*;\n?"),
    re.compile(
        r"^\s*PROVISIONING_PROFILE_SPECIFIER(?:\[[^\]]+\])?\s*=\s*[^;]*;\n?"
    ),
]


def staged_files() -> set[Path]:
    result = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
        cwd=REPO_ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    return {REPO_ROOT / line for line in result.stdout.splitlines() if line}


def clean_project_file(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    cleaned_lines: list[str] = []
    changed = False
    for line in original.splitlines(keepends=True):
        if any(pattern.match(line) for pattern in LINE_PATTERNS):
            changed = True
            continue
        cleaned_lines.append(line)

    if not changed:
        return False

    path.write_text("".join(cleaned_lines), encoding="utf-8")
    return True


def main() -> int:
    staged = staged_files()
    changed_files: list[Path] = []

    for path in REPO_ROOT.rglob(PROJECT_FILE_PATTERN):
        if clean_project_file(path):
            changed_files.append(path)

    restage = [path for path in changed_files if path in staged]
    if restage:
        subprocess.run(
            ["git", "add", "--", *[str(path.relative_to(REPO_ROOT)) for path in restage]],
            cwd=REPO_ROOT,
            check=True,
        )

    if changed_files:
        rels = ", ".join(str(path.relative_to(REPO_ROOT)) for path in changed_files)
        print(f"clean_xcode_signing: stripped local signing settings from {rels}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
