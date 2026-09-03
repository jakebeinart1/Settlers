#!/usr/bin/env python3

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "select-qa-simulator.py"
SPEC = importlib.util.spec_from_file_location("qa_simulator", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def device(name: str, identifier: str, device_type: str = "phone-type") -> dict:
    return {"name": name, "udid": identifier, "deviceTypeIdentifier": device_type}


class QASimulatorSelectionTests(unittest.TestCase):
    def test_override_rejects_a_personal_simulator(self) -> None:
        payload = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
            device("iPhone 17 Pro", "PERSONAL"),
            device("Empires QA", "ISOLATED"),
        ]}}
        with self.assertRaisesRegex(ValueError, "reserved Empires QA"):
            MODULE.select_or_create(payload, override="PERSONAL")

    def test_override_accepts_only_an_available_reserved_device(self) -> None:
        payload = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
            device("Empires QA", "ISOLATED"),
        ]}}
        self.assertEqual(MODULE.select_or_create(payload, override="ISOLATED"), "ISOLATED")
        with self.assertRaisesRegex(ValueError, "reserved Empires QA"):
            MODULE.select_or_create(payload, override="MISSING")

    def test_selects_named_qa_device_instead_of_booted_personal_phone(self) -> None:
        payload = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
            {**device("iPhone 17 Pro", "PERSONAL"), "state": "Booted"},
            device("Empires QA", "ISOLATED"),
        ]}}
        devices = MODULE.available_iphones(payload)
        self.assertEqual(MODULE.existing_qa_device(devices), "ISOLATED")

    def test_never_falls_back_to_a_personal_phone(self) -> None:
        payload = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
            device("iPhone 17 Pro", "PERSONAL")
        ]}}
        self.assertIsNone(MODULE.existing_qa_device(MODULE.available_iphones(payload)))

    def test_creation_uses_the_newest_runtime_numerically(self) -> None:
        payload = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-9-3": [device("iPhone 8", "OLD", "old-type")],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [device("iPhone 17", "NEW", "new-type")],
        }}
        self.assertEqual(
            MODULE.creation_template(MODULE.available_iphones(payload)),
            ("com.apple.CoreSimulator.SimRuntime.iOS-26-5", "new-type"),
        )

    def test_missing_iphone_is_a_loud_failure(self) -> None:
        with self.assertRaisesRegex(ValueError, "no available iPhone"):
            MODULE.creation_template([])


if __name__ == "__main__":
    unittest.main()
