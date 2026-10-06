"""External art pack root shared by authoring/import tools."""
import os
from pathlib import Path
CONTENT_ROOT = Path(os.environ.get("RMMO_CONTENT_ROOT", str(Path(__file__).resolve().parents[2] / "rmmo_runtime")))
def art_path(relative):
    return CONTENT_ROOT / "assets" / relative

def review_path(relative):
    return CONTENT_ROOT / "review_artifacts" / relative
