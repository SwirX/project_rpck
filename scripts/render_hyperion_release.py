#!/usr/bin/env python3
"""Render the JSON body Hyperion expects for a published release.

Reads the artifacts produced by the release workflow and prints one body per
platform on stdout, so the caller can post each one.

    python3 scripts/render_hyperion_release.py --version 1.2.0 --assets artifacts
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

# Hyperion publishes per platform and currently understands only "windows" and
# "android". A Linux bundle has no key to attach to, so it is reported rather
# than filed under the wrong platform, which would hand a Linux installer to a
# Windows user.
SUPPORTED_PLATFORMS = {"windows-x64": "windows"}


def find_assets(root: pathlib.Path) -> tuple[dict[str, pathlib.Path], list[str]]:
    """Returns publishable artifacts keyed by platform, plus skipped names."""
    found: dict[str, pathlib.Path] = {}
    skipped: list[str] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        name = path.name
        if name.endswith("-windows-x64.zip"):
            found["windows-x64"] = path
        elif name.endswith("-linux-x64.tar.gz"):
            skipped.append(name)
    return found, skipped


def sha256_of(path: pathlib.Path) -> str:
    import hashlib

    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--assets", required=True, type=pathlib.Path)
    parser.add_argument(
        "--repository",
        default="https://github.com/SwirX/project_rpck/releases",
    )
    parser.add_argument("--notes", default="")
    arguments = parser.parse_args()

    assets, skipped = find_assets(arguments.assets)

    for name in skipped:
        print(
            f"skipping {name}: Hyperion has no linux platform key",
            file=sys.stderr,
        )

    if not assets:
        print("no publishable release artifacts were found", file=sys.stderr)
        return 1

    for platform, path in assets.items():
        payload = {
            "platform": SUPPORTED_PLATFORMS[platform],
            "version": arguments.version,
            "changelog": [arguments.notes] if arguments.notes else [],
            "downloads": [
                {
                    "label": platform,
                    "url": f"{arguments.repository}/download/v{arguments.version}/{path.name}",
                    "size_bytes": path.stat().st_size,
                    "checksum_sha256": sha256_of(path),
                }
            ],
        }
        print(json.dumps(payload))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())