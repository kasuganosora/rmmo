"""Compare controlled viewport captures; measurements are not visual approval."""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_erosion

parser = argparse.ArgumentParser()
parser.add_argument('folder', type=Path)
args = parser.parse_args()
names = ('opaque_sss', 'transparent_sss', 'opaque_no_sss')
images = {name: np.asarray(Image.open(args.folder / f'{name}.png').convert('RGBA'), dtype=float) / 255 for name in names}
assert len({image.shape for image in images.values()}) == 1
mask = binary_erosion(images['transparent_sss'][:, :, 3] > .99, iterations=5)
assert mask.sum() > 1000, 'Insufficient foreground coverage'
report = {'foreground_pixels': int(mask.sum()), 'mask': 'alpha > .99, eroded 5 pixels', 'comparisons': {}}
for first, second in ((names[0], names[1]), (names[0], names[2]), (names[1], names[2])):
    delta = np.abs(images[first][:, :, :3] - images[second][:, :, :3])[mask] * 255
    report['comparisons'][f'{first} vs {second}'] = {
        'mean_8bit': float(delta.mean()), 'p99_8bit': float(np.quantile(delta, .99)), 'max_8bit': float(delta.max())}
(args.folder / 'comparison.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
