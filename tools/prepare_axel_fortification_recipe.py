"""Prepare data for native transactions; never edits a map or terrain arrays."""
import hashlib, json, math
from pathlib import Path

OUT=Path('D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016')
plan=json.loads((OUT/'fortification_plan_review.json').read_text(encoding='utf-8'))
records=json.loads((OUT/'source_records.json').read_text(encoding='utf-8'))
terrains=[r for r in records if 'terrain_mesh' in r]

def at(x,z):
    for r in terrains:
        lx=x-r['position'][0]; lz=z-r['position'][2]
        w,_,d=r['size'];t=r['terrain_mesh'];c=int(t['columns']);n=int(t['rows'])
        u=(lx/w+.5)*c;v=(lz/d+.5)*n
        if not(0<=u<=c and 0<=v<=n):continue
        i=min(int(u),c-1);j=min(int(v),n-1);u-=i;v-=j
        h=t['heights'];s=c+1;a=h[j*s+i];b=h[j*s+i+1];e=h[(j+1)*s+i+1];f=h[(j+1)*s+i]
        y=a+(b-a)*u+(e-b)*v if u>=v else a+(e-f)*u+(f-a)*v
        return r['uuid'], y*r['size'][1]+r['position'][1]
    raise ValueError((x,z))

def stamp(x,z,w,d,h,margin=4,yaw=0,grade=(0,0)):
    return dict(id=at(x,z)[0],mode='flatten',shape='rectangle',points=[[x,z]],plot_width=w,plot_depth=d,plot_yaw=yaw,plot_grade=list(grade),target_height=h,blend_margin=margin,strength=1.,cross_tiles=True)

settings=plan['settings']
settings['points'][16]=[235.,345.]
# Move the northeast tower and east wall outside R2, retaining the north
# gate's existing straight approach. The 16 m pad plus 2 m blend remains
# north of R2 and west of the tributary-owned samples; the wall runs east of R2.
settings['points'][8]=[383.,58.]
strokes=[]
for t in plan['tower_measurements']:
    x,z=settings['points'][int(t['index'])]
    h=10.6 if t['index']==3 else at(x,z)[1]
    # The northeast tower sits north of R2. Keep its native changed cells
    # outside that protected parcel, including the grid-cell halo.
    strokes.append(stamp(x,z,16,16,h,2) if t['index']==8 else stamp(x,z,16,16,h,6))
for g in plan['land_gate_measurements']:
    x,z=g['at'];w=18 if g['id'] in ('G2','G4') else 12;d=12 if g['id'] in ('G2','G4') else 18
    strokes.append(stamp(x,z,w,d,g['terrain']['center'],5))
# Smooth, narrow dry-bank strips support the north multi-bay water gate.
# Keep the existing water surface, channel bed and slope ownership untouched.
north=plan['water_gate_measurements'][0];a,b=[p['xz'] for p in north['bank_samples']]
dx=b[0]-a[0];dz=b[1]-a[1];l=math.hypot(dx,dz);dx/=l;dz/=l
yaw=-math.degrees(math.atan2(dz,dx))
for bank,side,length,grade in [(a,-1,20,-.10),(b,1,24,.08)]:
    center=[bank[0]+dx*side*(length/2-2),bank[1]+dz*side*(length/2-2)]
    h=9+grade*side*(length/2-2)
    strokes.append(stamp(*center,length,10,h,5,yaw,(grade,0)))
# Southern bank jambs are outside the original channel shoulder.
for gate in settings['gates']:
    if gate['id']=='axel_south_watergate':
        gate['width']=26.;gate['base_height']=4.05
        # Extend the dry east approach; keep the gate centered on the river.
        gate['t']=(235.-213.686492919922)/45.
# West approach to the lowered north tower: spread the 1 m descent along
# the dry wall alignment instead of the tower pad's short feather.
west_a=(112.,30.+(145.-112.)*32./63.)
west_b=(137.,30.+(145.-137.)*32./63.)
west_length=math.dist(west_a,west_b)
west_start=at(*west_a)[1]
west_yaw=-math.degrees(math.atan2(west_b[1]-west_a[1],west_b[0]-west_a[0]))
strokes.append(stamp((west_a[0]+west_b[0])/2,(west_a[1]+west_b[1])/2,west_length,14,(west_start+10.6)/2,6,west_yaw,((10.6-west_start)/west_length,0)))
strokes.append(stamp(145,30,14,14,10.6,4))
# Match dry southern jamb ground exactly: the 0.674 m boundary battlement
# must not absorb the former ~0.126 m bank/jamb mismatch as a steep ramp.
south=next(g for g in settings['gates'] if g['id']=='axel_south_watergate')
seg=int(south['segment']);pa=settings['points'][seg];pb=settings['points'][(seg+1)%len(settings['points'])]
length=math.dist(pa,pb);direction=((pb[0]-pa[0])/length,(pb[1]-pa[1])/length)
center=(pa[0]+(pb[0]-pa[0])*south['t'],pa[1]+(pb[1]-pa[1])*south['t'])
for side in [-1,1]:
    x=center[0]+direction[0]*side*south['width']/2
    z=center[1]+direction[1]*side*south['width']/2
    west=x<center[0]
    strokes.append(stamp(x,z,6 if west else 4,10,4.05,2 if west else 1,-math.degrees(math.atan2(direction[1],direction[0]))))
recipe=dict(source_sha256=plan['source_sha256'],fortification_request=settings,terrain_batches=[dict(strokes=strokes[:16]),dict(strokes=strokes[16:])],cameras=[],project_supplementary_design=True)
# These are two existing alley_04 turns, not new tower-access lanes. Preserve
# every edge and width; the native caller samples Y after the 22 terrain strokes.
# The all-tower probe is immutable evidence for these exact source/target XZs.
probe_path=OUT/'tower_road_layout_probe.json'
probe=json.loads(probe_path.read_text(encoding='utf-8'))
assert probe['tower_count']==12 and probe['original_conflict_towers']==[10,11]
assert probe['proposed_conflict_towers']==[] and probe['unchanged_edge_records']
meta_path=OUT/'source_metadata.json'
assert probe['source_metadata_sha256']==hashlib.sha256(meta_path.read_bytes()).hexdigest()
graph=json.loads(meta_path.read_text(encoding='utf-8'))['editor_layout']['roads']
node_by_id={node['id']:node for node in graph['nodes']}
recipe['road_node_adjustments']=[]
for move in probe['proposed_nodes']:
    assert node_by_id[move['id']]['position']==move['old']
    recipe['road_node_adjustments'].append(dict(id=move['id'],source_position=move['old'],target_xz=move['proposed_xz']))
recipe['road_adjustment_affected_edge_ids']=[edge['id'] for edge in probe['affected_edges']]
recipe['road_layout_probe']=dict(path=str(probe_path).replace('\\','/'),sha256=hashlib.sha256(probe_path.read_bytes()).hexdigest(),input_recipe_sha256=probe['recipe_sha256'])
recipe['road_adjustment_policy']='After terrain batches, before fortification: update_road_graph with a fresh expected_token and complete replacement nodes, sample each Y from final native terrain. Keep every edge and width unchanged.'
(OUT/'fortification_content_recipe.json').write_text(json.dumps(recipe,ensure_ascii=False,indent=2),encoding='utf-8')
print('Prepared',len(strokes),'native terrain strokes and',len(recipe['road_node_adjustments']),'existing road-node XZ adjustments. Map unchanged.')
