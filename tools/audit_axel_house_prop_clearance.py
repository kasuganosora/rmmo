"""Conservative XZ plot/roof/prop audit; never equate OBB risk with mesh contact."""
import json, math, hashlib
from pathlib import Path

OUT=Path('D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014')
def read(p): return json.loads(Path(p).read_text(encoding='utf8'))
def rect(low,size,origin,yaw):
    c,s=math.cos(math.radians(yaw)),math.sin(math.radians(yaw))
    return [(origin[0]+x*c+z*s,origin[-1]-x*s+z*c) for x,z in [(low[0],low[2]),(low[0]+size[0],low[2]),(low[0]+size[0],low[2]+size[2]),(low[0],low[2]+size[2])]]
def overlap(a,b,tolerance=.001):
    minimum=math.inf
    for p in [a,b]:
        for i in range(len(p)):
            x,z=p[i];nx,nz=p[(i+1)%len(p)];dx,dz=-(nz-z),nx-x;length=math.hypot(dx,dz)
            if not length:continue
            dx,dz=dx/length,dz/length
            aa=[x*dx+z*dz for x,z in a];bb=[x*dx+z*dz for x,z in b]
            depth=min(max(aa),max(bb))-max(min(aa),min(bb))
            if depth<=tolerance:return None
            minimum=min(minimum,depth)
    return minimum
def main():
    idx={t['id']:t for t in read(OUT/'house_templates.json')['templates']}
    houses=[];missing=[]
    for f in ['house_plan_s1_s2.json','house_plan_s10_s12.json']:
        for h in read(OUT/f)['houses']:
            t=idx.get(h['template_id'])
            if not t:missing.append(h['template_id']);continue
            p=t['parameters'];full=t['bounds'];houses.append({'id':h['id'],'shell':rect([-p['width']/2,0,-p['depth']/2],[p['width'],0,p['depth']],h['position'],h['yaw']),
               'full':rect(full['position'],full['size'],h['position'],h['yaw'])})
    requests=read(OUT/'props_recipe_probe.json')['requests'];applied={r['key']:r for r in read(OUT/'props_native_apply_probe.json')['result']['placements']}
    props=[];risks=[];connections=[];zones=read(OUT/'source_metadata.json')['editor_layout']['zones']
    for r in requests:
        e=r['entry']
        if not e:missing.append(r['key']);continue
        if 'prefab_path' in e:e=read(e['prefab_path'])['records'][0]
        low=e.get('bounds_position',[0,0,0]);size=e.get('bounds_size',[0,0,0]);scale=r['scale']
        # Native helper centers grounded models in XZ; wall mount and arch origins stay authored.
        offset=[low[0]+size[0]/2,low[1],low[2]+size[2]/2] if r['grounded'] else [0,0,0]
        pp=rect([(low[i]-offset[i])*scale[i] for i in range(3)],[size[i]*scale[i] for i in range(3)],r['position'],r['yaw'])
        typ='tree' if any(s in r['key'] for s in ['oak','redfruit']) else ('wall' if '/wall_' in r['key'] else ('pier' if 'gate_pier' in r['key'] else ('pole' if 'festival/' in r['key'] else 'attachment')))
        props.append({'key':r['key'],'type':typ,'polygon':pp,'y':r['position'][1],'height':size[1]*scale[1]})
        if typ in ['tree','wall','pier','pole']:
            for h in houses:
                depth=overlap(pp,h['full'])
                if depth is not None:risks.append({'a':r['key'],'b':h['id'],'kind':'tree_crown_vs_house_envelope' if typ=='tree' else 'prop_vs_house_envelope','overlap_min_axis_m':depth,'shell_overlap':overlap(pp,h['shell'])})
            for z in zones:
                if overlap(pp,z['polygon']) is not None:risks.append({'a':r['key'],'b':z['id'],'kind':'prop_vs_reserved_zone'})
    for i,a in enumerate(props):
        if a['type'] not in ['tree','wall','pier','pole']:continue
        for b in props[i+1:]:
            if b['type'] not in ['tree','wall','pier','pole']:continue
            depth=overlap(a['polygon'],b['polygon'])
            if depth is None:continue
            if a['type'] in ['wall','pier'] and b['type'] in ['wall','pier']:
                connections.append({'a':a['key'],'b':b['key'],'overlap_m':depth});continue
            if 'tree' in [a['type'],b['type']] and any(t in [a['type'],b['type']] for t in ['wall','pier']):
                # Whole-tree bounds include empty space below crown. Keep as inspection note.
                risks.append({'a':a['key'],'b':b['key'],'kind':'tree_bounds_above_low_wall_inspect_crown_height','overlap_min_axis_m':depth});continue
            risks.append({'a':a['key'],'b':b['key'],'kind':'prop_envelopes_overlap','overlap_min_axis_m':depth})
    source_hashes={name:hashlib.sha256((OUT/name).read_bytes()).hexdigest() for name in ['house_templates.json','house_plan_s1_s2.json','house_plan_s10_s12.json','props_recipe_probe.json']}
    report={'scope':'Conservative rotated plot/source bounds; no exact mesh or GPU claim','source_sha256':source_hashes,'house_count':len(houses),'prop_count':len(props),'missing':missing,'risks':risks,'allowed_wall_pier_connections':connections,'note':'Tree OBB includes sparse foliage corners; tree-house risk must be resolved or narrowed with actual geometry, never silently exempted.'}
    (OUT/'prop_clearance_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({k:v for k,v in report.items() if k not in ['allowed_wall_pier_connections','source_sha256']},ensure_ascii=False))
if __name__=='__main__':main()
