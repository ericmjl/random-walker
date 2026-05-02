#!/usr/bin/env python3
"""Print an xcodebuild ``-destination`` value for the newest usable iOS Simulator.

Chooses the highest-version **available** iOS Simulator runtime that has at least
one available iPhone device, then prints ``platform=iOS Simulator,id=<UDID>``.
Using the device id avoids fragile ``OS=`` strings and duplicate model names.

This tracks the newest *simulator* runtime you can actually run, not the device
SDK version (``OS=latest`` in xcodebuild often follows the device SDK and can
fail when that runtime has no simulator devices).
"""

from __future__ import annotations

import json
import subprocess
import sys
from typing import Any, cast


def _run_json(args: list[str]) -> dict[str, Any]:
    proc = subprocess.run(
        args,
        check=True,
        capture_output=True,
        text=True,
    )
    return cast(dict[str, Any], json.loads(proc.stdout))


def _ios_runtime_version_key(version: str) -> tuple[int, ...]:
    parts: list[int] = []
    for piece in version.split("."):
        if piece.isdigit():
            parts.append(int(piece))
    return tuple(parts) if parts else (0,)


def _pick_iphone(devices: list[dict[str, Any]]) -> dict[str, Any] | None:
    iphones = [
        d
        for d in devices
        if d.get("isAvailable")
        and str(d.get("name", "")).startswith("iPhone")
        and d.get("udid")
    ]
    if not iphones:
        return None
    preferred_exact = (
        "iPhone 16",
        "iPhone 15",
        "iPhone 17",
        "iPhone 14",
    )
    names_to_dev = {str(d["name"]): d for d in iphones}
    for want in preferred_exact:
        if want in names_to_dev:
            return names_to_dev[want]
    iphones_sorted = sorted(iphones, key=lambda d: str(d.get("name", "")))
    return iphones_sorted[0]


def main() -> int:
    runtimes_raw = _run_json(["xcrun", "simctl", "list", "runtimes", "available", "-j"])
    runtimes = cast(list[dict[str, Any]], runtimes_raw.get("runtimes", []))
    ios_runtimes = [
        r
        for r in runtimes
        if str(r.get("name", "")).startswith("iOS")
        and r.get("isAvailable")
        and r.get("identifier")
        and r.get("version")
    ]
    ios_runtimes.sort(
        key=lambda r: _ios_runtime_version_key(str(r["version"])),
        reverse=True,
    )

    devices_root = _run_json(["xcrun", "simctl", "list", "devices", "available", "-j"])
    devices_by_runtime = cast(
        dict[str, list[dict[str, Any]]],
        devices_root.get("devices", {}),
    )

    for rt in ios_runtimes:
        rid = str(rt["identifier"])
        devs = devices_by_runtime.get(rid, [])
        chosen = _pick_iphone(devs)
        if chosen is None:
            continue
        udid = str(chosen["udid"])
        print(f"platform=iOS Simulator,id={udid}")
        return 0

    print(
        "No available iPhone simulator found for any installed iOS runtime.",
        file=sys.stderr,
    )
    print(
        "Install a simulator runtime in Xcode → Settings → Platforms "
        "(or Components) and create an iPhone simulator if needed.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
