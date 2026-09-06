"""Freeze the pinned Rust runtime's outputs without training or exporting a model.

Compiles the original net.rs directly, with only its two dimension constants
supplied by the wrapper. Inputs and predictions are serialized as float32 bits,
so JSON parsing cannot introduce decimal rounding. The model is never rewritten.
"""

import argparse
import hashlib
import json
import platform
import struct
import subprocess
import tempfile
from pathlib import Path

SOURCE_COMMIT = "021279c56834b6203480e5292e1de7246e47bd68"
MODEL_SHA256 = "a3c957a8765ccbb3c9afd1a8ebee45b7cbaff134c40ce0456e5024560b3ef94e"
MODEL_BYTES = 4_438_528
INPUT_COUNT = 1350
PROBE_OFFSET = 4_433_092
RUST_FLAGS = ["--edition=2021", "-O", "-C", "codegen-units=1"]

RUST_MAIN = r'''
mod codec { pub const NUM_ACTIONS: usize = 299; }
mod obs { pub const OBS_DIM: usize = 1350; }
#[path = __NET_PATH__]
mod net;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let model = net::MlpNet::load(std::path::Path::new(&args[1]));
    let mut scratch = net::NetScratch::new(&model);
    let bytes = std::fs::read(&args[2]).unwrap();
    assert_eq!(bytes.len() % (obs::OBS_DIM * 4), 0);
    for sample in bytes.chunks_exact(obs::OBS_DIM * 4) {
        let input: Vec<f32> = sample.chunks_exact(4)
            .map(|v| f32::from_le_bytes(v.try_into().unwrap())).collect();
        model.trunk(&input, &mut scratch);
        for action in 0..codec::NUM_ACTIONS {
            print!("{} ", model.logit_from(&scratch, action).to_bits());
        }
        println!("{}", model.value_from(&scratch).to_bits());
    }
}
'''


def frozen_inputs(model: bytes) -> list[tuple[str, list[float]]]:
    """Exercise biases, both signs, sparsity, slot boundaries and dense reductions."""
    cases = [
        ("embedded", list(struct.unpack_from("<1350f", model, PROBE_OFFSET))),
        ("zero", [0.0] * INPUT_COUNT),
        ("negative-zero", [-0.0] * INPUT_COUNT),
        ("ones", [1.0] * INPUT_COUNT),
        ("alternating", [1.0 if i % 2 == 0 else -1.0 for i in range(INPUT_COUNT)]),
    ]
    for index in [0, 151, 152, 907, 908, 1195, 1264, 1334, 1349]:
        for sign in [-1.0, 1.0]:
            values = [0.0] * INPUT_COUNT
            values[index] = sign
            cases.append((f"basis-{index}-{sign:+.0f}", values))
    state = 0x43544E4E
    for sample in range(8):
        values = []
        for _ in range(INPUT_COUNT):
            state = (1664525 * state + 1013904223) & 0xFFFFFFFF
            # Dyadic fractions are represented exactly in binary32.
            value = ((state >> 16) - 32768) / 32768
            values.append(value if sample % 2 or state % 10 == 0 else 0.0)
        cases.append((f"lcg-{sample}", values))
    return cases


def rust_predictions(
    source: Path, model: Path, rustc: str, cases: list[tuple[str, list[float]]]
) -> list[list[int]]:
    """Use the unmodified upstream module as the oracle, not a second port."""
    net_path = source / "rust/catan-env/src/net.rs"
    with tempfile.TemporaryDirectory(prefix="empires-net-oracle-") as directory:
        scratch = Path(directory)
        wrapper = scratch / "oracle.rs"
        wrapper.write_text(RUST_MAIN.replace("__NET_PATH__", json.dumps(str(net_path))))
        inputs = scratch / "inputs.f32le"
        inputs.write_bytes(b"".join(struct.pack("<1350f", *values) for _, values in cases))
        binary = scratch / "oracle"
        subprocess.run([rustc, *RUST_FLAGS, str(wrapper), "-o", str(binary)], check=True)
        result = subprocess.run(
            [str(binary), str(model), str(inputs)], check=True, text=True, capture_output=True
        )
    rows = [[int(word) for word in line.split()] for line in result.stdout.splitlines()]
    if len(rows) != len(cases) or any(len(row) != 300 for row in rows):
        raise ValueError("Rust oracle returned an incomplete prediction matrix")
    return rows


def verified_source(source: Path) -> bytes:
    revision = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if revision != SOURCE_COMMIT:
        raise ValueError(f"unexpected upstream revision: {revision}")
    net_path = source / "rust/catan-env/src/net.rs"
    original = subprocess.check_output(["git", "-C", str(source), "show", f"{revision}:rust/catan-env/src/net.rs"])
    if net_path.read_bytes() != original:
        raise ValueError("upstream net.rs has local modifications")
    return original


def verified_model(model: Path) -> bytes:
    data = model.read_bytes()
    if len(data) != MODEL_BYTES or hashlib.sha256(data).hexdigest() != MODEL_SHA256:
        raise ValueError("model byte count or SHA-256 differs from pinned r2 final.ctnn")
    return data


def create_fixture(source: Path, model: Path, rustc: str) -> dict:
    original = verified_source(source)
    cases = frozen_inputs(verified_model(model))
    rows = rust_predictions(source, model, rustc, cases)
    if rows != rust_predictions(source, model, rustc, cases):
        raise ValueError("separate-process oracle drift")
    return {
        "sourceCommit": SOURCE_COMMIT, "modelSHA256": MODEL_SHA256,
        "netSourceSHA256": hashlib.sha256(original).hexdigest(),
        "rustc": subprocess.check_output([rustc, "-Vv"], text=True).strip(),
        "flags": RUST_FLAGS, "platform": platform.platform(),
        "cases": [
            {"name": name, "inputBits": list(struct.unpack("<1350I", struct.pack("<1350f", *values))),
             "logitsBits": row[:299], "valueBits": row[299]}
            for (name, values), row in zip(cases, rows, strict=True)
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--rustc", default="rustc")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    fixture = create_fixture(args.source.resolve(), args.model.resolve(), args.rustc)
    args.output.write_text(json.dumps(fixture, separators=(",", ":")) + "\n")
    print(f"Verified model SHA-256 {MODEL_SHA256}; froze {len(fixture['cases'])} cases in {args.output}")


if __name__ == "__main__":
    main()
