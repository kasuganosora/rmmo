"""Record the explicit default switch, preserving every other source byte."""
import base64
import difflib
import hashlib
import json
from pathlib import Path

root = Path('D:/code/rmmo')
folder = root / 'review_artifacts/joint_model_validation_20261011'
path = root / 'scripts/world3d/model_texture_cache.gd'
snapshot = folder / 'source_before.json'
output = folder / 'texture_sharing_default_transition.json'
before = path.read_bytes()
old = b'static var enabled := false # Enable only for the pending combined GPU/asset comparison.'
new = b'static var enabled := true # Default enabled after game/editor GPU acceptance; probes can override.'
prior = json.loads(snapshot.read_text(encoding='utf-8'))
frozen = next(row for row in prior['files'] if Path(row['path']) == path)
digest = lambda data: hashlib.sha256(data).hexdigest()
assert digest(before) == frozen['sha256'] and before.count(old) == 1
after = before.replace(old, new, 1)
b = before.decode('utf-8').splitlines(keepends=True)
a = after.decode('utf-8').splitlines(keepends=True)
record = {'version': 1, 'kind': 'model_texture_sharing_default', 'path': path.as_posix(),
    'source_before_sha256': digest(snapshot.read_bytes()),
    'before_sha256': digest(before), 'after_sha256': digest(after),
    'before_base64': base64.b64encode(before).decode('ascii'),
    'after_base64': base64.b64encode(after).decode('ascii'),
    'unified_diff': ''.join(difflib.unified_diff(b, a, fromfile=path.as_posix()+' (before)',
        tofile=path.as_posix()+' (after)', n=max(len(a), len(b)))),
    'user_authorization': {'explicit': True, 'source': 'user',
        'decision': 'enable_model_texture_sharing_default',
        'message': 'User explicitly requested enabling texture sharing despite little loading-time benefit: 还是值得开启把'}}
with output.open('x', encoding='utf-8', newline='\n') as stream:
    json.dump(record, stream, ensure_ascii=False, indent=2)
    stream.write('\n')
assert path.read_bytes() == before
path.write_bytes(after)
assert path.read_bytes() == after
print(json.dumps({'path': path.as_posix(), 'sha256': digest(after), 'transition': output.as_posix()}))
