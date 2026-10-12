"""Serial GPU queue for the conservative foliage profiles and pennant shadows."""
import subprocess
import sys
from pathlib import Path

ROOT = Path('D:/code/rmmo')
RUNNER = ROOT / 'review_artifacts/town_asset_size_audit_20261011/run_asset_reviews.py'
for asset in ['shrub_tall', 'shrub_round', 'foliage_boxwood']:
    common = ['foliage2k', '--filter=' + asset + '_pbr2k_albedo4k']
    for arguments in [common + ['--cases=candidate,compare', '--reuse-baseline=' + asset], common + ['--shadows']]:
        result = subprocess.run([sys.executable, str(RUNNER), *arguments], cwd=ROOT)
        if result.returncode:
            sys.exit(result.returncode)
result = subprocess.run([sys.executable, str(RUNNER), 'pennants', '--filter=quality', '--shadows'], cwd=ROOT)
sys.exit(result.returncode)
