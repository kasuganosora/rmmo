"""Compare the fixed receiver camera from the real native guild light probe."""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageStat


def summarize(folder: Path) -> dict:
    identity = json.loads((folder / 'identity.json').read_text(encoding='utf-8'))
    frames = json.loads((folder / 'frames.json').read_text(encoding='utf-8'))
    images = [Image.open(folder / f"fixed_{row['index']:02d}.png").convert('RGB') for row in frames]
    if len(images) != 25:
        raise ValueError('Expected all 25 orbit positions, including the return to origin')
    means = [sum(ImageStat.Stat(image).mean) / 3 for image in images]
    if min(means) <= 0:
        raise ValueError('Empty/black witness viewport is not evidence of stable lighting')
    states = [tuple(sorted((light['node'], light['shadow']) for light in row['lights'] if light['on'])) for row in frames]
    max_delta = max(max(high for low, high in ImageChops.difference(images[0], image).getextrema()) for image in images)
    return {
        'identity': identity, 'frames': len(frames), 'distinct_selections': len(set(states)),
        'selection_transitions': sum(a != b for a, b in zip(states, states[1:])),
        'mean_rgb_8bit_min': min(means), 'mean_rgb_8bit_max': max(means),
        'max_fixed_view_channel_delta': max_delta,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    before, after = summarize(args.before), summarize(args.after)
    # Native product and material/texture identities and exposure must agree.
    same_scene = before['identity'] == after['identity']
    reproduced = before['distinct_selections'] > 1 and before['max_fixed_view_channel_delta'] > 0
    stable = after['distinct_selections'] == 1 and after['max_fixed_view_channel_delta'] == 0
    report = {'passed': same_scene and reproduced and stable, 'same_scene': same_scene,
              'reproduced': reproduced, 'stable': stable, 'before': before, 'after': after,
              'scope': 'Static receiver camera, actual native guild, night. Moving camera is a scheduling probe without collision; game collision coverage is separate.'}
    with args.out.open('x', encoding='utf-8') as file:
        json.dump(report, file, ensure_ascii=False, indent=2)
    print(json.dumps({k: v for k, v in report.items() if k not in ('before', 'after')}, ensure_ascii=False))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
