"""Read-only acceptance against the running content editor; Python stdlib only.

Example: python tools/accept_tileset_mcp.py --tileset outside --expected manifest.json --out evidence
The manifest is {"Outside_A1":"sha256", ...}. A successful process exit means
technical checks passed, not that the requested visual style has been approved.
An AI reviewer must inspect the saved PNGs against the supplied art references.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import urllib.request

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--url',default='http://127.0.0.1:18765/mcp')
    p.add_argument('--tileset',default='outside')
    p.add_argument('--expected',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True)
    a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
    (a.out/'acceptance.json').write_text(json.dumps({'technical_passed':False,'status':'running','visual_status':'not_reviewed'}),encoding='utf-8')
    expected=json.loads(a.expected.read_text(encoding='utf-8'))
    if not isinstance(expected,dict) or not expected:
        raise ValueError('expected manifest must be a nonempty sheet-to-SHA256 object')
    evidence=[]
    def call(name,args,label):
        body={'jsonrpc':'2.0','id':len(evidence)+1,'method':'tools/call','params':{'name':name,'arguments':args}}
        req=urllib.request.Request(a.url,json.dumps(body).encode(),{'Content-Type':'application/json'})
        with urllib.request.urlopen(req,timeout=60) as r:reply=json.load(r)
        if 'error' in reply:raise RuntimeError(reply['error'])
        result=reply['result'];data={};images=[]
        for c in result.get('content',[]):
            if c['type']=='text':data.update(json.loads(c['text']))
            elif c['type']=='image':
                path=a.out/(label+'.png');path.write_bytes(base64.b64decode(c['data']))
                images.append({'path':str(path.resolve()),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        evidence.append({'tool':name,'arguments':args,'result':data,'images':images})
        (a.out/'operations.json').write_text(json.dumps(evidence,indent=2,ensure_ascii=False),encoding='utf-8')
        if result.get('isError') or not data.get('ok',False):raise RuntimeError(data)
        if name.startswith('preview_') and not images:raise RuntimeError('preview returned no image evidence')
        return data
    before=call('editor_state',{},'before')
    call('reload_tilesheets',{},'reload')
    audit=call('audit_tileset',{'tileset_id':a.tileset,'expected_sha256':expected},'audit')
    if not audit.get('technical_passed'):raise RuntimeError(audit['errors'])
    slots={int(s['slot']) for s in audit['sheets']}
    pages=[]
    for start,end,slot in [(0,16,0),(16,48,1),(48,80,2),(80,128,3)]:
        if slot not in slots:continue
        for k in range(start,end,8):
            for frame in range(4 if slot==0 else 1):
                label=f'cases_{k:03d}_frame_{frame}'
                call('preview_autotile_cases',{'tileset_id':a.tileset,'kinds':list(range(k,k+8)),'frame':frame,'path':str((a.out/(label+'.png')).resolve())},label)
                pages.append(label+'.png')
    final_audit=call('audit_tileset',{'tileset_id':a.tileset,'expected_sha256':expected},'final_audit')
    after=call('editor_state',{},'after')
    same=before==after
    report={'technical_passed':bool(final_audit.get('technical_passed')) and same,'editor_state_unchanged':same,
            'expected_sha256':expected,'fixture_pages':pages,'visual_status':'pending_AI_image_review',
            'visual_criteria':['reference style and redesigned silhouettes','48px layout and object slot meaning','concave/convex transitions and narrow paths','water and waterfall phase continuity'],
            'scope':'declared MV sheets, resolved disk/cache version, B0 and native renderer fixtures'}
    (a.out/'acceptance.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
    print(json.dumps({'technical_passed':report['technical_passed'],'fixture_pages':len(pages),'visual_status':report['visual_status']}))
    return 0 if report['technical_passed'] else 1

if __name__=='__main__':raise SystemExit(main())
