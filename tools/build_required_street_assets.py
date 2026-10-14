"""Blender 4.5: S10/S12 source assets. Metres; front -Y, exported +Z.
No publication. Own collections remain editable; reference-derived design only.
"""
import bpy, bmesh, math, json, hashlib, random, sys, struct
import numpy as np
from pathlib import Path
from mathutils import Vector

ROOT=Path('D:/code/rmmo_runtime')
OUT=ROOT/'art_sources/required_street_assets_20261013'
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'models').mkdir(exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
SC=bpy.context.scene; SC.unit_settings.system='METRIC'
R=random.Random(61013)
ASSETS=[]; CURRENT=[]

def surface(name,folder):
    base=ROOT/'packs/default/assets/materials'/folder
    m=bpy.data.materials.new(name);m.use_nodes=True
    nt=m.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
    bs.inputs['Roughness'].default_value=.8
    for file,socket in [('texture.jpg','Base Color'),('normal.png','Normal'),('roughness.png','Roughness')]:
        p=base/file
        if not p.exists():continue
        t=nt.nodes.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(p),check_existing=True);t.image.pack()
        if socket!='Base Color':t.image.colorspace_settings.name='Non-Color'
        if socket=='Normal':
            n=nt.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.32
            nt.links.new(t.outputs['Color'],n.inputs['Color']);nt.links.new(n.outputs[0],bs.inputs[socket])
        elif socket=='Roughness':
            sep=nt.nodes.new('ShaderNodeSeparateColor');nt.links.new(t.outputs[0],sep.inputs[0]);nt.links.new(sep.outputs[0],bs.inputs[socket])
        else:nt.links.new(t.outputs[0],bs.inputs[socket])
    return m

STONE=surface('Pale weathered limestone | existing owned scan','terrain/beach_cliff')
def plain(name,c,rough=.7,metal=0):
    m=bpy.data.materials.new(name);m.use_nodes=True;p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
    return m
IRON=plain('Hand forged tie and clamps',(.07,.062,.049),.55,.75)

def mesh(name,v,f,mat=STONE,bevel=0,smooth=False,collision='block'):
    me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.update()
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    o=bpy.data.objects.new(name,me);SC.collection.objects.link(o);me.materials.append(mat);CURRENT.append(o)
    o['rmmo_collision']=collision;o['design_provenance']='reference silhouette; unseen connections are project supplementary design'
    uv=me.uv_layers.new(name='StoneUV');offset=(R.random()*2,R.random()*2)
    for p in me.polygons:
        axis=max(range(3),key=lambda k:abs(p.normal[k]));p.use_smooth=smooth
        for li in p.loop_indices:
            c=me.vertices[me.loops[li].vertex_index].co
            xy=(c.x,c.y) if axis==2 else ((c.x,c.z) if axis==1 else (c.y,c.z))
            uv.data[li].uv=(xy[0]*.55+offset[0],xy[1]*.55+offset[1])
    if bevel:
        b=o.modifiers.new('Worked stone arris','BEVEL');b.width=bevel;b.segments=3
        w=o.modifiers.new('Weighted normals','WEIGHTED_NORMAL');w.keep_sharp=True
    return o

def box(name,loc,size,mat=STONE,bevel=.012,collision='block'):
    x,y,z=loc;w,d,h=size
    return mesh(name,[(x+sx*w/2,y+sy*d/2,z+sz*h/2) for sz in [-1,1] for sy in [-1,1] for sx in [-1,1]],[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)],mat,bevel,False,collision)

def lathe(name,x,y,profile,mat=STONE,n=48):
    v=[(x+r*math.cos(j*math.tau/n),y+r*math.sin(j*math.tau/n),z) for z,r in profile for j in range(n)]
    f=[tuple(reversed(range(n))),tuple((len(profile)-1)*n+j for j in range(n))]
    f += [(i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j) for i in range(len(profile)-1) for j in range(n)]
    return mesh(name,v,f,mat,smooth=True)

def arch_sector(name,r0,r1,a,b,spring,y0,y1,steps=8):
    pts=[(r*math.cos(a+(b-a)*i/steps),spring+r*math.sin(a+(b-a)*i/steps)) for r,seq in [(r0,range(steps+1)),(r1,range(steps,-1,-1))] for i in seq]
    n=len(pts)
    return mesh(name,[(x,y,z) for y in [y0,y1] for x,z in pts],[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],bevel=.006)

def pipe(name,points,r=.025,mat=STONE):
    cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.resolution_u=3;cu.bevel_depth=r;cu.bevel_resolution=2
    sp=cu.splines.new('POLY');sp.points.add(len(points)-1)
    for p,co in zip(sp.points,points):p.co=(*co,1)
    ob=bpy.data.objects.new(name,cu);SC.collection.objects.link(ob);cu.materials.append(mat);CURRENT.append(ob);ob['rmmo_collision']='none'
    return ob

def end(key,label,notes):
    global CURRENT
    col=bpy.data.collections.new(key);SC.collection.children.link(col)
    for o in CURRENT:
        for c in list(o.users_collection):c.objects.unlink(o)
        col.objects.link(o)
        o['asset_id']=key
    ASSETS.append({'id':key,'label':label,'objects':CURRENT,'installation':notes});CURRENT=[]

def build_arch():
    # Wall is Y=0; whole barrel returns into masonry .08m. Front columns bear the arch.
    for s in [-1,1]:
        x=s*1.48;y=-1.25
        box('Column foundation plinth',(x,y,.11),(.8,.8,.22))
        lathe('Moulded column base',x,y,[(.20,.35),(.27,.35),(.30,.30),(.33,.31),(.39,.26),(.43,.245)])
        for i in range(7):
            z0=.42+i*.385;z1=z0+.381
            r=.244-i*.005
            lathe('Jointed tapered shaft %d'%i,x,y,[(z0,r),(z1,r-.003)],n=48)
        lathe('Neck and bell capital',x,y,[(3.115,.208),(3.16,.224),(3.22,.23),(3.29,.28),(3.34,.34),(3.43,.35)])
        box('Capital abacus',(x,y,3.47),(.86,.88,.13))
        box('Impost bearing back to wall',(x,-.57,3.59),(.80,1.66,.16))
        box('Rear engaged pier',(x,.02,1.79),(.56,.24,3.58))
        box('Rear impost plate',(x,0,3.49),(.77,.34,.22))
    for i in range(17):
        a=i*math.pi/17+.001;b=(i+1)*math.pi/17-.001
        arch_sector('Radial barrel voussoir %02d'%i,1.14,1.58,a,b,3.67,-1.69,.10)
        arch_sector('Front archivolt moulding %02d'%i,1.49,1.65,a,b,3.67,-1.76,-1.61)
    # Tie at spring, close to wall, visibly anchored. Does not descend into passage.
    pipe('Rear spring tie rod',[(-1.48,-.24,3.60),(1.48,-.24,3.60)],.018,IRON)
    for s in [-1,1]:box('Tie anchor plate',(s*1.48,-.25,3.60),(.13,.11,.18),IRON,.004)
    end('s12_projecting_arch','S12 外挑双柱大拱门',{'wall_plane_blender_y':0,'front_blender_y':-1.76,'clear_column_width':2.48,'spring_height':3.67,'inside_crown_height':4.81,'top_height':5.32,'wall_requires_door_opening':True,'supplementary_design':['rear engaged piers','full barrel connection','spring tie anchors'],'note':'Do not use on an uncut solid wall; rear embed is 0.1m.'})

def build_panel():
    # Tall peaked slab; monochrome carved relief, not a printed emblem.
    outline=[(-.49,0),(.49,0),(.57,.10),(.57,2.70),(0,3.25),(-.57,2.70),(-.57,.10)]
    for layer,(scale,y0,y1) in enumerate([(1.,0,.16),(.91,-.035,.012),(.82,-.05,-.024)]):
        pts=[(x*scale,(z-1.625)*scale+1.625) for x,z in outline];n=len(pts)
        mesh('Carved panel layer '+str(layer),[(x,y,z) for y in [y0,y1] for x,z in pts],[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],bevel=.009)
    for scale,y in [(.94,-.06),(.83,-.085)]:
        pts=[(x*scale,y,(z-1.625)*scale+1.625) for x,z in outline];pipe('Perimeter carved bead',pts+[pts[0]],.022)
    def leaf(base,tip,width):
        base=Vector(base);d=Vector(tip)-base;side=Vector((d.z,0,-d.x)).normalized();v=[]
        for i in range(13):
            t=i/12;mid=base+d*t+Vector((0,-.022*math.sin(math.pi*t),0))
            w=width*math.sin(math.pi*t)**.7*(1+.12*math.sin(t*math.pi*6))
            for j in range(7):
                u=j/3-1;p=mid+side*w*u;p.y-=.025*(1-abs(u))*math.sin(math.pi*t);v.append(tuple(p))
        f=[(i*7+j,i*7+j+1,(i+1)*7+j+1,(i+1)*7+j) for i in range(12) for j in range(6)]
        ob=mesh('Lobed carved leaf',v,f,smooth=True,collision='none')
        # Thin leaf-shaped underside merges into the stone recess, not floating foil.
        so=ob.modifiers.new('Carved leaf thickness','SOLIDIFY');so.thickness=.012
        pipe('Carved central leaf rib',[tuple(base+d*t+Vector((0,-.052*math.sin(math.pi*t),0))) for t in np.linspace(0,1,18)],.007)
    stem=[(.065*math.sin(t*math.pi*4),-.082,.22+t*2.72) for t in np.linspace(0,1,150)]
    pipe('Continuous ascending carved vine',stem,.022)
    for i in range(5):
        z=.32+i*.47
        for s in [-1,1]:
            # Rounded volute returns into itself, with leaves sharing its root.
            pts=[]
            for k in range(72):
                t=k/71;a=-math.pi*.75+t*math.pi*2.;r=.20*(1-.72*t)
                pts.append((s*(.18+r*math.cos(a)),-.088,z+.21+r*math.sin(a)))
            pipe('Lateral carved volute',[(.02*s,-.08,z-.02)]+pts,.018)
            for j in range(2):
                leaf((s*(.10+j*.13),-.08,z+.04+j*.13),(s*(.27+j*.08),-.095,z+.29+j*.16),.054)
    for s in [-1,0,1]:leaf((0,-.08,2.62),(s*.16,-.1,2.99-abs(s)*.1),.067)
    end('s12_gable_relief','S12 山墙高窄雕饰板',{'width':1.14,'height':3.25,'wall_plane_blender_y':.16,'relief_front':-.17,'recommended_bottom_height':5.8,'supplementary_design':['abstract ascending foliate carving','concealed masonry fixing'],'note':'Reference visible border/peaked silhouette retained; internal carving not asserted as official pattern.'})

def build_rock(key,w,d,h,seed):
    rng=random.Random(seed);n=40
    phases=[rng.random()*math.tau for _ in range(4)]
    def shape(a):return 1+.055*math.sin(3*a+phases[0])+.04*math.sin(5*a+phases[1])+.025*math.sin(9*a+phases[2])
    rings=[(0,.86),(.075,.99),(.25,1.),(h-.10,.99),(h-.025,.94),(h,.85)]
    v=[]
    for z,f in rings:
        for i in range(n):
            a=math.tau*i/n;rad=shape(a)*f
            # Slightly squared eroded boulder, different outline at every height.
            ca=math.copysign(abs(math.cos(a))**.82,math.cos(a));sa=math.copysign(abs(math.sin(a))**.82,math.sin(a))
            warp=1+.025*math.sin(7*a+z*9+phases[2])
            v.append((ca*w*.5*rad*warp,sa*d*.5*rad*warp,z+.008*math.sin(a*4+phases[3]) if z>0 else 0))
    v.append((0,0,h+.003));top=len(v)-1
    faces=[tuple(reversed(range(n)))]+[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(len(rings)-1) for i in range(n)]
    faces += [((len(rings)-1)*n+i,(len(rings)-1)*n+(i+1)%n,top) for i in range(n)]
    ob=mesh('Natural thick limestone '+key,v,faces,bevel=.009,smooth=True,collision='walk')
    end(key,'S12 水中厚踏石 '+key[-1],{'nominal_dimensions':[w,d,h],'bed_embed':.10,'suggested_water_above_base':.34,'usable_centre_diameter_min':.60,'horizontal_gaps_max':.28,'note':'Origin at base; flat broad crown with rounded irregular sides, place bottom into solid creek bed.'})

def build_steps(key,n):
    width=2.2;rise=.16;tread=.40;landing=.84;length=(n-1)*tread+landing
    # Each tread has full masonry support to foundation. Adjacent regions do not overlap.
    for i in range(n):
        depth=tread if i<n-1 else landing;y=i*tread+depth*.5
        h=(i+1)*rise
        for c in range(4):
            box('Solid step masonry %d-%d'%(i,c),(-width/2+(c+.5)*width/4,y,h*.5),(width/4-.004,depth-.004,h),bevel=.007,collision='walk')
    end(key,'S12 下水石阶台 '+str(n)+'级',{'width':width,'total_rise':n*rise,'rise':rise,'tread':tread,'upper_landing':landing,'length':length,'bottom_blender_y':0,'top_blender_y':length,'note':'Origin bottom-front foundation; lower end faces exported +Z water, upper end -Z land. Embed bottom .06m, adapt bed level rather than stretch risers.'})

def evaluated(o):
    dg=bpy.context.evaluated_depsgraph_get();ev=o.evaluated_get(dg)
    m=bpy.data.meshes.new_from_object(ev,depsgraph=dg);c=bpy.data.objects.new(o.name,m);SC.collection.objects.link(c);c.matrix_world=o.matrix_world
    for key in o.keys():c[key]=o[key]
    return c

def export_asset(row):
    bpy.ops.object.select_all(action='DESELECT');clones=[evaluated(o) for o in row['objects']]
    # Merge only same collision/LOD semantics; original Blender parts stay independent.
    groups={}
    for o in clones:
        k=(o.get('component_id',''),o.get('rmmo_collision','block'),json.dumps(o['rmmo_visibility_range'].to_dict() if 'rmmo_visibility_range' in o else {},sort_keys=True),json.dumps(o['rmmo_wind'].to_dict() if 'rmmo_wind' in o else {},sort_keys=True))
        groups.setdefault(k,[]).append(o)
    joined=[]
    for i,objs in enumerate(groups.values()):
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:o.select_set(True)
        bpy.context.view_layer.objects.active=objs[0]
        bpy.ops.object.join();o=bpy.context.object;o.name=row['id']+'_part_'+str(i);joined.append(o)
    bpy.ops.object.select_all(action='DESELECT')
    for o in joined:o.select_set(True)
    path=OUT/'models'/(row['id']+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
    row['path']=str(path).replace('\\','/');row['source_blend']=str(OUT/'street_assets_master.blend').replace('\\','/')
    coords=[o.matrix_world@v.co for o in joined for v in o.data.vertices]
    lo=[min(v[k] for v in coords) for k in range(3)];hi=[max(v[k] for v in coords) for k in range(3)]
    row['bounds_godot']={'position':[lo[0],lo[2],-hi[1]],'size':[hi[0]-lo[0],hi[2]-lo[2],hi[1]-lo[1]]}
    row['stored_triangles']=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in joined)
    for o in joined:bpy.data.objects.remove(o,do_unlink=True)
    row['sha256']=hashlib.sha256(path.read_bytes()).hexdigest();row['source_bytes']=path.stat().st_size

def main():
    build_arch();build_panel()
    for i,(w,d,h) in enumerate([(1.12,.94,.60),(.98,.92,.58),(1.08,.90,.59),(1.11,.96,.61)]):build_rock('s12_water_step_'+chr(97+i),w,d,h,101+i)
    build_steps('s12_landing_steps_3',3);build_steps('s12_landing_steps_4',4)
    # Four independent nodes, deliberately uneven turns; 0.13m max transverse shift.
    group=[]
    for i,row in enumerate(ASSETS[2:6]):
        for o in row['objects']:
            c=o.copy();c.data=o.data.copy();SC.collection.objects.link(c);c.location=(i*1.28,[-.06,.06,-.03,.03][i],.60-row['installation']['nominal_dimensions'][2]);c.rotation_euler.z=[-.08,.12,-.13,.04][i];c['component_id']=row['id'];group.append(c)
    global CURRENT
    CURRENT=group
    end('s12_water_steps_four','S12 四石示例组合',{'stone_count':4,'centres_x':[0,1.28,2.56,3.84],'bed_height':.10,'suggested_water_height':.34,'top_height':.60,'note':'Four stones remain individually editable in master. No invisible bridge across gaps.'})
    # Installation proof: minimal cut facade, not a new residential house asset.
    original_arch=ASSETS[0]['objects'];original_panel=ASSETS[1]['objects']
    for o in original_arch+original_panel:
        c=o.copy();c.data=o.data.copy();SC.collection.objects.link(c)
        if o in original_panel:c.location.z=5.60
        CURRENT.append(c)
    for s in [-1,1]:box('Example wall opening sides',(s*2.60,.30,2.8),(2.20,.6,5.6))
    box('Example lintel and upper wall',(0,.30,6.4),(7.4,.6,3.4))
    mesh('Example gable',[(-3.7,0,8.1),(3.7,0,8.1),(0,0,11.),(-3.7,.6,8.1),(3.7,.6,8.1),(0,.6,11.)],[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)])
    end('s12_facade_installation_demo','S12 拱门及雕饰板安装验证立面',{'purpose':'installation example only, not complete house','real_opening_width':3.,'real_opening_height':4.7,'wall_blender_y':0})
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'street_assets_master.blend'),compress=True)
    for row in ASSETS:export_asset(row)
    manifest={'date':'2026-10-13','published':False,'production_map_modified':False,'assets':[{k:v for k,v in a.items() if k!='objects'} for a in ASSETS], 'material_source':'Existing owned Quixel Beach Cliff PBR (same as approved stone-surround library)', 'axis':'Blender Z up/-Y front; GLB Godot Y up/+Z front','optimization':'Modest bounded geometry, 3-segment arris retained. No forced decimation. Source objects kept editable.'}
    if (OUT/'manifest.json').exists():
        old=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
        manifest['assets'] += [a for a in old['assets'] if a['id'].startswith('s10_')]
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print('STREET_ASSETS_BUILT',len(ASSETS),flush=True)
if __name__=='__main__':main()
