"""S10 broadleaf red-fruit adaptation; retain acquired oak source and all leaf alpha.
Species intentionally unspecified. Source is an earlier approved Quixel-derived tree.
"""
import sys,math,json,hashlib,struct,random
from pathlib import Path
import bpy,numpy as np
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
import build_required_street_assets as kit
OUT=kit.OUT;SC=kit.SC
SRC=Path('D:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011/architecture/oak_9ba5457e_lossless.glb')
source_sha=hashlib.sha256(SRC.read_bytes()).hexdigest()
bpy.ops.import_scene.gltf(filepath=str(SRC))
objs=[o for o in bpy.context.selected_objects if o.type=='MESH']
canopies=sorted([o for o in objs if 'Canopy' in o.name],key=lambda o:o.name)
assert len(canopies)==3,[o.name for o in objs]
for o in objs:
    bpy.context.view_layer.objects.active=o
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
points=[v.co.copy() for v in canopies[0].data.vertices]
lo=Vector(tuple(min(v[k] for v in points) for k in range(3)));hi=Vector(tuple(max(v[k] for v in points) for k in range(3)))
sx=6.4/(hi.x-lo.x);sy=6.3/(hi.y-lo.y);sz=6.6/hi.z
for o in objs:
    for v in o.data.vertices:
        v.co.x*=sx;v.co.y*=sy;v.co.z*=sz
    o.name=o.name.replace('Oak','Redfruit')
    o['asset_id']='s10_redfruit_broadleaf'
    o['source_provenance']='Owned Quixel English Oak derived trunk and previously approved local-baked broadleaf canopy; no species claim'
    o['rmmo_collision']='none' if o in canopies else 'block'

def fruit_material():
    m=kit.plain('Red fruit waxy skin',(1.,1.,1.),.53)
    nt=m.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
    n=384;yy,xx=np.mgrid[0:n,0:n];u=xx/n;v=yy/n
    rng=np.random.default_rng(61013)
    noise=rng.random((n,n));stripes=np.sin(u*math.tau*19+np.sin(v*11)*.8)*.5+.5
    blush=.80+.16*np.sin(u*math.tau+v*2)+.04*stripes
    a=np.ones((n,n,4),np.float32)
    a[:,:,0]=np.clip(.40*blush+.045*stripes+(noise-.5)*.020,.02,1)
    a[:,:,1]=.023+.022*stripes;a[:,:,2]=.013+.009*stripes
    dots=noise>.998;a[dots,:3]=(.34,.21,.11)
    im=bpy.data.images.new('Original project red fruit skin',width=n,height=n,alpha=True);im.pixels.foreach_set(a.ravel());im.pack()
    tex=nt.nodes.new('ShaderNodeTexImage');tex.image=im;nt.links.new(tex.outputs[0],bs.inputs['Base Color'])
    return m
FRUIT=fruit_material();STEM=kit.plain('Fruit stem dark wood',(.10,.063,.028),.86)

# Woody canopy points provide real attachment positions, not floating random fruit.
can=canopies[0];woody=[]
for poly in can.data.polygons:
    mat=can.data.materials[poly.material_index]
    if 'bark' not in mat.name.lower():continue
    for ix in poly.vertices:
        p=can.data.vertices[ix].co
        if 2.8<p.z<5.6 and 1.4<math.hypot(p.x,p.y)<3.1:woody.append(tuple(p))
assert len(woody)>100
r=random.Random(61013);r.shuffle(woody);anchors=[]
for raw in woody:
    p=Vector(raw)
    if all((p-Vector(q)).length>.43 for q in anchors):anchors.append(raw)
    if len(anchors)==70:break
assert len(anchors)>=45,len(anchors)
fruit_specs=[]
for i,xyz in enumerate(anchors):
    radius=r.uniform(.095,.127)
    fruit_specs.append({'anchor':xyz,'centre':(xyz[0]+r.uniform(-.04,.04),xyz[1]+r.uniform(-.04,.04),xyz[2]-radius-.06),'radius':radius,'phase':r.random()*math.tau})

def add_fruit(spec,n,k):
    cx,cy,cz=spec['centre'];radius=spec['radius'];phase=spec['phase']
    v=[];uv=[]
    for j in range(k+1):
        t=math.pi*j/k
        z=math.cos(t)*.96-.16*math.exp(-(t/.35)**2)+.10*math.exp(-((math.pi-t)/.4)**2)
        for i in range(n+1):
            a=math.tau*i/n;rr=math.sin(t)*(1+.045*math.cos(5*a+phase)*math.sin(t)**2)
            v.append((cx+radius*rr*math.cos(a),cy+radius*rr*math.sin(a),cz+radius*z))
    f=[(j*(n+1)+i,j*(n+1)+i+1,(j+1)*(n+1)+i+1,(j+1)*(n+1)+i) for j in range(k) for i in range(n)]
    o=kit.mesh('Red fruit',v,f,FRUIT,smooth=True,collision='none')
    for p in o.data.polygons:
        for li in p.loop_indices:
            ix=o.data.loops[li].vertex_index;o.data.uv_layers[0].data[li].uv=(ix%(n+1)/n,ix//(n+1)/k)
    kit.pipe('Attached fruit stem',[spec['anchor'],(cx,cy,cz+radius*.79)],.009,STEM)

for level,can in enumerate(canopies):
    kit.CURRENT=[]
    for spec in fruit_specs:add_fruit(spec,*[(20,12),(12,7),(8,5)][level])
    extra=[kit.evaluated(o) for o in kit.CURRENT]
    for o in kit.CURRENT:bpy.data.objects.remove(o,do_unlink=True)
    bpy.ops.object.select_all(action='DESELECT');can.select_set(True)
    for o in extra:o.select_set(True)
    bpy.context.view_layer.objects.active=can;bpy.ops.object.join()
    # Shared bounds include deformation margin; all LODs use same full-tree centre.
    can['rmmo_visibility_range']={'begin':[0.,45.,100.][level],'end':[45.,100.,0.][level],'bounds':[-3.55,-.20,-3.50,7.1,7.1,7.0]}
    can['rmmo_editor_picking']={'version':1,'group':'redfruit_canopy','role':'canonical' if level==0 else 'render_lod'}
    if level<2:can['rmmo_wind']={'profile':'foliage','mesh':'*','amplitude':.045,'stiffness':.9,'anchor':'bottom','shelter':True}
    elif 'rmmo_wind' in can:del can['rmmo_wind']

kit.CURRENT=objs
kit.end('s10_redfruit_broadleaf','S10 写实红果阔叶树',{'species':'unspecified fantasy broadleaf; not botanically claimed','nominal_canopy_width':6.4,'height':6.6,'fruit_count':len(fruit_specs),'fruit_diameter':[.190,.254],'ground_origin':[0,0,0],'source_fab':'https://www.fab.com/listings/83642c38-7661-4df1-8629-0422e1898d26','source_glb':str(SRC),'source_sha256':source_sha,'note':'Fruit size is third-person legibility design, not measured botanical size. Grounded trunk; crown needs actual AABB clearance.'})
row=kit.ASSETS[-1]
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'redfruit_master.blend'),compress=True)
kit.export_asset(row)
path=Path(row['path']);data=path.read_bytes();ln=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+ln]);binary=data[28+ln:]
leafids=[]
for i,m in enumerate(doc.get('materials',[])):
    if 'leaf' in m.get('name','').lower():m['alphaMode']='MASK';m['alphaCutoff']=.4;m['doubleSided']=True;leafids.append(i)
for n in doc['nodes']:
    if 'mesh' in n:n.setdefault('extras',{})['rmmo_leaf_backlight']=[.14 if p.get('material') in leafids else 0. for p in doc['meshes'][n['mesh']]['primitives']]
enc=json.dumps(doc,separators=(',',':')).encode();enc+=b' '*((-len(enc))%4)
path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(enc)+len(binary))+struct.pack('<II',len(enc),0x4e4f534a)+enc+struct.pack('<II',len(binary),0x004e4942)+binary)
row['sha256']=hashlib.sha256(path.read_bytes()).hexdigest();row['source_bytes']=path.stat().st_size;row['source_blend']=str(OUT/'redfruit_master.blend')
row['lod_ranges']=[0,45,100,0];row['fruit_anchors']=fruit_specs
manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'));manifest['assets']=[a for a in manifest['assets'] if a['id']!=row['id']]+[{k:v for k,v in row.items() if k!='objects'}]
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
assert hashlib.sha256(SRC.read_bytes()).hexdigest()==source_sha
print('REDFRUIT_BUILT',len(fruit_specs),row['sha256'],flush=True)
