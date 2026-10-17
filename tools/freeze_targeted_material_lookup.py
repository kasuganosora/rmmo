"""Archive the exact previous batch; do not overwrite any earlier evidence."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT=Path(__file__).resolve().parents[1]
BASE="7be7f41d9d7ee74099e2db14f3f1852c234c44e7"
OUT=ROOT/"review_artifacts/material_targeted_20261017"
OUT.mkdir(parents=True,exist_ok=True)
files={}
for name in ["surface_material_library", "road_tools"]:
    data=subprocess.check_output(["git","show",f"{BASE}:scripts/world_editor/{name}.gd"],cwd=ROOT)
    path=OUT/(name+"_baseline.gd")
    if path.exists():assert path.read_bytes()==data,path
    path.write_bytes(data);files[path.name]=hashlib.sha256(data).hexdigest()
(OUT/"baseline.json").write_text(json.dumps({"commit":BASE,"files":files},indent=2),encoding="utf-8")
