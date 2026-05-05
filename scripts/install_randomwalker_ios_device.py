#!/usr/bin/env python3
"""Build **RandomWalker** for a connected iPhone and install it via devicectl.

Requires Xcode signed in with a team that owns ``dev.ericmjl.randomwalker`` (automatic
signing + ``DEVELOPMENT_TEAM`` in ``project.yml``). The device must be unlocked
for CLI launch after install—installation itself works while locked.

Environment
-----------

``RANDOM_WALKER_IOS_DEVICE_UDID``
    UDID printed by ``scripts/print_ios_physical_device_destination.py --list``

Typical invocation from the repo root::

    scripts/install_randomwalker_ios_device.py
    scripts/install_randomwalker_ios_device.py --skip-xcodegen
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
PROJECT = REPO_ROOT / "RandomWalker.xcodeproj"
SCHEME = "RandomWalker"
BUNDLE_ID = "dev.ericmjl.randomwalker"


def _run(cmd: list[str], *, cwd: pathlib.Path | None = None, check: bool = True) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, check=check)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0].strip())
    parser.add_argument(
        "--skip-xcodegen",
        action="store_true",
        help="do not regenerate the Xcode project (use after editing project.yml).",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help=(
            "skip xcodebuild; install an existing Debug app from --derived-data-path "
            "(Build/Products/Debug-iphoneos/RandomWalker.app must already exist)."
        ),
    )
    parser.add_argument(
        "--no-launch",
        action="store_true",
        help="install only; omit devicectl process launch (implies user opens the app manually).",
    )
    parser.add_argument(
        "--derived-data-path",
        type=pathlib.Path,
        default=REPO_ROOT / ".build/ios-device-derived",
        help="passed to xcodebuild -derivedDataPath (default: .build/ios-device-derived under the repo).",
    )
    args = parser.parse_args()

    if not PROJECT.is_dir():
        print(f"Missing Xcode project at {PROJECT}", file=sys.stderr)
        return 1

    printers = REPO_ROOT / "scripts/print_ios_physical_device_destination.py"
    dest_proc = subprocess.run(
        [sys.executable, str(printers)],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    destination = dest_proc.stdout.strip()
    ud_proc = subprocess.run(
        [sys.executable, str(printers), "--udid-only"],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    udid = ud_proc.stdout.strip()

    if not destination.startswith("platform=iOS,"):
        print(f"Unexpected destination string: {destination!r}", file=sys.stderr)
        return 1

    derived = args.derived_data_path.expanduser().resolve()
    debug_app = (
        derived / "Build/Products/Debug-iphoneos/RandomWalker.app"
    ).resolve()

    if not args.skip_xcodegen:
        _run(["xcodegen", "generate"], cwd=REPO_ROOT)

    if not args.skip_build:
        derived.mkdir(parents=True, exist_ok=True)
        _run(
            [
                "xcodebuild",
                "-project",
                str(PROJECT.relative_to(REPO_ROOT)),
                "-scheme",
                SCHEME,
                "-configuration",
                "Debug",
                "-destination",
                destination,
                "-derivedDataPath",
                str(derived),
                "-allowProvisioningUpdates",
                "build",
            ],
            cwd=REPO_ROOT,
        )

    if not debug_app.is_dir():
        print(f"Built app not found at {debug_app}", file=sys.stderr)
        return 1

    _run(
        [
            "xcrun",
            "devicectl",
            "device",
            "install",
            "app",
            "--device",
            udid,
            str(debug_app),
        ],
        cwd=REPO_ROOT,
    )

    if not args.no_launch:
        _run(
            [
                "xcrun",
                "devicectl",
                "device",
                "process",
                "launch",
                "--device",
                udid,
                BUNDLE_ID,
            ],
            cwd=REPO_ROOT,
            check=False,
        )

    print(
        "\nInstalled on device UDID:",
        udid,
        flush=True,
    )
    print(
        "If launch failed with “device was locked”, unlock the phone and tap the app—or run:",
        flush=True,
    )
    print(
        f"  xcrun devicectl device process launch --device {udid} {BUNDLE_ID}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
