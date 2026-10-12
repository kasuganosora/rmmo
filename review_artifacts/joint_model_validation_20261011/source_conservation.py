"""Full-byte source conservation, without Godot/import/cache writes.

Run only outside timed GPU samples. `before` refuses to overwrite its snapshot;
`compare` uses its fixed file set and also detects changed map dependency sets.
The source fingerprint is NOT a claimed Godot Compiled.generator() value.
"""
import argparse
import hashlib
import json
import re
import sys
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

REPO = Path("D:/code/rmmo")
RUNTIME = Path("D:/code/rmmo_runtime")
OUT = REPO / "review_artifacts/joint_model_validation_20261011"
DEFAULT_MANIFEST = RUNTIME / "cache/world3d/joint_model_validation_20261011_1791726474152524200/fixture_manifest.json"
BASELINE = OUT / "source_before.json"


def path(value):
    return Path(str(value).replace("\\", "/")).resolve()


def canon(value):
    return path(value).as_posix()


def load(value):
    return json.loads(path(value).read_text(encoding="utf-8"))


def utc():
    return datetime.now(timezone.utc).isoformat()


def collect(manifest):
    files = {}
    maps = []

    def add(value, role, sha=None, size=None):
        name = canon(value)
        item = files.setdefault(name, {"path": name, "roles": [], "expected_sha256": [], "expected_lengths": []})
        if role not in item["roles"]:
            item["roles"].append(role)
        if sha is not None and sha not in item["expected_sha256"]:
            item["expected_sha256"].append(sha)
        if size is not None and size not in item["expected_lengths"]:
            item["expected_lengths"].append(size)

    def add_map(value, role, expected):
        map_path = path(value)
        add(map_path, role, expected)
        document = load(map_path)
        extras = document["nodes"][0]["extras"]
        refs = {}
        for record in extras["rmmo_records"]:
            ref = record["rmmo_ref"]
            ref_path = path(map_path.parent / ref["uri"])
            if not ref_path.is_relative_to(map_path.parent):
                raise ValueError(f"Nonlocal definition: {ref_path}")
            add(ref_path, role + ":definition", ref["sha256"], ref["length"])
            refs[ref["uri"]] = {"path": canon(ref_path), "sha256": ref["sha256"], "length": ref["length"]}
        for uri, sha in extras["rmmo_resource_dependencies"].items():
            dependency = path(map_path.parent / uri)
            if not dependency.is_relative_to(map_path.parent):
                raise ValueError(f"Nonlocal dependency: {dependency}")
            add(dependency, role + ":dependency", sha)
        maps.append({"path": canon(map_path), "role": role,
                     "record_count": len(extras["rmmo_records"]), "definitions": refs,
                     "dependencies": extras["rmmo_resource_dependencies"]})

    add(manifest, "fixture_manifest")
    fixture = load(manifest)
    add_map(RUNTIME / "maps/medieval_river_town/map.gltf", "formal_map", fixture["source_sha256"])
    for name, row in fixture["fixtures"].items():
        add_map(row["map"], "fixture_" + name, row["sha256"])
    handoff_path = REPO / "review_artifacts/town_large_asset_art_handoff_20261011.json"
    add(handoff_path, "original_handoff")
    for row in load(handoff_path)["rows"]:
        add(row["path"], "original_32_glb", row["source_sha256"], row["source_bytes"])
    preferred_path = fixture["preferred_handoff"]
    add(preferred_path, "preferred_handoff")
    for row in load(preferred_path)["preferred"]:
        add(row["candidate"], "preferred_candidate", row["candidate_sha256"])
    for row in fixture["metadata_transplants"]:
        add(row["candidate"], "combined_overlay", row["candidate_sha256"])
        add(row["receiver"], "overlay_receiver", row["receiver_sha256"])
        add(row["donor"], "overlay_donor", row["donor_sha256"])
    for value, sha in fixture["protected_source_sha256"].items():
        add(value, "fixture_protected_source", sha)
    add(RUNTIME / "packs/default/assets/library.json", "formal_library")

    compiled = REPO / "scripts/world3d/compiled_asset_cache.gd"
    text = compiled.read_text(encoding="utf-8")
    function = text.split("static func generator()->String:", 1)[1].split("static func ", 1)[0]
    match = re.search(r"for path in (\[[^\]]+\]):", function)
    if not match:
        raise ValueError("Compiled.generator dependency array changed; inspect rather than assume coverage")
    dependencies = json.loads(match.group(1))
    for name in dependencies:
        add(REPO / "scripts/world3d" / name, "compiled_generator_source")
    add(REPO / "project.godot", "compiled_generator_project_settings")
    add(__file__, "conservation_harness")
    return sorted(files.values(), key=lambda x: x["path"].casefold()), maps, dependencies


def hash_row(spec):
    row = dict(spec)
    p = path(spec["path"])
    row["exists"] = p.is_file()
    if not row["exists"]:
        row["valid"] = False
        return row
    before = p.stat()
    size = 0
    h = hashlib.sha256()
    with p.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            h.update(chunk)
            size += len(chunk)
    after = p.stat()
    row.update(sha256=h.hexdigest(), bytes=size,
               stable_during_read=before.st_size == after.st_size == size and before.st_mtime_ns == after.st_mtime_ns)
    row["valid"] = row["stable_during_read"] and all(sha == row["sha256"] for sha in spec["expected_sha256"]) and all(length == size for length in spec["expected_lengths"])
    return row


def fingerprint(rows):
    data = [{"path": r["path"], "sha256": r.get("sha256")}
            for r in rows if any(role.startswith("compiled_generator_") for role in r["roles"])]
    return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("mode", choices=["before", "compare"])
    ap.add_argument("--fixture", default=str(DEFAULT_MANIFEST))
    ap.add_argument("--before", default=str(BASELINE))
    ap.add_argument("--output")
    args = ap.parse_args()
    started = time.monotonic()
    target = path(args.output or (args.before if args.mode == "before" else str(OUT / ("source_compare_" + datetime.now().strftime("%Y%m%d_%H%M%S") + ".json"))))
    if not target.is_relative_to(OUT.resolve()):
        ap.error("Reports must remain within review_artifacts/joint_model_validation_20261011")
    if target.exists():
        ap.error("Refusing to overwrite an existing evidence snapshot")
    specs, maps, dependencies = collect(args.fixture)
    prior = None
    inventory_changes = {}
    if args.mode == "compare":
        prior = load(args.before)
        old = {r["path"]: r for r in prior["files"]}
        current = {r["path"]: r for r in specs}
        inventory_changes = {"added_paths": sorted(current.keys() - old.keys()), "removed_paths": sorted(old.keys() - current.keys()),
                             "map_dependency_sets_changed": maps != prior["maps"]}
        # Still read removed former dependencies: dropping a reference cannot hide a mutation.
        for name in old.keys() - current.keys():
            current[name] = {k: old[name][k] for k in ("path", "roles", "expected_sha256", "expected_lengths")}
        specs = sorted(current.values(), key=lambda x: x["path"].casefold())
    rows = [hash_row(r) for r in specs]
    invalid = [r["path"] for r in rows if not r["valid"]]
    changes = []
    if prior:
        old = {r["path"]: r for r in prior["files"]}
        for row in rows:
            previous = old.get(row["path"])
            if previous and (row.get("sha256"), row.get("bytes"), row["exists"]) != (previous.get("sha256"), previous.get("bytes"), previous["exists"]):
                changes.append({"path": row["path"], "roles": row["roles"], "before_sha256": previous.get("sha256"), "after_sha256": row.get("sha256"), "before_bytes": previous.get("bytes"), "after_bytes": row.get("bytes")})
    passed = not invalid and not changes and not any(inventory_changes.values())
    counts = Counter(role for row in rows for role in row["roles"])
    report = {"version": 1, "mode": args.mode, "created_utc": utc(), "fixture_manifest": canon(args.fixture),
              "before_snapshot": canon(args.before) if prior else None,
              "source_fingerprint_note": "SHA of listed Compiled.generator dependency source files plus project.godot, not the runtime generator value (engine version/serialization not evaluated).",
              "compiled_generator_dependency_names": dependencies, "compiled_source_fingerprint": fingerprint(rows),
              "previous_compiled_source_fingerprint": prior.get("compiled_source_fingerprint") if prior else None,
              "passed": passed, "file_count": len(rows), "bytes_hashed": sum(r.get("bytes", 0) for r in rows),
              "role_counts": dict(counts), "elapsed_seconds": time.monotonic() - started,
              "invalid_current_files": invalid, "changed_files": changes, "inventory_changes": inventory_changes,
              "maps": maps, "files": rows}
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("x", encoding="utf-8") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print(json.dumps({k: report[k] for k in ("mode", "passed", "file_count", "bytes_hashed", "role_counts", "elapsed_seconds", "compiled_source_fingerprint", "invalid_current_files", "changed_files", "inventory_changes")}, ensure_ascii=False, indent=2))
    print("report=" + target.as_posix())
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
