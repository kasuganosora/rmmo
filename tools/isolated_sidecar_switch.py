"""Verify and switch only manifest-listed candidate sidecars in a private fixture.

The shared fixture lock covers cooperating runners only. Before invoking this
tool ensure no external process has the fixture open. Hashing and header reads
warm OS caches, so these runs are not physically cold disk measurements.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from isolated_fixture_lock import fixture_lock

REVIEW_ROOT = Path("D:/code/rmmo_runtime/review_artifacts")


def digest(path):
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(block)
    return sha.hexdigest()


def confined(root, value, *, existing=False):
    path = Path(value)
    if path.is_symlink():
        raise ValueError("symbolic link is not permitted")
    resolved = path.resolve(strict=existing)
    if resolved == root or not resolved.is_relative_to(root):
        raise ValueError("path escapes fixture")
    return resolved


def dds_evidence(path):
    with path.open("rb") as stream:
        data = stream.read(148)
    if len(data) < 128 or data[:4] != b"DDS " or struct.unpack_from("<I", data, 4)[0] != 124:
        raise ValueError("invalid DDS header")
    return {"width": struct.unpack_from("<I", data, 16)[0],
            "height": struct.unpack_from("<I", data, 12)[0],
            "mip_count": max(1, struct.unpack_from("<I", data, 28)[0]),
            "bytes": path.stat().st_size, "fourcc": data[84:88].decode("ascii")}


def selected(source, normal, flip):
    suffixes = ([".flip.dxt5.dds", ".flip.dxt1.dds"] if flip else
                [".dxt5.dds", ".dxt1.dds"])
    if normal or flip:
        suffixes.insert(0, ".flip.bc5.dds" if flip else ".bc5.dds")
    return next((Path(str(source) + suffix) for suffix in suffixes
                 if Path(str(source) + suffix).is_file()), None)


def _record(stable, path, sha):
    if path in stable and stable[path] != sha:
        raise ValueError("conflicting fixture file identities")
    stable[path] = sha


def load_fixture(root, manifest_sha, expected_candidates):
    root = Path(root).resolve(strict=True)
    review = REVIEW_ROOT.resolve(strict=True)
    if root == review or not root.is_relative_to(review):
        raise ValueError("fixture must be a private review-artifact directory")
    manifest_path = confined(root, root / "fixture_manifest.json", existing=True)
    if digest(manifest_path) != manifest_sha:
        raise ValueError("fixture manifest changed")
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    if Path(data["target_root"]).resolve(strict=True) != root:
        raise ValueError("manifest belongs to another root")
    stable = {}
    map_path = confined(root, data["target_map"], existing=True)
    _record(stable, map_path, data["target_map_sha256"])
    for uri, sha in data["resource_dependencies"].items():
        _record(stable, confined(root, map_path.parent / uri, existing=True), sha)
    for item in data["copied"]:
        _record(stable, confined(root, item["target"], existing=True), item["sha256"])
    for native in data["native"]:
        for item in native["files"]:
            _record(stable, confined(root, item["target"], existing=True), item["sha256"])
    targets = data["candidate_targets"]
    if len(targets) != expected_candidates or not data.get("texture_variants"):
        raise ValueError("candidate or variant count mismatch")
    for row in targets:
        source = confined(root, row["source"], existing=True)
        target = confined(root, row["target"])
        blob = confined(root, row["blob"], existing=True)
        if source not in stable or blob not in stable or target in stable:
            raise ValueError("candidate is not bound to fixture files")
        suffix = str(target)[len(str(source)):]
        valid = ([".flip.bc5.dds", ".flip.dxt1.dds", ".flip.dxt5.dds"] if row["flip"] and row["role"] == "normal" else
                 [".bc5.dds", ".dxt1.dds", ".dxt5.dds"] if row["role"] == "normal" and not row["flip"] else
                 [".dxt1.dds", ".dxt5.dds"] if row["role"] == "color" and not row["flip"] else [])
        if not str(target).startswith(str(source)) or suffix not in valid or stable[blob] != row["sha256"]:
            raise ValueError("candidate role or identity mismatch")
        row.update(_source=source, _target=target, _blob=blob)
    if len({row["_target"] for row in targets}) != len(targets):
        raise ValueError("duplicate candidate target")
    return root, data, stable


def check_state(root, data, stable):
    for path, expected in stable.items():
        if not path.is_file() or digest(path) != expected:
            raise ValueError(f"fixture file changed: {path}")
    targets = data["candidate_targets"]
    present = [row["_target"].exists() for row in targets]
    if any(present) and not all(present):
        raise ValueError("partial candidate installation")
    state = "B" if all(present) else "A"
    if state == "B":
        for row in targets:
            if row["_target"].is_symlink() or digest(row["_target"]) != row["sha256"]:
                raise ValueError("candidate target changed")
    evidence = []
    for row in data["texture_variants"]:
        source = confined(root, row["source"], existing=True)
        if source not in stable:
            raise ValueError("variant source is not in fixture manifest")
        candidate = row.get("candidate_sidecar", "")
        expected = candidate if state == "B" and candidate else row["baseline_sidecar"]
        actual = selected(source, row["normal"], row["flip"])
        expected_path = confined(root, expected, existing=True) if expected else None
        if actual != expected_path:
            raise ValueError(f"unexpected variant selection: {source}")
        header = dds_evidence(actual) if actual else {}
        declared = row["candidate_header"] if state == "B" and candidate else row["baseline_header"]
        if any(header.get(key) != declared.get(key) for key in header):
            raise ValueError(f"variant DDS header changed: {source}")
        evidence.append({"source": str(source), "source_sha256": stable[source],
                         "normal": row["normal"], "flip": row["flip"],
                         "sidecar": str(actual) if actual else "", "header": header,
                         "format": declared.get("format") if actual else None})
    return state, evidence


def switch(root, desired, manifest_sha, expected_candidates):
    with fixture_lock(root):
        root, data, stable = load_fixture(root, manifest_sha, expected_candidates)
        before, before_variants = check_state(root, data, stable)
        changed = []
        try:
            if before != desired:
                for row in data["candidate_targets"]:
                    if desired == "B":
                        with row["_blob"].open("rb") as source, row["_target"].open("xb") as target:
                            changed.append(row)
                            for block in iter(lambda: source.read(1024 * 1024), b""):
                                target.write(block)
                    else:
                        row["_target"].unlink()
                        changed.append(row)
            after, after_variants = check_state(root, data, stable)
            if after != desired:
                raise ValueError("switch did not reach requested state")
        except Exception:
            for row in reversed(changed):
                if desired == "B":
                    if row["_target"].exists():
                        row["_target"].unlink()
                else:
                    with row["_blob"].open("rb") as source, row["_target"].open("xb") as target:
                        for block in iter(lambda: source.read(1024 * 1024), b""):
                            target.write(block)
            raise
        return {"before": before, "after": after, "changed": len(changed),
                "candidate_count": len(data["candidate_targets"]),
                "variant_count": len(after_variants), "before_variants": before_variants,
                "after_variants": after_variants, "fixture_manifest_sha256": manifest_sha,
                "contract": "Private fixture only; OS page cache warmed by verification."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--state", choices=("A", "B"), required=True)
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--expected-candidates", type=int, default=11)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report = args.report.resolve()
    if not report.is_relative_to(REVIEW_ROOT.resolve()) or report.exists():
        parser.error("report must be a new review-artifact file")
    result = switch(args.root, args.state, args.manifest_sha256, args.expected_candidates)
    with report.open("x", encoding="utf-8") as out:
        json.dump(result, out, ensure_ascii=False, indent=2)
    print(json.dumps({key: value for key, value in result.items() if not key.endswith("_variants")}))


if __name__ == "__main__":
    main()
