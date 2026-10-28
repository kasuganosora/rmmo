"""Test-only independent competing publisher; never part of product runtime."""
from pathlib import Path
import json,os,sys
if len(sys.argv)!=4: raise SystemExit('usage: compete.py <target> <input> <marker>')
target,source,marker=map(Path,sys.argv[1:])
try:
    data=source.read_bytes()
    with target.open('xb') as f:
        f.write(data);f.flush();os.fsync(f.fileno())
    marker.write_text(json.dumps({'ok':True,'size':len(data)}),encoding='utf-8')
except Exception as exc:
    marker.write_text(json.dumps({'ok':False,'error':repr(exc)}),encoding='utf-8')
    raise
