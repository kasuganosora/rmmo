"""Local grass-topped rock escarpment; preserve original terrain and art masters.

Run in Blender background. Geometry follows the actual east bank, covers its old
sandy slope, and joins unchanged inland terrain and the existing bridge abutment.
"""
import bpy, json, math, random
from pathlib import Path
from mathutils import Vector

BASE=Path('D:/code/rmmo_runtime')
OUT=BASE/'art_sources/bridge_reference_scene_20261006'
OUT.mkdir(parents=True,exist_ok=True)
D=json.loads((BASE/'review_artifacts/bridge_scene_meta_inspect.json').read_text(encoding='utf8'))
terrains=[r for r in D['rmmo_records'] if 'terrain_mesh' in r]
bridge=next(r for r in D['rmmo_records'] if r['uuid']=='stone_e_0be972769041dbc9')
angle=math.radians(bridge['rotation'][1]); c,s=math.cos(angle),math.sin(angle)
cx,_,cz=bridge['position']
def world(x,z):return cx+c*x+s*z,cz-s*x+c*z
def ground(x,z):
    wx,wz=world(x,z)
    for r in terrains:
        tx,ty,tz=r['position'];sx,sy,sz=r['size'];t=r['terrain_mesh'];cols,rows=int(t['columns']),int(t['rows'])
        u=((wx-tx)/sx+.5)*cols;v=((wz-tz)/sz+.5)*rows
        if not(0<=u<=cols and 0<=v<=rows):continue
        ix,iz=min(int(u),cols-1),min(int(v),rows-1);u-=ix;v-=iz;k=iz*(cols+1)+ix
        a,b,d,e=[t['heights'][j]*sy for j in [k,k+1,k+cols+1,k+cols+2]]
        return ty+(a+(b-a)*u+(e-b)*v if u>=v else a+(e-d)*u+(d-a)*v)
    raise ValueError((wx,wz))
def contour(z,h):
    best=min((19+i*.05 for i in range(641)),key=lambda x:abs(ground(x,z)-h))
    return best
def pbr(folder):
    path=BASE/'packs/default/assets/materials'/folder
    spec=json.loads((path/'material.json').read_text(encoding='utf-8-sig'))['material']
    m=bpy.data.materials.new(folder);m.use_nodes=True;nt=m.node_tree;p=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Roughness'].default_value=1
    for key,socket in [('texture_path','Base Color'),('roughness_path','Roughness'),('normal_path','Normal')]:
        im=bpy.data.images.load(str(path/spec[key]),check_existing=True);im.pack()
        if key!='texture_path':im.colorspace_settings.name='Non-Color'
        tex=nt.nodes.new('ShaderNodeTexImage');tex.image=im
        if key=='normal_path':
            n=nt.nodes.new('ShaderNodeNormalMap');nt.links.new(tex.outputs[0],n.inputs['Color']);nt.links.new(n.outputs[0],p.inputs[socket])
        else:nt.links.new(tex.outputs[0],p.inputs[socket])
    return m
def mesh(name,vs,faces,uvs,mat):
    data=bpy.data.meshes.new(name);data.from_pydata(vs,[],faces);data.update()
    ob=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(ob);data.materials.append(mat)
    uv=data.uv_layers.new(name='Surface meters')
    for loop in data.loops:uv.data[loop.index].uv=uvs[loop.vertex_index]
    return ob

bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
rock=pbr('terrain/beach_cliff');grass=pbr('terrain/mossy_grass_vcjmej0s')
reports=[]
for side in [-1,1]:
    random.seed(610060+side);n=180;lines=[]
    for i in range(n+1):
        distance=5.16+34*i/n;z=side*distance
        fade=min(1,(39.16-distance)/5);fade=max(0,fade);fade=fade*fade*(3-2*fade)
        # Shallow water lies immediately at the rock face; no decorative rock row.
        front=contour(z,-1.52)+(.23*math.sin(distance*2.1)+.10*math.sin(distance*5.8))*fade
        inland=contour(z,-.005)+.8
        top=ground(front,z)*(1-fade)+(.035+.07*math.sin(distance*1.3)**2)*fade
        lines.append((z,front,inland,top,fade))
    verts=[];uvs=[];faces=[];across=20
    for z,front,inland,top,fade in lines:
        for j in range(across+1):
            t=j/across;x=front+(inland-front)*t
            y=max(ground(x,z)+.008,top*(1-t)+ground(inland,z)*t+.008)
            if t>.8:y=ground(x,z)+(.008+(y-ground(x,z))*(1-t)/.2)
            verts.append((x,-z,y));wx,wz=world(x,z);uvs.append((wx/4,-wz/4))
    for i in range(n):
        for j in range(across):
            a=i*(across+1)+j;quad=(a,a+1,a+across+2,a+across+1)
            faces.append(quad if side<0 else tuple(reversed(quad)))
    cap=mesh('Continuous grass bank '+str(side),verts,faces,uvs,grass)
    for poly in cap.data.polygons:poly.use_smooth=True
    vs=[];uv=[];fs=[];vertical=12
    for i,(z,front,inland,top,fade) in enumerate(lines):
        # Long irregular fissures and overhangs, rather than repeated round boulders.
        phase=(abs(z)*.63)%1
        fissure=max(0,1-abs(phase-.5)/.075)*.32*fade
        for j in range(vertical+1):
            t=j/vertical;y=top*(1-t)+(-2.35)*t
            x=front+fissure*math.sin(math.pi*t)+fade*(.17*math.sin(abs(z)*1.63+t*1.4)+.055*math.sin(abs(z)*7.3+t*4))*math.sin(math.pi*t)
            vs.append((x,-z,y));uv.append((z/2,y/2))
    for i in range(n):
        for j in range(vertical):
            a=i*(vertical+1)+j;quad=(a,a+1,a+vertical+2,a+vertical+1)
            fs.append(quad if side>0 else tuple(reversed(quad)))
    face=mesh('Fractured limestone river face '+str(side),vs,fs,uv,rock)
    # Preserve broad fractures; scan normals carry the smaller material detail.
    for poly in face.data.polygons:poly.use_smooth=True
    reports.append({'side':side,'length_m':34,'water_level':-1.5,'top_range':[min(r[3] for r in lines),max(r[3] for r in lines)],'cross_sections':lines[::15]})

bpy.context.scene.unit_settings.system='METRIC'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'grass_rock_bank_master.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'grass_rock_bank.glb'),export_format='GLB',export_yup=True,export_extras=True,export_materials='EXPORT')
(OUT/'bank_recipe.json').write_text(json.dumps({'bridge':bridge['uuid'],'position':[cx,0,cz],'yaw':bridge['rotation'][1],'banks':reports,'source':'Quixel Beach Cliff and Mossy Grass already installed; generated local bank geometry, not a scanned cliff model','triangles':sum(len(o.data.polygons)*2 for o in bpy.context.scene.objects if o.type=='MESH')},indent=2),encoding='utf8')
print('BANK_EXPORTED',OUT)
