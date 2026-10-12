"""Independent game-sharing ABBA; never edits the conserved benchmark harness.

Run with --run only after the current 32 native products are ready and code is
frozen. Uses the preferred fixture, identical spawn/readiness and collision off.
All GPU execution remains in the imported private-desktop run_one implementation.
"""
import argparse
import json
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_joint_benchmarks as bench

JOBS = (
    ("game_sharing_off_a1_v2", "off"),
    ("game_sharing_on_b1_v2", "on"),
    ("game_sharing_on_b2_v2", "on"),
    ("game_sharing_off_a2_v2", "off"),
)
CODE_NAMES = (
    "scripts/world3d/model_parse_preparation.gd", "scripts/world3d/deferred_asset_loader.gd",
    "scripts/world3d/model_collision_requirements.gd", "scripts/world3d/model_texture_cache.gd",
    "scripts/world_editor/picking_lod_policy.gd", "scripts/world_editor/load_job.gd",
    "tools/profile_game_entry.gd", "tools/test_house_town_editor_incremental.gd",
)


def write_new(path, value):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Execute four sequential private-desktop GPU runs")
    args = parser.parse_args()
    if not args.run:
        print(json.dumps({"jobs": JOBS, "map": bench.PREFERRED.as_posix(), "collision": "off",
                          "run": False, "note": "No engine, hashes or evidence writes without --run."}, indent=2))
        return 0
    bench.OUT.mkdir(parents=True, exist_ok=True)
    code_receipt = bench.OUT / "game_sharing_v2_code_identity.json"
    aggregate = bench.OUT / "game_sharing_v2_run_receipts.json"
    outputs = [code_receipt, aggregate]
    for name, _ in JOBS:
        outputs.extend(bench.OUT / (name + suffix) for suffix in (".json", ".log", ".hardware.json", ".receipt.json"))
    if any(path.exists() for path in outputs):
        raise RuntimeError("Refusing to overwrite existing game-sharing evidence")
    code_state = {(bench.REPO / name).as_posix(): bench.sha(bench.REPO / name) for name in CODE_NAMES}
    write_new(code_receipt, code_state)
    # Keep this exclusive stream open; only this new invocation may update its
    # progress receipt. A later invocation cannot replace any earlier evidence.
    with aggregate.open("x+", encoding="utf-8", newline="\n") as receipts:
        completed = []

        def progress():
            receipts.seek(0)
            json.dump(completed, receipts, ensure_ascii=False, indent=2)
            receipts.write("\n"); receipts.truncate(); receipts.flush()

        progress()
        for name, sharing in JOBS:
            if any(bench.sha(Path(path)) != digest for path, digest in code_state.items()):
                raise RuntimeError("Measured code changed before " + name)
            began = time.time()
            summary = bench.run_one(name, "game", bench.PREFERRED, collision="off", picking="off", sharing=sharing)
            if any(bench.sha(Path(path)) != digest for path, digest in code_state.items()):
                raise RuntimeError("Measured code changed during " + name)
            report = json.loads((bench.OUT / (name + ".json")).read_text(encoding="utf-8"))
            if report.get("model_texture_sharing") is not (sharing == "on") or report.get("collision_geometry") is not False:
                raise RuntimeError("Actual experiment flags differ from request: " + name)
            receipt = {**summary, "sharing": sharing, "collision": "off", "started_epoch_s": began,
                       "fixture": bench.PREFERRED.as_posix(), "fixture_sha256": bench.MAP_SHAS[bench.PREFERRED],
                       "formal_sha256": bench.FORMAL_SHA, "code_identity": code_receipt.as_posix(),
                       "scope": "Same preferred resources/code/native generation; explicit sharing only; no default flip, cache rebuild or publication by this harness."}
            write_new(bench.OUT / (name + ".receipt.json"), receipt)
            completed.append(receipt); progress()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
