from pathlib import Path
import json, os, sys

if len(sys.argv) != 3:
    raise SystemExit('usage: compete_pair.py manifest.json marker.json')
manifest, marker = map(Path, sys.argv[1:])
try:
    rows = json.loads(manifest.read_text(encoding='utf-8'))
    done = []
    for row in rows:
        target, data = Path(row['target']), Path(row['source']).read_bytes()
        with target.open('xb') as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        done.append({'target': str(target), 'bytes': len(data)})
    marker.write_text(json.dumps({'ok': True, 'written': done}), encoding='utf-8')
except Exception as error:
    marker.write_text(json.dumps({'ok': False, 'error': repr(error)}), encoding='utf-8')
    raise
