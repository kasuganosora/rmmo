"""Prepare a receipt-bound checkpoint or verify the frozen prepublication sources.

Run ONLY after publication, outside timed GPU samples. This tool never launches
Godot, imports models, rebuilds caches, edits the formal map/catalog, overwrites
evidence, or removes files. A checkpoint copies exactly map.gltf and its declared
adjacent reference definitions; it is a test fixture, not a directory backup.

Examples (from the repository):
  python review_artifacts/joint_model_validation_20261011/postpublish_validation.py checkpoint --receipt <publish_combined_receipt.json>
  python review_artifacts/joint_model_validation_20261011/postpublish_validation.py verify --receipt <publish_combined_receipt.json>

The verify mode hashes the complete fixed source_before file set, including old
definitions no longer referenced by the new map. Only the two exact formal-map
and catalog paths may change, and only to their successful receipt SHA values.
New immutable imported targets and the new formal dependency closure are also
verified. Native products, GPU behavior and performance require separate tests.
An optional --code-transition records the user's explicit default-sharing choice
and permits exactly the model_texture_cache.gd enabled false -> true line. Its
full before/after bytes, full-context diff and the old snapshot SHA are verified;
all other frozen generator files must still match the original snapshot.
"""
import argparse
import base64
import binascii
import difflib
import hashlib
import json
import os
import re
import stat
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

REPO = Path("D:/code/rmmo")
RUNTIME = Path("D:/code/rmmo_runtime")
CACHE = RUNTIME / "cache/world3d"
EVIDENCE = RUNTIME / "review_artifacts/joint_model_validation_20261011"
SOURCE_EVIDENCE = REPO / "review_artifacts/joint_model_validation_20261011"
BEFORE = SOURCE_EVIDENCE / "source_before.json"
FORMAL = RUNTIME / "maps/medieval_river_town/map.gltf"
LIBRARY = RUNTIME / "packs/default/assets/library.json"
FORMAL_BEFORE = "779c513dc5433ddbe66d018471a8a505260e161d1656c690a00cde2675fb7a7f"
DIGEST = re.compile(r"[0-9a-f]{64}\Z")
REPARSE_POINT = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
CHUNK = 1024 * 1024
TEXTURE_CODE = REPO / "scripts/world3d/model_texture_cache.gd"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def absolute(value):
    p = Path(value)
    require(p.is_absolute(), f"Absolute path required: {value}")
    return Path(os.path.abspath(p))


def key(value):
    return str(absolute(value)).replace("\\", "/").casefold()


def confined(value, roots=(REPO, RUNTIME)):
    p = absolute(value)
    require(any(p.is_relative_to(absolute(root)) for root in roots), f"Path outside permitted roots: {p}")
    # resolve() alone would conceal a junction or symlink. Check every existing
    # ancestor before opening/creating anything; no recursive copying/deletion.
    for ancestor in (p, *p.parents):
        try:
            info = ancestor.lstat()
        except FileNotFoundError:
            continue
        require(not stat.S_ISLNK(info.st_mode) and not (getattr(info, "st_file_attributes", 0) & REPARSE_POINT),
                f"Symlink/reparse path rejected: {ancestor}")
    return p


def signature(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns


def stable_read(path, limit):
    p = confined(path)
    with p.open("rb") as stream:
        before = os.fstat(stream.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_size <= limit, f"Invalid/oversized JSON: {p}")
        raw = stream.read(limit + 1)
        after = os.fstat(stream.fileno())
    require(len(raw) == before.st_size and signature(before) == signature(after) == signature(p.stat()),
            f"File changed while reading: {p}")
    return raw


def load(path, limit=32 * CHUNK):
    raw = stable_read(path, limit)
    return json.loads(raw.decode("utf-8-sig")), hashlib.sha256(raw).hexdigest()


def hash_file(path, expected=None, length=None):
    p = confined(path)
    digest = hashlib.sha256()
    count = 0
    with p.open("rb") as stream:
        before = os.fstat(stream.fileno())
        require(stat.S_ISREG(before.st_mode), f"Not a regular file: {p}")
        while chunk := stream.read(CHUNK):
            digest.update(chunk)
            count += len(chunk)
        after = os.fstat(stream.fileno())
    sha = digest.hexdigest()
    require(count == before.st_size and signature(before) == signature(after) == signature(p.stat()),
            f"File changed while hashing: {p}")
    require(expected is None or sha == expected, f"SHA mismatch: {p}")
    require(length is None or count == length, f"Length mismatch: {p}")
    return {"path": p.as_posix(), "sha256": sha, "bytes": count, "stable_during_read": True}


def write_new(path, value):
    p = confined(path, (EVIDENCE, CACHE))
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def bindings(receipt_path, before_path):
    receipt_path = confined(receipt_path, (EVIDENCE,))
    before_path = confined(before_path, (SOURCE_EVIDENCE,))
    receipt, receipt_sha = load(receipt_path)
    prior, before_sha = load(before_path)
    require(isinstance(receipt, dict) and receipt.get("ok") is True and receipt.get("map_published") is True
            and receipt.get("publish_requested") is True and receipt.get("mode") == "published_reference_map"
            and receipt.get("failures") == [], "A successful completed publication receipt is required")
    require(key(receipt["source"]) == key(FORMAL) and receipt["expected_formal_sha"] == FORMAL_BEFORE,
            "Receipt is not for the frozen formal town map")
    for field in ("published_sha256", "catalog_sha_before", "catalog_sha_after"):
        require(isinstance(receipt.get(field), str) and DIGEST.fullmatch(receipt[field]), f"Invalid receipt {field}")
    require(receipt["published_sha256"] != FORMAL_BEFORE, "Receipt did not publish a changed map")
    require(prior.get("version") == 1 and prior.get("mode") == "before" and prior.get("passed") is True
            and prior.get("invalid_current_files") == [] and prior.get("changed_files") == [],
            "A successful source_before snapshot is required")
    old = {}
    for row in prior["files"]:
        p = confined(row["path"])
        require(key(p) not in old and row.get("valid") is True and row.get("exists") is True
                and row.get("stable_during_read") is True and DIGEST.fullmatch(row.get("sha256", "")),
                f"Invalid or duplicate frozen source row: {p}")
        old[key(p)] = row
    require(len(old) == prior["file_count"] and old[key(FORMAL)]["sha256"] == FORMAL_BEFORE
            and old[key(LIBRARY)]["sha256"] == receipt["catalog_sha_before"], "Receipt/snapshot generation mismatch")
    require("formal_map" in old[key(FORMAL)]["roles"] and "formal_library" in old[key(LIBRARY)]["roles"],
            "Frozen map/catalog roles are missing")
    for role in ("original_32_glb", "compiled_generator_source", "fixture_baseline", "fixture_preferred", "fixture_combined"):
        count = sum(role in r["roles"] for r in old.values())
        require(count == 32 if role == "original_32_glb" else count > 0, f"Incomplete snapshot role: {role}")
    choice = receipt.get("choice")
    require(choice in ("preferred", "combined"), "Unknown publication choice")
    type_count, instance_count = (11, 59) if choice == "preferred" else (14, 690)
    require(receipt.get("expected_counts") == {"records": 4437, "houses": 61, "model_types": type_count}
            and receipt.get("expected_changed_instances") == instance_count
            and len(set(receipt.get("changed_ids", []))) == len(receipt.get("changed_ids", [])) == instance_count,
            "Publication population does not match the validated scenario")
    require(len(receipt.get("model_plan", [])) == len(receipt.get("imports", [])) == type_count,
            "Incomplete import plan/receipt")
    origins, targets = set(), set()
    for row in receipt["model_plan"]:
        origin, candidate = confined(row["original"], (RUNTIME,)), confined(row["candidate"], (RUNTIME,))
        sha = row["candidate_sha256"]
        require(isinstance(sha, str) and DIGEST.fullmatch(sha), "Invalid model SHA")
        target = LIBRARY.parent / (sha + ".glb")
        require(key(row["target"]) == key(target) and key(origin) not in origins and key(target) not in targets,
                "Model targets are not unique immutable library paths")
        require(old[key(origin)]["sha256"] == row["original_sha256"] and old[key(candidate)]["sha256"] == sha,
                "Model identity is not part of the frozen source set")
        matching = [item for item in receipt["imports"] if key(item["target"]) == key(target)]
        require(len(matching) == 1, "Missing/duplicate per-model import proof")
        item = matching[0]
        require(item.get("import_ok") is True and item.get("native", {}).get("ok") is True
                and item.get("footprint", {}).get("ok") is True and item.get("expected_source_sha256") == sha
                and key(item["source"]) == key(candidate) and key(item["original"]) == key(origin),
                f"Incomplete successful import proof: {target}")
        origins.add(key(origin)); targets.add(key(target))
    return receipt, prior, old, {"receipt": receipt_path.as_posix(), "receipt_sha256": receipt_sha,
                                "source_before": before_path.as_posix(), "source_before_sha256": before_sha}


def read_formal(receipt):
    document, digest = load(FORMAL)
    require(digest == receipt["published_sha256"], "Formal map differs from successful publication receipt")
    extras = document["nodes"][0]["extras"]
    require(extras.get("rmmo_format") == "rmmo_gltf_map" and extras.get("rmmo_version") == 2
            and extras.get("rmmo_storage") == "references_v1", "Unsupported reference map format")
    records, dependencies = extras["rmmo_records"], extras["rmmo_resource_dependencies"]
    require(len(records) == 4437 and len({r["uuid"] for r in records}) == 4437
            and len(extras["building_instances"]) == 61, "Published record/house population changed")
    require(isinstance(dependencies, dict) and dependencies, "Missing declared dependency closure")
    references = {}
    for record in records:
        ref = record["rmmo_ref"]
        sha, uri, length = ref["sha256"], ref["uri"], ref["length"]
        require(ref.get("version") == 1 and isinstance(sha, str) and DIGEST.fullmatch(sha)
                and uri == "map.gltf.resources/" + sha + ".rmres"
                and type(length) in (int, float) and 0 < length <= 65 * CHUNK and int(length) == length,
                "Invalid adjacent reference definition")
        value = {"uri": uri, "sha256": sha, "length": int(length)}
        require(uri not in references or references[uri] == value, "Conflicting repeated reference identity")
        references[uri] = value
    require(dependencies == {uri: row["sha256"] for uri, row in references.items()},
            "Declared dependencies differ from actual author references")
    # Native reference documents have only an embedded placement cube. Refuse
    # another glTF with hidden adjacent image/buffer copying requirements.
    for item in document.get("buffers", []):
        require(isinstance(item.get("uri"), str) and item["uri"].startswith("data:"), "External proxy buffer unsupported")
    require(not document.get("images"), "Unexpected image payload in reference map")
    return digest, sorted(references.values(), key=lambda row: row["uri"])


def code_transition(path, old, context):
    """Validate one exact, human-authorized default line transition.

    This is not a general source whitelist. Full original bytes must reproduce
    the frozen row; only the two exact agreed default/comment lines below may
    differ. All other settings/formatting/generator files remain protected. The
    original source_before file is never edited.
    """
    path = confined(path, (SOURCE_EVIDENCE, EVIDENCE))
    transition, transition_sha = load(path, 4 * CHUNK)
    fields = {"version", "kind", "path", "source_before_sha256", "before_sha256", "after_sha256",
              "before_base64", "after_base64", "unified_diff", "user_authorization"}
    require(isinstance(transition, dict) and set(transition) == fields and transition.get("version") == 1
            and transition.get("kind") == "model_texture_sharing_default", "Unsupported code-transition record")
    require(key(transition["path"]) == key(TEXTURE_CODE), "Only model_texture_cache.gd may transition")
    frozen = old.get(key(TEXTURE_CODE))
    require(frozen is not None and "compiled_generator_source" in frozen["roles"],
            "Sharing helper is not a frozen generator dependency")
    require(transition["source_before_sha256"] == context["source_before_sha256"],
            "Transition does not bind the unchanged original source_before snapshot")
    authorization = transition["user_authorization"]
    require(isinstance(authorization, dict) and set(authorization) == {"explicit", "source", "decision", "message"}
            and authorization.get("explicit") is True and authorization.get("source") == "user"
            and authorization.get("decision") == "enable_model_texture_sharing_default"
            and isinstance(authorization.get("message"), str) and bool(authorization["message"].strip()),
            "Transition must record the user's explicit default-sharing authorization")
    for field in ("before_sha256", "after_sha256"):
        require(isinstance(transition[field], str) and DIGEST.fullmatch(transition[field]), "Invalid transition " + field)
    try:
        before = base64.b64decode(transition["before_base64"], validate=True)
        after = base64.b64decode(transition["after_base64"], validate=True)
    except (binascii.Error, TypeError, ValueError) as error:
        raise ValueError("Invalid complete code bytes in transition") from error
    require(len(before) <= CHUNK and len(after) <= CHUNK and len(before) == frozen["bytes"],
            "Invalid complete transition source size")
    require(hashlib.sha256(before).hexdigest() == frozen["sha256"] == transition["before_sha256"]
            and hashlib.sha256(after).hexdigest() == transition["after_sha256"],
            "Complete transition bytes do not match original/current identities")
    old_line = b"static var enabled := false # Enable only for the pending combined GPU/asset comparison."
    new_line = b"static var enabled := true # Default enabled after game/editor GPU acceptance; probes can override."
    require(len(re.findall(rb"(?m)^" + re.escape(old_line) + rb"\r?$", before)) == 1
            and before.count(old_line) == after.count(new_line) == 1
            and after == before.replace(old_line, new_line, 1)
            and hashlib.sha256(after.replace(new_line, old_line, 1)).hexdigest() == frozen["sha256"],
            "Only the exact approved enabled/comment line may change; all other bytes must remain identical")
    try:
        before_lines = before.decode("utf-8").splitlines(keepends=True)
        after_lines = after.decode("utf-8").splitlines(keepends=True)
    except UnicodeError as error:
        raise ValueError("Transition source must be UTF-8") from error
    full_diff = "".join(difflib.unified_diff(before_lines, after_lines,
        fromfile=TEXTURE_CODE.as_posix() + " (before)", tofile=TEXTURE_CODE.as_posix() + " (after)",
        n=max(len(before_lines), len(after_lines))))
    require(transition["unified_diff"] == full_diff and bool(full_diff),
            "Transition must include the exact full-context source diff")
    require(stable_read(TEXTURE_CODE, CHUNK) == after, "Current sharing code differs from the exact authorized after bytes")
    hash_file(context["source_before"], context["source_before_sha256"])
    return {"record": path.as_posix(), "record_sha256": transition_sha, "path": TEXTURE_CODE.as_posix(),
            "source_before_sha256": context["source_before_sha256"], "before_sha256": frozen["sha256"],
            "after_sha256": transition["after_sha256"], "user_authorization": authorization,
            "unified_diff": full_diff, "only_default_line_changed": True,
            "scope": "Authorization is recorded evidence supplied by the operator; exact byte/identity constraints are independently enforced. Native rebuild/renderer acceptance is separate."}


def copy_verified(source, target, expected, length=None):
    source, target = confined(source, (FORMAL.parent,)), confined(target, (CACHE,))
    target.parent.mkdir(parents=True, exist_ok=True)
    digest, count = hashlib.sha256(), 0
    with source.open("rb") as incoming, target.open("xb") as outgoing:
        before = os.fstat(incoming.fileno())
        require(stat.S_ISREG(before.st_mode), f"Not a regular file: {source}")
        while chunk := incoming.read(CHUNK):
            digest.update(chunk); count += len(chunk); outgoing.write(chunk)
        outgoing.flush()
        after = os.fstat(incoming.fileno())
    require(count == before.st_size and signature(before) == signature(after) == signature(source.stat()),
            f"Source changed during copy: {source}")
    require(digest.hexdigest() == expected and (length is None or count == length), f"Copy source identity mismatch: {source}")
    verified = hash_file(target, expected, count)
    return {"source": source.as_posix(), **verified}


def checkpoint(receipt, context):
    digest, references = read_formal(receipt)
    hash_file(LIBRARY, receipt["catalog_sha_after"])
    root = confined(CACHE / ("joint_published_checkpoint_" + str(time.time_ns()) + "_" + uuid.uuid4().hex[:8]), (CACHE,))
    require(root.parent == absolute(CACHE), "Checkpoint must be a direct cache/world3d child")
    root.mkdir()
    print("checkpoint_root=" + root.as_posix(), flush=True)
    # Failed attempts leave only this unique partial fixture for inspection.
    # No success manifest is written until every copied byte has been verified.
    copied = []
    for ref in references:
        copied.append(copy_verified(FORMAL.parent / ref["uri"], root / ref["uri"], ref["sha256"], ref["length"]))
    map_row = copy_verified(FORMAL, root / "map.gltf", digest)
    hash_file(FORMAL, digest)
    hash_file(LIBRARY, receipt["catalog_sha_after"])
    return root / "checkpoint_manifest.json", {**context, "version": 1, "mode": "checkpoint", "passed": True,
        "scope": "Exact published map plus declared adjacent CPU definitions only; no directory backup or derived cache copy",
        "source_map": FORMAL.as_posix(), "source_sha256": digest, "map": map_row["path"], "sha256": digest,
        "records": 4437, "houses": 61, "dependencies": len(copied),
        "dependency_bytes": sum(row["bytes"] for row in copied), "map_bytes": map_row["bytes"], "files": copied,
        "model_source_scope": "Referenced immutable GLBs stay in the persistent library; verify mode hashes their receipt identities separately",
        "snapshot_scope": "Each dependency SHA checked while copying; map and catalog SHA rechecked at completion. Not a filesystem-wide atomic snapshot.",
        "no_engine_or_native_build": True}


def expanded_catalog(entries):
    require(isinstance(entries, list), "Catalog must be an array")
    result = []
    for item in entries:
        require(isinstance(item, dict), "Invalid catalog entry")
        item = dict(item)
        for field in ("asset_path", "prefab_path", "thumbnail_path"):
            if isinstance(item.get(field), str):
                value = Path(item[field])
                item[field] = key(value if value.is_absolute() else LIBRARY.parent / value)
        result.append(item)
    return result


def verify(receipt, prior, old, context, transition=None):
    allowed = {key(FORMAL): receipt["published_sha256"], key(LIBRARY): receipt["catalog_sha_after"]}
    if transition is not None:
        allowed[key(TEXTURE_CODE)] = transition["after_sha256"]
    rows, failures, changes = [], [], []
    for index, previous in enumerate(old.values()):
        p = previous["path"]
        changed_allowed = key(p) in allowed
        expected = allowed.get(key(p), previous["sha256"])
        row = {"path": p, "roles": previous["roles"], "before_sha256": previous["sha256"],
               "expected_sha256": expected, "publication_change_allowed": key(p) in (key(FORMAL), key(LIBRARY)),
               "code_transition_allowed": transition is not None and key(p) == key(TEXTURE_CODE)}
        try:
            row.update(hash_file(p, expected, None if changed_allowed else previous["bytes"]), valid=True)
            if row["sha256"] != previous["sha256"]:
                changes.append(p)
        except (OSError, ValueError) as error:
            row.update(valid=False, error=str(error)); failures.append(str(error))
        rows.append(row)
        if index % 500 == 0:
            print(f"verified_frozen_sources={index + 1}/{len(old)}", flush=True)
    new_targets, definitions, catalog_preserved = [], [], False
    try:
        _, references = read_formal(receipt)
        for ref in references:
            definitions.append(hash_file(FORMAL.parent / ref["uri"], ref["sha256"], ref["length"]))
        for row in receipt["model_plan"]:
            new_targets.append(hash_file(row["target"], row["candidate_sha256"]))
        catalog, catalog_sha = load(LIBRARY)
        require(catalog_sha == receipt["catalog_sha_after"], "Catalog differs from publication receipt")
        current = expanded_catalog(catalog)
        previous_catalog = receipt.get("catalog_entries_before")
        require(isinstance(previous_catalog, list) and previous_catalog, "Receipt lacks the original catalog entries for conservation checking")
        require(all(entry in current for entry in expanded_catalog(previous_catalog)), "An original catalog entry changed/disappeared")
        for row in receipt["model_plan"]:
            matching = [entry for entry in current if entry.get("asset_path") == key(row["target"])]
            require(len(matching) == 1 and matching[0].get("label") == row.get("published_catalog_label"),
                    "Published target/catalog label differs from receipt: " + row["target"])
        catalog_preserved = True
        # This is a serial audit, not a transactional lock on all protected files.
        hash_file(FORMAL, receipt["published_sha256"])
        hash_file(LIBRARY, receipt["catalog_sha_after"])
        hash_file(context["source_before"], context["source_before_sha256"])
        if transition is not None:
            hash_file(TEXTURE_CODE, transition["after_sha256"])
            hash_file(transition["record"], transition["record_sha256"])
    except (OSError, ValueError, KeyError, TypeError) as error:
        failures.append(str(error))
    return {**context, "version": 1, "mode": "verify", "passed": not failures, "failures": failures,
        "scope": "Fixed prepublication source set with two publication receipt exceptions and, only when supplied, one exact authorized sharing-default line transition; plus new formal closure/imported sources",
        "allowed_changes": [{"path": previous["path"], "sha256": allowed[name]} for name, previous in old.items() if name in allowed],
        "code_transition": transition,
        "changed_files": changes, "file_count": len(rows), "files": rows,
        "original_catalog_entries_preserved": catalog_preserved, "new_targets": new_targets, "new_definitions": definitions,
        "previous_compiled_source_fingerprint": prior.get("compiled_source_fingerprint"),
        "generator_scope": "Every frozen generator source row must match the old snapshot except the explicitly supplied single-line sharing transition; no other generator changes are allowed and no runtime generator/native compatibility is claimed",
        "snapshot_scope": "Each file must be stable during its full-byte read. No filesystem-wide atomic snapshot is claimed.",
        "no_engine_or_native_build": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("checkpoint", "verify"))
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--before", default=str(BEFORE))
    parser.add_argument("--code-transition", help="Exact authorized model_texture_cache.gd false-to-true record; original snapshot is never rewritten")
    parser.add_argument("--output", help="New verification JSON under the runtime evidence directory; checkpoint writes its own manifest")
    args = parser.parse_args()
    if args.mode == "checkpoint" and args.output:
        parser.error("checkpoint chooses its own unique directory/manifest; do not supply --output")
    started = time.monotonic()
    output = None
    try:
        if args.mode == "verify":
            output = confined(args.output or EVIDENCE / ("postpublish_verify_" + str(time.time_ns()) + ".json"), (EVIDENCE,))
            require(not output.exists(), "Refusing to overwrite earlier verification evidence")
        receipt, prior, old, context = bindings(args.receipt, args.before)
        transition = code_transition(args.code_transition, old, context) if args.code_transition else None
        if transition is not None:
            context = {**context, "code_transition": transition}
        if args.mode == "checkpoint":
            output, report = checkpoint(receipt, context)
        else:
            report = verify(receipt, prior, old, context, transition)
        report.update(created_utc=datetime.now(timezone.utc).isoformat(), elapsed_seconds=time.monotonic() - started)
        write_new(output, report)
        print(json.dumps({"mode": args.mode, "passed": report["passed"], "report": output.as_posix(),
                          "map": report.get("map"), "sha256": report.get("sha256"), "failures": report.get("failures", [])}, ensure_ascii=False))
        return 0 if report["passed"] else 1
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("POSTPUBLICATION_VALIDATION_FAILED: " + str(error), file=sys.stderr)
        # Do not overwrite any file or remove a partially copied fixture. An
        # absent passed manifest is never a usable checkpoint/verification.
        return 1


if __name__ == "__main__":
    sys.exit(main())
