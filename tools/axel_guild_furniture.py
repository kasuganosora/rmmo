"""Reusable guild furniture geometry, metres, floor-centred origin, front -Y.

U02/U03/U05/U06/U07/U12 establish visible forms, not measured dimensions.
Upper-floor furniture, hidden joinery and all dimensions are authored proposals.
No gameplay, catalogue or building generation side effects in this module.
"""
import math
import bpy
import bmesh
from mathutils import Vector

ASSETS = {
    'hall_lantern': ('大厅方柱落地灯', 'U02,U03,U05,U12'),
    'dining_table': ('长餐桌', 'U03,U06'),
    'small_table': ('小餐桌', 'U06'),
    'long_bench': ('长餐凳', 'U03,U06'),
    'short_bench': ('短餐凳', 'U06'),
    'stool': ('方凳', 'U06'),
    'waiting_bench': ('靠背候坐长椅', 'U12'),
    'notice_lectern': ('独立告示架', 'U12'),
    'bar_counter': ('木吧台', 'U07'),
    'bottle_shelf': ('酒瓶陈列架', 'U07'),
    'barrel': ('箍铁木桶', 'U07'),
    'planter': ('室内长方花箱', 'U12'),
    'single_bed': ('客房单人床', 'L1 design proposal'),
    'bedside_cabinet': ('客房小柜', 'L1 design proposal'),
    'storage_cabinet': ('储物高柜', 'L1 design proposal'),
    'writing_desk': ('书写桌', 'L1 design proposal'),
}


def build_furniture(kind, collection, materials, quality='game', name=None):
    assert kind in ASSETS
    name = name or 'guild_' + kind
    root = bpy.data.objects.new(name, None)
    collection.objects.link(root)
    for key, value in {'asset_id': 'guild_' + kind, 'asset_version': 1,
                       'independent_prop': True, 'structural_wall': False,
                       'front_axis': '-Y', 'dimensions_are_proposed': True,
                       'reference_ids': ASSETS[kind][1]}.items(): root[key] = value
    parts = []
    segments = 2 if quality == 'game' else 4

    def mesh(label, vs, fs, mat, bevel=0, collision=True):
        data = bpy.data.meshes.new(name + '_' + label)
        data.from_pydata(vs, [], fs); data.update()
        bm = bmesh.new(); bm.from_mesh(data)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces)); bm.to_mesh(data); bm.free()
        obj = bpy.data.objects.new(data.name, data); collection.objects.link(obj)
        obj.parent = root; data.materials.append(materials[mat])
        obj['prop_part'] = label; obj['collision_review'] = collision
        obj['independent_prop'] = True; obj['structural_wall'] = False
        # Per-board local grain follows its longest direction. No shared world UV
        # that would turn a vertical leg into horizontal stripes.
        uv = data.uv_layers.new(name='FurnitureUV')
        extents = [max(v[i] for v in vs)-min(v[i] for v in vs) for i in range(3)]
        long_axis = max(range(3), key=lambda i: extents[i])
        offset = len(parts) * .173
        for p in data.polygons:
            normal_axis = max(range(3), key=lambda i: abs(p.normal[i]))
            axes = [i for i in range(3) if i != normal_axis]
            if long_axis in axes: axes.remove(long_axis); axes.append(long_axis)
            for li in p.loop_indices:
                co = data.vertices[data.loops[li].vertex_index].co
                uv.data[li].uv = (co[axes[0]] * 2 + offset, co[axes[1]] * .7 + offset)
        if bevel:
            mod=obj.modifiers.new('Rounded working edges', 'BEVEL')
            mod.width=bevel; mod.segments=4 if bevel>=.018 else segments
            mod=obj.modifiers.new('Stable face normals', 'WEIGHTED_NORMAL'); mod.keep_sharp=True
        parts.append(obj)
        return obj

    def box(label, loc, size, mat='wood', bevel=.004):
        x,y,z=loc; w,d,h=size
        vs=[(x+a*w/2,y+b*d/2,z+c*h/2) for c in [-1,1] for b in [-1,1] for a in [-1,1]]
        return mesh(label,vs,[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)],mat,bevel)

    def frustum(label, z0,z1,w0,w1,d0=None,d1=None,mat='metal',bevel=.003):
        d0=w0 if d0 is None else d0; d1=w1 if d1 is None else d1
        vs=[(a*w/2,b*d/2,z) for z,w,d in [(z0,w0,d0),(z1,w1,d1)] for b in [-1,1] for a in [-1,1]]
        return mesh(label,vs,[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)],mat,bevel)

    def beam(label,a,b,width,mat='metal'):
        a,b=Vector(a),Vector(b)
        obj=box(label,(0,0,0),(width,width,(b-a).length),mat,min(.003,width*.15))
        obj.location=(a+b)/2; obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
        return obj

    def board_top(label,w,d,z,h=.10,mat='wood',metal=True):
        n=max(2,round(d/.18)); step=d/n
        for i in range(n):box(label+'_plank', (0,-d/2+(i+.5)*step,z-h/2),(w,step-.003,h),mat)
        if metal:
            for x in [-w/2+.055,w/2-.055]:box(label+'_metal_end', (x,0,z-h/2+.002),(.122,d+.012,h+.004),'steel',.006)

    def table(w,d,h,desk=False):
        board_top('Tabletop',w,d,h)
        for x in [-w/2+.13,w/2-.13]:
            for y in [-d/2+.13,d/2-.13]:
                leg=frustum('Tapered_table_leg',0,h-.10,.085,.115,mat='wood')
                leg.location=(x,y,0)
        for y in [-d/2+.13,d/2-.13]: box('Long_apron',(0,y,h-.20),(w-.22,.065,.2))
        for x in [-w/2+.13,w/2-.13]: box('End_apron',(x,0,h-.20),(.065,d-.2,.2))
        if desk:
            box('Desk_drawer_front',(0,-d/2+.045,h-.20),(.6,.045,.17))
            box('Drawer_handle',(0,-d/2+.008,h-.20),(.13,.034,.025),'steel')

    def bench(w,d=.28,back=False):
        board_top('Seat',w,d,.505,.09)
        for x in [-w/2+.15,w/2-.15]:
            for y in [-d/2+.065,d/2-.065]:box('Bench_leg',(x,y,.21),(.085,.085,.42))
        box('Bench_stretcher',(0,0,.18),(w-.25,.065,.09))
        if back:
            for x in [-w/2+.06,w/2-.06]:
                box('Back_post',(x,d/2-.06,.675),(.095,.095,1.35))
                box('Front_arm_post',(x,-d/2+.06,.61),(.065,.065,.39))
                box('Armrest',(x,0,.83),(.13,d,.07))
            for z in [.91,1.16]: box('Backrest_board',(0,d/2-.055,z),(w-.15,.065,.22))
            box('Back_top_rail',(0,d/2-.055,1.32),(w,.085,.055))
        root['seat_height_m']=.505
        root['multi_seat_interaction_implemented']=False

    if kind=='hall_lantern':
        root['light_socket_blender']=[0.,0.,2.82]
        root['light_runtime_connected']=False
        root['proposed_light_color_linear']=[1.,.86,.69]
        box('Foot_plinth',(0,0,.05),(.48,.48,.10),'metal',.008)
        frustum('Plinth_bevel',.10,.17,.48,.405)
        box('Pedestal',(0,0,.34),(.365,.365,.34),'metal',.01)
        # Recessed inset panels keep the heavy square pedestal readable.
        for angle in [0,math.pi/2,math.pi,3*math.pi/2]:
            o=box('Pedestal_inset',(0,-.183,.34),(.245,.006,.235),'inset',.008)
            o.rotation_euler.z=angle
            # Rotation above rotates the local mesh about the floor centre.
        frustum('Pedestal_shoulder',.51,.65,.40,.23)
        box('Pedestal_cap',(0,0,.665),(.29,.29,.05),'metal',.006)
        frustum('Square_tapered_shaft',.69,2.32,.18,.135)
        for z in [.79,1.28,1.72,2.25]:box('Shaft_collar',(0,0,z),(.205,.205,.052),'metal')
        box('Lantern_neck',(0,0,2.38),(.19,.19,.13),'metal')
        frustum('Lower_lantern_cup',2.43,2.53,.20,.34)
        box('Bottom_frame',(0,0,2.55),(.365,.365,.07),'metal')
        from axel_guild_magic_lantern import build_magic_core
        parts.extend(build_magic_core(root,collection,materials['glass'],materials.get('magic_stone',materials['glass'])))
        for sx in [-1,1]:
            for sy in [-1,1]:beam('Corner_mullion',(sx*.15,sy*.15,2.57),(sx*.245,sy*.245,3.075),.04)
        box('Top_frame',(0,0,3.075),(.535,.535,.06),'metal',.006)
        box('Upper_cornice',(0,0,3.13),(.565,.565,.05),'metal')
        frustum('Pyramid_cap',3.155,3.405,.535,.016)
        frustum('Finial',3.405,3.48,.047,.004)
    elif kind in ['dining_table','small_table','writing_desk']:
        table(2.4 if kind=='dining_table' else 1.1 if kind=='small_table' else 1.8,
              .8,.85 if kind!='writing_desk' else .80,kind=='writing_desk')
    elif kind in ['long_bench','short_bench','waiting_bench']:
        bench(2.4 if kind=='long_bench' else 1.1 if kind=='short_bench' else 1.9,
              .65 if kind=='waiting_bench' else .28,kind=='waiting_bench')
    elif kind=='stool':
        board_top('Stool_seat',.38,.38,.48,.06,metal=False)
        for x in [-.13,.13]:
            for y in [-.13,.13]:box('Stool_leg',(x,y,.21),(.065,.065,.42))
        for y in [-.13,.13]:box('Stool_stretcher',(0,y,.16),(.26,.045,.055))
        root['seat_height_m']=.48
        root['seat_socket_blender']=[0.,0.,.48]
        root['seat_runtime_connected']=False
    elif kind=='notice_lectern':
        # Four foot A-frame, top notice board inclined, removable blank paper.
        for x in [-.29,.29]:
            beam('Front_support',(x,-.185,0),(x,.025,1.32),.055,'wood')
            beam('Rear_support',(x,.185,0),(x,.025,1.28),.055,'wood')
        box('Bottom_tie',(0,0,.24),(.64,.06,.065))
        for x in [-.345,.345]:box('Notice_side_frame',(x,0,1.03),(.06,.075,.76),'metal')
        for z in [.65,1.4]:box('Notice_frame_rail',(0,0,z),(.766,.085,.055),'metal')
        box('Notice_backing',(0,0,1.02),(.64,.04,.69),'wood')
        box('Blank_replaceable_notice',(0,-.024,1.02),(.585,.003,.635),'paper',.001)
        root['notice_surface_replaceable']=True
    elif kind=='bar_counter':
        board_top('Countertop',4.6,.85,1.12,.12)
        for x in [-2.16,0,2.16]:box('Counter_post',(x,0,.51),(.14,.69,1.02))
        for x in [i*.195-2.0475 for i in range(22)]:box('Counter_front_plank',(x,-.32,.55),(.191,.052,.9))
        for z in [.12,.91]:box('Counter_front_rail',(0,-.355,z),(4.38,.065,.12))
        box('Counter_low_shelf',(0,.02,.25),(4.3,.57,.055))
        for x in [-2.18,2.18]:box('Counter_end',(x,0,.55),(.055,.65,.9))
    elif kind=='bottle_shelf':
        for x in [-.86,.86]:box('Shelf_upright',(x,0,.9),(.08,.30,1.8))
        for z in [.09,.58,1.1,1.73]:box('Shelf',(0,0,z),(1.64,.30,.06))
        for x in [-.7,0,.7]:box('Shelf_back_batten',(x,.125,.9),(.12,.045,1.65))
        root['contents_included']=False
    elif kind=='barrel':
        n=32  # Stave count is construction, not an LOD parameter.
        profile=[(0,.277),(.07,.296),(.25,.331),(.475,.35),(.70,.331),(.88,.296),(.95,.277)]
        # Each stave is closed; actual gaps, curved barrel silhouette, separate hoops.
        for i in range(n):
            a=(i+.015)*math.tau/n; b=(i+.985)*math.tau/n
            vs=[(r*math.cos(t),r*math.sin(t),z) for inward in [0,.025] for z,r0 in profile for r in [r0-inward] for t in [a,b]]
            m=len(profile)*2
            fs=[]
            for j in range(len(profile)-1):
                k=j*2;fs.extend([(k,k+1,k+3,k+2),(m+k,m+k+2,m+k+3,m+k+1),
                                 (k,k+2,m+k+2,m+k),(k+1,m+k+1,m+k+3,k+3)])
            fs.extend([(0,m,m+1,1),(m-2,m-1,2*m-1,2*m-2)])
            o=mesh('Barrel_stave',vs,fs,'wood',.0007)
            if quality=='game':o.modifiers[0].segments=1
            for p in o.data.polygons:p.use_smooth=True
        for z,r in [(.095,.302),(.29,.343),(.66,.343),(.855,.302)]:
            vs=[(rr*math.cos(t*math.tau/n),rr*math.sin(t*math.tau/n),zz)
                for zz,rr in [(z-.026,r),(z+.026,r),(z-.026,r-.012),(z+.026,r-.012)] for t in range(n)]
            fs=[]
            for i in range(n):
                j=(i+1)%n;fs.extend([(i,j,n+j,n+i),(2*n+i,3*n+i,3*n+j,2*n+j),
                                     (i,2*n+i,2*n+j,j),(n+i,n+j,3*n+j,3*n+i)])
            o=mesh('Iron_hoop',vs,fs,'steel',.001)
            if quality=='game':o.modifiers[0].segments=1
            for p in o.data.polygons:p.use_smooth=True
        # Inset wooden heads as closed disks, with plank seams represented by UV grain.
        for z in [.026,.925]:
            vs=[(.267*math.cos(i*math.tau/n),.267*math.sin(i*math.tau/n),zz) for zz in [z-.012,z+.012] for i in range(n)]
            mesh('Wooden_head',vs,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],'wood',.001)
    elif kind=='planter':
        for x in [-.45,.45]:box('Planter_end',(x,0,.42),(.1,.55,.76))
        for y in [-.235,.235]:
            for z in [.18,.405,.63]:box('Planter_side',(0,y,z),(.82,.08,.216))
            box('Planter_rim',(0,y,.785),(1.012,.09,.05),'steel')
        box('Planter_bottom',(0,0,.09),(.9,.48,.1))
        box('Soil',(0,0,.7),(.81,.385,.035),'soil',.003)
        for x in [-.38,.38]:box('Planter_foot',(x,0,.04),(.11,.47,.08))
        root['vegetation_included']=False
    elif kind=='single_bed':
        for x in [-.44,.44]:
            for y in [-.95,.95]:box('Bed_post',(x,y,.21),(.12,.12,.42))
            box('Bed_side_rail',(x,0,.33),(.10,1.92,.19))
        box('Slatted_bed_base',(0,0,.39),(.85,1.98,.05))
        box('Mattress',(0,0,.52),(.91,1.94,.23),'linen',.055)
        box('Blanket',(0,-.35,.65),(.925,1.22,.045),'cloth',.018)
        box('Pillow',(0,.68,.71),(.64,.36,.16),'linen',.065)
        for x in [-.44,.44]:box('Head_post',(x,.98,.65),(.115,.115,1.3))
        for x in [-.3,-.1,.1,.3]:box('Headboard_plank',(x,.98,.86),(.197,.065,.74))
        box('Head_rail',(0,.98,1.28),(1,.13,.06))
        root['bed_interaction_implemented']=False
    elif kind in ['bedside_cabinet','storage_cabinet']:
        w,d,h=(.7,.6,1.2) if kind=='bedside_cabinet' else (1.1,.4,1.8)
        box('Cabinet_top',(0,0,h-.03),(w,d,.06))
        box('Cabinet_bottom',(0,0,.11),(w-.06,d-.04,.07))
        for x in [-w/2+.045,w/2-.045]:box('Cabinet_side',(x,0,h/2),(.065,d-.02,h-.10))
        box('Cabinet_back',(0,d/2-.025,h/2),(w-.1,.035,h-.12))
        for x in [-w/2+.085,w/2-.085]:
            for y in [-d/2+.085,d/2-.085]:box('Cabinet_foot',(x,y,.055),(.10,.10,.11))
        for side in [-1,1]:
            start=len(parts)
            box('Independent_door_leaf',(side*w*.236,-d/2+.012,h/2+.02),(w*.465,.045,h-.18))
            box('Door_inset',(side*w*.236,-d/2-.014,h/2+.02),(w*.365,.012,h-.34),'wood_dark')
            box('Door_handle',(side*.055,-d/2-.035,h*.55),(.026,.035,.095),'steel')
            for obj in parts[start:]:obj['replaceable_group']='left_door' if side<0 else 'right_door'
        root['door_animation_implemented']=False
    bpy.context.view_layer.update()
    deps=bpy.context.evaluated_depsgraph_get()
    bottom=min((obj.evaluated_get(deps).matrix_world @ Vector(corner)).z
               for obj in parts for corner in obj.evaluated_get(deps).bound_box)
    for obj in parts:obj.location.z-=bottom
    return root, parts


def bake_game_meshes(root, parts):
    """Apply bevels and combine within this asset by material; never across props."""
    from collections import defaultdict
    by_mat=defaultdict(list)
    bpy.context.view_layer.update()
    deps=bpy.context.evaluated_depsgraph_get()
    for obj in parts:
        ev=obj.evaluated_get(deps)
        data=bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=deps)
        old=obj.data; obj.modifiers.clear(); obj.data=data
        if old.users==0:bpy.data.meshes.remove(old)
        by_mat[(data.materials[0].name, bool(obj.get('collision_review',True)),obj.get('replaceable_group','static'))].append(obj)
    result=[]
    for (mat,collision,replaceable),objects in by_mat.items():
        bpy.ops.object.select_all(action='DESELECT')
        for obj in objects:obj.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        bpy.ops.object.join()
        obj=objects[0]; obj.name=root.name+'_'+mat
        obj['collision_review']=collision; obj['structural_wall']=False
        obj['replaceable_group']=replaceable
        result.append(obj)
    bpy.ops.object.select_all(action='DESELECT')
    return result
