#!/usr/bin/env python3
"""Build, install, and launch RandomWalker on a paired iPhone + Watch simulator.

Runs ``xcodebuild`` for ``RandomWalker`` once; **RandomWalkerWatch** is embedded under
``RandomWalker.app/Watch/`` so WatchConnectivity reports the companion as installed (required on Simulator).

Pick an active device pair (or pass UDIDs), boot both simulators, ``simctl install`` +
``launch`` each.

Usage (from repo root)::

    ./scripts/run_ios_watch_sim_pair.py

Override UDIDs::

    RANDOM_WALKER_PHONE_UDID=... RANDOM_WALKER_WATCH_UDID=... \\
      ./scripts/run_ios_watch_sim_pair.py

List pairs and exit::

    ./scripts/run_ios_watch_sim_pair.py --list-pairs
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, cast


REPO_ROOT = Path(__file__).resolve().parents[1]
IOS_SCHEME = "RandomWalker"
IOS_BUNDLE = "dev.ericmjl.randomwalker"
WATCH_BUNDLE = "dev.ericmjl.randomwalker.watchkitapp"
XCODEPROJ = REPO_ROOT / "RandomWalker.xcodeproj"
DERIVED = REPO_ROOT / ".build" / "sim-paired-derived"


def _run_json(args: list[str]) -> dict[str, Any]:
    proc = subprocess.run(
        args,
        check=True,
        capture_output=True,
        text=True,
    )
    return cast(dict[str, Any], json.loads(proc.stdout))


def _run(
    args: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> None:
    merged = os.environ.copy()
    if env:
        merged.update(env)
    subprocess.run(args, check=True, cwd=cwd, env=merged)


def _pairs_payload() -> dict[str, Any]:
    return _run_json(["xcrun", "simctl", "list", "pairs", "-j"])


def _list_pairs() -> None:
    data = _pairs_payload()
    pairs = cast(dict[str, Any], data.get("pairs", {}))
    for _pair_id, meta in sorted(pairs.items(), key=lambda x: str(x[1].get("phone", {}).get("name", ""))):
        phone = cast(dict[str, Any], meta.get("phone", {}))
        watch = cast(dict[str, Any], meta.get("watch", {}))
        st = meta.get("state", "")
        print(
            f"{phone.get('name', '')} ({phone.get('udid', '')})\n"
            f"  + {watch.get('name', '')} ({watch.get('udid', '')})\n"
            f"  state: {st}\n"
        )


def _pick_default_pair_phone_watch() -> tuple[str, str]:
    env_p = os.environ.get("RANDOM_WALKER_PHONE_UDID", "").strip()
    env_w = os.environ.get("RANDOM_WALKER_WATCH_UDID", "").strip()
    if env_p and env_w:
        return env_p, env_w
    data = _pairs_payload()
    pairs = cast(dict[str, Any], data.get("pairs", {}))
    if not pairs:
        print("No simulator pairs found. Pair a Watch with an iPhone in ", file=sys.stderr)
        print("  Xcode → Window → Devices and Simulators → Simulators.", file=sys.stderr)
        raise SystemExit(1)

    preferred_phone_name = "iPhone 17"
    for _pid, meta in pairs.items():
        phone = cast(dict[str, Any], meta.get("phone", {}))
        if phone.get("name") == preferred_phone_name:
            watch = cast(dict[str, Any], meta.get("watch", {}))
            pu, wu = phone.get("udid"), watch.get("udid")
            if isinstance(pu, str) and isinstance(wu, str):
                return pu, wu

    first = next(iter(pairs.values()))
    phone = cast(dict[str, Any], first.get("phone", {}))
    watch = cast(dict[str, Any], first.get("watch", {}))
    pu, wu = phone.get("udid"), watch.get("udid")
    if not isinstance(pu, str) or not isinstance(wu, str):
        print("Could not read UDIDs from first simulator pair.", file=sys.stderr)
        raise SystemExit(1)
    return pu, wu


def _boot_if_needed(udid: str) -> None:
    proc = subprocess.run(
        ["xcrun", "simctl", "bootstatus", udid, "-b"],
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0 and "Booted" in proc.stdout:
        return
    subprocess.run(["xcrun", "simctl", "boot", udid], check=False)


def _open_simulator() -> None:
    subprocess.run(["open", "-a", "Simulator"], check=False)


def _build_install_launch(
    *,
    phone_udid: str,
    watch_udid: str,
    skip_xcodegen: bool,
) -> None:
    if not XCODEPROJ.is_dir():
        print(f"Missing {XCODEPROJ}. Run from repo root or run xcodegen first.", file=sys.stderr)
        raise SystemExit(1)

    DERIVED.mkdir(parents=True, exist_ok=True)

    if not skip_xcodegen:
        _run(["xcodegen", "generate"], cwd=REPO_ROOT)

    _boot_if_needed(phone_udid)
    _boot_if_needed(watch_udid)
    _open_simulator()

    _run(
        [
            "xcodebuild",
            "-project",
            str(XCODEPROJ),
            "-scheme",
            IOS_SCHEME,
            "-destination",
            f"platform=iOS Simulator,id={phone_udid}",
            "-derivedDataPath",
            str(DERIVED),
            "build",
        ],
        cwd=REPO_ROOT,
    )
    ios_app = DERIVED / "Build" / "Products" / "Debug-iphonesimulator" / "RandomWalker.app"
    if not ios_app.is_dir():
        print(f"Expected iOS app at {ios_app}", file=sys.stderr)
        raise SystemExit(1)
    _run(["xcrun", "simctl", "install", phone_udid, str(ios_app)])

    embedded_watch_app = ios_app / "Watch" / "RandomWalkerWatch.app"
    if not embedded_watch_app.is_dir():
        print(
            f"Embedded watch app missing at {embedded_watch_app}. "
            "Rebuild the RandomWalker scheme (watch companion must embed).",
            file=sys.stderr,
        )
        raise SystemExit(1)
    _run(["xcrun", "simctl", "install", watch_udid, str(embedded_watch_app)])

    _run(["xcrun", "simctl", "launch", phone_udid, IOS_BUNDLE])
    _run(["xcrun", "simctl", "launch", watch_udid, WATCH_BUNDLE])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--list-pairs",
        action="store_true",
        help="Print paired simulators and exit.",
    )
    parser.add_argument(
        "--skip-xcodegen",
        action="store_true",
        help="Do not run xcodegen generate before building.",
    )
    args = parser.parse_args()
    if args.list_pairs:
        _list_pairs()
        return 0
    phone_udid, watch_udid = _pick_default_pair_phone_watch()
    print(f"Phone: {phone_udid}\nWatch: {watch_udid}\n", file=sys.stderr)
    _build_install_launch(
        phone_udid=phone_udid,
        watch_udid=watch_udid,
        skip_xcodegen=args.skip_xcodegen,
    )
    print(
        "Launched iOS and watchOS apps on the paired simulators.\n"
        "Watch: companion is bundled at RandomWalker.app/Watch/RandomWalkerWatch.app "
        "(required for WatchConnectivity on Simulator).\n"
        "Open **Random Walker** on the Watch grid/List View after install; "
        "re-run this script after Erase or if the icon is missing.",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
