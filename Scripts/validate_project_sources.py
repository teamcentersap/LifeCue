#!/usr/bin/env python3
"""Validate LifeCue project generator source lists match the repository.

Also checks project.pbxproj for:
- every on-disk Swift file referenced by path
- no duplicate Swift path references
- every Swift fileRef appearing in at least one PBXGroup (no navigator orphans)
"""

from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def discover_swift_files(relative_root: str) -> set[str]:
    base = ROOT / relative_root
    return {
        str(path.relative_to(ROOT)).replace("\\", "/")
        for path in sorted(base.rglob("*.swift"))
    }


def load_generator_lists() -> tuple[set[str], set[str]]:
    script_path = ROOT / "Scripts" / "generate_xcodeproj.py"
    namespace: dict = {}
    exec(script_path.read_text(encoding="utf-8"), namespace)
    return set(namespace["APP_FILES"]), set(namespace["TEST_FILES"])


def load_pbxproj() -> str:
    return (ROOT / "LifeCue.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")


def pbx_swift_paths(pbx: str) -> list[str]:
    return re.findall(r'path = "([^"]+\.swift)"', pbx)


def orphan_swift_paths(pbx: str) -> list[str]:
    """Swift fileRefs that never appear as a PBXGroup child."""
    refs = re.findall(
        r'([A-F0-9]{24}) /\* ([^*]+) \*/ = \{isa = PBXFileReference; '
        r'lastKnownFileType = sourcecode\.swift; path = "([^"]+)";',
        pbx,
    )
    path_by_id = {fid: path for fid, _name, path in refs}
    group_child_ids: set[str] = set()
    for children in re.findall(
        r"isa = PBXGroup;\s*children = \((.*?)\);",
        pbx,
        flags=re.S,
    ):
        group_child_ids.update(re.findall(r"([A-F0-9]{24}) /\*", children))

    orphans = [
        path
        for fid, path in path_by_id.items()
        if fid not in group_child_ids
    ]
    return sorted(orphans)


def main() -> int:
    app_expected = discover_swift_files("LifeCue")
    test_expected = discover_swift_files("LifeCueTests")
    app_listed, test_listed = load_generator_lists()
    expected = app_expected | test_expected

    failed = False

    missing_app = sorted(app_expected - app_listed)
    extra_app = sorted(app_listed - app_expected)
    missing_test = sorted(test_expected - test_listed)
    extra_test = sorted(test_listed - test_expected)

    if missing_app:
        failed = True
        print("Missing from APP_FILES:")
        for path in missing_app:
            print(f"  - {path}")
    if extra_app:
        failed = True
        print("Extra in APP_FILES:")
        for path in extra_app:
            print(f"  - {path}")
    if missing_test:
        failed = True
        print("Missing from TEST_FILES:")
        for path in missing_test:
            print(f"  - {path}")
    if extra_test:
        failed = True
        print("Extra in TEST_FILES:")
        for path in extra_test:
            print(f"  - {path}")

    pbx = load_pbxproj()
    pbx_paths = pbx_swift_paths(pbx)
    pbx_set = set(pbx_paths)

    missing_pbx = sorted(expected - pbx_set)
    extra_pbx = sorted(pbx_set - expected)
    if missing_pbx:
        failed = True
        print("Missing from project.pbxproj:")
        for path in missing_pbx:
            print(f"  - {path}")
    if extra_pbx:
        failed = True
        print("Extra in project.pbxproj:")
        for path in extra_pbx:
            print(f"  - {path}")

    duplicates = sorted({path for path in pbx_paths if pbx_paths.count(path) > 1})
    if duplicates:
        failed = True
        print("Duplicate Swift path references in project.pbxproj:")
        for path in duplicates:
            print(f"  - {path}")

    orphans = orphan_swift_paths(pbx)
    if orphans:
        failed = True
        print("Swift files in Sources/file refs but absent from any PBXGroup:")
        for path in orphans:
            print(f"  - {path}")

    if failed:
        return 1

    print("OK")
    print(f"  app={len(app_expected)} test={len(test_expected)} pbx={len(pbx_set)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
