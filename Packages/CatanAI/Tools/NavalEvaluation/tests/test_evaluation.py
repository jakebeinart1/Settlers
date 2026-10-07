"""Reject corrupted evidence and pin packaging to the frozen statistical method."""

import copy
import json
import pathlib
import subprocess
import sys

import pytest

from naval_evaluation import evaluation as study

CANDIDATE = "d8639917f68563b6fd2ca0d38c5fc28d3fc80a18"
ANCHOR = "a316139bb2daa22d7224c19953f4a2e32c699c2f"


def save(path: pathlib.Path, value: object) -> None:
    path.write_text(json.dumps(value) + "\n")


def dataset(root: pathlib.Path, strong: bool = True) -> pathlib.Path:
    """Create the whole declared paired plan, not a favorable partial sample."""
    comparison = dict(
        candidateSource=CANDIDATE,
        anchorSource=ANCHOR,
        candidateSHA256="5" * 64,
        anchorSHA256="1" * 64,
        engineOriginalCommit="8" * 40,
    )
    save(root / "comparison.json", comparison)
    records, commands = [], []
    for job in study.plan("held-out"):
        source = ANCHOR if job.arm == "control" else CANDIDATE
        commands.append(
            (job.name, job.command(pathlib.Path("/artifact/naval-sim"), source))
        )
        rows = []
        for seed in range(job.seed, job.seed + job.games):
            winner = seed % job.players
            if job.arm == "candidate" and strong:
                winner = job.chair if job.chair < 2 else (job.chair + 1) % job.players
            row = dict(
                study.VERSIONS,
                family=job.family,
                fogEnabled=job.fog,
                resourceChoiceEnabled=job.wild,
                playerCount=job.players,
                arm=job.arm,
                focalChair=job.chair,
                buildID=source,
                policies=[f"naval-{seat}-v1" for seat in job.seats],
                seed=seed,
                winner=winner,
                fingerprint=f"seed-{seed}",
                behavior=[dict(shipsBought=1, colonies=1)] * job.players,
                forcedEnds=0,
                sailingCycles=1,
                idleSailingCycles=0,
                tradeCycles=0,
                duplicateProposals=0,
                moves=400,
            )
            rows.append(row)
        (root / f"{job.name}.jsonl").write_text(
            "".join(json.dumps(row) + "\n" for row in rows)
        )
        (root / f"{job.name}.timing").write_text(
            "".join(
                f"naval-sim seed={seed} decisions=400 p95=10ms p99=20ms over50=0 over150=0\n"
                for seed in range(job.seed, job.seed + job.games)
            )
        )
        records.append(
            dict(name=job.name, returncode=0, games=job.games, rejects=0, seconds=1)
        )
    save(root / "jobs.json", records)
    save(root / "commands.json", commands)
    return root


def mutate_row(root: pathlib.Path, **changes: object) -> None:
    file = root / "0-3-candidate-0.jsonl"
    rows = [json.loads(line) for line in file.read_text().splitlines()]
    rows[0].update(changes)
    file.write_text("".join(json.dumps(row) + "\n" for row in rows))


def test_declared_plan_counts_every_cell_chair_and_seed() -> None:
    held = study.plan("held-out")
    assert len(held) == 168
    for players, expected in ((3, 396), (4, 336)):
        for arm in ("candidate", "control"):
            jobs = [job for job in held if job.players == players and job.arm == arm]
            assert sum(job.games for job in jobs) == expected
            assert {job.chair for job in jobs} == set(range(players))
            assert {job.cell for job in jobs} == set(range(12))
            assert all(job.seed == 800000 + job.cell * 1000 for job in jobs)
    assert len(study.plan("matrix")) == 48
    assert len(study.plan("mixed-development")) == 84
    assert len(study.plan("land-development")) == 84
    assert all(
        job.seed < 800000 for stage in study.STAGES[:3] for job in study.plan(stage)
    )


def test_valid_complete_plan_and_frozen_hashes(tmp_path: pathlib.Path) -> None:
    study.verify_frozen_scripts()
    assert len(study.validate_rows(dataset(tmp_path), "held-out")) == 1464


@pytest.mark.parametrize(
    "corruption", ("extra-control", "missing-control", "extra-shard", "duplicate-seed")
)
def test_asymmetric_or_incomplete_pairs_rejected(
    tmp_path: pathlib.Path, corruption: str
) -> None:
    root = dataset(tmp_path)
    file = root / "0-3-control-0.jsonl"
    lines = file.read_text().splitlines()
    if corruption == "extra-control":
        extra = json.loads(lines[-1])
        extra["seed"] += 1
        file.write_text("\n".join(lines + [json.dumps(extra)]) + "\n")
    elif corruption == "missing-control":
        file.write_text("\n".join(lines[1:]) + "\n")
    elif corruption == "extra-shard":
        (root / "unpaired.jsonl").write_text(file.read_text())
    else:
        lines[1] = lines[0]
        file.write_text("\n".join(lines) + "\n")
    with pytest.raises(ValueError):
        study.validate_rows(root, "held-out")


@pytest.mark.parametrize(
    "changes",
    (
        {"buildID": ANCHOR},
        {"policies": ["naval-traditional-v1"] * 3},
        {"fogEnabled": False},
        {"schemaVersion": 2},
        {"engineRulesVersion": 2},
        {"focalChair": 1},
        {"winner": 7},
        {"behavior": [{}]},
    ),
)
def test_mislabeled_configuration_or_provenance_rejected(
    tmp_path: pathlib.Path, changes: dict
) -> None:
    root = dataset(tmp_path)
    mutate_row(root, **changes)
    with pytest.raises(ValueError):
        study.validate_rows(root, "held-out")


@pytest.mark.parametrize(
    "kind",
    (
        "failed-process",
        "missing-process",
        "duplicate-process",
        "tampered-command",
        "missing-timing",
    ),
)
def test_process_command_and_timing_evidence_required(
    tmp_path: pathlib.Path, kind: str
) -> None:
    root = dataset(tmp_path)
    records = study.read_json(root / "jobs.json")
    if kind == "failed-process":
        records[0]["returncode"] = 1
    elif kind == "missing-process":
        records.pop()
    elif kind == "duplicate-process":
        records.append(copy.deepcopy(records[0]))
    elif kind == "tampered-command":
        commands = study.read_json(root / "commands.json")
        commands[0][1][-1] = "2"
        save(root / "commands.json", commands)
    else:
        (root / "0-3-candidate-0.timing").write_text("")
    save(root / "jobs.json", records)
    with pytest.raises(ValueError):
        study.validate_rows(root, "held-out")


def test_changed_release_artifact_rejected(tmp_path: pathlib.Path) -> None:
    binary = tmp_path / "naval-sim"
    binary.write_bytes(b"frozen executable")
    manifest = dict(
        sourceCommit=CANDIDATE,
        sha256=study.sha256(binary),
        configuration="Release",
        schemaVersion=3,
        protocolVersion=3,
        mapVersion=1,
        engineRulesVersion=3,
        navalRulesVersion=1,
    )
    save(tmp_path / "provenance.json", manifest)
    assert study.artifact(binary)["sourceCommit"] == CANDIDATE
    binary.write_bytes(b"recompiled executable")
    with pytest.raises(ValueError, match="artifact changed"):
        study.artifact(binary)


def test_analysis_equals_exact_frozen_calculation_and_passes_strong_fixture(
    tmp_path: pathlib.Path,
) -> None:
    root = dataset(tmp_path)
    subprocess.run(
        [
            sys.executable,
            str(study.ROOT / "frozen" / "analyze_measurement.py"),
            str(root),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    original = study.read_json(root / "analysis.json")
    portable = study.analyze(root, "held-out", verify_binaries=False)
    # All descriptive fields are identical; only paired arithmetic is canonical.
    compared = copy.deepcopy(portable)
    compared.pop("analysisArithmetic")
    compared.pop("frozenAnalyzerSHA256")
    compared.pop("artifactVerification")
    for players in ("3", "4"):
        current, old = (
            compared["byTable"][players]["paired"],
            original["byTable"][players]["paired"],
        )
        assert current["difference"] == pytest.approx(old["difference"], abs=1e-14)
        assert current["difference95CI"] == pytest.approx(
            old["difference95CI"], abs=1e-14
        )
        current["difference"], current["difference95CI"] = (
            old["difference"],
            old["difference95CI"],
        )
    assert compared == original
    assert portable["functionalGatePassed"]
    for players in (3, 4):
        paired = portable["byTable"][str(players)]["paired"]
        assert paired["substantiveGatePassed"]
        assert paired["difference95CI"][0] > 0.1
        assert paired["seedClusters"] == (132 if players == 3 else 84)
        assert paired["correlationUsedForSampleDiscount"] is False


def test_zero_effect_cannot_pass_strength_threshold(tmp_path: pathlib.Path) -> None:
    report = study.analyze(
        dataset(tmp_path, strong=False), "held-out", verify_binaries=False
    )
    for players in (3, 4):
        paired = report["byTable"][str(players)]["paired"]
        assert paired["difference"] == 0
        assert paired["difference95CI"] == [0, 0]
        assert not paired["substantiveGatePassed"]


def test_null_winner_not_replaced_with_vp_margin(tmp_path: pathlib.Path) -> None:
    root = dataset(tmp_path)
    mutate_row(root, winner=None, victoryPoints=[13, 1, 1])
    records = study.read_json(root / "jobs.json")
    records[0]["rejects"] = 1
    save(root / "jobs.json", records)
    assert study.validate_rows(root, "held-out")[0]["winner"] is None
    with pytest.raises(subprocess.CalledProcessError):
        study.analyze(root, "held-out", verify_binaries=False)


def test_integer_zero_bound_cannot_become_positive_epsilon() -> None:
    from naval_evaluation.statistics import integer_bootstrap

    strata = {
        (0,): [1] * 5 + [0] * 6,
        (1,): [1] * 2 + [0] * 9,
        (2,): [-1] * 7 + [0] * 4,
        **{(index,): [0] * 11 for index in range(3, 12)},
    }
    floating = (
        sum(sum(value / 3 for value in values) for values in strata.values()) / 132
    )
    assert abs(floating) < 1e-16  # The old rounding varies by Python version.
    result = integer_bootstrap(strata, players=3)
    assert result["difference"] == 0
    assert not result["substantiveGatePassed"]


def test_real_sample_draws_differ_only_by_roundoff(tmp_path: pathlib.Path) -> None:
    from naval_evaluation.statistics import paired_integers

    root = dataset(tmp_path)
    rows = study.validate_rows(root, "held-out")
    # Vary candidate wins across seeds while retaining all control rotations.
    for row in rows:
        if row["arm"] == "candidate" and row["seed"] % 3 == 0:
            row["winner"] = (row["focalChair"] + 1) % row["playerCount"]
    for job in study.plan("held-out"):
        shard = [
            row
            for row in rows
            if row["family"] == job.family
            and row["fogEnabled"] == job.fog
            and row["resourceChoiceEnabled"] == job.wild
            and row["playerCount"] == job.players
            and row["arm"] == job.arm
            and row["focalChair"] == job.chair
        ]
        (root / f"{job.name}.jsonl").write_text(
            "".join(json.dumps(row) + "\n" for row in shard)
        )
    subprocess.run(
        [
            sys.executable,
            str(study.ROOT / "frozen" / "analyze_measurement.py"),
            str(root),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    frozen = study.read_json(root / "analysis.json")
    for players in (3, 4):
        original = frozen["byTable"][str(players)]["paired"]
        canonical = paired_integers(rows, players)
        assert canonical["difference"] == pytest.approx(
            original["difference"], abs=1e-14
        )
        assert canonical["difference95CI"] == pytest.approx(
            original["difference95CI"], abs=1e-14
        )


@pytest.mark.parametrize("kind", ("divergent-control", "truncated-decision-count"))
def test_reproducibility_and_all_decision_latency_required(
    tmp_path: pathlib.Path, kind: str
) -> None:
    root = dataset(tmp_path)
    if kind == "divergent-control":
        file = root / "0-3-control-1.jsonl"
        rows = [json.loads(line) for line in file.read_text().splitlines()]
        rows[0]["fingerprint"] = "different-path-same-winner"
        file.write_text("".join(json.dumps(row) + "\n" for row in rows))
    else:
        file = root / "0-3-candidate-0.timing"
        file.write_text(file.read_text().replace("decisions=400", "decisions=399", 1))
    with pytest.raises(ValueError):
        study.validate_rows(root, "held-out")


@pytest.mark.parametrize("corruption", ("changed", "missing", "extra"))
def test_retained_raw_evidence_hashes_detect_corruption(
    tmp_path: pathlib.Path, corruption: str
) -> None:
    raw = tmp_path / "game.jsonl"
    raw.write_text('{"winner":0}\n')
    save(tmp_path / "checksums.json", {"game.jsonl": study.sha256(raw)})
    study.verify_evidence(tmp_path)
    if corruption == "changed":
        raw.write_text('{"winner":1}\n')
    elif corruption == "missing":
        raw.unlink()
    else:
        (tmp_path / "unregistered.jsonl").write_text("{}\n")
    with pytest.raises(ValueError):
        study.verify_evidence(tmp_path)


def test_portable_runner_uses_distinct_frozen_artifacts_and_refuses_overwrite(
    tmp_path: pathlib.Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    binaries = {}
    for name, source in (("candidate", CANDIDATE), ("anchor", ANCHOR)):
        directory = tmp_path / name
        directory.mkdir()
        binary = directory / "naval-sim"
        binary.write_bytes(name.encode())
        manifest = dict(
            sourceCommit=source,
            sha256=study.sha256(binary),
            configuration="Release",
            schemaVersion=3,
            protocolVersion=3,
            mapVersion=1,
            engineRulesVersion=3,
            navalRulesVersion=1,
            engineOriginalCommit="8" * 40,
        )
        save(directory / "provenance.json", manifest)
        binaries[name] = binary
    real_run = subprocess.run
    calls = []

    def simulate(args: list, **kwargs: object) -> subprocess.CompletedProcess:
        if args[0] == sys.executable:
            return real_run(args, **kwargs)
        flags = dict(zip(args[1::2], args[2::2]))
        calls.append((args[0], flags["--arm"], flags["--build-id"]))
        players, chair = int(flags["--players"]), int(flags["--focal-chair"])
        for seed in range(
            int(flags["--seed"]), int(flags["--seed"]) + int(flags["--games"])
        ):
            row = dict(
                study.VERSIONS,
                family=flags["--family"],
                fogEnabled=flags["--fog"] == "on",
                resourceChoiceEnabled=flags["--wild"] == "on",
                playerCount=players,
                arm=flags["--arm"],
                focalChair=chair,
                buildID=flags["--build-id"],
                seed=seed,
                policies=[f"naval-{tier}-v1" for tier in flags["--seats"].split(",")],
                winner=seed % players,
                behavior=[dict(shipsBought=1, colonies=1)] * players,
                forcedEnds=0,
                sailingCycles=0,
                idleSailingCycles=0,
                tradeCycles=0,
                duplicateProposals=0,
                moves=400,
                fingerprint=f"seed-{seed}",
            )
            kwargs["stdout"].write(json.dumps(row) + "\n")
            kwargs["stderr"].write(
                f"naval-sim seed={seed} decisions=400 p95=10ms p99=20ms over50=0 over150=0\n"
            )
        return subprocess.CompletedProcess(args, 0)

    monkeypatch.setattr(subprocess, "run", simulate)
    output = tmp_path / "measurement"
    study.execute(
        binaries["candidate"], binaries["anchor"], "held-out", output, workers=2
    )
    assert len(calls) == 168
    assert all(
        binary == str(binaries["anchor"]) and source == ANCHOR
        for binary, arm, source in calls
        if arm == "control"
    )
    assert all(
        binary == str(binaries["candidate"]) and source == CANDIDATE
        for binary, arm, source in calls
        if arm == "candidate"
    )
    assert len(study.validate_rows(output, "held-out")) == 1464
    with pytest.raises(ValueError, match="output must be new or empty"):
        study.execute(
            binaries["candidate"], binaries["anchor"], "held-out", output, workers=2
        )


@pytest.mark.parametrize(
    "corruption", ("none", "truncated-trace", "wrong-winner", "idle-cycle")
)
def test_revisit_evidence_checks_full_trace_and_completed_endpoint(
    tmp_path: pathlib.Path, corruption: str
) -> None:
    from naval_evaluation import revisits

    trace = ["P0:endTurn", "P1:endTurn"]
    row = dict(
        seed=800000,
        playerCount=3,
        focalChair=0,
        arm="candidate",
        family="archipelago",
        fogEnabled=True,
        resourceChoiceEnabled=True,
        winner=1,
        buildID=CANDIDATE,
        sailingCycles=1,
        moves=2,
        fingerprint=revisits.trace_fingerprint(trace),
    )
    name = revisits.artifact_name(row)
    (tmp_path / f"{name}.failure").write_text(
        f"build={CANDIDATE}\nCompletion/revisit evidence: winner=Optional(1), forced=0, "
        "raw sailing=1, idle sailing=0, trading=0\n"
    )
    (tmp_path / f"{name}.txt").write_text("\n".join(trace) + "\n")
    save(
        tmp_path / f"{name}.json",
        {"state": {"phase": {"gameOver": {"winner": {"index": 1}}}}},
    )
    if corruption == "truncated-trace":
        (tmp_path / f"{name}.txt").write_text(trace[0] + "\n")
    elif corruption == "wrong-winner":
        save(
            tmp_path / f"{name}.json",
            {"state": {"phase": {"gameOver": {"winner": {"index": 0}}}}},
        )
    elif corruption == "idle-cycle":
        path = tmp_path / f"{name}.failure"
        path.write_text(path.read_text().replace("idle sailing=0", "idle sailing=1"))
    if corruption == "none":
        report = revisits.preserve([row], tmp_path, tmp_path / "durable")
        assert report["gamesInspected"] == 1 and report["idleRevisits"] == 0
        assert len(list((tmp_path / "durable").iterdir())) == 3
    else:
        with pytest.raises(ValueError):
            revisits.inspect(row, tmp_path)


def test_land_control_requires_its_real_distinct_policy_id() -> None:
    job = study.plan("land-development")[0]
    row = dict(
        study.VERSIONS,
        family=job.family,
        fogEnabled=job.fog,
        resourceChoiceEnabled=job.wild,
        playerCount=job.players,
        arm=job.arm,
        focalChair=job.chair,
        buildID=CANDIDATE,
        policies=[
            "naval-traditional-land-control-v1",
            "naval-traditional-v1",
            "naval-traditional-v1",
        ],
        winner=0,
        moves=400,
        behavior=[{}] * 3,
    )
    study.validate_row(row, job, CANDIDATE)
    row["policies"][0] = "naval-land-control-v1"
    with pytest.raises(ValueError):
        study.validate_row(row, job, CANDIDATE)


def test_uncontended_latency_plan_is_expert_only_and_one_worker(
    tmp_path: pathlib.Path,
) -> None:
    jobs = study.plan("uncontended-latency")
    assert len(jobs) == 24 and all(
        job.seats == ("expert",) * job.players for job in jobs
    )
    with pytest.raises(ValueError, match="one worker"):
        study.execute(
            tmp_path / "candidate",
            tmp_path / "anchor",
            "uncontended-latency",
            tmp_path,
            workers=2,
        )


@pytest.mark.parametrize("kind", ("changed-executable", "over-budget-actions"))
def test_artifact_path_and_action_budget_are_integrity_gates(
    tmp_path: pathlib.Path, kind: str
) -> None:
    root = dataset(tmp_path)
    if kind == "changed-executable":
        commands = study.read_json(root / "commands.json")
        commands[0][1][0] = "/different/artifact/naval-sim"
        save(root / "commands.json", commands)
    else:
        mutate_row(root, moves=6001)
        timing = root / "0-3-candidate-0.timing"
        timing.write_text(
            timing.read_text().replace("decisions=400", "decisions=6001", 1)
        )
    with pytest.raises(ValueError):
        study.validate_rows(root, "held-out")
