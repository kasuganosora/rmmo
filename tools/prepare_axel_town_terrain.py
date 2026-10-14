"""Build the editable, uncarved 450x360 m Axel heightfield recipe.
No game/map writes. Heights and shore design are project proposals, not surveyed data.
"""
from pathlib import Path
import json, math
import numpy as np
OUT=Path('D:/code/rmmo_runtime/review_artifacts/axel_town_terrain_20261014/recipe.json')
X=[-30,30,90,150,210,270,330,390,450,480]
Z=[-30,30,90,150,210,270,330,390]
RIVER=[[180,-30],[180,-15],[180,0],[199,41],[231,72],[277,104],[310,142],[320,186],[302,228],[263,267],[228,292],[215,325],[214,360],[214,375],[214,390]]
WEST=[[166.5,47,12],[166.5,49,12],[185,49,11],[185,73,9.6],[195,73,9],[195,90,8.2],[195,125,7],[195,155,7.3],[195,219,7.5],[156,219,7.5],[156,235,7],[195,235,6.5],[248,235,5.5],[274,235,5.5]]
EAST=[[288,85,10.1],[284,85,10.1],[284,60,10.1],[329,60,10],[329,100,9],[329,121.5,8],[329,129.5,8],[329,159,6.2]]
ROUTES=[WEST,EAST,[[301,165,6.2],[248,145,5.4],[248,166,4.4],[248,184,3.6],[248,201,3.8]],[[296,256,5.5],[311,270,6],[381,270,6.4]],[[329,121.5,8],[379,121.5,8]],[[329,129.5,8],[379,129.5,8]],[[42,171,7.5],[126,171,7.5],[126,219,7.5],[156,219,7.5]]]
BRIDGES=[([[219,83],[244,60]],8),([[301,165],[329,159]],6.2),([[274,235],[296,256]],5.5),([[229,275],[247,295]],4.8),([[200,325],[230,325]],4.2)]
def spline(raw,spacing=2.,tension=.5):
 p=np.array(raw,float);result=[]
 for i in range(len(p)-1):
  a,b=p[i:i+2];before=p[i-1] if i else 2*a-b;after=p[i+2] if i+2<len(p) else 2*b-a;m=(b-before)*tension;n=(after-a)*tension
  steps=max(1,math.ceil((np.linalg.norm(b-a)+np.linalg.norm(m)+np.linalg.norm(n))/(3*spacing)))
  for j in range(steps):
   t=j/steps;u=t*t;v=u*t;result.append((2*v-3*u+1)*a+(v-2*u+t)*m+(-2*v+3*u)*b+(v-u)*n)
 return np.array(result+[p[-1]])
PATH=spline(RIVER)
def distance(points,path):
 points=np.asarray(points);best=np.full(points.shape[:-1],np.inf)
 for a,b in zip(path[:-1],path[1:]):
  delta=b-a;t=np.clip(np.sum((points-a)*delta,axis=-1)/max(1e-9,np.dot(delta,delta)),0,1)
  best=np.minimum(best,np.linalg.norm(points-a-t[...,None]*delta,axis=-1))
 return best

def smooth(a,b,v):
 t=np.clip((v-a)/(b-a),0,1);return t*t*(3-2*t)
def route_influence(x,z,route):
 p=np.stack([x,z],axis=-1);best=np.full(x.shape,np.inf);height=np.zeros(x.shape);candidates=[]
 for aa,bb in zip(route[:-1],route[1:]):
  a=np.array([aa[0],aa[1]]);b=np.array([bb[0],bb[1]]);d=b-a;t=np.clip(np.sum((p-a)*d,axis=-1)/max(1e-9,np.dot(d,d)),0,1);dist=np.linalg.norm(p-a-t[...,None]*d,axis=-1);mask=dist<best
  value=aa[2]+t*(bb[2]-aa[2]);candidates.append((dist,value));height=np.where(mask,value,height);best=np.minimum(best,dist)
 weights=[np.exp(-np.maximum(0,dd*dd-best*best)/4) for dd,value in candidates]
 height=sum(w*value for w,(dd,value) in zip(weights,candidates))/sum(weights)
 return best,height
# Smooth interpolation through broad area control samples. No riverbed lowering here.
ANCHORS=np.array([[0,0,9],[130,40,11.7],[166,47,12],[110,80,10],[165,93,9],[95,145,7.6],[110,210,7.5],[156,210,7.5],[195,155,7.3],[245,183,3.7],[280,210,4],[280,160,4.7],[298,77,10.6],[320,85,10.5],[355,122,8],[370,160,7.3],[350,200,6.8],[346,260,6.4],[135,282,5.2],[175,325,4.5],[290,315,4.8],[400,310,5.7],[30,330,5],[450,40,9],[450,350,5]],float)
def heightfield(x,z):
 x,z=np.broadcast_arrays(np.asarray(x,float),np.asarray(z,float));weights=[];values=[]
 for ax,az,h in ANCHORS:
  w=1/(((x-ax)**2+(z-az)**2)+22**2)**2;weights.append(w);values.append(w*h)
 h=np.sum(values,axis=0)/np.sum(weights,axis=0)
 # Shallow valley shoulder, still wholly dry before the native river carve.
 d=distance(np.stack([x,z],axis=-1),PATH)
 # Scene/forecourt plateaus blend outside their footprint.
 for xa,xb,za,zb,target,feather in [(140,172,198,220,7.5,14),(288,319,70,96,10.5,12),(337,379,112,139,8,16),(226,272,166,198,3.8,12)]:
  gap=np.hypot(np.maximum(np.maximum(xa-x,x-xb),0),np.maximum(np.maximum(za-z,z-zb),0));w=1-smooth(0,feather,gap);h=h*(1-w)+target*w
 # Route bands; nearest segment among all routes prevents sequential cross-road steps.
 rd=np.full(x.shape,np.inf);rh=np.zeros(x.shape)
 for route in ROUTES:
  dd,hh=route_influence(x,z,route);mask=dd<rd;rh=np.where(mask,hh,rh);rd=np.minimum(rd,dd)
 w=1-smooth(3,15,rd);h=h*(1-w)+rh*w
 # Endpoint pads only. Never interpolate across bridge spans into a soil dam.
 for ends,target in BRIDGES:
  for bx,bz in ends:
   w=1-smooth(2,10,np.hypot(x-bx,z-bz));h=h*(1-w)+target*w
 # Main-river datum +3m leaves farmland dry and avoids artificial high banks.
 # One broad grassy valley; no S1 cliff mask or narrow rock-step formula.
 transition=smooth(9.5,36,d);h=3.8*(1-transition)+h*transition
 # Bridge approaches rise gradually from the dry carve boundary. Their broad
 # lateral feather avoids isolated mounds while preserving planned deck heights.
 approach=3.8+.5*np.maximum(d-9.5,0)
 for ends,target in BRIDGES:
  for bx,bz in ends:
   w=1-smooth(3,25,np.hypot(x-bx,z-bz))
   local_approach=3.8+.6*np.maximum(d-8.5,0) if target>=8 else approach
   raised=np.minimum(target,local_approach)
   h=h*(1-w)+raised*w
 w=1-smooth(3,18,rd)
 high_route=smooth(5.6,6.2,rh)
 preserve=(1-smooth(0,3,rd))*(1-high_route)+(1-smooth(2,5,rd))*high_route
 level=np.minimum(rh,approach)*(1-preserve)+rh*preserve
 h=h*(1-w)+level*w
 return h

def uid(i,j):return f'axel_terrain_{i:02d}_{j:02d}'
def blocks(spacing,river_coarse=False):
 result=[]
 for j,(za,zb) in enumerate(zip(Z[:-1],Z[1:])):
  for i,(xa,xb) in enumerate(zip(X[:-1],X[1:])):
   fine=(xa==330 and za==90) or (xa==270 and za==210);step=1 if fine else spacing
   # Spend detail on S1's visible gentle bank; coarsen peripheral river tiles.
   # Three 3m buffer tiles plus a southern river tile keep work below4M.
   if (i,j) in [(3,0),(3,6),(4,6),(5,5)]:step=3
   # conservative overlap selection by dense rectangle probes, includes interior crossing
   xx,zz=np.meshgrid(np.arange(xa,xb+.1,1),np.arange(za,zb+.1,1));touch=bool(np.min(distance(np.stack([xx,zz],axis=-1),PATH))<=10.25)
   if river_coarse and touch and not fine:step=3
   result.append({'i':i,'j':j,'bounds':[xa,za,xb,zb],'step':step,'touch':touch,'uuid':uid(i,j)})
 return result

def make_records(layout):
 lookup={(b['i'],b['j']):b for b in layout};records=[];edges=[]
 for b in layout:
  xa,za,xb,zb=b['bounds'];step=b['step'];xs=np.arange(xa,xb+.01,step);zs=np.arange(za,zb+.01,step);xx,zz=np.meshgrid(xs,zs);hh=heightfield(xx,zz)
  # Restrict mixed-resolution boundaries to common knots (LCM step). The fine side
  # follows the exact coarse piecewise-linear edge, not independent curved samples.
  for di,dj,axis,side in [(-1,0,'z',0),(1,0,'z',-1),(0,-1,'x',0),(0,1,'x',-1)]:
   other=lookup.get((b['i']+di,b['j']+dj))
   if other is None:continue
   knot_step=math.lcm(step,other['step'])
   if axis=='z':
    knots=np.arange(za,zb+.01,knot_step);vals=heightfield(np.full_like(knots,xa if side==0 else xb),knots);hh[:,side]=np.interp(zs,knots,vals)
   else:
    knots=np.arange(xa,xb+.01,knot_step);vals=heightfield(knots,np.full_like(knots,za if side==0 else zb));hh[side,:]=np.interp(xs,knots,vals)
  records.append({'uuid':b['uuid'],'kind':'box','name':f'Axel terrain {b["i"]},{b["j"]}','surface_id':'ground','color':[.38,.43,.29],'collision':'walk','position':[(xa+xb)/2,0,(za+zb)/2],'rotation':[0,0,0],'size':[xb-xa,1,zb-za],'terrain_mesh':{'version':1,'columns':len(xs)-1,'rows':len(zs)-1,'floor':-20,'heights':np.round(hh,6).flatten().tolist(),'holes':[False]*((len(xs)-1)*(len(zs)-1))}})
 return records

def sample(records,x,z):
 for r in records:
  cx,_,cz=r['position'];w,_,d=r['size'];t=r['terrain_mesh'];u=(x-cx+w/2)/w*t['columns'];v=(z-cz+d/2)/d*t['rows']
  if not (0<=u<=t['columns'] and 0<=v<=t['rows']):continue
  ix=min(int(u),t['columns']-1);iz=min(int(v),t['rows']-1);a=u-ix;b=v-iz;hh=np.array(t['heights']).reshape(t['rows']+1,t['columns']+1);p,q,s,k=hh[iz,ix],hh[iz,ix+1],hh[iz+1,ix+1],hh[iz+1,ix]
  return float(p+(q-p)*a+(s-q)*b if a>=b else p+(s-k)*a+(k-p)*b)
 raise ValueError((x,z))
def river_cross_sections(records,river_ids):
 # Offline native carve simulation on the actual grid, then triangle sampling.
 import copy
 carved=copy.deepcopy(records)
 for r in carved:
  if r['uuid'] not in river_ids:continue
  t=r['terrain_mesh'];cx,_,cz=r['position'];w,_,depth=r['size']
  xx,zz=np.meshgrid(np.linspace(cx-w/2,cx+w/2,t['columns']+1),np.linspace(cz-depth/2,cz+depth/2,t['rows']+1))
  d=distance(np.stack([xx,zz],axis=-1),PATH);h=np.array(t['heights']).reshape(d.shape)
  blend=smooth(3.85,9.5,d);t['heights']=np.minimum(h,2.2*(1-blend)+h*blend).ravel().tolist()
 sections=[]
 for z in [215,228,246,267,282]:
  i=int(np.argmin(abs(PATH[:,1]-z)));center=PATH[i];direction=PATH[i+1]-PATH[i-1];direction/=np.linalg.norm(direction);normal=np.array([-direction[1],direction[0]])
  for side in [-1,1]:
   offsets=np.arange(7,36.01,.25);positions=center+side*offsets[:,None]*normal;heights=np.array([sample(carved,*p) for p in positions]);grades=abs(np.diff(heights))/.25
   sections.append({'river_z':float(center[1]),'side':side,'max_d7_to36_m_per_m':float(max(grades)),'max_d9_5_to36_m_per_m':float(max(grades[10:])),'samples':[{'offset':d,'height':sample(carved,*(center+side*d*normal))} for d in [6.8,7,8,9.5,10,14,20,30,36]]})
 return {'method':'Native 14m width, bank2.5, water3, depth0.8 formula applied to recipe vertices; actual grid triangle samples every0.25m. Native waterline transition d3.85..9.5; broad dry bank d>=9.5.','sections':sections,'bridges_after_carve':[{'ends':ends,'heights':[sample(carved,*v) for v in ends]} for ends,target in BRIDGES],'unflooded_land_min_before_carve':min(min(r['terrain_mesh']['heights']) for r in records),'near_water_limit':'With level3.8 banks, theoretical native maximum slope is 0.425m/m and waterline d6.675 is inside water half-width7. Grid and bridge influence are measured above.'}

def main():
 proposals=[]
 for spacing,coarse in [(2,False),(2,True),(3,False)]:
  layout=blocks(spacing,coarse);cost=sum((int((b['bounds'][2]-b['bounds'][0])/b['step'])+1)*(int((b['bounds'][3]-b['bounds'][1])/b['step'])+1) for b in layout if b['touch'])*len(PATH)
  proposals.append({'ordinary_spacing':spacing,'river_only_3m':coarse,'fine_tiles':['axel_terrain_05_04','axel_terrain_06_02'],'buffer_3m_tiles':['axel_terrain_03_00','axel_terrain_03_06','axel_terrain_04_06','axel_terrain_05_05'],'selected_blocks':sum(b['touch'] for b in layout),'path_samples':len(PATH),'work':cost,'within_budget':cost<=4000000})
  if cost<=4000000:break
 assert cost<=4000000
 records=make_records(layout);byid={r['uuid']:r for r in records};seam=0.;grades=[]
 for b in layout:
  r=byid[b['uuid']];t=r['terrain_mesh'];h=np.array(t['heights']).reshape(t['rows']+1,t['columns']+1);gx=np.diff(h,axis=1)/b['step'];gz=np.diff(h,axis=0)/b['step'];grades.extend(np.hypot(gx[:-1,:],gz[:,:-1]).ravel().tolist())
  for di,dj in [(1,0),(0,1)]:
   other=next((v for v in layout if v['i']==b['i']+di and v['j']==b['j']+dj),None)
   if not other:continue
   q=byid[other['uuid']];qh=np.array(q['terrain_mesh']['heights']).reshape(q['terrain_mesh']['rows']+1,q['terrain_mesh']['columns']+1)
   aa=h[:,-1] if di else h[-1,:];bb=qh[:,0] if di else qh[0,:];span=b['bounds'][3]-b['bounds'][1] if di else b['bounds'][2]-b['bounds'][0];grid=np.arange(0,span+.001,.25);seam=max(seam,float(np.max(np.abs(np.interp(grid,np.linspace(0,span,len(aa)),aa)-np.interp(grid,np.linspace(0,span,len(bb)),bb)))))
 route_report=[]
 for i,route in enumerate(ROUTES):
  maximum=0;worst=None
  for a,b in zip(route[:-1],route[1:]):
   aa=np.array(a[:2]);bb=np.array(b[:2]);length=np.linalg.norm(bb-aa);n=max(2,int(math.ceil(length)));points=np.linspace(aa,bb,n+1);hs=[sample(records,*p) for p in points];gg=np.abs(np.diff(hs))/(length/n);mx=float(np.max(gg))
   if mx>maximum:maximum=mx;worst=points[int(np.argmax(gg))].tolist()
  route_report.append({'route':i,'actual_sampled_max_grade_percent':round(maximum*100,3),'worst_xz':worst})
 river_ids=[b['uuid'] for b in layout if b['touch']];shallow_ids=[b['uuid'] for b in layout if b['bounds']==[330,90,390,150]]
 report={'tile_count':len(records),'vertices':sum(len(r['terrain_mesh']['heights']) for r in records),'surface_triangles':sum(r['terrain_mesh']['columns']*r['terrain_mesh']['rows']*2 for r in records),'height_range':[min(min(r['terrain_mesh']['heights']) for r in records),max(max(r['terrain_mesh']['heights']) for r in records)],'maximum_seam_m':seam,'grade_percentiles_percent':dict(zip(['p50','p95','p99','max'],(np.percentile(grades,[50,95,99,100])*100).tolist())),'routes':route_report,'bridges':[{'ends':p,'target':h,'sampled':[sample(records,*v) for v in p]} for p,h in BRIDGES],'spawn':{'xz':[156,209],'ground_y':sample(records,156,209),'pad':[150,203,162,215],'note':'Set actor feet by collision ray after native build; no cross-river spawn route until bridges exist.'},'budget_proposals':proposals,'main_river_not_carved':True,'native_schema_note':'terrain_mesh columns/rows are cell counts; floor -20; no material assigned.','slope_note':'Broad grassy banks replace the S1 cliff mask. Native-carved dry-bank cross-sections are reported separately; underwater bed slopes are not pedestrian bank grades.','river_seed_selection':'Conservative rectangle overlap via 1m probes plus 0.75m tolerance; includes every boundary within native half+bank=9.5m.','s12':{'left_path_y':sample(records,329,121.5),'right_path_y':sample(records,329,129.5),'scene_center_y':sample(records,355,125.5)}}
 report['native_carved_cross_sections']=river_cross_sections(records,river_ids)
 assert len(records)==63 and seam<.000002
 output={'format':'axel_town_terrain_recipe_v1','map_extent':[0,0,450,360],'terrain_extent':[-30,-30,480,390],'records':records,'report':report,'main_river':{'id':'axel_main_river','terrain_ids':river_ids,'points':RIVER,'width':14,'bank_width':2.5,'water_level':3,'depth':.8,'curved':True,'natural_materials':False},'main_river_sampled_points':PATH.tolist(),'s12_stream':{'id':'axel_s12_stream','terrain_ids':shallow_ids,'points':[[337,125.5],[378,125.5]],'width':3.6,'bank_width':1,'water_level':7.45,'depth':.5,'curved':False,'natural_materials':False},'notes':['Main river datum revised to +3m, dry valley base +3.8m; streets and districts remain in original absolute coordinates. This is project supplementary design, not a source-reference measurement.','Native river tool minimum depth is 0.5m, so S12 bed is 6.95m, not initial conceptual 7.15m.','S12 paths at z121.5/129.5 retain ~0.6m between 2m-wide path inner edge and carve envelope; west endpoint x337 leaves dry connection to x329.','No bridge segment interpolated into terrain. Native main-river carve will lower endpoint shoulders; recheck actual endpoint heights after carving before building bridges.','Only touched terrain blocks are river seeds, not all 63. Budget follows existing tool sum(vertices)*path.size.','S1 tile 05_04 and S12 tile 06_02 use 1m grids; north/south boundary tiles03_00,03_06,04_06 and far-southern tile05_05 use3m. Mixed 2m/3m edges use 6m common knots (LCM), 1m/3m edges use 3m knots, ensuring exactly identical piecewise-linear geometry.','No production map, settings, editor budget or materials modified.']}
 OUT.parent.mkdir(parents=True,exist_ok=True);OUT.write_text(json.dumps(output,ensure_ascii=False,separators=(',',':')),encoding='utf8');print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()

