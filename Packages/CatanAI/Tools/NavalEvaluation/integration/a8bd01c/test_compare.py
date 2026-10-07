"""Guard the bridge against ignored mutations or asymmetric result sets."""

from copy import deepcopy

import pytest
from compare import compare_results


def row() -> dict:
    return {
        "family": "archipelago",
        "fogEnabled": True,
        "resourceChoiceEnabled": True,
        "playerCount": 3,
        "seed": 700000,
        "arm": "expert",
        "focalChair": 0,
        "buildID": "historical",
        "fingerprint": "original",
        "moves": 500,
        "winner": 2,
        "behavior": [{"coloniesBuilt": 2}],
    }


def test_only_build_label_is_excluded() -> None:
    before, after = row(), row()
    after["buildID"] = "integrated"
    result = compare_results([before], [after])
    assert result["allEqual"]
    assert result["records"][0]["changedFields"] == []


@pytest.mark.parametrize("field,value", [("fingerprint", "changed"), ("moves", 501)])
def test_trajectory_changes_fail(field: str, value: object) -> None:
    before, after = row(), row()
    after[field] = value
    result = compare_results([before], [after])
    assert not result["allEqual"]
    assert result["records"][0]["changedFields"] == [field]


def test_nested_telemetry_change_fails() -> None:
    before = row()
    after = deepcopy(before)
    after["behavior"][0]["coloniesBuilt"] = 3
    assert not compare_results([before], [after])["allEqual"]


def test_added_null_field_is_not_ignored() -> None:
    before, after = row(), row()
    after["unexpected"] = None
    assert not compare_results([before], [after])["allEqual"]


def test_missing_trajectory_fails() -> None:
    with pytest.raises(ValueError, match="keys differ"):
        compare_results([row()], [])


def test_duplicate_trajectory_fails() -> None:
    with pytest.raises(ValueError, match="duplicate trajectory"):
        compare_results([row(), row()], [row()])
