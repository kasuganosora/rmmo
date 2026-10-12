"""Reference corrections: roof junctions and reusable entrance standards.

Supplemental construction follows Copper Development Association dormer flashing
details; this is game geometry, not a certified structural design.
"""
import math
import bpy
import bmesh
from mathutils import Vector


def build(api):
    mesh, mat = api['mesh'], api['mat']
    roof = bpy.data.materials['Guild PBR | terracotta']
    trim = bpy.data.materials['Guild PBR | cut limestone trim']
    flashing = bpy.data.materials['Guild PBR | roof flashing']
    slope = 5.8/7
    specs = [(16,5.8,10.8,13.8,-.62,'Central frontage',False)]
    specs += [(x,2.75,9.7,11.9,-.2,'Secondary gable',False) for x in [3.5,10.2,21.8,28.5]]
    specs += [(x,1.65,11.55,12.85,2,'Small dormer',False) for x in [7,25]]
    specs += [(x,1.8,11.55,12.85,2,'Rear dormer',True) for x in [3.5,10,16]]
    for o in list(bpy.data.objects):
        if any(o.name.startswith(n) and any(t in o.name for t in [' roof left',' roof right',' valley flashing',' verge left',' verge right']) for n in ['Central frontage','Secondary gable','Small dormer','Rear dormer']):
            bpy.data.objects.remove(o,do_unlink=True)
    report=[]
    for cx,w,eave,peak,front,name,rear in specs:
        k=(peak-eave)/(w/2); key='roof_join_'+str(cx)+('_rear' if rear else '_front')
        def roofheight(x):return peak+.24-k*abs(x-cx)
        def obj(label,vs,fs,material,closed=False):
            if rear:
                vs=[(x,14-y,z) for x,y,z in vs];fs=[tuple(reversed(f)) for f in fs]
            structural=label=='closed roof pitch'
            o=mesh(name+' '+label,vs,fs,material,'50_Roof',collision=structural)
            o['finish_component']=key+('_solid' if structural else '_trim');o['roof_hide_group']=True
            uv=o.data.uv_layers.new(name='RoofMetresUV')
            for loop in o.data.loops:
                p=o.data.vertices[loop.vertex_index].co
                # Unroll each pitch: tile courses run downslope in X.
                uv.data[loop.index].uv=(p.y,abs(p.x-cx)*math.sqrt(1+k*k)/.72)
            bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
            if closed:assert all(e.is_manifold for e in bm.edges),o.name
            bm.to_mesh(o.data);bm.free();return o
        for sign in [-1,1]:
            edge=cx+sign*(w/2+.14)
            z=roofheight(edge); zc=peak+.24
            # Rear overlap is buried beneath the main slope, never a raised lip.
            ye=(z-8.2)/slope+.14;yp=(zc-8.2)/slope+.14
            top=[(edge,front-.19,z),(cx,front-.19,zc),(cx,yp,zc),(edge,ye,z)]
            vs=top+[(x,y,z-.18) for x,y,z in top]
            obj('closed roof pitch',vs,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],roof,True)
            # Mitered verge strip meets the opposite strip exactly on centreline.
            q=[(edge,front-.21,z+.01),(cx,front-.21,zc+.01),(cx,front-.21,zc-.22),(edge,front-.21,z-.22)]
            obj('mitered stone verge',q+[(x,y+.15,z) for x,y,z in q],[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],trim,True)
            # Close the small seat between masonry cheek and roof soffit.
            wallx=cx+sign*w/2;end=(eave-8.2)/slope+.04
            q=[(wallx+dx,y,z) for z in [eave-.07,eave+.075] for y in [front+.02,end] for dx in [-.09,.09]]
            obj('cheek eave closure',q,[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)],trim,True)
            # A folded valley apron follows BOTH roof planes rather than a beam
            # floating across their intersection. End under ridge cap.
            vs=[];fs=[]
            for t in [i/20 for i in range(21)]:
                x=edge+(cx-edge)*t;z=roofheight(x);y=(z-8.2)/slope
                for d in [-.12,0,.12]:vs.append((x,y+d,max(z,8.2+slope*(y+d))+.012))
            for i in range(20):
                for j in range(2):a=i*3+j;fs.append((a,a+1,a+4,a+3))
            obj('folded valley apron',vs,fs,flashing)
        # Narrow ridge cap hides coincident pitch edges and joins the main roof.
        vs=[];fs=[]
        for y in [front-.23,(peak+.24-8.2)/slope+.12]:
            for j in range(13):
                a=j*math.pi/12;vs.append((cx+.115*math.cos(a),y,peak+.225+.115*math.sin(a)))
        for j in range(12):fs.append((j,j+1,j+14,j+13))
        obj('terracotta ridge cap',vs,fs,roof)
        report.append({'name':key,'pitch_halves':2,'roof_clearance_at_wall_m':.06,'side_overhang_m':.14,'front_overhang_m':.29})
    # The outer tips of the central piers previously rose past the sloping eave.
    for o in bpy.data.objects:
        if not o.name.startswith('Central gable pier'):continue
        inv=o.matrix_world.inverted()
        for v in o.data.vertices:
            p=o.matrix_world@v.co
            if p.z>10.5:p.z=10.5
            v.co=inv@p
    # One shared reusable mesh, instanced on both existing parapet capstones.
    brass=mat('Guild entrance standard golden brass',(.57,.34,.075),.82,.29)
    pieces=[]
    def piece(label,vs,fs):
        o=mesh(label,vs,fs,brass,'12_Facade_Detail');o['finish_component']='entrance_standard';pieces.append(o);return o
    def lathe(label,profile,n=32):
        vs=[(r*math.cos(j*math.tau/n),r*math.sin(j*math.tau/n),z) for r,z in profile for j in range(n)]
        fs=[]
        for i in range(len(profile)-1):
            for j in range(n):a=i*n+j;b=i*n+(j+1)%n;fs.append((a,b,b+n,a+n))
        o=piece(label,vs,fs)
        for p in o.data.polygons:p.use_smooth=True
    lathe('Standard turned base and shaft',[(0,0),(.14,0),(.14,.05),(.115,.075),(.10,.15),(.06,.28),(.045,.32),(.041,1.54),(.067,1.56),(.067,1.61),(.047,1.64),(.045,1.87),(0,1.87)])
    for z in [.35,.62,.89,1.16,1.43]:lathe('Standard shaft collar',[(.041,z-.02),(.053,z-.014),(.053,z+.014),(.041,z+.02)])
    # Open crescent, solid tapered section, with blunt rounded tips.
    vs=[];fs=[];n=60;m=10
    for i in range(n+1):
        a=math.radians(-145+290*i/n);rad=.325;r=.012+.05*math.sin(math.pi*i/n)**.45
        for j in range(m):
            b=j*math.tau/m;vs.append(((rad+r*math.cos(b))*math.cos(a),r*math.sin(b),1.90+(rad+r*math.cos(b))*math.sin(a)))
    for i in range(n):
        for j in range(m):a=i*m+j;b=i*m+(j+1)%m;fs.append((a,b,b+m,a+m))
    fs += [tuple(reversed(range(m))),tuple(n*m+j for j in range(m))]
    o=piece('Standard crescent crest',vs,fs)
    for p in o.data.polygons:p.use_smooth=True
    # Central medallion and diagonal lance all physically join the crescent/stem.
    lathe('Standard central medallion',[(0,-.055),(.09,-.045),(.125,0),(.09,.045),(0,.055)])
    o=pieces[-1]
    for v in o.data.vertices:x,y,z=v.co;v.co=(x,z,1.9+y)
    a=Vector((.10,0,1.84));b=Vector((-.57,0,2.14));d=(b-a).normalized();u=Vector((0,1,0));v=d.cross(u)
    vs=[a+.043*(u*math.cos(j*math.tau/12)+v*math.sin(j*math.tau/12)) for j in range(12)]+[b]
    spike=piece('Standard diagonal tapered spike',vs,[(j,(j+1)%12,12) for j in range(12)]+[tuple(reversed(range(12)))])
    for p in list(spike.data.polygons)[:12]:p.use_smooth=True
    bpy.ops.object.select_all(action='DESELECT')
    for o in pieces:o.select_set(True)
    bpy.context.view_layer.objects.active=pieces[0];bpy.ops.object.join();o=bpy.context.object
    o.name='Guild entrance crescent standard left';o['asset_id']='guild_entrance_crescent_standard';o['independent_prop']=True
    o['reference_status']='User U35 silhouette; back, fasteners and dimensions are supplemental design'
    # Exclude from the general finish join to keep the two instances selectable.
    o['finish_component']='entrance_standard_left';o.location=(12.75,-1.44,.87)
    right=o.copy();right.data=o.data;bpy.data.collections['12_Facade_Detail'].objects.link(right)
    right.name='Guild entrance crescent standard right';right['finish_component']='entrance_standard_right';right.location=(19.25,-1.44,.87);right.rotation_euler.z=math.pi
    return report
