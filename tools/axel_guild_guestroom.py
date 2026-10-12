"""U15/U22 guestroom joinery; metres, -Y front. No runtime interactions."""
import math,json
import bpy
from mathutils import Vector,Matrix
from axel_guild_furnishings import Geometry, ASSETS as COMMON_ASSETS

ASSETS={
 'guest_bed':('弧顶木床与白色床品','U15,U22'),
 'guest_nightstand':('窄高床头柜','U15,U22'),
 'guest_desk':('客房木书桌','U15,U22'),
 'guest_chair':('红色软包高背椅','U15,U22'),
 'guest_low_cabinet':('拱饰低柜','U22'),
 'guest_candlestick':('细杆台式烛台','U15,U22'),
 'guest_candle_sconce':('单烛壁灯','U22'),
}
COMMON_ASSETS.update(ASSETS)

def arch(w,z0,shoulder,rise,n):
 return [(-w/2,z0),(w/2,z0)]+[(w/2*math.cos(i*math.pi/n),shoulder+rise*math.sin(i*math.pi/n)) for i in range(n+1)]

def cushion(g,name,loc,size,mat):
 # Closed rounded superellipsoid, unique poles; no collapsed grid vertices.
 nx,nz=(32,16) if g.quality=='game' else (64,32)
 def sp(x,p):return math.copysign(abs(x)**p,x)
 vs=[(loc[0],loc[1],loc[2]-size[2]/2)]
 for j in range(1,nz):
  t=-math.pi/2+j*math.pi/nz
  for i in range(nx):
   u=i*math.tau/nx
   vs.append((loc[0]+size[0]/2*sp(math.cos(t),.35)*sp(math.cos(u),.28),loc[1]+size[1]/2*sp(math.cos(t),.35)*sp(math.sin(u),.28),loc[2]+size[2]/2*sp(math.sin(t),.45)))
 top=len(vs);vs.append((loc[0],loc[1],loc[2]+size[2]/2));fs=[]
 for i in range(nx):
  k=(i+1)%nx;fs.append((0,1+k,1+i));fs.append((top,1+(nz-2)*nx+i,1+(nz-2)*nx+k))
 for j in range(nz-2):
  for i in range(nx):
   k=(i+1)%nx;a=1+j*nx;fs.append((a+i,a+k,a+nx+k,a+nx+i))
 return g.mesh(name,vs,fs,mat,group='replaceable_upholstery',smooth=True)

def bedsheet(g):
 nx,ny=(32,48) if g.quality=='game' else (64,96);vs=[];surface=[]
 # Piecewise continuous rounded mattress edges, sheet hanging down both sides/foot.
 for side in [0]:
  for j in range(ny+1):
   y=-1.32+2.30*j/ny
   for i in range(nx+1):
    x=-.87+1.74*i/nx;dx=max(0,abs(x)-.55);dy=max(0,-y-.99)
    xx=math.copysign(min(abs(x),.55)+.055*math.tanh(dx/.055),x)
    yy=max(y,-.99)-.055*math.tanh(dy/.055)
    sag=math.sqrt(dx*dx+dy*dy);zz=.66-sag+.006*math.sin(x*16+y*3)*math.cos(y*7)
    if dx:xx+=.006*math.sin(y*12)*min(1,dx/.15)
    if dy:yy+=.006*math.sin(x*14)*min(1,dy/.15)
    surface.append(Vector((xx,yy,zz)))
 for side in [-1,1]:
  for j in range(ny+1):
   for i in range(nx+1):
    tx=surface[j*(nx+1)+min(i+1,nx)]-surface[j*(nx+1)+max(i-1,0)]
    ty=surface[min(j+1,ny)*(nx+1)+i]-surface[max(j-1,0)*(nx+1)+i]
    normal=tx.cross(ty).normalized()
    vs.append(tuple(surface[j*(nx+1)+i]+normal*side*.002))
 n=(nx+1)*(ny+1);fs=[]
 for j in range(ny):
  for i in range(nx):
   k=j*(nx+1)+i;fs.extend([(k,k+1,k+nx+2,k+nx+1),(n+k,n+k+nx+1,n+k+nx+2,n+k+1)])
 edge=list(range(nx+1))+[j*(nx+1)+nx for j in range(1,ny+1)]+[ny*(nx+1)+i for i in range(nx-1,-1,-1)]+[j*(nx+1) for j in range(ny-1,0,-1)]
 for i,k in enumerate(edge):q=edge[(i+1)%len(edge)];fs.append((k,n+k,n+q,q))
 o=g.mesh('Draped_white_sheet',vs,fs,'linen',group='replaceable_bedding',smooth=True)
 for loop in o.data.loops:
  k=loop.vertex_index%n;o.data.uv_layers.active.data[loop.index].uv=((k%(nx+1))/nx,(k//(nx+1))/ny)

def candle(g,xy,z):
 x,y=xy
 g.lathe('Wax_candle',[(0,0),(.020,0),(.021,.22),(.018,.235),(.010,.232),(0,.232)],'wax',(x,y,z),n=24 if g.quality=='game' else 48,group='replaceable_candle')
 g.tube('Wick',[(x,y,z+.23),(x+.002,y,z+.248)],.002,'wick',group='replaceable_candle')
 g.root['light_socket_local']=[x,y,z+.26]
 g.root['flame_included']=False

def build_guestroom(kind,col,mats,quality='game',name=None):
 g=Geometry(kind,col,mats,quality,name or 'guild_'+kind);n=24 if quality=='game' else 64
 if kind=='guest_bed':
  for x in [-.61,.61]:
   for y in [-1.04,1.04]:g.box('Bed_post',(x,y,.22),(.115,.115,.44),'wood',.008)
   g.box('Side_rail',(math.copysign(.54,x),0,.32),(.07,2.08,.15),'wood',.008)
  for i in range(12):g.box('Bed_slat',(0,-.93+i*.169,.41),(1.12,.14,.04),'wood',.002)
  cushion(g,'Mattress',(0,0,.53),(1.12,2.03,.24),'linen')
  for x in [-.61,.61]:g.box('Head_post',(x,1.04,.73),(.115,.12,1.46),'wood',.012)
  for i in range(8):
   x=-.54+i*.154;top=1.26+.19*math.sqrt(max(0,1-(x/.62)**2))
   g.box('Headboard_vertical_plank',(x,1.045,(.43+top)/2),(.15,.07,top-.43),'wood',.003)
  top=[(-.64+1.28*i/n,1.26+.20*math.sqrt(max(0,1-(-1+2*i/n)**2))) for i in range(n+1)]
  outline=top+[(x,z-.095) for x,z in reversed(top)]
  g.extrude('Broad_arched_head_rail',outline,.965,1.125,'wood',.009)
  bedsheet(g);cushion(g,'White_pillow',(0,.71,.74),(.74,.40,.18),'linen')
 elif kind in ['guest_nightstand','guest_low_cabinet']:
  w,d,h=(.48,.43,.96) if kind=='guest_nightstand' else (1.25,.43,.91)
  for x in [-w/2+.04,w/2-.04]:
   for y in [-d/2+.04,d/2-.04]:g.box('Stile_foot',(x,y,(h-.05)/2),(.07,.07,h-.05),'wood',.004)
  g.box('Cabinet_top',(0,0,h-.025),(w+.04,d+.035,.05),'wood',.005)
  for x in [-w/2+.03,w/2-.03]:g.box('Side_panel',(x,0,h*.52),(.04,d-.06,h-.18),'wood',.003)
  g.box('Back',(0,d/2-.025,h*.52),(w-.08,.03,h-.18),'wood',.003)
  g.box('Floor',(0,0,.14),(w-.07,d-.07,.04),'wood',.003)
  g.box('Interior_shelf',(0,.014,.46),(w-.10,d-.095,.024),'wood',.002,group='interior_shelf')
  g.box('Upper_front_rail',(0,-d/2+.023,h-.076),(w-.08,.06,.062),'wood',.003)
  count=1 if kind=='guest_nightstand' else 2
  hinges=[]
  for i in range(count):
   cx=(i-(count-1)/2)*(w-.12)/count;dw=(w-.12)/count-.012;group='door_'+str(i)
   g.box('Door_leaf',(cx,-d/2-.002,.52),(dw,.035,h-.25),'wood_dark',.003,group)
   for k in range(4):g.box('Door_plank',(cx-dw/2+dw*(k+.5)/4,-d/2-.025,.52),(dw/4-.003,.018,h-.27),'wood',.002,group)
   if kind=='guest_low_cabinet':
    pts=[(cx+dw/2*math.cos(t*math.pi/n),-d/2-.044,.67+.10*math.sin(t*math.pi/n)) for t in range(n+1)]
    g.tube('Arched_door_strap',pts,.014,'iron',group=group)
    g.box('Hinge_strap',(cx,-d/2-.049,.34),(dw*.9,.018,.035),'iron',.004,group)
   else:
    for z in [.26,.77]:g.box('Door_crossrail',(cx,-d/2-.048,z),(dw,.035,.05),'wood',.002,group)
   direction=1 if i==0 else -1
   hx=cx-direction*(dw/2+.007);hy=-d/2-.056
   hinges.append({'group':group,'pivot':[hx,hy,0],'angle_degrees':-95*direction})
   # Fixed and moving hinge leaves alternate along a common vertical pin.
   for z in [.30,.72]:
    g.box('Fixed_hinge_leaf',(hx-direction*.030,hy+.012,z),(.048,.014,.068),'iron',.002)
    g.box('Moving_hinge_strap',(hx+direction*.072,hy+.007,z),(.145,.012,.030),'iron',.002,group)
    for segment in range(5):
     zz=z-.037+segment*.015
     g.lathe('Hinge_knuckle',[(.006,zz),(.012,zz),(.012,zz+.013),(.006,zz+.013)],'iron',(hx,hy,0),n=16 if quality=='game' else 32,group=group if segment%2 else 'fixed_hinge')
    g.lathe('Vertical_hinge_pin',[(0,z-.047),(.006,z-.047),(.006,z+.047),(0,z+.047)],'iron',(hx,hy,0),n=16)
    for xx,gg in [(hx-direction*.033,'fixed_hinge'),(hx+direction*.030,group),(hx+direction*.116,group)]:
     head=g.lathe('Hinge_rivet',[(0,0),(.006,0),(.006,.004),(.004,.006),(0,.007)],'iron',(xx,hy-.003,z),n=12 if quality=='game' else 24,group=gg)
     head.rotation_euler.x=math.pi/2
   px=cx+direction*dw*.27
   g.box('Handle_backplate',(px,hy-.012,.51),(.040,.010,.110),'iron',.006,group)
   g.tube('Pull_handle',[(px,hy-.02,.477),(px,hy-.055,.487),(px,hy-.055,.548),(px,hy-.02,.554)],.008,'iron',group=group)
   # Small internal door stop, not a solid block sealing the cavity.
   g.box('Internal_door_stop',(cx,d/2-.072,.80),(dw*.50,.04,.035),'wood',.002)
  g.root['door_hinges_json']=json.dumps(hinges)
  g.root['door_animation_connected']=False
 elif kind=='guest_desk':
  for x in [-.61,.61]:
   for y in [-.285,.285]:g.box('Square_leg',(x,y,.39),(.07,.07,.78),'wood',.004)
  for x in [-.61,.61]:g.box('Side_apron',(x,0,.705),(.05,.57,.14),'wood',.003)
  for y in [-.285,.285]:g.box('Long_apron',(0,y,.705),(1.22,.05,.14),'wood',.003)
  for i in range(4):g.box('Desktop_board',(0,-.30+i*.20,.81),(1.38,.197,.06),'wood',.004)
 elif kind=='guest_chair':
  for x in [-.23,.23]:
   for y in [-.22,.22]:
    g.beam('Chair_leg',(x*1.12,y*1.12,.035),(x,y,.48),.052,'wood',.003)
   g.box('Side_seat_rail',(x,0,.46),(.055,.5,.085),'wood',.004)
   g.beam('Back_post',(x,.22,.42),(x,.32,1.40),.052,'wood',.004)
   g.beam('Side_stretcher',(x*1.06,-.24,.19),(x*1.06,.24,.19),.025,'wood')
  for y in [-.22,.22]:g.box('Seat_rail',(0,y,.46),(.5,.055,.085),'wood',.004)
  cushion(g,'Red_seat',(0,0,.525),(.48,.48,.10),'upholstery')
  # Arched wood perimeter remains visible around the red padded insert.
  g.extrude('Arched_back_frame',arch(.51,.57,1.32,.21,n),.255,.325,'wood',.010)
  g.extrude('Red_padded_back',arch(.42,.64,1.315,.16,n),.215,.256,'upholstery',.012,group='replaceable_upholstery')
  pts=[(x,.211,z) for x,z in arch(.425,.635,1.315,.163,n)]
  g.tube('Upholstery_edge_welt',pts,.004,'welt',closed=True,group='replaceable_upholstery')
 elif kind=='guest_candlestick':
  g.lathe('Weighted_base',[(0,0),(.078,0),(.080,.015),(.065,.030),(.035,.04),(.015,.06),(0,.06)],'brass')
  g.lathe('Slender_stem',[(0,.035),(.017,.035),(.011,.085),(.009,.29),(.017,.31),(0,.31)],'brass')
  g.lathe('Drip_pan_and_socket',[(0,.30),(.044,.30),(.049,.308),(.049,.316),(.040,.312),(.025,.312),(.025,.351),(.021,.351),(.021,.319),(0,.319)],'brass')
  candle(g,(0,0),.332)
 elif kind=='guest_candle_sconce':
  g.box('Wall_plate',(0,.10,.21),(.07,.025,.25),'iron',.008)
  g.tube('Forged_bracket',[(0,.095,.10),(0,.025,.075),(0,-.10,.085),(0,-.14,.14),(0,-.14,.20)],.012,'iron')
  g.lathe('Drip_tray',[(0,.19),(.063,.19),(.068,.20),(.069,.218),(.061,.218),(.057,.203),(0,.203)],'iron',(0,-.14,0))
  g.lathe('Candle_socket',[(.018,.20),(.026,.20),(.026,.25),(.021,.25),(.021,.21),(.018,.21)],'iron',(0,-.14,0))
  candle(g,(0,-.14),.227)
  for z in [.12,.30]:
   screw=g.lathe('Plate_rivet',[(0,0),(.006,0),(.006,.006),(0,.008)],'iron',(0,.081,z),n=12)
   screw.rotation_euler.x=math.pi/2
 bpy.context.view_layer.update()
 deps=bpy.context.evaluated_depsgraph_get()
 bottom=min((o.evaluated_get(deps).matrix_world@Vector(v)).z for o in g.parts for v in o.evaluated_get(deps).bound_box)
 root,parts=g.finish()
 if kind.startswith('guest_candle'):
  # finish grounds wall fittings too; retain the corresponding local light socket.
  socket=list(root['light_socket_local']);socket[2]-=bottom;root['light_socket_local']=socket
  root['runtime_light_connected']=False
 return root,parts

def rig_cabinet(root,parts,animate=True):
 """Independent material meshes share a hinge pivot and synchronized named clips.

 No static material merge crosses a door group. Direct mesh pivots also survive
 whitebox instance copying without relying on hidden constraint objects.
 """
 if 'door_hinges_json' not in root:return
 bpy.context.scene.frame_set(1);bpy.context.view_layer.update()
 hinges={v['group']:v for v in json.loads(root['door_hinges_json'])}
 for index,o in enumerate(parts):
  group=o.get('replaceable_group','static')
  if group not in hinges:continue
  h=hinges[group];pivot=Vector(h['pivot'])
  o.data.transform(Matrix.Translation(-pivot)@o.matrix_basis)
  o.matrix_basis=Matrix.Translation(pivot)
  o['hinge_pivot_local']=list(pivot);o['hinge_axis_local']=[0,0,1]
  o['door_group']=group;o['open_angle_degrees']=h['angle_degrees']
  if animate:
   for clip,values,start in [('Open',(0,h['angle_degrees']),1),('Close',(h['angle_degrees'],0),32)]:
    o.animation_data_create();o.animation_data.action=None
    for frame,value in [(1,values[0]),(31,values[1])]:
     o.rotation_euler.z=math.radians(value);o.keyframe_insert(data_path='rotation_euler',frame=frame)
    action=o.animation_data.action;action.name=root.name+'_'+group+'_'+clip+'_'+str(index)
    slot=o.animation_data.action_slot;o.animation_data.action=None
    track=o.animation_data.nla_tracks.new();track.name=group+'_'+clip
    strip=track.strips.new(track.name,start,action);strip.action_slot=slot;strip.extrapolation='NOTHING'
   o.rotation_euler.z=0
 root['door_animation_connected']=animate
 root['door_opening_degrees']=95
 root['runtime_interaction_connected']=False
 bpy.context.scene.frame_set(1);bpy.context.view_layer.update()
