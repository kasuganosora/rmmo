"""Second guild furnishing set from U02/U03/U07–U12; front -Y, metric.

Reference screenshots establish appearance; dimensions/back supports are proposals.
Geometric builders are shared by standalone exports and the offline whitebox.
"""
import math
import json
import bpy
import bmesh
from mathutils import Vector

ASSETS={
 'quest_board_blank':('任务招募板·空板','U09'),
 'quest_board_filled':('任务招募板·张贴版','U09'),
 'registration_crystal':('水晶登记装置','U10,U11,U12'),
 'round_notice_board':('圆顶告示立牌','U08,U12'),
 'sloped_notice_stand':('斜面告示架','U12'),
 'entry_runner':('入口花纹长毯','U02'),
 'round_planter':('圆柱盆栽容器','U02'),
 'bar_stool':('吧台软座圆凳','U07'),
 'bottle_tall':('长颈酒瓶','U07'),
 'bottle_round':('圆腹酒瓶','U07'),
 'bottle_squat':('矮肩酒瓶','U07'),
 'tankard':('带柄酒杯','U03'),
 'dining_plate':('餐盘','U03'),
 'serving_jug':('陶制酒壶','U07'),
 'registration_counter':('登记石柜台模块','U08,U12'),
}


class Geometry:
 def __init__(self,kind,col,mats,quality,name):
  self.col,self.mats,self.quality=col,mats,quality
  self.root=bpy.data.objects.new(name,None);col.objects.link(self.root);self.parts=[]
  self.root['asset_id']='guild_'+kind;self.root['independent_prop']=True
  self.root['structural_wall']=False;self.root['reference_ids']=ASSETS[kind][1]
  self.root['dimensions_are_proposed']=True;self.root['front_axis']='-Y'
  self.root['runtime_interaction_connected']=False
  self.steps=48 if quality=='game' else 96

 def mesh(self,label,vs,fs,mat,bevel=0,group='static',smooth=False):
  me=bpy.data.meshes.new(label);me.from_pydata(vs,[],fs);me.update()
  bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
  obj=bpy.data.objects.new(self.root.name+'_'+label,me);self.col.objects.link(obj);obj.parent=self.root
  me.materials.append(self.mats[mat]);obj['collision_review']=True;obj['replaceable_group']=group
  obj['prop_part']=label;obj['independent_prop']=True;obj['structural_wall']=False
  uv=me.uv_layers.new(name='SurfaceUV')
  for p in me.polygons:
   p.use_smooth=smooth
   axes=[i for i in range(3) if i!=max(range(3),key=lambda j:abs(p.normal[j]))]
   for li in p.loop_indices:
    co=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]],co[axes[1]])
  if bevel:
   mod=obj.modifiers.new('Physical softened edges','BEVEL');mod.width=bevel;mod.segments=2 if self.quality=='game' else 4
   mod=obj.modifiers.new('Preserve broad face normals','WEIGHTED_NORMAL');mod.keep_sharp=True
  self.parts.append(obj);return obj

 def box(self,label,loc,size,mat,bevel=.003,group='static'):
  x,y,z=loc;w,d,h=size
  return self.mesh(label,[(x+a*w/2,y+b*d/2,z+c*h/2) for c in [-1,1] for b in [-1,1] for a in [-1,1]],
    [(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)],mat,bevel,group)

 def beam(self,label,a,b,width,mat,bevel=.002):
  a,b=Vector(a),Vector(b);obj=self.box(label,(0,0,0),(width,width,(b-a).length),mat,bevel)
  obj.location=(a+b)/2;obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return obj

 def lathe(self,label,profile,mat,loc=(0,0,0),n=None,group='static'):
  # Profile is a closed radial section (r,z); no degenerate axis-ring vertices.
  n=n or self.steps;vs=[];rings=[]
  for r,z in profile:
   if r<1e-7:rings.append([len(vs)]);vs.append((0,0,z))
   else:
    rings.append(list(range(len(vs),len(vs)+n)))
    vs.extend([(r*math.cos(i*math.tau/n),r*math.sin(i*math.tau/n),z) for i in range(n)])
  fs=[]
  for j in range(len(rings)):
   a,b=rings[j],rings[(j+1)%len(rings)]
   if len(a)==len(b)==1:continue
   for i in range(n):
    k=(i+1)%n
    fs.append((a[0],b[k],b[i]) if len(a)==1 else (a[i],a[k],b[0]) if len(b)==1 else (a[i],a[k],b[k],b[i]))
  obj=self.mesh(label,vs,fs,mat,group=group,smooth=True);obj.location=loc
  # Smooth around the axis, but keep horizontal tops/undersides planar.
  for p in obj.data.polygons:p.use_smooth=abs(p.normal.z)<.98
  return obj

 def ring(self,label,r,z,thick,width,mat,loc=(0,0,0),group='static'):
  return self.lathe(label,[(r-width/2,z-thick/2),(r+width/2,z-thick/2),
                         (r+width/2,z+thick/2),(r-width/2,z+thick/2)],mat,loc,group=group)

 def tube(self,label,points,r,mat,closed=False,group='static'):
  # Parallel-frame tube along an explicit path, then cap open ends.
  sides=8 if self.quality=='game' else 12;vs=[];previous_axis=None
  for i,p in enumerate(points):
   before=Vector(points[(i-1)%len(points)] if closed or i else points[i])
   after=Vector(points[(i+1)%len(points)] if closed or i<len(points)-1 else points[i])
   tangent=(after-before).normalized()
   # Parallel transport avoids a 90/180 degree frame flip at vertical tangents,
   # which otherwise creates pinched handles and brass moulding seams.
   axis=previous_axis-tangent*previous_axis.dot(tangent) if previous_axis is not None else tangent.cross(Vector((0,0,1)))
   if axis.length<.01:axis=tangent.cross(Vector((0,1,0)))
   axis.normalize();previous_axis=axis.copy();other=tangent.cross(axis).normalized()
   vs.extend([tuple(Vector(p)+r*(axis*math.cos(j*math.tau/sides)+other*math.sin(j*math.tau/sides))) for j in range(sides)])
  fs=[]
  for i in range(len(points) if closed else len(points)-1):
   a=i*sides;b=((i+1)%len(points))*sides
   for j in range(sides):k=(j+1)%sides;fs.append((a+j,a+k,b+k,b+j))
  if not closed:fs.extend([tuple(reversed(range(sides))),tuple(range(len(vs)-sides,len(vs)))])
  return self.mesh(label,vs,fs,mat,group=group,smooth=True)

 def extrude(self,label,outline,y0,y1,mat,bevel=.003,group='static'):
  n=len(outline)
  return self.mesh(label,[(x,y,z) for y in [y0,y1] for x,z in outline],
    [tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],mat,bevel,group)

 def finish(self):
  bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
  bottom=min((o.evaluated_get(deps).matrix_world@Vector(v)).z for o in self.parts for v in o.evaluated_get(deps).bound_box)
  for o in self.parts:o.location.z-=bottom
  return self.root,self.parts


def rounded_outline(w,h,z0=0,r=.05,n=5):
 pts=[]
 for cx,cz,start in [(w/2-r,z0+h-r,0),(-w/2+r,z0+h-r,90),(-w/2+r,z0+r,180),(w/2-r,z0+r,270)]:
  for j in range(n+1):a=math.radians(start+j*90/n);pts.append((cx+r*math.cos(a),cz+r*math.sin(a)))
 return pts


def front_uv(obj):
 xs=[v.co.x for v in obj.data.vertices];zs=[v.co.z for v in obj.data.vertices]
 for loop in obj.data.loops:
  co=obj.data.vertices[loop.vertex_index].co
  obj.data.uv_layers.active.data[loop.index].uv=((co.x-min(xs))/(max(xs)-min(xs)),(co.z-min(zs))/(max(zs)-min(zs)))


def smooth_outline(points,steps=3):
 # Quadratic corner fillets retain the carved outline without angular silhouette.
 result=[]
 for i,p in enumerate(points):
  previous=Vector(points[i-1]);current=Vector(p);following=Vector(points[(i+1)%len(points)])
  a=current.lerp(previous,.24);b=current.lerp(following,.24)
  for j in range(steps+1):
   t=j/steps;v=(1-t)**2*a+2*t*(1-t)*current+t*t*b;result.append(tuple(v))
 return result


def build_furnishing(kind,col,mats,quality='game',name=None):
 g=Geometry(kind,col,mats,quality,name or 'guild_'+kind);R=g.root
 if kind.startswith('quest_board'):
  # Board itself 3.6 x 2.5m, raised 0.75m by separate authored rear support.
  outline=[(-1.8,.85),(-1.70,.85),(-1.70,.75),(1.70,.75),(1.70,.85),(1.8,.85),
           (1.8,3.15),(1.70,3.15),(1.70,3.25),(-1.70,3.25),(-1.70,3.15),(-1.8,3.15)]
  g.extrude('Red_brown_board',outline,-.06,.06,'redwood',.014)
  for inset,radius in [(0,.017),(.11,.014),(.19,.011)]:
   pts=[(x*(1-inset/1.8),-.078-inset*.02,2+(z-2)*(1-inset/1.25)) for x,z in outline]
   g.tube('Stepped_brass_moulding',pts,radius,'brass',True)
  for z in [.82,3.18]:
   for x in [-1.04,1.04]:
    for dx in [-.049,-.016,.016,.049]:
     g.tube('Bundled_corner_clasp',[(x+dx,.066,z-.07),(x+dx,-.08,z-.07),(x+dx,-.095,z+.07),(x+dx,.065,z+.07)],.009,'brass')
  # Replaceable top/bottom ornamental inscription strip uses original invented marks.
  for z in [.87,3.11]:
   o=g.box('Ornament_strip',(0,-.082,z),(1.55,.014,.14),'inscription',.002)
   for p in o.data.polygons:
    for li in p.loop_indices:
     co=o.data.vertices[o.data.loops[li].vertex_index].co;o.data.uv_layers.active.data[li].uv=(co.x/1.55+.5,(co.z-z)/.14+.5)
  for x in [-1.40,1.40]:
   g.box('Rear_support_post',(x,.074,.83),(.10,.10,1.66),'wood')
   g.box('Rear_foot',(x,.075,.035),(.17,.50,.07),'wood')
   g.beam('Rear_diagonal',(x,.29,.06),(x,.10,.72),.065,'wood')
  slots=[]
  if kind.endswith('filled'):
   layout=[(-1.26,2.66,.45,.37),(-.68,2.62,.35,.53),(-.14,2.70,.37,.35),(.38,2.55,.34,.61),(1.15,2.65,.37,.46),
           (-1.24,1.98,.35,.54),(-.72,2.02,.41,.49),(-.11,2.03,.39,.54),(.85,2.07,.33,.56),(1.31,1.91,.28,.41),
           (-1.11,1.35,.45,.33),(-.37,1.42,.39,.55),(.17,1.46,.35,.55),(.76,1.39,.34,.51),(1.27,1.35,.39,.29)]
   for i,(x,z,w,h) in enumerate(layout):
    card=g.box('Replaceable_paper_'+str(i),(x,-.098,z),(w,.002,h),'papers',.0007,group='quest_papers')
    card.rotation_euler.y=math.radians([-2,1,0,2,-1][i%5])
    uv=card.data.uv_layers.active
    for p in card.data.polygons:
     for li in p.loop_indices:
      co=card.data.vertices[card.data.loops[li].vertex_index].co
      uv.data[li].uv=((i%4+(co.x-x)/w+.5)/4,(3-i//4+(co.z-z)/h+.5)/4)
    for vertex in card.data.vertices:vertex.co-=Vector((x,-.098,z))
    card.location=(x,-.098,z)
    # Independent paper identity remains in metadata even when game cards share a draw call.
    slots.append({'id':i,'position_blender':[x,-.098,z],'size_m':[w,h],'atlas_tile':i})
   R['paper_slots_json']=json.dumps(slots)
  R['board_variant']='filled' if slots else 'blank';R['interaction_point_blender']=[0,-.8,1.55]
  R['rear_support_is_authored']=True
 elif kind=='registration_crystal':
  g.box('Base_lower',(0,0,.025),(.66,.45,.05),'dark',.009,'base')
  g.box('Base_upper',(0,0,.063),(.58,.39,.048),'dark',.006,'base')
  g.box('Base_top_inset',(0,0,.089),(.47,.29,.007),'dark_inset',.006,'base')
  for side in [-1,1]:
   # Carved forked supports; broad crescent shoulders visible in U10.
   shape=[(side*x,z) for x,z in [(.20,.078),(.29,.078),(.27,.13),(.26,.24),(.285,.33),(.26,.41),(.34,.48),(.37,.53),(.32,.59),(.275,.58),(.25,.53),(.21,.49),(.19,.43),(.225,.36),(.205,.25),(.22,.14)]]
   support=g.extrude('Carved_side_support',smooth_outline(shape,4),-.092,.092,'dark',.006,'supports')
   for face in support.data.polygons:face.use_smooth=abs(face.normal.y)<.90
   for z in [.22,.32]:g.extrude('Support_inlay',[(side*.213,z-.05),(side*.265,z),(side*.218,z+.043)],-.098,-.093,'dark_inset',.001,'supports')
   g.extrude('Blue_lower_insert',[(side*.135,.095),(side*.218,.095),(side*.218,.22)],-.102,-.093,'blueglass',.002,'inlays')
   g.extrude('Blue_upper_insert',[(side*.218,.40),(side*.282,.47),(side*.205,.51)],-.099,-.09,'blueglass',.002,'inlays')
  # Globe diameter .42m, top at .86m; exposed top touch area.
  bpy.ops.mesh.primitive_uv_sphere_add(segments=64 if quality=='game' else 128,ring_count=32 if quality=='game' else 64,radius=.21)
  sphere=bpy.context.object
  for c in list(sphere.users_collection):c.objects.unlink(sphere)
  col.objects.link(sphere);sphere.parent=R;sphere.location=(0,0,.65);sphere.name=R.name+'_Crystal_sphere'
  sphere.data.materials.append(mats['crystal']);sphere['replaceable_group']='crystal';sphere['collision_review']=False
  for p in sphere.data.polygons:p.use_smooth=True
  g.parts.append(sphere)
  for z,r,w,mat in [(.51,.234,.040,'steel'),(.57,.256,.016,'brass'),(.665,.272,.043,'steel'),(.723,.220,.009,'brass')]:
   g.ring('Orbital_ring',r,z,.013,w,mat,group='ring_frames')
  for a in [i*math.tau/6 for i in range(6)]:
   x,y=.271*math.cos(a),.271*math.sin(a)
   g.lathe('Axle',[(0,.56),(.012,.56),(.012,.69),(0,.69)],'brass',(x,y,0),n=16,group='ring_hardware')
   g.ring('Handwheel_rim',.031,.634,.005,.005,'brass',(x,y,0),'ring_hardware')
   for j in range(5):
    b=j*math.tau/5;g.beam('Handwheel_spoke',(x,y,.634),(x+.028*math.cos(b),y+.028*math.sin(b),.634),.0035,'brass',.0004)
   g.lathe('Fastener',[(0,.678),(.012,.678),(.012,.687),(0,.687)],'brass',(x,y,0),n=12,group='ring_hardware')
   g.box('Fastener_slot',(x,y,.6875),(.014,.002,.001),'dark',.0002,'ring_hardware')
  # Four curled, pointed gold plates seated on the upper small ring.
  motif=[(-.042,0),(-.036,.016),(-.018,.013),(-.010,.043),(0,.079),(.01,.043),(.023,.018),(.046,.012),(.038,0),(.015,.004),(0,.002),(-.018,.004)]
  for a in [math.pi/4+i*math.pi/2 for i in range(4)]:
   o=g.extrude('Gold_crown_plate',smooth_outline([(x*1.6,.718+z*1.25) for x,z in motif],3),-.223,-.216,'brass',.0015,'gold_ornaments');o.rotation_euler.z=a
  for z,r in [(.408,.065),(.373,.047),(.345,.031)]:
   g.lathe('Suspended_blue_disc',[(0,z-.005),(r*.88,z-.005),(r,z),(r*.90,z+.006),(0,z+.006)],'blueglass',group='pendant')
  g.lathe('Pendant_tip',[(0,.275),(.004,.275),(.007,.34),(0,.34)],'brass',n=16,group='pendant')
  R['touch_point_blender']=[0,0,.86];R['idle_emission']=.12;R['active_emission']=1.0
  R['countertop_prop']=True;R['gear_animation_inferred']=False
 elif kind in ['round_notice_board','sloped_notice_stand']:
  if kind=='round_notice_board':
   shape=[(-.30,.30),(.30,.30),(.30,1.34)]+[(.30*math.cos(i*math.pi/20),1.34+.19*math.sin(i*math.pi/20)) for i in range(21)]
   g.extrude('Round_top_frame',shape,-.033,.033,'metal',.008)
   inner=[(x*.89,.90+(z-.90)*.94) for x,z in shape]
   front_uv(g.extrude('Parchment_notice',inner,-.039,-.034,'notice',.002,'notice_surface'))
   for x in [-.20,.20]:
    g.beam('Front_leg',(x,-.14,0),(x,0,.48),.045,'metal')
    g.beam('Rear_leg',(x,.24,0),(x,.015,1.05),.045,'metal')
  else:
   g.box('Foot',(0,0,.025),(.47,.38,.05),'metal',.006)
   g.beam('Column',(0,.02,.05),(0,.02,.79),.065,'metal')
   a=math.radians(25)
   o=g.box('Sloping_board',(0,0,0),(.57,.06,.48),'metal',.006);o.location=(0,0,1.0);o.rotation_euler.x=-a
   o=g.box('Notice_surface',(0,-.034,0),(.52,.004,.425),'notice',.002,'notice_surface');front_uv(o);o.location=(0,0,1.0);o.rotation_euler.x=-a
  R['notice_content_replaceable']=True
 elif kind=='entry_runner':
  # Flat functional runner with a slight irregular edge; real thin closed volume.
  w,d=2.5,5.8;nx,ny=8,24;vs=[]
  for layer in [0,1]:
   for j in range(ny+1):
    for i in range(nx+1):
     x=-w/2+w*i/nx;y=-d/2+d*j/ny
     z=(.009+.0015*math.sin(j*.9+i*.7)) if layer else .001
     vs.append((x,y,z))
  stride=nx+1;n=(nx+1)*(ny+1);fs=[]
  for j in range(ny):
   for i in range(nx):
    k=j*stride+i;fs.extend([(k,k+stride,k+stride+1,k+1),(n+k,n+k+1,n+k+stride+1,n+k+stride)])
  edge=list(range(nx+1))+[j*stride+nx for j in range(1,ny+1)]+[ny*stride+i for i in range(nx-1,-1,-1)]+[j*stride for j in range(ny-1,0,-1)]
  for i,k in enumerate(edge):j=edge[(i+1)%len(edge)];fs.append((k,j,n+j,n+k))
  o=g.mesh('Woven_runner',vs,fs,'rug',group='textile')
  for p in o.data.polygons:
   for li in p.loop_indices:
    co=o.data.vertices[o.data.loops[li].vertex_index].co;o.data.uv_layers.active.data[li].uv=(co.x/w+.5,co.y/d+.5)
  o['collision_review']=False
 elif kind=='round_planter':
  g.lathe('Metal_planter',[(0,0),(.255,0),(.29,.035),(.275,.10),(.285,.61),(.31,.64),(.31,.685),(.275,.685),(.264,.65),(.249,.075),(0,.075)],'metal')
  g.ring('Rolled_rim',.30,.682,.025,.036,'brass')
  for i in range(32):
   a=i*math.tau/32
   for z,shift in [(.606,0),(.637,.5)]:
    x,y=.29*math.cos(a+shift*math.tau/32),.29*math.sin(a+shift*math.tau/32)
    o=g.box('Checker_inlay',(0,0,0),(.035,.006,.025),'terracotta',0 if quality=='game' else .001)
    o.location=(x,y,z);o.rotation_euler.z=a+shift*math.tau/32-math.pi/2
  g.lathe('Soil',[(0,.615),(.258,.615),(.258,.631),(0,.631)],'soil')
  R['plant_socket_blender']=[0,0,.63];R['vegetation_included']=False
 elif kind=='bar_stool':
  g.lathe('Padded_round_seat',[(0,.685),(.205,.685),(.223,.70),(.225,.745),(.207,.764),(0,.764)],'purple')
  g.lathe('Seat_frame',[(0,.66),(.225,.66),(.225,.685),(0,.685)],'wood')
  for a in [math.pi/4+i*math.pi/2 for i in range(4)]:
   g.beam('Splayed_stool_leg',(.18*math.cos(a),.18*math.sin(a),.012),(.13*math.cos(a),.13*math.sin(a),.67),.047,'wood')
  g.ring('Footrest',.175,.27,.025,.018,'steel')
  R['seat_socket_blender']=[0,0,.764]
 elif kind.startswith('bottle_'):
  if kind=='bottle_tall':profile=[(0,0),(.044,0),(.049,.01),(.049,.20),(.043,.22),(.018,.255),(.016,.34),(.021,.34),(.021,.355),(.013,.355),(.012,.25),(.039,.205),(.039,.016),(0,.016)]
  elif kind=='bottle_round':profile=[(0,0),(.036,0),(.063,.035),(.072,.09),(.055,.14),(.020,.18),(.018,.27),(.024,.274),(.024,.287),(.012,.287),(.012,.18),(.047,.133),(.060,.09),(.049,.04),(0,.016)]
  else:profile=[(0,0),(.052,0),(.064,.02),(.064,.17),(.03,.21),(.018,.245),(.018,.29),(.024,.294),(.024,.305),(.012,.305),(.012,.243),(.026,.215),(.052,.17),(.052,.03),(0,.015)]
  obj=g.lathe('Glass_bottle',smooth_outline(profile,2), 'bottle',n=48 if quality=='game' else 96)
  h=max(z for r,z in profile)
  g.lathe('Cork',[(0,h-.006),(.011,h-.006),(.013,h+.013),(0,h+.013)],'cork',n=16)
  # Thin closed label conforms to the bottle shoulder/body rather than floating.
  outer=profile[:next(i for i,(r,z) in enumerate(profile) if z==h)+1]
  def radius(z):
   for (r0,z0),(r1,z1) in zip(outer,outer[1:]):
    if z0<=z<=z1 and z1>z0:return r0+(r1-r0)*(z-z0)/(z1-z0)
   return max(r for r,z in outer)
  vs=[];nu,nv=12,6
  for thickness in [.0004,.0009]:
   for j in range(nv+1):
    z=h*.40-.035+.070*j/nv;r=radius(z)+thickness
    for i in range(nu+1):
     a=(i/nu-.5)*1.08;vs.append((r*math.sin(a),-r*math.cos(a),z))
  n=(nu+1)*(nv+1);fs=[]
  for j in range(nv):
   for i in range(nu):
    k=j*(nu+1)+i;fs.extend([(k,k+1,k+nu+2,k+nu+1),(n+k,n+k+nu+1,n+k+nu+2,n+k+1)])
  edge=list(range(nu+1))+[j*(nu+1)+nu for j in range(1,nv+1)]+[nv*(nu+1)+i for i in range(nu-1,-1,-1)]+[j*(nu+1) for j in range(nv-1,0,-1)]
  for i,k in enumerate(edge):q=edge[(i+1)%len(edge)];fs.append((k,q,n+q,n+k))
  label=g.mesh('Conforming_label',vs,fs,'label',group='label',smooth=True)
  for loop in label.data.loops:
   idx=loop.vertex_index%n;label.data.uv_layers.active.data[loop.index].uv=((idx%(nu+1))/nu,(idx//(nu+1))/nv)
 elif kind=='tankard':
  g.lathe('Cup',[(0,0),(.06,0),(.067,.018),(.070,.18),(.065,.19),(.058,.188),(.058,.026),(0,.026)],'pewter')
  g.ring('Cup_lip',.065,.189,.009,.012,'pewter')
  g.tube('Handle',[(.065+.055*math.sin(i*math.pi/16),0,.105+.062*math.cos(i*math.pi/16)) for i in range(17)],.011,'pewter')
 elif kind=='dining_plate':
  g.lathe('Glazed_plate',[(0,.006),(.069,.006),(.072,0),(.085,0),(.086,.007),(.13,.016),(.142,.03),(.143,.039),(.133,.041),(.11,.021),(0,.017)],'ceramic')
 elif kind=='serving_jug':
  g.lathe('Ceramic_jug',[(0,0),(.052,0),(.072,.026),(.078,.10),(.064,.18),(.039,.225),(.038,.28),(.053,.289),(.049,.301),(.032,.295),(.027,.226),(.054,.18),(.066,.10),(.057,.036),(0,.017)],'ceramic')
  g.tube('Jug_handle',[(.045+.058*math.sin(i*math.pi/24),0,.175+.087*math.cos(i*math.pi/24)) for i in range(25)],.012,'ceramic')
 elif kind=='registration_counter':
  # Reusable 2.275m segment: not a generic timber bar, screenshot masonry apron.
  body=g.box('Stone_body',(0,0,.48),(2.275,.58,.96),'stone',.006)
  for loop in body.data.uv_layers.active.data:loop.uv*=.5
  g.box('Dark_countertop',(0,-.02,1.04),(2.275,.80,.12),'counter_stone',.006,'countertop')
  # Stone courses are carried by the scanned PBR maps, not duplicated as bricks.
  for side in [-1,1]:
   outline=[(side*1.105,.65),(side*1.105,.98),(side*.76,.98)]
   outline += [(side*(.76+.27*math.sin(i*math.pi/16)),.71+.27*math.cos(i*math.pi/16)) for i in range(1,9)]
   outline += [(side*1.035,.65)]
   g.extrude('Curved_stone_corbel',outline,-.41,-.31,'pale_stone',.004)
  R['modular_length_m']=2.275;R['countertop_height_m']=1.10
 return g.finish()
