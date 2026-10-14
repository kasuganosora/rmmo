"""Read-only map/plan audit; emit an editable native 3D road graph recipe.
No writes to the production map. Run again after terrain edits to refresh heights.
"""
from pathlib import Path
import json, re, math, hashlib, importlib.util
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
PLAN=Path('C:/Users/luna/.codex/visualizations/2026/10/06/01a10fd2-fe81-7772-8270-8bdcb713321f/compact-town-plan.html')
MAP=Path('D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf')
OUT=Path('D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014/recipe.json')
spec=importlib.util.spec_from_file_location('terrain_recipe',ROOT/'tools/prepare_axel_town_terrain.py')
T=importlib.util.module_from_spec(spec);spec.loader.exec_module(T)

def array(text,name):
    start=re.search(r'const\s+'+name+r'\s*=\s*\[',text).end()-1
    depth=0
    for end in range(start,len(text)):
        depth+=int(text[end]=='[')-int(text[end]==']')
        if depth==0:return json.loads(text[start:end+1])
    raise ValueError(name)

def cross(a,b):return float(a[0]*b[1]-a[1]*b[0])
def dist(p,a,b):
    p,a,b=map(np.asarray,(p,a,b));d=b-a
    return float(np.linalg.norm(p-a-np.clip(np.dot(p-a,d)/np.dot(d,d),0,1)*d))
def key(p):return tuple(round(float(v),5) for v in p)
def node_id(p):return 'axel_n_'+hashlib.sha256(str(key(p)).encode()).hexdigest()[:12]

def main():
    text=PLAN.read_text(encoding='utf8');gltf=json.loads(MAP.read_text(encoding='utf8'))
    meta=gltf['nodes'][0]['extras'];base=json.loads(T.OUT.read_text(encoding='utf8'))
    terrain={r['uuid']:r for r in base['records']}
    # Saved native river after-records are authoritative for all carved tiles.
    for river in meta['terrain_rivers']:
        for pair in river['terrains']:
            terrain[pair['after']['uuid']]=pair['after']
    source_records_path=OUT.parent/'source_records.json'
    source_records=json.loads(source_records_path.read_text(encoding='utf8'))
    terrains=[r for r in source_records if 'terrain_mesh' in r]
    for r in terrains:
        r['terrain_mesh']['rows']=int(r['terrain_mesh']['rows'])
        r['terrain_mesh']['columns']=int(r['terrain_mesh']['columns'])
    sample=lambda p:T.sample(terrains,*p)
    families=[('main','roads',5),('alley','alleys',2.6),('market','marketRoads',3),('farm','farmPaths',2.6),('entry','homeEntries',1.8),('stream','scenePaths',2)]
    authored=[]
    for family,name,width in families:
        for i,points in enumerate(array(text,name)):
            authored.append({'id':f'{family}_{i+1:02}','points':points,'width':width,'family':family})
    # The drawn x310/x327 river alleys overlap the actual curved water ribbon.
    for path in authored:
        if path['id']=='alley_02':path['points']=[[296,256],[321,248],[321,232],[321,220],[381,220]]
        if path['id']=='alley_15':path['points']=[[329+52*21/61,180],[332,180],[332,220]];path['width']=2
        if path['id']=='entry_37':path['points']=[[333,188],[332,188]]
        if path['id']=='entry_38':path['points']=[[335,208],[332,208]]
    authored.append({'id':'guild_forecourt_axis','points':array(text,'forecourtPath'),'width':6,'family':'forecourt'})
    gates=[{'id':'G1','at':[42,171],'width':7,'points':[[12,171],[60,171]]},
           {'id':'G2','at':[329,50.701754386],'width':5,'points':[[329,60],[329,12]]},
           {'id':'G3','at':[397.963855422,220],'width':5,'points':[[381,220],[438,220]]},
           {'id':'G4','at':[274,337.282352941],'width':5,'points':[[274,325],[274,354]]}]
    for g in gates:authored.append(dict(g,family='gate'))
    bridges=array(text,'bridges');extended=[];bridge_heights={};bridge_widths=[6,6,7,5,5]
    replacements={}
    for i,(aa,bb) in enumerate(bridges):
        a,b=np.array(aa,float),np.array(bb,float);length=np.linalg.norm(b-a);direction=(b-a)/length
        extension=6 if i==1 else (5.5 if i==3 else 3)
        start,end=a-direction*extension,b+direction*extension;extended.append([start.tolist(),end.tolist()])
        lift=1 if i==3 else (1.5 if i==4 else 0)
        ya,yb=sample(a)+lift,sample(b)+lift;grade=(yb-ya)/length
        inset=bridge_widths[i]/2 if abs(ya-yb)>.001 else 0
        bridge_heights[key(start)]=ya-grade*(extension-inset);bridge_heights[key(end)]=yb+grade*(extension-inset)
        replacements[key(a)]=start.tolist();replacements[key(b)]=end.tolist()
    original_bridge_pairs={tuple(sorted(map(key,b))) for b in bridges}
    for path in authored:
        points=path['points'];new=[]
        for i,p in enumerate(points):
            if key(p) in replacements:
                for before in [True,False]:
                    j=i-1 if before else i+1
                    if before:
                        if j>=0 and tuple(sorted([key(p),key(points[j])])) not in original_bridge_pairs:
                            delta=np.array(points[j])-p;new.append((np.array(p)+delta/np.linalg.norm(delta)*min(9,np.linalg.norm(delta)/2)).tolist())
                        new.append(replacements[key(p)])
                    elif j<len(points) and tuple(sorted([key(p),key(points[j])])) not in original_bridge_pairs:
                        delta=np.array(points[j])-p;new.append((np.array(p)+delta/np.linalg.norm(delta)*min(9,np.linalg.norm(delta)/2)).tolist())
            else:new.append(p)
        path['points']=new
    # Bridge 2 east wing end-post occupies the inside of the old diagonal
    # approach. Move only its preceding bend; retain the actual bridge portal.
    for path in authored:
        if path['id']=='main_09':
            path['points']=[[332.,150.] if key(p)==(329.,150.) else p for p in path['points']]
    bridge_pairs={tuple(sorted(map(key,b))):i+1 for i,b in enumerate(extended)}
    segments=[]
    for path in authored:
        for a,b in zip(path['points'],path['points'][1:]):
            segments.append({'a':np.array(a,float),'b':np.array(b,float),'width':path['width'],'sources':[path['id']],'cuts':[0.,1.]})
    # All T-junctions/crossings and collinear overlaps get a shared native node.
    extra=[np.array(p,float) for b in extended for p in b]+[np.array(g['at'],float) for g in gates]
    for s in segments:
        a,b=s['a'],s['b'];v=b-a
        for p in extra:
            if dist(p,a,b)<1e-5:s['cuts'].append(float(np.clip(np.dot(p-a,v)/np.dot(v,v),0,1)))
    for i,s in enumerate(segments):
        p=s['a'];v=s['b']-p
        for t in segments[i+1:]:
            q=t['a'];w=t['b']-q;det=cross(v,w)
            if abs(det)>1e-8:
                a=cross(q-p,w)/det;b=cross(q-p,v)/det
                if -1e-8<=a<=1+1e-8 and -1e-8<=b<=1+1e-8:
                    s['cuts'].append(float(np.clip(a,0,1)));t['cuts'].append(float(np.clip(b,0,1)))
            elif abs(cross(q-p,v))<1e-6:
                for point in [t['a'],t['b']]:
                    if dist(point,s['a'],s['b'])<1e-5:s['cuts'].append(float(np.clip(np.dot(point-p,v)/np.dot(v,v),0,1)))
                for point in [s['a'],s['b']]:
                    if dist(point,t['a'],t['b'])<1e-5:t['cuts'].append(float(np.clip(np.dot(point-q,w)/np.dot(w,w),0,1)))
    merged={}
    for s in segments:
        cuts=sorted(set(round(t,9) for t in s['cuts']))
        for lo,hi in zip(cuts,cuts[1:]):
            a=key(s['a']+(s['b']-s['a'])*lo);b=key(s['a']+(s['b']-s['a'])*hi)
            if np.linalg.norm(np.array(a)-b)<.001:continue
            pair=tuple(sorted([a,b]))
            if pair in merged:
                merged[pair]['width']=max(merged[pair]['width'],s['width']);merged[pair]['sources']+=s['sources']
            else:merged[pair]={'a':a,'b':b,'width':s['width'],'sources':s['sources'].copy()}
    nodes={};edges=[];edge_details=[];risks=[]
    river_path=T.spline(meta['terrain_rivers'][0]['request']['points'])
    reserves=array(text,'reserves');wall=array(text,'wall')
    grass=[r for r in source_records if r.get('kind')=='asset']
    grass_hits=set();reservation_hits=[];wall_hits=[];terrain_hits=[]
    for pair,s in sorted(merged.items()):
        a,b=map(np.array,(s['a'],s['b']));length=float(np.linalg.norm(b-a));bridge=bridge_pairs.get(pair,0)
        for p in [a,b]:
            nid=node_id(p);raise_y=max([0.]+[(1 if bi==3 else 1.5)*(1-float(T.smooth(3,18 if bi==3 else 25,np.linalg.norm(p-np.array(end))))) for bi in [3,4] for end in bridges[bi]])
            nodes[nid]={'id':nid,'position':[float(p[0]),round(bridge_heights.get(key(p),sample(p)+raise_y),6),float(p[1])]}
        eid='axel_e_'+hashlib.sha256(str(pair).encode()).hexdigest()[:12]
        edge={'id':eid,'from':node_id(a),'to':node_id(b),'name':f'Bridge {bridge}' if bridge else '+'.join(sorted(set(s['sources']))),'width_start':bridge_widths[bridge-1] if bridge else s['width'],'width_end':bridge_widths[bridge-1] if bridge else s['width'],'kind':'bridge' if bridge else 'ground'}
        edges.append(edge)
        n=max(2,int(math.ceil(length)));points=np.linspace(a,b,n+1);heights=np.array([sample(p) for p in points]);normal=np.array([-(b-a)[1],(b-a)[0]])/length
        grade=abs(nodes[edge['to']]['position'][1]-nodes[edge['from']]['position'][1])/length
        detail={'id':eid,'sources':sorted(set(s['sources'])),'length':length,'endpoint_grade':float(grade),'centerline_max_grade':float(max(abs(np.diff(heights)))/(length/n)),'bridge_number':bridge}
        if length<.5:risks.append({'type':'short_native_edge','edge':eid,'length':length})
        if grade>.15:risks.append({'type':'native_graph_grade','edge':eid,'grade':grade,'a':a.tolist(),'b':b.tolist()})
        if not bridge:
            grades=[]
            for offset in [-s['width']/2,0,s['width']/2]:
                strip=points+normal*offset
                hs=np.array([sample(p) for p in strip]);grades.extend((abs(np.diff(hs))/(length/n)).tolist())
                for p in strip:
                    gx=(sample(p+[.05,0])-sample(p-[.05,0]))/.1;gz=(sample(p+[0,.05])-sample(p-[0,.05]))/.1
                    grades.append(math.hypot(gx,gz))
            detail['sampled_footprint_max_grade']=max(grades)
            if max(grades)>.1501:terrain_hits.append({'edge':eid,'max_grade':max(grades),'a':a.tolist(),'b':b.tolist(),'sources':detail['sources']})
            d=T.distance(points,river_path);detail['minimum_water_margin']=float(min(d)-7-s['width']/2)
            if detail['minimum_water_margin']<-.05:risks.append({'type':'ground_river_overlap','edge':eid,'margin':detail['minimum_water_margin'],'a':a.tolist(),'b':b.tolist()})
            for g in grass:
                if dist(np.array(g['position'])[[0,2]],a,b)<s['width']/2+.8:grass_hits.add(g['uuid'])
            for ri,(x,z,w,h) in enumerate(reserves):
                # Sampled corridor/AABB audit, later native preview is authoritative.
                inset=s['width']/2
                if any(x-inset<p[0]<x+w+inset and z-inset<p[1]<z+h+inset for p in points):reservation_hits.append({'edge':eid,'reserve':f'R{ri+1}'})
            for wa,wb in zip(wall,wall[1:]):
                if min(dist(p,np.array(wa),np.array(wb)) for p in points)<s['width']/2+1:
                    if not any(dist(np.array(g['at']),a,b)<s['width']/2+1 for g in gates):wall_hits.append({'edge':eid,'a':a.tolist(),'b':b.tolist()});break
        edge_details.append(detail)
    graph={'nodes':list(nodes.values()),'edges':edges}
    assert len(nodes)<=256 and len(edges)<=512,(len(nodes),len(edges))
    assert len(set(e['id'] for e in edges))==len(edges)
    assert sum(e['kind']=='bridge' for e in edges)==5
    zones=[]
    for i,(x,z,w,h) in enumerate(reserves):zones.append({'id':f'R{i+1}','name':f'Reserved special building R{i+1}','polygon':[[x,z],[x+w,z],[x+w,z+h],[x,z+h]],'min_y':-20,'max_y':80,'purpose':'no_build'})
    zones.append({'id':'guild_player_trade_clear','name':'Player trading forecourt; no permanent props','polygon':[[144,200],[168,200],[168,216],[144,216]],'min_y':-20,'max_y':80,'purpose':'reserved_passage'})
    plaza={'uuid':'axel_guild_forecourt_paving','kind':'box','name':'Guild player trading forecourt','surface_id':'ground','color':[1,1,1],'collision':'walk','position':[156,7.425,208],'rotation':[0,0,0],'size':[24,.2,16],'road_mesh':{'polygons':[[[-.5,-.5],[-.125,-.5],[-.125,.5],[-.5,.5]],[[.125,-.5],[.5,-.5],[.5,.5],[.125,.5]]],'uv_origin':[0,0,0]},'road_clearance':3}
    import copy
    adjusted=copy.deepcopy(terrains);patches=[];modified_total=0;water_protected=0
    hotids={hit['edge'] for hit in terrain_hits}
    for edge in edges:
        if edge['kind']=='ground' and any(np.linalg.norm(np.array(nodes[nid]['position'])[[0,2]]-np.array(end))<28 for nid in [edge['from'],edge['to']] for bi in [3,4] for end in bridges[bi]):hotids.add(edge['id'])
    correction_edges=[e for e in edges if e['kind']=='ground']
    # Follow the actual longitudinal ground profile. Interpolating only graph
    # endpoint heights previously filled natural river-valley dips by over 5m.
    road_profiles={}
    for edge in correction_edges:
        aa=np.array(nodes[edge['from']]['position']);bb=np.array(nodes[edge['to']]['position']);a=aa[[0,2]];b=bb[[0,2]]
        ticks=np.linspace(0,1,max(3,int(np.linalg.norm(b-a)/2)+1))
        profile=np.array([sample(a+(b-a)*t) for t in ticks])
        # Retain the deliberate bridge approach lifts locally, not across a
        # complete long street. Actual bridge support platforms follow below.
        length=np.linalg.norm(b-a)
        profile+=(aa[1]-profile[0])*(1-T.smooth(0,25,ticks*length))
        profile+=(bb[1]-profile[-1])*(1-T.smooth(0,25,(1-ticks)*length))
        road_profiles[edge['id']]=(ticks,profile)
    for record in adjusted:
        tm=record['terrain_mesh'];cx,_,cz=record['position'];sx,_,sz=record['size'];step=max(sx/tm['columns'],sz/tm['rows'])
        xx,zz=np.meshgrid(np.linspace(cx-sx/2,cx+sx/2,tm['columns']+1),np.linspace(cz-sz/2,cz+sz/2,tm['rows']+1));positions=np.stack([xx,zz],axis=-1);old=np.array(tm['heights']).reshape(xx.shape)
        weight=np.zeros(xx.shape);total=np.zeros(xx.shape);strongest=np.zeros(xx.shape)
        for edge in correction_edges:
            aa=np.array(nodes[edge['from']]['position']);bb=np.array(nodes[edge['to']]['position']);a=aa[[0,2]];b=bb[[0,2]];v=b-a
            t=np.clip(np.sum((positions-a)*v,axis=-1)/np.dot(v,v),0,1);d=np.linalg.norm(positions-a-t[...,None]*v,axis=-1)
            core=edge['width_start']/2+step*1.42;w=1-T.smooth(core,core+18,d)
            ticks,profile=road_profiles[edge['id']];h=np.interp(t,ticks,profile);influence=w*np.exp(-d*d/8);weight+=influence;total+=influence*h
            if edge['id'] in hotids:strongest=np.maximum(strongest,w)
        dwater=T.distance(positions,river_path);protect=dwater<=7
        # Keep the independent elevated creek and its immediate banks intact.
        protect|=((xx>=334)&(xx<=381)&(zz>=121.7)&(zz<=129.3))
        zone_protect=np.zeros(xx.shape,dtype=bool)
        for zx,zz0,zw,zh in reserves:zone_protect|=((xx>=zx-step)&(xx<=zx+zw+step)&(zz>=zz0-step)&(zz<=zz0+zh+step))
        protect|=zone_protect
        blend=strongest*(~protect);target=np.divide(total,weight,out=old.copy(),where=weight>0)
        new=old*(1-blend)+target*blend
        for bi,(ba,bb) in enumerate(bridges):
            ba,bb=np.array(ba,float),np.array(bb,float);run=bb-ba;length=np.linalg.norm(run);direction=run/length;normal=np.array([-direction[1],direction[0]])
            lift=1 if bi==3 else (1.5 if bi==4 else 0);ya,yb=sample(ba)+lift,sample(bb)+lift
            for endpoint,outward in [(ba,-direction),(bb,direction)]:
                delta=positions-endpoint;along=np.sum(delta*outward,axis=-1);across=abs(np.sum(delta*normal,axis=-1))
                extension=6 if bi==1 else (5.5 if bi==3 else 3)
                gap=np.hypot(np.maximum(across-(bridge_widths[bi]/2+.6+step),0),np.maximum(np.maximum(-1-step-along,along-(extension+3)),0))
                platform_protect=(old<=3.0001)|(dwater<=7)|((xx>=334)&(xx<=381)&(zz>=121.7)&(zz<=129.3))
                w=(1-T.smooth(0,12,gap))*(~platform_protect)*(~zone_protect)
                desired=ya+(yb-ya)*np.sum((positions-ba)*direction,axis=-1)/length
                new=new*(1-w)+desired*w
        changed=np.abs(new-old)>.00001
        if changed.any():
            tm['heights']=np.round(new,6).ravel().tolist();indices=np.flatnonzero(changed.ravel()).tolist();modified_total+=len(indices)
            patches.append({'id':record['uuid'],'indices':indices,'heights':[tm['heights'][i] for i in indices],'changed_vertices':len(indices),'max_abs_delta':float(max(abs(new-old).ravel())),'bounds':[float(xx[changed].min()),float(zz[changed].min()),float(xx[changed].max()),float(zz[changed].max())]})
    # Reconcile mixed-resolution edges to their original shared lattice, only if
    # both sides are in the local dry-road edit; retain every protected river node.
    for i,r in enumerate(adjusted):
        for q in adjusted[i+1:]:
            ax,_,az=r['position'];aw,_,ad=r['size'];bx,_,bz=q['position'];bw,_,bd=q['size']
            vertical=abs(ax+aw/2-(bx-bw/2))<1e-6 and abs(az-bz)<1e-6
            horizontal=abs(az+ad/2-(bz-bd/2))<1e-6 and abs(ax-bx)<1e-6
            if not(vertical or horizontal):continue
            ta,tb=r['terrain_mesh'],q['terrain_mesh'];ha=np.array(ta['heights']).reshape(ta['rows']+1,ta['columns']+1);hb=np.array(tb['heights']).reshape(tb['rows']+1,tb['columns']+1)
            ea=ha[:,-1] if vertical else ha[-1,:];eb=hb[:,0] if vertical else hb[0,:]
            span=ad if vertical else aw;sa=round(span/(len(ea)-1));sb=round(span/(len(eb)-1));knots=np.arange(0,span+.01,math.lcm(sa,sb));values=(np.interp(knots,np.linspace(0,span,len(ea)),ea)+np.interp(knots,np.linspace(0,span,len(eb)),eb))*.5
            ea[:]=np.interp(np.linspace(0,span,len(ea)),knots,values);eb[:]=np.interp(np.linspace(0,span,len(eb)),knots,values)
            ta['heights']=ha.ravel().tolist();tb['heights']=hb.ravel().tolist()
    # Native triangle/road overlaps from collect_constraints.gd are a precise
    # fit domain, including junction corners missed by centreline sampling.
    constraints_path=OUT.parent/'road_constraints.json';slope_projection={"available":False}
    if constraints_path.exists():
        constraints=json.loads(constraints_path.read_text(encoding='utf8'))
        vertex_ids={};values=[];refs=[];xz=[]
        for rec in adjusted:
            tm=rec['terrain_mesh'];cx,_,cz=rec['position'];sx,_,sz=rec['size']
            for iz in range(tm['rows']+1):
                for ix in range(tm['columns']+1):
                    xy=key([cx-sx/2+sx*ix/tm['columns'],cz-sz/2+sz*iz/tm['rows']]);at=iz*(tm['columns']+1)+ix
                    if xy not in vertex_ids:vertex_ids[xy]=len(values);values.append(tm['heights'][at]);refs.append([]);xz.append(xy)
                    refs[vertex_ids[xy]].append((rec,at))
        values=np.array(values);xz=np.array(xz);fixed=T.distance(xz,river_path)<=7
        fixed|=((xz[:,0]>=334)&(xz[:,0]<=381)&(xz[:,1]>=121.7)&(xz[:,1]<=129.3))
        original_by_id={r['uuid']:r for r in terrains}
        for vi,xy in enumerate(xz):
            step=max(max(rec['size'][0]/rec['terrain_mesh']['columns'],rec['size'][2]/rec['terrain_mesh']['rows']) for rec,at in refs[vi])
            if any(zx-step<=xy[0]<=zx+zw+step and zz0-step<=xy[1]<=zz0+zh+step for zx,zz0,zw,zh in reserves):
                fixed[vi]=True;rec,at=refs[vi][0];values[vi]=original_by_id[rec['uuid']]['terrain_mesh']['heights'][at]
        # Preserve every river-owned changed vertex, including shared seam samples.
        for river in meta['terrain_rivers']:
            for pair in river['terrains']:
                a=np.array(pair['before']['terrain_mesh']['heights']);b=np.array(pair['after']['terrain_mesh']['heights'])
                rec=original_by_id[pair['after']['uuid']];tm=rec['terrain_mesh'];cx,_,cz=rec['position'];sx,_,sz=rec['size']
                for at in np.flatnonzero(abs(a-b)>1e-7):
                    iz,ix=divmod(int(at),tm['columns']+1);xy=key([cx-sx/2+sx*ix/tm['columns'],cz-sz/2+sz*iz/tm['rows']]);vi=vertex_ids[xy]
                    if b[at]<=3.0001 or float(T.distance(np.array(xy),river_path))<=7:fixed[vi]=True;values[vi]=rec['terrain_mesh']['heights'][at]
        for bi,(ba,bb) in enumerate(bridges):
            ba,bb=np.array(ba,float),np.array(bb,float);direction=(bb-ba)/np.linalg.norm(bb-ba);normal=np.array([-direction[1],direction[0]])
            for endpoint,outward in [(ba,-direction),(bb,direction)]:
                # Anchor only the native triangles carrying the actual three
                # support probes. A broad rectangular fixed pad used to force
                # high earth beyond the bridge wall into the open river bank.
                for lateral in [-bridge_widths[bi]/2,0,bridge_widths[bi]/2]:
                    point=endpoint+outward*.06+normal*lateral
                    for rec in adjusted:
                        tm=rec['terrain_mesh'];cx,_,cz=rec['position'];sx,_,sz=rec['size'];u=(point[0]-cx+sx/2)/sx*tm['columns'];v=(point[1]-cz+sz/2)/sz*tm['rows']
                        if not (0<=u<=tm['columns'] and 0<=v<=tm['rows']):continue
                        ix=min(int(u),tm['columns']-1);iz=min(int(v),tm['rows']-1)
                        corners=[(ix,iz),(ix+1,iz+1),(ix+1,iz)] if u-ix>=v-iz else [(ix,iz),(ix+1,iz+1),(ix,iz+1)]
                        for xx0,zz0 in corners:
                            xy=key([cx-sx/2+sx*xx0/tm['columns'],cz-sz/2+sz*zz0/tm['rows']]);fixed[vertex_ids[xy]]=True
        seams=[]
        for i,r in enumerate(adjusted):
            for q in adjusted[i+1:]:
                ax,_,az=r['position'];aw,_,ad=r['size'];bx,_,bz=q['position'];bw,_,bd=q['size']
                vertical=abs(ax+aw/2-(bx-bw/2))<1e-6 and abs(az-bz)<1e-6;horizontal=abs(az+ad/2-(bz-bd/2))<1e-6 and abs(ax-bx)<1e-6
                if not(vertical or horizontal):continue
                span=ad if vertical else aw;sa=round(span/(r['terrain_mesh']['rows'] if vertical else r['terrain_mesh']['columns']));sb=round(span/(q['terrain_mesh']['rows'] if vertical else q['terrain_mesh']['columns']));common=math.lcm(sa,sb)
                def edgepoint(t):return key([ax+aw/2,az-ad/2+t] if vertical else [ax-aw/2+t,az+ad/2])
                for distance in sorted(set(np.arange(0,span+.01,sa).tolist()+np.arange(0,span+.01,sb).tolist())):
                    if abs(distance/common-round(distance/common))<1e-8:continue
                    lo=math.floor(distance/common)*common;hi=lo+common;child=vertex_ids[edgepoint(distance)];left=vertex_ids[edgepoint(lo)];right=vertex_ids[edgepoint(hi)];t=(distance-lo)/common
                    seams.append((child,left,right,t))
                    if fixed[child]:
                        fixed[left]=True;fixed[right]=True
                        if values[child]<=3.0001:
                            for parent in [left,right]:
                                rec,at=refs[parent][0];values[parent]=original_by_id[rec['uuid']]['terrain_mesh']['heights'][at]
        indices=np.array([[vertex_ids[key([c[0],c[2]])] for c in tri['corners']] for tri in constraints])
        coords=xz[indices];mat=np.linalg.inv(np.stack([coords[:,1]-coords[:,0],coords[:,2]-coords[:,0]],axis=1));C=np.concatenate([-mat.sum(axis=2,keepdims=True),mat],axis=2)
        free=(~fixed[indices]);pinv=np.linalg.pinv(C*free[:,None,:]);touched=np.unique(indices.ravel())
        for iteration in range(600):
            grad=np.einsum('nij,nj->ni',C,values[indices]);slope=np.linalg.norm(grad,axis=1);bad=slope>.145
            if not bad.any():break
            change=np.einsum('nij,nj->ni',pinv[bad],grad[bad])*(.142/slope[bad]-1)[:,None]
            delta=np.zeros(len(values));count=np.zeros(len(values));np.add.at(delta,indices[bad].ravel(),change.ravel());np.add.at(count,indices[bad].ravel(),np.ones(change.size))
            values+=np.divide(delta,count,out=np.zeros_like(delta),where=count>0)
            for child,left,right,t in seams:values[child]=values[left]*(1-t)+values[right]*t
        grades=np.linalg.norm(np.einsum('nij,nj->ni',C,values[indices]),axis=1)
        # Extend the *final* fitted-road delta into the surrounding ground.
        # Otherwise the slope solver's road-only vertex changes form a narrow
        # ridge at the pavement edge even when the pavement itself is legal.
        from scipy.spatial import cKDTree
        original_values=np.array([original_by_id[rec['uuid']]['terrain_mesh']['heights'][at] for group in refs for rec,at in group[:1]])
        road_distance=cKDTree(xz[touched]).query(xz)[0]
        shoulder_free=(road_distance>1e-6)&(road_distance<24)&(~fixed)
        adjacency=set();surface_triangles=[]
        for rec in adjusted:
            tm=rec['terrain_mesh'];cx,_,cz=rec['position'];sx,_,sz=rec['size']
            grid=np.array([[vertex_ids[key([cx-sx/2+sx*ix/tm['columns'],cz-sz/2+sz*iz/tm['rows']])] for ix in range(tm['columns']+1)] for iz in range(tm['rows']+1)])
            for left,right in [(grid[:,:-1],grid[:,1:]),(grid[:-1,:],grid[1:,:])]:
                adjacency.update(tuple(sorted((int(a),int(b)))) for a,b in zip(left.ravel(),right.ravel()))
            surface_triangles.extend(np.stack([grid[:-1,:-1].ravel(),grid[:-1,1:].ravel(),grid[1:,1:].ravel()],axis=1).tolist())
            surface_triangles.extend(np.stack([grid[:-1,:-1].ravel(),grid[1:,1:].ravel(),grid[1:,:-1].ravel()],axis=1).tolist())
        links=np.array(sorted(adjacency));weights=1/np.sum((xz[links[:,0]]-xz[links[:,1]])**2,axis=1)
        degree=np.bincount(links[:,0],weights,minlength=len(values))+np.bincount(links[:,1],weights,minlength=len(values))
        deltas=values-original_values
        for shoulder_iteration in range(300):
            totals=np.bincount(links[:,0],weights*deltas[links[:,1]],minlength=len(values))+np.bincount(links[:,1],weights*deltas[links[:,0]],minlength=len(values))
            next_delta=totals/degree
            # Screened diffusion restores the source progressively, instead of
            # ending an elevated planar shoulder at a hard radius boundary.
            next_delta/=1+.012*(road_distance/12)**2
            delta_change=next_delta[shoulder_free]-deltas[shoulder_free]
            deltas[shoulder_free]+=.8*delta_change
            values=original_values+deltas
            for child,left,right,t in seams:values[child]=values[left]*(1-t)+values[right]*t
            deltas=values-original_values
            if max(abs(delta_change),default=0)<1e-6:break
        # Shared 1/2/3m border interpolation can touch a road-corner sample;
        # repeat the exact native-domain constraint after shoulder diffusion.
        for final_iteration in range(300):
            grad=np.einsum('nij,nj->ni',C,values[indices]);slope=np.linalg.norm(grad,axis=1);bad=slope>.145
            if not bad.any():break
            change=np.einsum('nij,nj->ni',pinv[bad],grad[bad])*(.142/slope[bad]-1)[:,None]
            delta=np.zeros(len(values));count=np.zeros(len(values));np.add.at(delta,indices[bad].ravel(),change.ravel());np.add.at(count,indices[bad].ravel(),np.ones(change.size))
            values+=np.divide(delta,count,out=np.zeros_like(delta),where=count>0)
            for child,left,right,t in seams:values[child]=values[left]*(1-t)+values[right]*t
        grades=np.linalg.norm(np.einsum('nij,nj->ni',C,values[indices]),axis=1)
        # Smooth the dry-bank/shoulder domain itself, not only the pavement.
        # Native water-bed vertices and reserved zones remain exact anchors.
        surface_triangles=np.array(surface_triangles)
        active=(road_distance[surface_triangles].min(axis=1)<32)&(~fixed[surface_triangles].all(axis=1))
        bank_indices=surface_triangles[active]
        coords=xz[bank_indices];mat=np.linalg.inv(np.stack([coords[:,1]-coords[:,0],coords[:,2]-coords[:,0]],axis=1));bank_C=np.concatenate([-mat.sum(axis=2,keepdims=True),mat],axis=2)
        combined_indices=np.concatenate([indices,bank_indices]);combined_C=np.concatenate([C,bank_C])
        bank_centers=xz[bank_indices].mean(axis=1);under_bridge=np.zeros(len(bank_indices),dtype=bool)
        for bi,(ba,bb) in enumerate(bridges):
            ba,bb=np.array(ba,float),np.array(bb,float);length=np.linalg.norm(bb-ba);direction=(bb-ba)/length;normal=np.array([-direction[1],direction[0]])
            along=(bank_centers-ba)@direction;across=abs((bank_centers-ba)@normal)
            under_bridge|=(along>=-2)&(along<=length+2)&(across<=bridge_widths[bi]/2+.8)
        # The masonry deck/abutment covers this narrow core. Do not force its
        # buried earth to meet a grass-bank slope: that would require changing
        # either the frozen bridge support height or the protected water bed.
        head_distance=np.min(np.stack([np.linalg.norm(bank_centers-np.array(endpoint),axis=1) for pair in bridges for endpoint in pair]),axis=0)
        bank_limits=np.where(under_bridge,3.,.38+.62*(1-T.smooth(4,12,head_distance)))
        limits=np.concatenate([np.full(len(indices),.145),bank_limits])
        combined_pinv=np.linalg.pinv(combined_C*(~fixed[combined_indices])[:,None,:])
        for bank_iteration in range(5000):
            grad=np.einsum('nij,nj->ni',combined_C,values[combined_indices]);slope=np.linalg.norm(grad,axis=1);bad=slope>limits
            if not bad.any():break
            change=np.einsum('nij,nj->ni',combined_pinv[bad],grad[bad])*((limits[bad]-.002)/slope[bad]-1)[:,None]
            delta=np.zeros(len(values));count=np.zeros(len(values));np.add.at(delta,combined_indices[bad].ravel(),change.ravel());np.add.at(count,combined_indices[bad].ravel(),np.ones(change.size))
            values+=np.divide(delta,count,out=np.zeros_like(delta),where=count>0)
            for child,left,right,t in seams:values[child]=values[left]*(1-t)+values[right]*t
        grades=np.linalg.norm(np.einsum('nij,nj->ni',C,values[indices]),axis=1)
        bank_grades=np.linalg.norm(np.einsum('nij,nj->ni',bank_C,values[bank_indices]),axis=1)
        # Pavement is the strict native safety constraint. Give it the final
        # projection even when fixed bridge/water anchors make a local shoulder
        # target infeasible; report those shoulder exceptions explicitly.
        for final_iteration in range(1200):
            grad=np.einsum('nij,nj->ni',C,values[indices]);slope=np.linalg.norm(grad,axis=1);bad=slope>.145
            if not bad.any():break
            change=np.einsum('nij,nj->ni',pinv[bad],grad[bad])*(.142/slope[bad]-1)[:,None]
            delta=np.zeros(len(values));count=np.zeros(len(values));np.add.at(delta,indices[bad].ravel(),change.ravel());np.add.at(count,indices[bad].ravel(),np.ones(change.size))
            values+=np.divide(delta,count,out=np.zeros_like(delta),where=count>0)
            for child,left,right,t in seams:values[child]=values[left]*(1-t)+values[right]*t
        grades=np.linalg.norm(np.einsum('nij,nj->ni',C,values[indices]),axis=1)
        bank_grades=np.linalg.norm(np.einsum('nij,nj->ni',bank_C,values[bank_indices]),axis=1)
        ordinary=(~under_bridge)&(head_distance>=12)
        polish_indices=np.concatenate([indices,bank_indices[ordinary]]);polish_C=np.concatenate([C,bank_C[ordinary]])
        polish_limits=np.concatenate([np.full(len(indices),.145),np.full(sum(ordinary),.39)])
        polish_pinv=np.linalg.pinv(polish_C*(~fixed[polish_indices])[:,None,:])
        for polish_iteration in range(1800):
            grad=np.einsum('nij,nj->ni',polish_C,values[polish_indices]);slope=np.linalg.norm(grad,axis=1);bad=slope>polish_limits
            if not bad.any():break
            change=np.einsum('nij,nj->ni',polish_pinv[bad],grad[bad])*((polish_limits[bad]-.002)/slope[bad]-1)[:,None]
            delta=np.zeros(len(values));count=np.zeros(len(values));np.add.at(delta,polish_indices[bad].ravel(),change.ravel());np.add.at(count,polish_indices[bad].ravel(),np.ones(change.size))
            values+=np.divide(delta,count,out=np.zeros_like(delta),where=count>0)
            for child,left,right,t in seams:values[child]=values[left]*(1-t)+values[right]*t
        grades=np.linalg.norm(np.einsum('nij,nj->ni',C,values[indices]),axis=1)
        bank_grades=np.linalg.norm(np.einsum('nij,nj->ni',bank_C,values[bank_indices]),axis=1)
        assert max(grades)<=.1501,('native pavement grade',float(max(grades)))
        assert max(bank_grades[ordinary])<=.4001,('ordinary shoulder grade',float(max(bank_grades[ordinary])))
        for vi in range(len(values)):
            for rec,at in refs[vi]:rec['terrain_mesh']['heights'][at]=float(values[vi])
        slope_projection={"available":True,"iterations":iteration+1,"triangles":len(indices),"max_grade":float(max(grades)),"remaining_over_native_limit":int(sum(grades>.1501)),"native_overlap_source":str(constraints_path),"shoulder_diffusion_iterations":shoulder_iteration+1,"shoulder_radius_m":24,"bank_constraint_iterations":bank_iteration+1,"bank_max_grade":float(max(bank_grades)),"ordinary_bank_max_grade":float(max(bank_grades[ordinary])),"ordinary_bank_triangles_over_04":int(sum(bank_grades[ordinary]>.4001)),"bridgehead_shoulder_max_grade":float(max(bank_grades[(~under_bridge)&(~ordinary)])),"bridgehead_shoulder_exceptions":[{"center":p.tolist(),"grade":float(g)} for p,g,exc in zip(bank_centers,bank_grades,(~under_bridge)&(~ordinary)) if exc and g>.6],"structural_abutment_note":"Buried bridge core is exempt; fixed high bridge supports transition to ordinary grass-bank slope over 12m. Near-head steep exceptions are listed explicitly and require GPU appearance review; not claimed ordinary <=0.4.","longitudinal_profile":"sample existing terrain every 2m; preserve local bridge lifts","maximum_fill_m":float(max(values-original_values)),"maximum_cut_m":float(max(original_values-values))}
    # Preserve untouched source floats exactly. Native river ownership uses a
    # much tighter equality than our meaningful-edit reporting epsilon.
    for original,changed in zip(terrains,adjusted):
        old=original['terrain_mesh']['heights'];new=changed['terrain_mesh']['heights']
        changed['terrain_mesh']['heights']=[a if abs(b-a)<=1e-5 else b for a,b in zip(old,new)]
    # Export complete changed arrays after edge reconciliation, not pre-join deltas.
    patches=[]
    for original,changed in zip(terrains,adjusted):
        old=np.array(original['terrain_mesh']['heights']);new=np.array(changed['terrain_mesh']['heights']);indices=np.flatnonzero(abs(new-old)>1e-5).tolist()
        if indices:patches.append({'id':changed['uuid'],'indices':indices,'heights':[float(new[i]) for i in indices],'terrain_mesh':changed['terrain_mesh'],'changed_vertices':len(indices),'max_abs_delta':float(max(abs(new-old)))})
    rebase=[];adjusted_by_id={r['uuid']:r for r in adjusted};underwater_changes=0;zone_intersections=[]
    for river in meta['terrain_rivers']:
        for pair in river['terrains']:
            original=original_by_id[pair['after']['uuid']];changed=adjusted_by_id[original['uuid']];delta=np.array(changed['terrain_mesh']['heights'])-np.array(original['terrain_mesh']['heights']);indices=np.flatnonzero(abs(delta)>1e-5).tolist()
            owned=abs(np.array(pair['after']['terrain_mesh']['heights'])-np.array(pair['before']['terrain_mesh']['heights']))>1e-7
            if indices:rebase.append({'river_id':river['id'],'terrain_id':original['uuid'],'indices':indices,'deltas':[float(delta[i]) for i in indices],'owned_carve_samples_changed':sum(bool(owned[i]) for i in indices),'instruction':'Add these exact deltas to BOTH before and after heights; preserve carve difference, then refresh native signatures through the original editor transaction.'})
            tm=original['terrain_mesh'];cx,_,cz=original['position'];sx,_,sz=original['size'];water_path=T.spline(river['request']['points']) if river['request']['curved'] else np.array(river['request']['points'])
            for at in indices:
                iz,ix=divmod(at,tm['columns']+1);point=np.array([cx-sx/2+ix*sx/tm['columns'],cz-sz/2+iz*sz/tm['rows']])
                if original['terrain_mesh']['heights'][at]<=river['request']['water_level'] and float(T.distance(point,water_path))<=river['request']['width']/2:
                    underwater_changes+=1;print('UNDERWATER_DELTA',river['id'],original['uuid'],at,point.tolist(),float(delta[at]))
    for original,changed in zip(terrains,adjusted):
        tm=changed['terrain_mesh'];cx,_,cz=changed['position'];sx,_,sz=changed['size'];step=max(sx/tm['columns'],sz/tm['rows']);delta=np.array(tm['heights'])-np.array(original['terrain_mesh']['heights'])
        for at in np.flatnonzero(abs(delta)>1e-5):
            iz,ix=divmod(int(at),tm['columns']+1);x=cx-sx/2+ix*sx/tm['columns'];z=cz-sz/2+iz*sz/tm['rows']
            for i,(zx,zz0,zw,zh) in enumerate(reserves):
                if zx-step<x<zx+zw+step and zz0-step<z<zz0+zh+step:zone_intersections.append([changed['uuid'],int(at),f'R{i+1}'])
    assert underwater_changes==0,underwater_changes
    assert not zone_intersections,zone_intersections[:10]
    maximum_seam=0.
    for i,a in enumerate(adjusted):
        for b in adjusted[i+1:]:
            ax,_,az=a['position'];aw,_,ad=a['size'];bx,_,bz=b['position'];bw,_,bd=b['size'];vertical=abs(ax+aw/2-(bx-bw/2))<1e-6 and abs(az-bz)<1e-6;horizontal=abs(az+ad/2-(bz-bd/2))<1e-6 and abs(ax-bx)<1e-6
            if not(vertical or horizontal):continue
            ta,tb=a['terrain_mesh'],b['terrain_mesh'];ha=np.array(ta['heights']).reshape(ta['rows']+1,ta['columns']+1);hb=np.array(tb['heights']).reshape(tb['rows']+1,tb['columns']+1);ea=ha[:,-1] if vertical else ha[-1,:];eb=hb[:,0] if vertical else hb[0,:];span=ad if vertical else aw;grid=np.arange(0,span+.01,.25)
            maximum_seam=max(maximum_seam,float(max(abs(np.interp(grid,np.linspace(0,span,len(ea)),ea)-np.interp(grid,np.linspace(0,span,len(eb)),eb)))))
    # Exact untouched source floats can leave <=2 reporting epsilons at mixed-grid seams.
    # This is an authoring audit only; native adjacency tolerances are unchanged.
    assert maximum_seam<2e-5,maximum_seam
    out={'format':'axel_native_roads_v1','source_plan':str(PLAN),'source_plan_sha256':hashlib.sha256(PLAN.read_bytes()).hexdigest(),'source_map':str(MAP),'source_map_sha256':hashlib.sha256(MAP.read_bytes()).hexdigest(),'authored_paths':authored,'graph':graph,'river_rebase_adjustments':rebase,'terrain_protection_report':{'maximum_seam_m':maximum_seam,'underwater_changed_vertices':underwater_changes,'reserved_zone_cell_conflicts':zone_intersections},'terrain_slope_projection':slope_projection,'terrain_adjustments':patches,'terrain_records_after_adjustment':adjusted,'future_home_adjustments':[{'home_index':37,'from':[330,181],'to':[333,181],'reason':'Keep new 2m riverside access on dry bank'},{'home_index':38,'from':[332,201],'to':[335,201],'reason':'Keep new 2m riverside access on dry bank'}],'road_surface_settings':{'follow_terrain':True,'thickness':.2,'lift':.025,'clearance':3,'material_id':'pack:default:paving/outdoor_flagstone/material','kerb_enabled':True,'kerb_width':.24,'kerb_height':.035,'kerb_material_id':'pack:default:paving/automatic_limestone_kerb_readable/material'},'planning_zones':zones,'plaza_record':plaza,'bridge_connections':[{'number':i+1,'ends':b,'edge_id':next(e['id'] for e in edges if e['name']==f'Bridge {i+1}'),'width':bridge_widths[i],'edge_ends':extended[i],'abutment_raise':1 if i==3 else (1.5 if i==4 else 0)} for i,b in enumerate(bridges)],'report':{'nodes':len(nodes),'edge_count':len(edges),'source_path_count':len(authored),'road_length_m':sum(x['length'] for x in edge_details),'schema_limits_pass':True,'native_godot_preview_pending':True,'risks':risks,'terrain_fit_hotspots':terrain_hits,'reservation_conflicts':reservation_hits,'wall_clearance_review':wall_hits,'grass_clearance_candidate_ids':sorted(grass_hits),'edges':edge_details},'integration_notes':['Read get_city_layout and insert current road_token as expected_token; do not use a stale token. Graph already splits same-level crossings and coalesces duplicate centerlines.','Native follow_terrain fits EVERY patch including an unbound bridge edge: bind/generated stone bridges and portals before final all-graph pavement; do not terrain-fit a raw bridge slab into the riverbed.','terrain_projection enforces 15% slope anywhere in pavement footprint, not only road centre. Resolve listed actual-heightfield hotspots before preview; do not bypass grade validation.','Guild plaza record contains only two9m side rectangles; its central6m strip is intentionally absent because the native forecourt road supplies it. No overlapping coplanar pavement and no round plaza endcaps; no permanent stalls.','Use the authorized continuous automatic kerb .24m wide/.035m high with readable limestone material, and outdoor flagstone pavement. No individually placed curb stones.','Grass IDs are current obj_1..obj_314 records, as supplied in the task. Conservative centre-distance candidates use0.8m radius; verify actual clump footprint before moving.','45 home entry stubs are future door proposals; preserve later house/door alignment and do not pave through house footprints.','Terrain data uses fresh source_records.json exported by native Doc; no formal map/config writes.']}
    fingerprint=hashlib.sha256(json.dumps([graph,adjusted,out['road_surface_settings']],sort_keys=True,separators=(',',':')).encode()).hexdigest()
    out['validation_content_sha256']=fingerprint
    validation_path=OUT.parent/'native_validation.json'
    if validation_path.exists():
        validation=json.loads(validation_path.read_text(encoding='utf8'))
        if validation.get('content_sha256')==fingerprint:out['native_validation']=validation;out['report']['native_godot_preview_pending']=False
    OUT.parent.mkdir(parents=True,exist_ok=True);OUT.write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({k:v for k,v in out['report'].items() if k not in ['edges','grass_clearance_candidate_ids','terrain_fit_hotspots']},ensure_ascii=False,indent=2))
    print('terrain_fit_hotspots',len(terrain_hits),'grass_candidates',len(grass_hits))

def refit_bound_recipe():
    """Narrow repair using the saved candidate's real five-portal footprint.

    collect_constraints.gd must collect Plan.build(full graph, settings, portals),
    including residual approach strips. Existing broad shoulders are the seed;
    only a four-metre neighbourhood of newly failing bridge triangles is free.
    """
    import copy
    p=json.loads(OUT.read_text(encoding='utf8'));before=copy.deepcopy(p['terrain_records_after_adjustment']);adjusted=copy.deepcopy(before)
    provenance=json.loads((OUT.parent/'road_constraints_source.json').read_text(encoding='utf8'))
    assert provenance['full_bound_graph'] and len(provenance['portals'])==5 and not provenance['failures']
    assert hashlib.sha256(Path(provenance['map']).read_bytes()).hexdigest()==provenance['map_sha256']
    constraints=json.loads((OUT.parent/'road_constraints.json').read_text(encoding='utf8'))
    original={r['uuid']:r for r in json.loads((OUT.parent/'source_records.json').read_text(encoding='utf8')) if 'terrain_mesh' in r}
    metadata=json.loads((OUT.parent/'source_metadata.json').read_text(encoding='utf8'))
    vertex_ids={};refs=[];xz=[];values=[];boundary=[]
    for rec in adjusted:
        tm=rec['terrain_mesh'];cx,_,cz=rec['position'];sx,_,sz=rec['size']
        for iz in range(tm['rows']+1):
            for ix in range(tm['columns']+1):
                xy=key([cx-sx/2+sx*ix/tm['columns'],cz-sz/2+sz*iz/tm['rows']]);at=iz*(tm['columns']+1)+ix
                if xy not in vertex_ids:vertex_ids[xy]=len(values);xz.append(xy);values.append(tm['heights'][at]);refs.append([]);boundary.append(False)
                vi=vertex_ids[xy];refs[vi].append((rec,at));boundary[vi]|=ix in [0,tm['columns']] or iz in [0,tm['rows']]
    values=np.array(values);seed=values.copy();xz=np.array(xz)
    indices=np.array([[vertex_ids[key([c[0],c[2]])] for c in tri['corners']] for tri in constraints])
    coords=xz[indices];mat=np.linalg.inv(np.stack([coords[:,1]-coords[:,0],coords[:,2]-coords[:,0]],axis=1));C=np.concatenate([-mat.sum(axis=2,keepdims=True),mat],axis=2)
    grades=np.linalg.norm(np.einsum('nij,nj->ni',C,values[indices]),axis=1);initial_bad=grades>.1501
    centers=coords[initial_bad].mean(axis=1)
    if not len(centers):print('Full bound footprint already passes');return
    free=np.min(np.linalg.norm(xz[:,None,:]-centers[None,:,:],axis=2),axis=1)<=4
    free&=~np.array(boundary)
    river_path=T.spline(metadata['terrain_rivers'][0]['request']['points']);free&=T.distance(xz,river_path)>7
    free&=~((xz[:,0]>=334)&(xz[:,0]<=381)&(xz[:,1]>=121.7)&(xz[:,1]<=129.3))
    for zone in p['planning_zones'][:5]:
        points=np.array(zone['polygon']);lo=points.min(axis=0);hi=points.max(axis=0)
        free&=~((xz[:,0]>=lo[0]-3)&(xz[:,0]<=hi[0]+3)&(xz[:,1]>=lo[1]-3)&(xz[:,1]<=hi[1]+3))
    for bridge in p['bridge_connections']:
        ba,bb=np.array(bridge['ends'],float);direction=(bb-ba)/np.linalg.norm(bb-ba);normal=np.array([-direction[1],direction[0]])
        for endpoint,outward in [(ba,-direction),(bb,direction)]:
            for lateral in [-bridge['width']/2,0,bridge['width']/2]:
                point=endpoint+outward*.06+normal*lateral
                for rec in adjusted:
                    tm=rec['terrain_mesh'];cx,_,cz=rec['position'];sx,_,sz=rec['size'];u=(point[0]-cx+sx/2)/sx*tm['columns'];v=(point[1]-cz+sz/2)/sz*tm['rows']
                    if not (0<=u<=tm['columns'] and 0<=v<=tm['rows']):continue
                    ix=min(int(u),tm['columns']-1);iz=min(int(v),tm['rows']-1)
                    corners=[(ix,iz),(ix+1,iz+1),(ix+1,iz)] if u-ix>=v-iz else [(ix,iz),(ix+1,iz+1),(ix,iz+1)]
                    for xx,zz in corners:free[vertex_ids[key([cx-sx/2+sx*xx/tm['columns'],cz-sz/2+sz*zz/tm['rows']])]]=False
    pinv=np.linalg.pinv(C*free[indices][:,None,:])
    for iteration in range(1500):
        grad=np.einsum('nij,nj->ni',C,values[indices]);grade=np.linalg.norm(grad,axis=1);bad=grade>.145
        if not bad.any():break
        change=np.einsum('nij,nj->ni',pinv[bad],grad[bad])*(.143/grade[bad]-1)[:,None]
        delta=np.zeros(len(values));count=np.zeros(len(values));np.add.at(delta,indices[bad].ravel(),change.ravel());np.add.at(count,indices[bad].ravel(),np.ones(change.size))
        values+=np.divide(delta,count,out=np.zeros_like(delta),where=count>0)
    grades=np.linalg.norm(np.einsum('nij,nj->ni',C,values[indices]),axis=1)
    assert max(grades)<=.1501,('bound footprint remains too steep',float(max(grades)))
    values=np.where(abs(values-seed)<=1e-5,seed,values)
    changed_vertices=[]
    for vi in np.flatnonzero(abs(values-seed)>1e-5):
        changed_vertices.append({'xz':xz[vi].tolist(),'before':float(seed[vi]),'after':float(values[vi]),'delta':float(values[vi]-seed[vi])})
        for rec,at in refs[vi]:rec['terrain_mesh']['heights'][at]=float(values[vi])
    # All freed vertices are strictly internal to their existing tile, so every
    # mixed-grid seam and the preceding broad-shoulder pass remain unchanged.
    patches=[];rebase=[];by_id={r['uuid']:r for r in adjusted}
    for rec in adjusted:
        old=np.array(original[rec['uuid']]['terrain_mesh']['heights']);new=np.array(rec['terrain_mesh']['heights']);ix=np.flatnonzero(abs(new-old)>1e-5).tolist()
        if ix:patches.append({'id':rec['uuid'],'indices':ix,'heights':[float(new[i]) for i in ix],'terrain_mesh':rec['terrain_mesh'],'changed_vertices':len(ix),'max_abs_delta':float(max(abs(new-old)))})
    for river in metadata['terrain_rivers']:
        for pair in river['terrains']:
            uid=pair['after']['uuid'];delta=np.array(by_id[uid]['terrain_mesh']['heights'])-np.array(original[uid]['terrain_mesh']['heights']);ix=np.flatnonzero(abs(delta)>1e-5).tolist();owned=abs(np.array(pair['after']['terrain_mesh']['heights'])-np.array(pair['before']['terrain_mesh']['heights']))>1e-7
            if ix:rebase.append({'river_id':river['id'],'terrain_id':uid,'indices':ix,'deltas':[float(delta[i]) for i in ix],'owned_carve_samples_changed':sum(bool(owned[i]) for i in ix),'instruction':'Add these exact deltas to BOTH before and after heights; preserve carve difference, then refresh native signatures through the original editor transaction.'})
    p['terrain_records_after_adjustment']=adjusted;p['terrain_adjustments']=patches;p['river_rebase_adjustments']=rebase
    p['terrain_slope_projection'].update(triangles=len(indices),max_grade=float(max(grades)),remaining_over_native_limit=int(sum(grades>.1501)),full_bound_graph=True)
    # Refresh reported near-head slopes affected by this local repair rather
    # than leaving the preceding GPU candidate's numerical exceptions stale.
    exceptions=[];head_max=0.
    ends=np.array([end for bridge in p['bridge_connections'] for end in bridge['ends']])
    for rec in adjusted:
        tm=rec['terrain_mesh'];cx,_,cz=rec['position'];sx,_,sz=rec['size'];dx=sx/tm['columns'];dz=sz/tm['rows'];h=np.array(tm['heights']).reshape(tm['rows']+1,tm['columns']+1)
        xx,zz=np.meshgrid(cx-sx/2+np.arange(tm['columns'])*dx,cz-sz/2+np.arange(tm['rows'])*dz)
        for part in [0,1]:
            g=np.hypot((h[:-1,1:]-h[:-1,:-1])/dx,(h[1:,1:]-h[:-1,1:])/dz) if part==0 else np.hypot((h[1:,1:]-h[1:,:-1])/dx,(h[1:,:-1]-h[:-1,:-1])/dz)
            centers=np.stack([xx+(2/3 if part==0 else 1/3)*dx,zz+(1/3 if part==0 else 2/3)*dz],axis=-1).reshape(-1,2)
            distance=np.min(np.linalg.norm(centers[:,None,:]-ends[None,:,:],axis=2),axis=1);under=np.zeros(len(centers),dtype=bool)
            for bridge in p['bridge_connections']:
                a,b=np.array(bridge['ends']);length=np.linalg.norm(b-a);direction=(b-a)/length;normal=np.array([-direction[1],direction[0]]);along=(centers-a)@direction
                under|=(along>=-2)&(along<=length+2)&(abs((centers-a)@normal)<=bridge['width']/2+.8)
            nearby=(distance<12)&(~under)
            if nearby.any():head_max=max(head_max,float(max(g.ravel()[nearby])))
            exceptions.extend({'center':center.tolist(),'grade':float(grade)} for center,grade in zip(centers[nearby],g.ravel()[nearby]) if grade>.6)
    p['terrain_slope_projection'].update(bridgehead_shoulder_exceptions=exceptions,bridgehead_shoulder_max_grade=head_max)
    p['bound_approach_repair']={'source':provenance,'initial_bad_triangles':int(sum(initial_bad)),'iterations':iteration+1,'changed_vertices':changed_vertices,'ordinary_shoulders_preserved':'Only internal vertices within4m of eight actual bridge-approach triangles are eligible; previous broad shoulder field is unchanged elsewhere.'}
    p['validation_content_sha256']=hashlib.sha256(json.dumps([p['graph'],adjusted,p['road_surface_settings']],sort_keys=True,separators=(',',':')).encode()).hexdigest();p.pop('native_validation',None);p['report']['native_godot_preview_pending']=True
    OUT.write_text(json.dumps(p,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({'full_bound_triangles':len(indices),'initial_bad':int(sum(initial_bad)),'changed_vertices':len(changed_vertices),'max_grade':float(max(grades))}))


if __name__=='__main__':
    import sys
    refit_bound_recipe() if '--refit-bound' in sys.argv else main()
