"""Independent U04/U07 textiles and authored L1 sanitary fittings, metric -Y front."""
import math
import bpy
from mathutils import Vector
from axel_guild_furnishings import Geometry, smooth_outline, ASSETS as COMMON_ASSETS

ASSETS={
 'hall_canopy':('屋架悬垂图案织物','U04'),
 'wall_tapestry':('大幅壁挂织毯','U04; hanging orientation proposed'),
 'long_banner':('窄长穗饰垂幡','U04,U07'),
 'washstand':('双盆木制盥洗台','L1 authored; NT426464'),
 'wash_basin':('独立石质洗手盆','L1 authored'),
 'brass_faucet':('黄铜鹅颈龙头','L1 authored fantasy plumbing'),
 'privy_seat':('木座厕位','L1 authored; EH garderobe'),
 'shower_tray':('石质淋浴底盘','L1 authored'),
 'shower_column':('黄铜淋浴立管','L1 authored fantasy plumbing'),
 'privacy_screen':('木框布面隔屏','L1 authored'),
 'towel_rail':('毛巾架与垂巾','L1 authored'),
 'wash_ewer':('盥洗陶壶','L1 authored; NT14168'),
 'soap_dish':('陶制皂碟','L1 authored; NT14168'),
}
COMMON_ASSETS.update(ASSETS)

def cloth(g,name,width,height,position,mat,nx,ny,canopy=False,swallow=False):
    # Closed 4mm cloth, gently draped; dense master and sampled game share surface.
    vs=[];towel='towel' in name.lower()
    for side in [-1,1]:
        for j in range(ny+1):
            v=j/ny
            for i in range(nx+1):
                u=i/nx;x=(u-.5)*width
                if canopy:
                    y=(v-.5)*height;z=.56*(2*v-1)**2+.07*math.sin(u*math.tau*3)*math.sin(v*math.pi)+side*.002
                else:
                    bottom=.30*(1-abs(2*u-1)) if swallow else (.005 if towel else .025)*math.cos(u*math.tau*2)
                    z=bottom+(height-bottom)*v
                    amplitude=.008 if towel else min(.065,width*.05)
                    folds=2 if towel else 4
                    y=amplitude*math.sin(u*math.tau*folds+.35*(1-v))*(.5+.5*(1-v))+(.018 if towel else .09)*math.sin(v*math.pi)+side*.002
                vs.append((x+position[0],y+position[1],z+position[2]))
    n=(nx+1)*(ny+1);fs=[]
    for j in range(ny):
        for i in range(nx):
            k=j*(nx+1)+i;fs += [(k,k+nx+1,k+nx+2,k+1),(n+k,n+k+1,n+k+nx+2,n+k+nx+1)]
    edge=list(range(nx+1))+[j*(nx+1)+nx for j in range(1,ny+1)]+[ny*(nx+1)+i for i in range(nx-1,-1,-1)]+[j*(nx+1) for j in range(ny-1,0,-1)]
    for a,k in enumerate(edge):q=edge[(a+1)%len(edge)];fs.append((k,q,n+q,n+k))
    o=g.mesh(name,vs,fs,mat,group='replaceable_textile',smooth=True);o['collision_review']=False
    uv=o.data.uv_layers.active
    for loop in o.data.loops:
        k=loop.vertex_index%n;uv.data[loop.index].uv=((k%(nx+1))/nx,(k//(nx+1))/ny)
    vg=o.vertex_groups.new(name='WindWeight')
    for idx in range(len(vs)):
        v=(idx%n)//(nx+1)/ny;weight=math.sin(math.pi*v) if canopy else (1-v)**1.4
        vg.add([idx],weight,'REPLACE')
    weight_attribute=o.data.attributes.new(name='_WIND_WEIGHT',type='FLOAT',domain='POINT')
    for idx,c in enumerate(weight_attribute.data):c.value=vg.weight(idx)
    o['wind_encoding']='custom _WIND_WEIGHT; 0 fixed / 1 free; runtime shader not connected'
    return o

def cut(g,obj,loc,scale):
    bpy.ops.mesh.primitive_cylinder_add(vertices=64 if g.quality=='game' else 96,radius=1,depth=1,location=loc)
    cutter=bpy.context.object;cutter.scale=scale
    bpy.context.view_layer.objects.active=obj
    mod=obj.modifiers.new('Actual opening','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
    bpy.ops.object.modifier_move_up(modifier=mod.name)
    bpy.ops.object.modifier_move_up(modifier=mod.name)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter,do_unlink=True)

def build_fitting(kind,col,mats,quality='game',name=None):
    g=Geometry(kind,col,mats,quality,name or 'guild_'+kind);R=g.root
    R['authored_sanitary_design']=kind not in ['hall_canopy','wall_tapestry','long_banner']
    R['runtime_water_connected']=False
    fine=quality=='master'
    if kind in ['hall_canopy','wall_tapestry','long_banner']:
        if kind=='hall_canopy':
            cloth(g,'Suspended_woven_panel',4.2,3.2,(0,0,0),'tapestry',80 if fine else 40,64 if fine else 32,canopy=True)
            for y in [-1.6,1.6]:
                g.tube('Support_pole',[(-2.28,y,.57),(2.28,y,.57)],.035,'wood',group='support')
                for x in [-2.10,2.10]:g.tube('Suspension_cord',[(x,y,.57),(x,y,.92)],.009,'rope',group='support')
            R['ceiling_mount_points']=[[-2.1,-1.6,.92],[2.1,-1.6,.92],[-2.1,1.6,.92],[2.1,1.6,.92]]
        else:
            w,h=(2.2,3.8) if kind=='wall_tapestry' else (.78,4.8)
            base=.60 if kind=='long_banner' else .22;delta=base-.22
            cloth(g,'Embroidered_hanging',w,h,(0,0,base),'tapestry' if kind=='wall_tapestry' else 'banner',64 if fine else 32,112 if fine else 56,swallow=kind=='long_banner')
            g.tube('Top_crossbar',[(-w/2-.15,0,h+base+.06),(w/2+.15,0,h+base+.06)],.032,'wood',group='support')
            for x in [-w*.36,w*.36]:g.tube('Hanging_loop',[(x,.02,h+base-.02),(x,.12,h+base+.21),(x,.15,h+base-.02)],.009,'rope',group='support')
            for x in [-w/2,w/2]:
                g.lathe('Tassel_cap',[(0,.15+delta),(.046,.15+delta),(.052,.19+delta),(.03,.23+delta),(0,.23+delta)],'brass',(x,0,0),n=24)
                for i in range(12):
                    a=i*math.tau/12
                    g.tube('Tassel_thread',[(x+.038*math.cos(a),.038*math.sin(a),.155+delta),(x+.048*math.cos(a),.045*math.sin(a),.012)],.0035,'rope',group='fringe')
            R['mount_height_m']=h+base+.21
        R['textile_thickness_m']=.004;R['pattern_original']=True
    elif kind=='washstand':
        top=g.box('Timber_top',(0,0,.79),(1.70,.76,.10),'wood',.012)
        for x in [-.43,.43]:cut(g,top,(x,-.035,.80),(.095,.095,.35))
        for x in [-.72,.72]:
            for y in [-.29,.29]:g.box('Leg',(x,y,.35),(.09,.09,.70),'wood',.007)
        for y in [-.31,.31]:g.box('Apron',(0,y,.66),(1.5,.055,.19),'wood',.006)
        for i in range(5):g.box('Lower_shelf',(0,-.235+i*.1175,.23),(1.51,.11,.06),'wood',.005)
        g.box('Back_splash',(0,.35,.965),(1.7,.055,.26),'wood',.008)
        R['basin_sockets']=[[-.43,-.035,.84],[.43,-.035,.84]]
    elif kind=='wash_basin':
        # Annular section has an actual drain all the way through.
        profile=[(.032,0),(.145,0),(.202,.05),(.267,.165),(.275,.195),(.261,.217),(.242,.210),(.226,.17),(.173,.075),(.095,.045),(.032,.040)]
        g.lathe('Hollow_stone_basin',smooth_outline(profile,2),'pale_stone')
        g.ring('Drain_mouth',.032,.039,.005,.010,'brass')
        R['drain_radius_m']=.027
    elif kind=='brass_faucet':
        g.lathe('Base',[(0,0),(.045,0),(.045,.014),(.028,.026),(0,.026)],'brass')
        path=[(0,0,.022),(0,0,.31)]
        path += [(0,-.075+.075*math.cos(a),.31+.075*math.sin(a)) for a in [i*math.pi/16 for i in range(1,17)]]
        path.append((0,-.15,.278));g.tube('Gooseneck',path,.017,'brass')
        g.lathe('Spout_end',[(.009,.274),(.021,.274),(.021,.294),(.009,.294)],'brass',(0,-.15,0))
        for x in [-.075,.075]:
            g.lathe('Valve',[(0,0),(.03,0),(.03,.012),(.016,.025),(.016,.055),(0,.055)],'brass',(x,0,0),n=24)
            for axis in [0,1]:
                a=[x,0,.064];b=a.copy();a[axis]-=.028;b[axis]+=.028;g.tube('Cross_handle',[a,b],.006,'brass')
        R['water_outlet']=[0,-.15,.274]
    elif kind=='privy_seat':
        # Serviceable bench latrine: no invented modern flush cistern.
        g.box('Front_cabinet',(0,-.31,.23),(.64,.07,.46),'wood',.01)
        for x in [-.285,.285]:g.box('Side_cabinet',(x,0,.23),(.07,.62,.46),'wood',.01)
        g.box('Back_cabinet',(0,.27,.23),(.64,.07,.46),'wood',.01)
        seat=g.box('Seat_board',(0,0,.49),(.70,.72,.08),'wood',.02,group='seat')
        cut(g,seat,(0,-.035,.49),(.13,.17,.22))
        lid=g.lathe('Raised_lid',[(0,0),(.22,0),(.23,.009),(.22,.028),(0,.028)],'wood',group='lid')
        lid.rotation_euler.x=math.radians(98);lid.location=(0,.26,.77)
        for x in [-.15,.15]:g.box('Lid_hinge',(x,.255,.54),(.10,.06,.025),'brass',.004,'lid_hardware')
        R['seat_height_m']=.53;R['waste_connection_required']=True
    elif kind=='shower_tray':
        n=64 if fine else 32;vs=[]
        profiles=[('rect',.725,.56,0),('rect',.725,.56,.10),('rect',.66,.495,.10),('rect',.66,.495,.056),('circle',.052,.052,.025),('circle',.052,.052,0)]
        for shape,rx,ry,z in profiles:
            for i in range(n):
                a=i*math.tau/n;c,s=math.cos(a),math.sin(a)
                if shape=='rect':t=1/max(abs(c),abs(s));c*=t;s*=t
                vs.append((rx*c,ry*s,z))
        fs=[]
        for j in range(len(profiles)):
            k=(j+1)%len(profiles)
            for i in range(n):q=(i+1)%n;fs.append((j*n+i,j*n+q,k*n+q,k*n+i))
        g.mesh('Sloped_drained_tray',vs,fs,'pale_stone',.008)
        g.ring('Drain_frame',.047,.027,.009,.009,'brass')
        for x in [-.027,-.009,.009,.027]:g.box('Drain_grille',(x,0,.027),(.008,.064,.006),'brass',.001)
        R['drain_point']=[0,0,.02]
    elif kind=='shower_column':
        path=[(0,.14,.08),(0,.14,2.06)]
        path += [(0,.02+.12*math.cos(i*math.pi/32),2.06+.12*math.sin(i*math.pi/32)) for i in range(1,33)]
        path.append((0,-.10,2.015));g.tube('Brass_riser',path,.018,'brass')
        for z in [.35,1.85]:
            plate=g.lathe('Wall_flange',[(0,0),(.065,0),(.065,.018),(0,.018)],'brass',n=32)
            plate.rotation_euler.x=math.pi/2;plate.location=(0,.25,z)
            g.tube('Wall_standoff',[(0,.25,z),(0,.14,z)],.016,'brass')
        g.lathe('Shower_rose',[(0,2.013),(.11,2.013),(.13,2.024),(.12,2.044),(.03,2.083),(0,2.083)],'brass',(0,-.10,0))
        for j in range(3):
            for i in range(12):
                a=i*math.tau/12;r=.025+j*.033
                g.lathe('Nozzle',[(0,2.009),(.002,2.009),(.002,2.013),(0,2.013)],'dark',(r*math.cos(a),-.10+r*math.sin(a),0),n=6)
        g.tube('Valve_spindle',[(0,.14,.95),(0,.02,.95)],.013,'brass')
        for axis in [0,2]:
            a=[0,.02,.95];b=a.copy();a[axis]-=.058;b[axis]+=.058;g.tube('Cross_valve',[a,b],.01,'brass')
        R['water_outlet']=[0,-.10,2.01];R['wall_mount']=True
    elif kind=='privacy_screen':
        for x in [-.67,.67]:g.box('Upright',(x,0,1.075),(.085,.085,2.15),'wood',.01)
        for z in [.18,2.05]:g.box('Crossbar',(0,0,z),(1.35,.07,.09),'wood',.007)
        panel=cloth(g,'Opaque_linen',1.24,1.79,(0,0,.22),'linen',40 if fine else 24,48 if fine else 28)
        panel['collision_review']=True
        R['floor_fixed']=True
    elif kind=='towel_rail':
        for x in [-.34,.34]:g.box('Wall_mount',(x,.10,.42),(.08,.06,.15),'wood',.009)
        g.tube('Towel_rod',[(-.39,-.05,.43),(.39,-.05,.43)],.019,'wood')
        cloth(g,'Front_towel',.45,.42,(0,-.075,0),'linen',40 if fine else 16,48 if fine else 20)
        cloth(g,'Back_towel',.45,.35,(0,-.015,.07),'linen',40 if fine else 16,48 if fine else 20)
        fold=g.tube('Fold_over_rail',[(-.225,-.045,.42),(.225,-.045,.42)],.030,'linen',group='replaceable_textile')
        fold['collision_review']=False
        R['wall_mount']=True
    elif kind=='wash_ewer':
        profile=[(0,0),(.085,0),(.105,.02),(.133,.12),(.12,.24),(.063,.33),(.055,.40),(.082,.43),(.073,.45),(.044,.425),(.044,.34),(.105,.235),(.115,.12),(.081,.025),(0,.025)]
        body=g.lathe('Ceramic_ewer',smooth_outline(profile,3),'ceramic')
        for v in body.data.vertices:
            if v.co.z>.395 and v.co.y<0:
                factor=max(0,(-v.co.y/.085))**4*(v.co.z-.395)/.055
                v.co.y-=.047*factor;v.co.z+=.016*factor
        g.tube('Handle',[(.060+.11*math.sin(i*math.pi/24),0,.25+.13*math.cos(i*math.pi/24)) for i in range(25)],.015,'ceramic')
    elif kind=='soap_dish':
        g.lathe('Soap_dish',smooth_outline([(0,0),(.065,0),(.098,.019),(.104,.03),(.093,.04),(.071,.017),(0,.015)],2),'ceramic')
        soap=g.box('Soap',(0,0,.041),(.105,.067,.03),'soap',.012,'replaceable_soap')
        soap.modifiers[0].segments=4
    initial_z=g.parts[0].location.z
    root,parts=g.finish()
    offset=g.parts[0].location.z-initial_z
    if 'ceiling_mount_points' in root:root['ceiling_mount_points']=[[p[0],p[1],p[2]+offset] for p in root['ceiling_mount_points']]
    if 'mount_height_m' in root:root['mount_height_m']+=offset
    for key in ['water_outlet','drain_point']:
        if key in root:root[key]=[root[key][0],root[key][1],root[key][2]+offset]
    # Geometry metadata remains on masters; optimized exports preserve attributes.
    return root,parts
