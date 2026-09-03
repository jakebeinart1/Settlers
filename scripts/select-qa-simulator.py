#!/usr/bin/env python3

"""Return a dedicated Empires QA simulator, creating one when necessary.

UI tests deliberately erase app data. Selecting the first available iPhone
therefore destroys whichever manual game a developer happens to be playing.
This selector reserves a named device and never falls back to a personal one.
"""

import json
import os
import re
import subprocess
from typing import Dict, List, Optional, Tuple


QA_DEVICE_NAME = "Empires QA"
Device = Dict[str, object]


def available_iphones(payload: Dict[str, object]) -> List[Tuple[str, Device]]:
    """Flatten available iPhone devices while retaining their runtime IDs."""
    runtimes = payload.get("devices")
    if not isinstance(runtimes, dict):
        raise ValueError("simctl JSON has no devices object")
    return [
        (runtime, device)
        for runtime, devices in runtimes.items()
        if isinstance(devices, list)
        for device in devices
        if isinstance(device, dict)
        and (device.get("name") == QA_DEVICE_NAME or "iPhone" in str(device.get("name", "")))
    ]


def existing_qa_device(devices: List[Tuple[str, Device]]) -> Optional[str]:
    """Return only the reserved device; never substitute a personal simulator."""
    for _, device in devices:
        if device.get("name") == QA_DEVICE_NAME and isinstance(device.get("udid"), str):
            return str(device["udid"])
    return None


def runtime_version(identifier: str) -> Tuple[int, ...]:
    """Make iOS-26-5 sort numerically rather than lexically."""
    match = re.search(r"\.iOS-(\d+(?:-\d+)*)$", identifier)
    return tuple(int(part) for part in match.group(1).split("-")) if match else ()


def creation_template(devices: List[Tuple[str, Device]]) -> Tuple[str, str]:
    """Choose the newest available runtime and one of its iPhone device types."""
    if not devices:
        raise ValueError("no available iPhone simulator can seed an Empires QA device")
    runtime, device = max(devices, key=lambda item: runtime_version(item[0]))
    device_type = device.get("deviceTypeIdentifier")
    if not isinstance(device_type, str):
        raise ValueError("simctl JSON omitted the iPhone device type identifier")
    return runtime, device_type


def select_or_create(payload: Dict[str, object], override: Optional[str] = None) -> str:
    """Resolve the reserved UDID, creating exactly that named device if absent."""
    devices = available_iphones(payload)
    if override:
        if any(device.get("udid") == override and device.get("name") == QA_DEVICE_NAME
               for _, device in devices):
            return override
        raise ValueError("simulator override must identify an available reserved Empires QA device")
    existing = existing_qa_device(devices)
    if existing is not None:
        return existing
    runtime, device_type = creation_template(devices)
    result = subprocess.run(
        ["xcrun", "simctl", "create", QA_DEVICE_NAME, device_type, runtime],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def main() -> int:
    """Read the authoritative simulator inventory and print one QA UDID."""
    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        check=True,
        capture_output=True,
        text=True,
    )
    print(select_or_create(json.loads(result.stdout), os.environ.get("SETTLERS_QA_SIMULATOR_ID")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
