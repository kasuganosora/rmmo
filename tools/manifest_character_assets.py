"""Record reproducible asset provenance and checksums; no image editing."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path
import hashlib
import json

root = art_path("character_creator")
manifest = {
    "version": 2,
    "origin": "ImageGen-generated original layers; user BRP references informed pale skin and proportions",
    "types": ["Male", "Female", "YoungMale", "YoungFemale"],
    "directions": ["front", "left", "right", "back", "front_left", "front_right", "back_left", "back_right"],
    "actions": ["idle", "walk", "attack", "dash", "cast", "death", "sit_ground", "sit_chair"],
    "motion_cell": [96, 96], "motion_sheet": [384, 6144], "frames_per_action": 4,
    "static_cell": [48, 72], "static_sheet": [144, 576],
    "equipment_layers": {"Clothing1": "chest", "Clothing2": "legs", "Boots": "feet", "Belt": "belt"},
    "body_contains_equipment": False,
    "notes": "Idle uses first frame; holds reuse keyframes. Right-facing actions mirror left-facing sources. Base underwear is not an equipment item.",
    "sha256": {str(p.relative_to(root)).replace('\\','/'): hashlib.sha256(p.read_bytes()).hexdigest()
               for directory in ["source", "TV", "Motion"] for p in sorted((root/directory).glob("**/*.png"))},
}
(root / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
print(f"Recorded {len(manifest['sha256'])} source and runtime layers")
