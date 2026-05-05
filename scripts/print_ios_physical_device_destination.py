#!/usr/bin/env python3
"""Print an xcodebuild ``-destination`` value for a **physical** iOS device.

Chooses exactly one attached iPhone/iPod with ``platform iphoneos``. If zero or
many devices qualify, exits non-zero unless ``RANDOM_WALKER_IOS_DEVICE_UDID`` is
set to disambiguate.

Examples
--------

Override when several devices are connected::

    export RANDOM_WALKER_IOS_DEVICE_UDID="00008130-001A485A02F8001C"
    xcodebuild ... -destination "$(scripts/print_ios_physical_device_destination.py)"

List connected physical iOS devices (name + UDID)::

    scripts/print_ios_physical_device_destination.py --list
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from typing import Any, cast


def _run_xcdevice_list() -> list[dict[str, Any]]:
    proc = subprocess.run(
        ["xcrun", "xcdevice", "list"],
        check=True,
        capture_output=True,
        text=True,
    )
    return cast(list[dict[str, Any]], json.loads(proc.stdout))


def _physical_ios_devices() -> list[dict[str, Any]]:
    devices = []
    for item in _run_xcdevice_list():
        if item.get("simulator"):
            continue
        if str(item.get("platform", "")) != "com.apple.platform.iphoneos":
            continue
        if not item.get("available"):
            continue
        udid = item.get("identifier")
        name = item.get("name")
        if udid and name:
            devices.append({"name": str(name), "udid": str(udid)})
    return devices


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    parser.add_argument(
        "--list",
        action="store_true",
        help="print connected physical iPhone/iPod destinations and exit",
    )
    parser.add_argument(
        "--udid-only",
        action="store_true",
        help="print only the device UDID (for devicectl, etc.)",
    )
    args = parser.parse_args()

    forced = os.environ.get("RANDOM_WALKER_IOS_DEVICE_UDID", "").strip()

    physical = _physical_ios_devices()
    if args.list:
        if not physical:
            print(
                "No available physical iOS devices (USB or trusted network?).",
                file=sys.stderr,
            )
            print(
                "Connect the device, unlock it, tap Trust This Computer, "
                "and verify Xcode → Devices shows it.",
                file=sys.stderr,
            )
            return 1
        for d in physical:
            print(f"{d['name']}\t{d['udid']}")
        return 0

    if forced:
        chosen = forced
    elif len(physical) == 1:
        chosen = physical[0]["udid"]
    elif len(physical) == 0:
        print("No usable physical iOS device detected.", file=sys.stderr)
        print(
            "Connect an iPhone, unlock it, trust the Mac, or set "
            "RANDOM_WALKER_IOS_DEVICE_UDID.",
            file=sys.stderr,
        )
        return 1
    else:
        print(
            "Multiple physical iOS devices detected; pick one:",
            file=sys.stderr,
        )
        for d in physical:
            print(f"  {d['name']}\t{d['udid']}", file=sys.stderr)
        print(
            "\nSet RANDOM_WALKER_IOS_DEVICE_UDID to one of those UDIDs, "
            "or run scripts/print_ios_physical_device_destination.py --list.",
            file=sys.stderr,
        )
        return 1

    if args.udid_only:
        print(chosen)
        return 0

    print(f"platform=iOS,id={chosen}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
