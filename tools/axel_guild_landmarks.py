"""Reusable neutral landmark meshes, based on U04/U18/U23, metres / Z up.

Unseen radial counts and fantasy anatomy are authored, not measured canon.
No texture, catalogue, user map or existing furniture is changed here.
"""
import math
import bpy
import bmesh
from mathutils import Vector

TAU = 2 * math.pi


class Builder:
    def __init__(self, collection, mats, asset):
        self.collection, self.mats, self.parts = collection, mats, []
        self.root = bpy.data.objects.new(asset, None)
        collection.objects.link(self.root)
        self.root['asset_id'] = asset
        self.root['independent_prop'] = True
        self.root['whitebox_only'] = True
        self.root['reference'] = 'U04/U18' if 'skeleton' in asset else 'U23'
        self.root['design_completion_authorized'] = True
        self.root['design_status'] = 'Authored whitebox design; unseen details completed 2026-10-08'

    def adopt(self, obj, name, mat='stone', smooth=False):
        obj.name = name
        for col in list(obj.users_collection): col.objects.unlink(obj)
        self.collection.objects.link(obj)
        obj.parent = self.root
        obj.data.materials.append(self.mats[mat])
        obj['whitebox_only'] = True
        obj['collision_review'] = False
        if obj.type == 'MESH':
            for p in obj.data.polygons: p.use_smooth = smooth
        self.parts.append(obj)
        return obj

    def mesh(self, name, verts, faces, mat='stone', smooth=False):
        me = bpy.data.meshes.new(name)
        me.from_pydata(verts, [], faces); me.update()
        bm = bmesh.new(); bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(me); bm.free()
        obj = bpy.data.objects.new(name, me)
        return self.adopt(obj, name, mat, smooth)

    def tube(self, name, points, radii, mat='metal', sides=12, hollow=False, wall=.025):
        """Parallel-transport frames, capped solid rods or open annular shells."""
        points = [Vector(p) for p in points]
        if isinstance(radii, (float, int)): radii = [radii] * len(points)
        verts, faces, frames = [], [], []
        normal = None
        for i, p in enumerate(points):
            tangent = (points[min(i+1,len(points)-1)]-points[max(i-1,0)]).normalized()
            if normal is None:
                guide = Vector((0,0,1)) if abs(tangent.z)<.9 else Vector((1,0,0))
                normal = tangent.cross(guide).normalized()
            else: normal = (normal - tangent * normal.dot(tangent)).normalized()
            other = tangent.cross(normal).normalized()
            frames.append((normal.copy(),other,tangent))
        for layer in range(2 if hollow else 1):
            for i,p in enumerate(points):
                n,v,_ = frames[i]; r = radii[i] - wall*layer
                for j in range(sides):
                    a=TAU*j/sides; verts.append(tuple(p+r*(math.cos(a)*n+math.sin(a)*v)))
        length=len(points)*sides
        for layer in range(2 if hollow else 1):
            offset=layer*length
            for i in range(len(points)-1):
                for j in range(sides):
                    a=offset+i*sides+j; b=offset+i*sides+(j+1)%sides
                    f=(a,b,b+sides,a+sides)
                    faces.append(f if layer==0 else tuple(reversed(f)))
        if hollow:
            for i in [0,len(points)-1]:
                for j in range(sides):
                    a=i*sides+j;b=i*sides+(j+1)%sides
                    faces.append((a,a+length,b+length,b))
        else:
            faces += [tuple(reversed(range(sides))),tuple((len(points)-1)*sides+j for j in range(sides))]
        obj=self.mesh(name,verts,faces,mat,True)
        if hollow:
            obj['open_bore']=True;obj['wall_thickness_m']=wall
            obj['mouth_center']=list(points[-1]);obj['mouth_axis']=list(frames[-1][2]);obj['mouth_radius']=radii[-1]
        return obj

    def sphere(self,name,p,size,mat='bone'):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,location=p)
        o=bpy.context.object;o.scale=size
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        return self.adopt(o,name,mat,True)

    def difference(self,obj,cutter):
        bpy.context.view_layer.objects.active=obj
        mod=obj.modifiers.new('Real opening','BOOLEAN');mod.operation='DIFFERENCE';mod.object=cutter
        bpy.ops.object.modifier_apply(modifier=mod.name)
        if cutter in self.parts:self.parts.remove(cutter)
        bpy.data.objects.remove(cutter,do_unlink=True)

    def ring(self,name,r,z,thick,mat='metal'):
        return self.tube(name,[(r*math.cos(TAU*i/128),r*math.sin(TAU*i/128),z) for i in range(129)],thick,mat)

    def lathe(self,name,profile,mat='stone',segments=128, smooth=True):
        verts=[(r*math.cos(TAU*i/segments),r*math.sin(TAU*i/segments),z) for r,z in profile for i in range(segments)]
        faces=[]
        for k in range(len(profile)):
            for i in range(segments):
                j=(i+1)%segments; n=(k+1)%len(profile)
                faces.append((k*segments+i,k*segments+j,n*segments+j,n*segments+i))
        return self.mesh(name,verts,faces,mat,smooth)


def radial(p,a):
    x,y,z=p
    return (x*math.cos(a)-y*math.sin(a),x*math.sin(a)+y*math.cos(a),z)


def build_crown(collection,mats):
    b=Builder(collection,mats,'guild_alarm_crown')
    # Local origin at the shaft/crown junction, world Z=23.
    drum=b.lathe('Crown hollow masonry drum',[(3.30,.55),(3.30,4.35),(3.02,4.35),(3.02,.55)])
    for i in range(8):
        a=TAU*i/8
        outline=[(-.28,1.05),(.28,1.05),(.28,1.91)]
        outline += [(.28*math.cos(t),1.91+.28*math.sin(t)) for t in [math.pi*j/16 for j in range(1,17)]]
        verts=[radial((r,y,z),a) for r in [2.80,3.65] for y,z in outline]
        n=len(outline);faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
        b.difference(drum,b.mesh('Temporary arched window cutter',verts,faces))
        path=[(-.36,1.02),(-.36,1.91)]+[(.36*math.cos(t),1.91+.36*math.sin(t)) for t in [math.pi*(1-j/20) for j in range(21)]]+[(.36,1.02)]
        b.tube('Arched window reveal', [radial((3.32,y,z),a) for y,z in path],.085,'trim',sides=8)
    # Arched lower edge is geometry, with visible masonry behind the pale skirt.
    for label,zbase,ztop,rout,rin,depth,count in [
        ('Lower arched corbels',-.55,.70,3.34,2.48,1.02,20),
        ('Eaves scalloped arcade',3.05,4.46,3.49,3.27,.85,24)]:
        n=count*24; verts=[]
        for layer in range(4):
            for i in range(n):
                phase=(i/24)%1; u=(phase-.5)/.37
                arch=math.sqrt(max(0,1-u*u)) if abs(u)<1 else 0
                low=zbase+depth*arch
                r=(rout if layer<2 else rin)
                if label.startswith('Lower') and layer in [0,3]:r=2.58
                z=low if layer in [0,3] else ztop
                a=TAU*i/n;verts.append((r*math.cos(a),r*math.sin(a),z))
        faces=[]
        for k in range(4):
            for i in range(n):faces.append((k*n+i,k*n+(i+1)%n,((k+1)%4)*n+(i+1)%n,((k+1)%4)*n+i))
        b.mesh(label,verts,faces,'trim',True)
    b.lathe('Crown top cornice',[(3.29,4.40),(3.60,4.48),(3.60,4.62),(3.28,4.62)],'trim')
    b.root['authored_window_count']=8;b.root['authored_lower_corbel_count']=20
    return b


def build_roof(collection,mats):
    b=Builder(collection,mats,'guild_alarm_conical_roof')
    roof=b.lathe('Conical roof shell',[(3.67,4.62),(3.25,5.04),(2.25,6.40),(1.02,8.35),(.07,9.38),(.07,9.22),(.91,8.26),(2.14,6.31),(3.14,4.96),(3.54,4.62)],'roof')
    # Eight triangular dormer mouths, actually opened through the roof shell.
    for i in range(8):
        a=TAU*i/8
        tri=[(-.36,5.60),(.36,5.60),(0,6.42)]
        verts=[radial((r,y,z),a) for r in [2.25,3.45] for y,z in tri]
        b.difference(roof,b.mesh('Temporary dormer opening',verts,[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)]))
        front=[radial((3.0,y,z),a) for y,z in [(-.46,5.52),(.46,5.52),(0,6.62)]]
        back=[radial((2.20,y,z),a) for y,z in [(-.46,5.52),(.46,5.52),(0,6.62)]]
        b.mesh('Dormer pitched cheeks',front+back,[(0,2,5,3),(2,1,4,5),(0,3,4,1)],'roof')
        for j in range(3):b.tube('Dormer stone lip',[front[j],front[(j+1)%3]],.065,'trim',8)
    b.lathe('Roof finial',[(.03,9.23),(.14,9.30),(.14,9.42),(.07,9.52),(.065,9.82),(.12,9.85),(.05,9.91),(.008,10.37),(.002,9.23)],'metal',48)
    b.root['authored_dormer_count']=8
    return b


def build_ring(collection,mats):
    b=Builder(collection,mats,'guild_alarm_ring_supports')
    b.ring('Horn outer support ring',4.20,2.75,.075)
    b.ring('Drum mounting belt',3.37,2.10,.055)
    for i in range(8):
        a=TAU*i/8
        for z in [1.10,2.73]:
            # Tangential mounting plate sits on the drum; outward bolt heads
            # remain distinct meshes so material/fastener variants can replace them.
            vertices=[radial((r,y,zz),a) for r in [3.285,3.40] for y,zz in [(-.20,z-.19),(.20,z-.19),(.20,z+.19),(-.20,z+.19)]]
            b.mesh('Ring wall anchor plate',vertices,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'metal')
            for y in [-.13,.13]:
                b.tube('Anchor hex bolt',[radial((3.40,y,z),a),radial((3.455,y,z),a)],.047,'trim',6)
        for label,points,radius in [
            ('Radial ring stay',[(3.28,0,2.73),(4.23,0,2.75)],.055),
            ('Diagonal bracket',[(3.30,0,1.12),(3.48,0,1.08),(4.22,0,2.73)],.055),
            ('Wall mounting strap',[(3.34,0,1.02),(3.34,0,2.88)],.09)]:
            b.tube(label,[radial(p,a) for p in points],radius)
        # Scrolls in the local tangent/Z plane, joined to horizontal ring.
        for sign in [-1,1]:
            points=[(4.2,0,2.75),(4.2,sign*.14,2.98)]
            for j in range(49):
                t=TAU*1.25*j/48; r=.29*(1-.82*j/48)
                points.append((4.2,sign*(.28-r*math.cos(t)),3.00+r*math.sin(t)))
            b.tube('Forged scroll bracket',[radial(p,a) for p in points],.033)
    return b


def build_horn(collection,mats):
    b=Builder(collection,mats,'guild_alarm_horn')
    # Continuous bent pipe becoming a bell. Mouth faces outward/down slightly.
    points=[];radii=[]
    for j in range(21):
        t=j/20;points.append((4.20,0,2.74+.83*t));radii.append(.095)
    for j in range(1,33):
        t=math.pi*j/32;points.append((4.20+.31*(1-math.cos(t)),0,3.57+.31*math.sin(t)));radii.append(.095)
    for j in range(1,33):
        t=j/32;points.append((4.82+.86*t*t,0,3.57-1.37*t));radii.append(.095+.66*t**3)
    bell=b.tube('Hollow curved alarm horn',points,radii,'metal',48,True,.026)
    bell['reference']='U23; repeated count authored'
    for z in [2.79,3.06]:
        b.tube('Pipe split collar',[(4.2+.119*math.cos(TAU*j/48),.119*math.sin(TAU*j/48),z) for j in range(49)],.025,'trim',8)
        b.tube('Pipe collar clamp bolt',[(4.32,-.06,z),(4.32,.06,z)],.028,'metal',6)
    # Rolled rim follows the mouth plane, not a solid circular face.
    p=Vector(points[-1]);direction=(p-Vector(points[-2])).normalized()
    n=Vector((0,1,0));v=direction.cross(n).normalized()
    b.tube('Horn rolled lip',[p+.75*(math.cos(TAU*i/96)*n+math.sin(TAU*i/96)*v) for i in range(97)],.036,'trim')
    for k in range(10):
        a=TAU*k/10; seam=[]
        for j in range(12,33):
            t=j/32;pt=Vector((4.82+.86*t*t,0,3.57-1.37*t));r=.095+.66*t**3+.003
            tangent=Vector((1.72*t,0,-1.37)).normalized();v=tangent.cross(n)
            seam.append(pt+r*(math.cos(a)*n+math.sin(a)*v))
        b.tube('Bell segment raised seam',seam,.008,'metal',6)
    return b


def build_skeleton(collection,mats):
    b=Builder(collection,mats,'guild_hanging_skeleton')
    b.root['anatomy']='Fantasy skull/rib assembly; species and hidden anatomy unconfirmed'
    # Longitudinal hidden steel armature, with bone geometry around each joint.
    b.tube('Internal spine armature',[(0,-1.65,.18),(0,2.7,.04)],.033,'metal')
    for i in range(18):
        y=-1.50+i*.24; scale=1 if i<13 else 1-(i-12)*.11
        b.sphere('Vertebral centrum',(0,y,.12),(.21*scale,.14,.17*scale))
        b.tube('Neural arch',[(-.17*scale,y,.12),(-.18*scale,y,.33),(0,y,.43),(.18*scale,y,.33),(.17*scale,y,.12)],.055*scale,'bone')
        b.tube('Neural spine',[(0,y,.40),(0,y+.07,.68*scale)], [.095*scale,.018],'bone')
        for s in [-1,1]:b.tube('Transverse process',[(s*.10,y,.20),(s*.36*scale,y+.04,.18)],[.10*scale,.035],'bone')
    for i in range(13):
        y=-1.35+i*.265; width=.64+.66*math.sin(math.pi*(i+1)/15)
        depth=.80+.91*math.sin(math.pi*(i+1)/15)
        for s in [-1,1]:
            points=[];r=[]
            for j in range(41):
                t=j/40;theta=.12+2.62*t
                points.append((s*(.13+width*math.sin(theta)),y+.28*t,.18-depth*(1-math.cos(theta))*.60))
                r.append(.07*(1-.67*t)+.014*math.sin(math.pi*t))
            b.tube('Rib %02d %s'%(i+1,'L' if s<0 else 'R'),points,r,'bone',12)
    # Skull is an open bone cage: real eye sockets and nasal aperture, separate jaw.
    cranium=b.sphere('Skull rear cranium',(0,-1.92,.04),(.53,.56,.45))
    cutter=b.sphere('Temporary orbital opening',(0,-2.10,.14),(.80,.24,.25))
    b.difference(cranium,cutter)
    # Broad snout roof with arched brow and zygomatic struts; no solid muzzle ball.
    b.mesh('Skull nasal bridge',[(-.36,-2.15,.27),(.36,-2.15,.27),(-.24,-3.00,.03),(.24,-3.00,.03),(-.33,-2.15,.13),(.33,-2.15,.13),(-.21,-3.00,-.08),(.21,-3.00,-.08)],
           [(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)],'bone',True)
    for s in [-1,1]:
        b.tube('Skull cheek arch',[(s*.35,-1.60,-.08),(s*.58,-1.98,-.12),(s*.45,-2.45,-.11),(s*.25,-3.01,-.09)], [.15,.12,.085,.07],'bone')
        b.tube('Orbital brow ridge',[(s*.38,-1.73,.28),(s*.54,-1.95,.40),(s*.46,-2.25,.31),(s*.36,-2.39,.15)], [.10,.10,.075,.04],'bone')
        b.tube('Skull posterior crest',[(s*.28,-1.58,.24),(s*.42,-1.38,.49),(s*.29,-1.22,.62)],[.16,.09,.012],'bone')
    jaw=bpy.data.objects.new('Skeleton jaw separate root',None);collection.objects.link(jaw);jaw.parent=b.root
    jaw['independent_part']=True
    first=len(b.parts)
    for s in [-1,1]:
        b.tube('Open lower mandible',[(s*.40,-1.65,-.15),(s*.52,-1.98,-.48),(s*.37,-2.52,-.82),(s*.21,-2.98,-.87)], [.15,.12,.10,.075],'bone')
    b.tube('Mandibular symphysis',[(-.21,-2.98,-.87),(0,-3.07,-.89),(.21,-2.98,-.87)],.078,'bone')
    for s in [-1,1]:
        for i in range(9):
            t=i/8;y=-1.98-.92*t;x=s*(.46-.22*t);z=-.48-.39*t
            b.tube('Lower tooth',[(x,y,z),(x*.93,y-.035,z+.20+.09*math.sin(math.pi*t))],[.052,.003],'bone',10)
    for o in b.parts[first:]:o.parent=jaw
    for s in [-1,1]:
        for i in range(10):
            t=i/9;y=-1.96-1.0*t;x=s*(.48-.24*t)
            b.tube('Upper tooth',[(x,y,-.12),(x*.95,y-.035,-.32-.11*math.sin(math.pi*t))],[.055,.003],'bone',10)
    b.parts.append(jaw)
    # Visible exhibition fasteners, not speculative biological bone structures.
    for s in [-1,1]:
        b.tube('Jaw hinge pin',[(s*.28,-1.65,-.15),(s*.48,-1.65,-.15)],.055,'metal',12)
        b.tube('Jaw pin retaining head',[(s*.48,-1.65,-.15),(s*.52,-1.65,-.15)],.077,'metal',12)
    # The crossbeam ends attach to existing truss king posts x=13/19.
    b.tube('Suspension crossbeam',[(-3,-.5,1.90),(3,-.5,1.90)],.08,'metal',12)
    for x in [-2.94,2.94]:
        for z in [1.79,2.01]:
            b.tube('King post fixing collar',[(x+.12*math.cos(TAU*j/32),-.5+.12*math.sin(TAU*j/32),z) for j in range(33)],.025,'metal',8)
        b.tube('Beam end fixing pin',[(x,-.67,1.90),(x,-.33,1.90)],.035,'metal',6)
    for y in [-1.42,1.62]:
        for s in [-1,1]:
            foot=Vector((s*.18,y,.26));top=Vector((s*1.2,-.5,1.90))
            b.tube('V suspension cable',[foot,top],.012,'metal',8)
            for t in [.06,.84]:
                b.tube('Suspension cable ferrule',[foot.lerp(top,t),foot.lerp(top,t+.05)],.032,'trim',10)
            b.tube('Crossbeam cable collar',[(s*1.2,-.5+.103*math.cos(TAU*j/32),1.90+.103*math.sin(TAU*j/32)) for j in range(33)],.019,'metal',8)
            b.tube('Armature sling',[(s*.18,y,.26),(s*.21,y,-.04),(0,y,-.08)],.018,'metal',8)
    return b


def install_landmarks(api):
    mats={'stone':api['WHITE'],'trim':api['TRIM'],'roof':api['ROOF'],'metal':api['WOOD'],'bone':api['TRIM']}
    builders=[]
    def install(builder,g,loc,angle=0):
        root=builder.root;root.parent=api['ROOTS'][g];root.location=loc;root.rotation_euler.z=angle
        for o in [root]+builder.parts:
            o['semantic_group']=g;o['collision_review']=False
            api['OBJECTS'].append(o)
        builders.append(builder)
    install(build_skeleton(api['COLLECTIONS']['44_Hanging_Landmark'],mats),'44_Hanging_Landmark',(16,7.5,10.6))
    g='70_Alarm_Tower_Context';col=api['COLLECTIONS'][g]
    for fn in [build_crown,build_roof,build_ring]:install(fn(col,mats),g,(23,42,23))
    original=build_horn(col,mats);install(original,g,(23,42,23))
    for i in range(1,8):
        clone=object.__new__(Builder);clone.root=original.root.copy();clone.root.name='guild_alarm_horn_%02d'%(i+1);col.objects.link(clone.root);clone.parts=[]
        for part in original.parts:
            o=part.copy();o.data=part.data;col.objects.link(o);o.parent=clone.root;clone.parts.append(o)
        install(clone,g,(23,42,23),TAU*i/8)
    return builders
