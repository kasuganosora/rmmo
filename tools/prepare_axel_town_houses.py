"""Assemble reviewed shot recipes; author only task-owned intermediate JSON."""
from pathlib import Path
import json, math, hashlib, copy, importlib.util
ROOT=Path(__file__).resolve().parents[1]
OUT=Path('D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014')
def read(n):return json.loads((OUT/n).read_text(encoding='utf8'))
def write(n,v):(OUT/n).write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf8')
spec=importlib.util.spec_from_file_location('terrain_recipe',ROOT/'tools/prepare_axel_town_terrain.py')
T=importlib.util.module_from_spec(spec);spec.loader.exec_module(T)
def main():
    plans=[read('house_plan_s1_s2.json'),read('house_plan_s10_s12.json')]
    meta=read('source_metadata.json');records=read('source_records.json')
    terrains=[r for r in records if 'terrain_mesh' in r]
    for r in terrains:
        for k in ('columns','rows'):r['terrain_mesh'][k]=int(r['terrain_mesh'][k])
    sample=lambda p:float(T.sample(terrains,*p))
    templates={t['id']:t for t in read('house_templates.json')['templates']}
    setbacks={r['id']:r for r in read('house_access_setbacks.json').get('houses',[])} if (OUT/'house_access_setbacks.json').is_file() else {}
    houses=sum([p['houses'] for p in plans],[])
    for h in houses:
        if h['id']=='s2_south_oculus':h['template_id']='s2_oculus_home'
        base=h['template_id']
        if base not in templates:base='s2_low_gable' if base=='s2_oculus_home' else 'building_10e2848ee287d056ac56'
        t=templates[base];params=h.get('parameters',t['parameters']);w,d=params['width'],params['depth']
        a=math.radians(h['yaw']);c,s=math.cos(a),math.sin(a)
        transform=lambda q:[h['position'][0]+c*q[0]+s*q[1],h['position'][1]-s*q[0]+c*q[1]]
        doorway=transform([t['entrance'][0],t['entrance'][2]])
        h['ground_y']=h.get('suggested_ground_y',h.get('recommended_base_y',sample(doorway)))
        highest=h.get('terrain_max_y',h.get('terrain_sample',{}).get('max',h['ground_y']))
        h['grade']={'center':h['position'],'width':w+2.0,'depth':d+2.2,'yaw':h['yaw'],'height':h['ground_y'],'margin':3.0,'required':highest>h['ground_y']+params.get('base_height',0)-.025}
        h['grade'].update(h.get('grade_override',{}))
        h['ground_y']=h['grade']['height']
        # A native footprint/road-plan audit supplies the complete door sweep
        # setback, including tessellated end caps and the continuous kerb.
        setback=setbacks.get(h['id'],{})
        if setback:
            assert setback['template_sha256']==t['sha256'], 'Stale access footprint: '+h['id']
            assert setback.get('ok') is True and setback.get('native_footprint_clear') is True and setback.get('terrain_fit_passed') is True
            assert math.dist(setback['position'],h['position'])<.001 and abs(setback['yaw']-h['yaw'])<.001, 'Stale access pose: '+h['id']
        offset=float(setback.get('offset_from_entrance_m',.9))
        assert math.isfinite(offset) and offset>=.9
        h['access_start_offset_m']=offset
        h['access_setback_evidence']=setback
        front=[-s,-c];begin=[doorway[0]+front[0]*offset,doorway[1]+front[1]*offset]
        points=setback.get('updated_connector_points',h.get('entrance_connector',{}).get('points'))
        h['access_points']=[begin]+points[1:] if points else [begin]
        h['entrance_xz']=doorway
    graph=copy.deepcopy(meta['editor_layout']['roads']);nodes={n['id']:n for n in graph['nodes']}
    # Replace only door stubs belonging to this batch's housing areas. Removing
    # unrelated town stubs changes junction/end-cap shapes on preserved roads.
    replaced_entries={'entry_01',*(f'entry_{i:02}' for i in [33,34,35,36,40,41,42,43,44,45])}
    removed=[e['id'] for e in graph['edges'] if all(n in replaced_entries for n in e.get('name','').split('+'))]
    edges={e['id']:e for e in graph['edges'] if e['id'] not in removed}
    # Authored courtyard/back-lane changes remain part of the same native road
    # graph. Apply them before attaching individual door paths.
    for plan in plans:
        override=plan.get('road_overrides',{})
        for key in override.get('remove_edges',[]):
            edges.pop(key,None)
            if key not in removed:removed.append(key)
        for key in override.get('remove_nodes',[]):nodes.pop(key,None)
        for node in override.get('nodes',[]):
            node=copy.deepcopy(node);p=node['position']
            if len(p)==2:node['position']=[p[0],sample(p),p[1]]
            nodes[node['id']]=node
        for edge in override.get('edges',[]):edges[edge['id']]=copy.deepcopy(edge)
    edges=list(edges.values())
    assert all(e[k] in nodes for e in edges for k in ('from','to'))
    def xz(n):p=nodes[n]['position'];return [p[0],p[2]]
    def nid(p):
        for k,n in nodes.items():
            if math.dist(p,[n['position'][0],n['position'][2]])<.03:return k
        k='home_n_'+hashlib.sha256(repr([round(v,5) for v in p]).encode()).hexdigest()[:12]
        nodes[k]={'id':k,'position':[p[0],sample(p),p[1]]};return k
    def project(p,a,b):
        v=[b[i]-a[i] for i in range(2)];l=sum(x*x for x in v)
        t=max(0,min(1,sum((p[i]-a[i])*v[i] for i in range(2))/l))
        return [a[i]+v[i]*t for i in range(2)],t
    for h in houses:
        pts=h['access_points'];at=pts[-1];choices=[]
        for e in edges:
            if e['kind']!='ground' or e.get('name','').startswith('home_'):continue
            q,t=project(at,xz(e['from']),xz(e['to']));choices.append((math.dist(at,q),q,t,e))
        _,q,t,e=min(choices,key=lambda x:x[0])
        if len(pts)<=2 and math.dist(pts[0],q)<e['width_start']*.5:
            h['access_points']=[q]
            continue
        if math.dist(at,q)>.03:pts.append(q)
        else:pts[-1]=q
        split=nid(q)
        if .0001<t<.9999:
            duplicate=copy.deepcopy(e);duplicate['id']=e['id']+'_h'+str(len(edges));duplicate['from']=split;e['to']=split;edges.append(duplicate)
        for i,(a,b) in enumerate(zip(pts,pts[1:])):
            if math.dist(a,b)<.05:continue
            edges.append({'id':f'home_e_{h["id"]}_{i}','name':'home_'+h['id'],'from':nid(a),'to':nid(b),'kind':'ground','width_start':1.6,'width_end':1.6})
    used={e[k] for e in edges for k in ('from','to')}
    for n in nodes.values():
        if n['id'] not in used:continue
        # Existing bridge endpoints retain their authored deck heights.
    graph={'nodes':[n for k,n in nodes.items() if k in used],'edges':edges}
    assert len(graph['nodes'])<=256 and len(edges)<=512
    write('housing_recipe.json',{'source':read('source_identity.json'),'houses':houses,'cameras':sum([p['cameras'] for p in plans],[]),'grass_moves':sum([p.get('grass_moves',[]) for p in plans],[]),'road_graph':graph,'remove_edges':removed,'remove_nodes':[n['id'] for n in meta['editor_layout']['roads']['nodes'] if n['id'] not in used],'road_settings':meta['editor_layout']['road_surface']['settings']})
    print('housing recipe',len(houses),'houses',len(graph['nodes']),'road nodes',len(edges),'edges')
if __name__=='__main__':main()
