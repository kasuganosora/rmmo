"""Reference/material repairs on isolated copies of today's S10/S12 mothers.

No original source, existing catalogue, map or previous review is overwritten.
Blender background only; GPU visual acceptance is a separate scheduled step.
"""
import bpy, bmesh, json, hashlib, math, sys, struct, shutil
import numpy as np
from pathlib import Path
from mathutils import Vector

BASE=Path('D:/code/rmmo_runtime/art_sources/required_street_assets_20261013')
OUT=BASE/'review_v2'
MAPS=OUT/'materials'
GUILD_MAPS=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3/materials')
MANIFEST=json.loads((BASE/'manifest.json').read_text(encoding='utf8'))
REPORT={'reference_revision':'20261013','source_manifest':str(BASE/'manifest.json'),'changes':[]}

def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def principal(mat):return next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')

def assign_uv(ob,faces=None,tile=1.):
    uv=ob.data.uv_layers.active or ob.data.uv_layers.new(name='MetreStoneUV')
    for face in ob.data.polygons if faces is None else faces:
        n=face.normal.normalized();axis=Vector((1,0,0)) if abs(n.x)<.85 else Vector((0,1,0))
        u=(axis-n*axis.dot(n)).normalized();v=n.cross(u)
        for li in face.loop_indices:
            co=ob.data.vertices[ob.data.loops[li].vertex_index].co
            uv.data[li].uv=(co.dot(u)/tile,co.dot(v)/tile)

def cut_material():
    mat=bpy.data.materials.new('S12 cut limestone mineral | reviewed 20261013');mat.use_nodes=True
    p=principal(mat);p.inputs['Roughness'].default_value=.8
    for file,socket,color in [('guild_cut_limestone_mineral_color.png','Base Color',True),
                              ('guild_cut_limestone_roughness.png','Roughness',False),
                              ('guild_cut_limestone_micro_normal.png','Normal',False)]:
        source=GUILD_MAPS/file;assert source.is_file(),source;target=MAPS/file
        shutil.copy2(source,target)
        image=bpy.data.images.load(str(target),check_existing=False);image.colorspace_settings.name='sRGB' if color else 'Non-Color';image.pack()
        node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=image
        if socket=='Normal':
            normal=mat.node_tree.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.23
            mat.node_tree.links.new(node.outputs['Color'],normal.inputs['Color']);mat.node_tree.links.new(normal.outputs['Normal'],p.inputs[socket])
        else:mat.node_tree.links.new(node.outputs['Color'],p.inputs[socket])
    mat['provenance']='Project fine cut limestone maps; avoids cliff strata across small worked stone and relief carving'
    return mat

def realise(ob):
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    if ob.type=='CURVE':bpy.ops.object.convert(target='MESH')
    return bpy.context.object

def repair_leaf(ob):
    """Retain sculpted front, close rear into the relief base at Y=-.035 m."""
    for m in list(ob.modifiers):
        if m.type=='SOLIDIFY':ob.modifiers.remove(m)
    me=ob.data;vs=[tuple(v.co) for v in me.vertices];front=[tuple(p.vertices) for p in me.polygons]
    edge_counts={}
    for face in front:
        for a,b in zip(face,face[1:]+face[:1]):
            key=tuple(sorted((a,b)));edge_counts[key]=edge_counts.get(key,0)+1
    n=len(vs);vs += [(v[0],-.035,v[2]) for v in vs]
    fs=front+[tuple(i+n for i in reversed(face)) for face in front]
    fs += [(a,b,b+n,a+n) for (a,b),count in edge_counts.items() if count==1]
    fresh=bpy.data.meshes.new(me.name+' embedded relief');fresh.from_pydata(vs,[],fs);fresh.update()
    bm=bmesh.new();bm.from_mesh(fresh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(fresh);bm.free()
    for m in me.materials:fresh.materials.append(m)
    ob.data=fresh
    for p in fresh.polygons:p.use_smooth=True

def repair_street():
    source=BASE/'street_assets_master.blend';bpy.ops.wm.open_mainfile(filepath=str(source))
    stone=cut_material();leaf_count=0;curve_count=0;uv_faces=0
    groups={}
    for row in MANIFEST['assets']:
        if not row['id'].startswith('s12_'):continue
        col=bpy.data.collections[row['id']];groups[row['id']]=list(col.objects)
        if row['id'].startswith('s12_water_step'):
            for ob in groups[row['id']]:
                # Rounded boulder shoulders previously intercepted the leading
                # support ray below the crown. Give the real visible crown a
                # broad, shallow arris; do not hide a bridging collision slab.
                if ob.type!='MESH' or len(ob.data.vertices)!=241:continue
                h=ob.data.vertices[240].co.z-.003
                for i in range(40):
                    # Crown covers every lower contour, so a down ray cannot
                    # catch an outward bulging belly hidden below the tread.
                    edge=max((ob.data.vertices[ring*40+i].co.copy() for ring in range(6)),key=lambda p:p.x*p.x+p.y*p.y)
                    ripple=ob.data.vertices[200+i].co.z-h
                    for ring,z,factor in [(3,h-.035,1.012),(4,h-.009,1.018),(5,h,1.020)]:
                        v=ob.data.vertices[ring*40+i];v.co.x=edge.x*factor;v.co.y=edge.y*factor;v.co.z=z+ripple
                ob.data.update();ob['reference_revision']='20261013'
            continue
        for ob in groups[row['id']]:
            if ob.name.startswith('Lobed carved leaf'):repair_leaf(ob);leaf_count+=1
            elif ob.type=='CURVE':
                # Raised carved vines/volutes must grow out of the back slab,
                # rather than hover 10–30 mm above it like attached metal wire.
                if any(k in ob.name for k in ['ascending carved vine','Lateral carved volute','Perimeter carved bead']):
                    for spline in ob.data.splines:
                        for p in spline.points:p.co.y+=.025
                ob=realise(ob);curve_count+=1
            if ob.type!='MESH':continue
            touched=False
            for i,mat in enumerate(ob.data.materials):
                if mat and 'limestone' in mat.name.lower():ob.data.materials[i]=stone;touched=True
            if touched:assign_uv(ob);uv_faces+=len(ob.data.polygons)
            ob['reference_revision']='20261013'
    REPORT['changes'].append({'kind':'S12 cut stone and relief','closed_embedded_leaf_parts':leaf_count,
                              'curves_realised_for_valid_uv':curve_count,'metre_uv_faces':uv_faces,
                              'geometry_preserved':['arch bearing/clear opening','step rise .16m/tread .40m'],
                              'stone_fix':'Real broad flat crowns with 9mm arris, preserves separated gaps; no invisible bridge or collision enlargement',
                              'supplementary_design':'Interior foliate motif remains project supplementary design, not an official pattern'})
    mother=OUT/'street_assets_master_reviewed.blend';bpy.ops.wm.save_as_mainfile(filepath=str(mother),compress=True)
    result=[]
    for row in MANIFEST['assets']:
        if row['id'] in groups:result.append(export(row,groups[row['id']],mother))
    return result

def uv_metrics(ob):
    uv=ob.data.uv_layers.active;values=[]
    for face in ob.data.polygons:
        if abs(face.center.z)>2.1 or len(face.vertices)<3:continue
        ps=[ob.data.vertices[i].co for i in face.vertices[:3]]
        us=[uv.data[i].uv for i in face.loop_indices[:3]]
        a=np.array([ps[1]-ps[0],ps[2]-ps[0]]);b=np.array([us[1]-us[0],us[2]-us[0]])
        gradients=np.linalg.lstsq(a,b,rcond=None)[0]
        values.append(np.abs(gradients[2]))
    return np.median(values,axis=0).tolist()

def repair_tree():
    source=BASE/'redfruit_master.blend';bpy.ops.wm.open_mainfile(filepath=str(source))
    objects=[o for o in bpy.data.objects if o.type=='MESH'];fruit_faces=0;tree_log=[]
    for ob in objects:
        uv=ob.data.uv_layers.get('UVMap');fruit_uv=ob.data.uv_layers.get('StoneUV')
        assert uv
        bark_slots={i for i,m in enumerate(ob.data.materials) if 'bark' in m.name.lower()}
        fruit_slots={i for i,m in enumerate(ob.data.materials) if m.name=='Red fruit waxy skin'}
        if fruit_slots:
            assert fruit_uv
            for face in ob.data.polygons:
                if face.material_index not in fruit_slots:continue
                for li in face.loop_indices:uv.data[li].uv=fruit_uv.data[li].uv
                fruit_faces+=1
        if 'Trunk' in ob.name:
            tree_log.append({'object':ob.name,'median_abs_uv_change_per_vertical_m_before':uv_metrics(ob)})
        # Original bark's tall furrows ran horizontally around this trunk.
        # Make growth-aligned UVs only for bark. Canopy leaf atlas and fruits
        # retain their established independent maps.
        for face in ob.data.polygons:
            if face.material_index not in bark_slots:continue
            n=face.normal;axis=0 if abs(n.y)>abs(n.x) else 1
            for li in face.loop_indices:
                co=ob.data.vertices[ob.data.loops[li].vertex_index].co
                uv.data[li].uv=(co[axis]/1.,co.z/2.)
        ob.data.uv_layers.active=uv;uv.active_render=True
        ob['reference_revision']='20261013'
    # The spherical fruits had an unbound secondary UV; the existing skin map
    # is retained, with a portable matched roughness map rather than flat gloss.
    mat=bpy.data.materials['Red fruit waxy skin'];mat.name='Red fruit waxy skin | reviewed 20261013'
    p=principal(mat);n=384;yy,xx=np.mgrid[0:n,0:n];rng=np.random.default_rng(6132026)
    pores=rng.random((n,n));rough=.47+.08*np.sin(xx/n*math.tau*19+np.sin(yy/n*11)*.8)**2+(pores-.5)*.018
    im=bpy.data.images.new('Fruit skin roughness reviewed',width=n,height=n,alpha=False);im.colorspace_settings.name='Non-Color'
    rgba=np.ones((n,n,4),np.float32);rgba[:,:,:3]=rough[:,:,None];im.pixels.foreach_set(rgba.ravel())
    im.filepath_raw=str(MAPS/'fruit_skin_roughness.png');im.file_format='PNG';im.save();im.pack()
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im;mat.node_tree.links.new(tex.outputs['Color'],p.inputs['Roughness'])
    REPORT['changes'].append({'kind':'S10 UV/material','fruit_faces_corrected':fruit_faces,'bark_checks':tree_log,
                              'preserved':'All leaves/alpha/leaf atlas UV, fruit anchors and geometry, canopy LOD ranges and wind metadata',
                              'fix':'Correct fruit secondary-UV merge; metre-scale vertical bark rather than horizontal stretch'})
    mother=OUT/'redfruit_master_reviewed.blend';bpy.ops.wm.save_as_mainfile(filepath=str(mother),compress=True)
    row=next(r for r in MANIFEST['assets'] if r['id']=='s10_redfruit_broadleaf')
    return export(row,objects,mother,tree=True)

def export(row,objects,mother,tree=False):
    clones=[];dg=bpy.context.evaluated_depsgraph_get()
    for ob in objects:
        me=bpy.data.meshes.new_from_object(ob.evaluated_get(dg),depsgraph=dg)
        c=bpy.data.objects.new(ob.name,me);bpy.context.scene.collection.objects.link(c);c.matrix_world=ob.matrix_world.copy()
        for k in ob.keys():c[k]=ob[k]
        clones.append(c)
    groups={}
    for o in clones:
        key=(o.get('component_id',''),o.get('rmmo_collision','block'),
             repr(o.get('rmmo_visibility_range',{}).to_dict() if hasattr(o.get('rmmo_visibility_range',{}),'to_dict') else {}),
             repr(o.get('rmmo_wind',{}).to_dict() if hasattr(o.get('rmmo_wind',{}),'to_dict') else {}))
        groups.setdefault(key,[]).append(o)
    joined=[]
    for i,parts in enumerate(groups.values()):
        bpy.ops.object.select_all(action='DESELECT')
        for o in parts:o.select_set(True)
        bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();o=bpy.context.object
        o.name=row['id']+'_part_'+str(i);joined.append(o)
    bpy.ops.object.select_all(action='DESELECT')
    for o in joined:o.select_set(True)
    path=OUT/'models'/(row['id']+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,
                              export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
    tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in joined)
    coords=[o.matrix_world@v.co for o in joined for v in o.data.vertices]
    lo=[min(v[k] for v in coords) for k in range(3)];hi=[max(v[k] for v in coords) for k in range(3)]
    bounds={'position':[lo[0],lo[2],-hi[1]],'size':[hi[0]-lo[0],hi[2]-lo[2],hi[1]-lo[1]]}
    for o in joined:bpy.data.objects.remove(o,do_unlink=True)
    if tree:
        raw=path.read_bytes();ln=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+ln]);binary=raw[28+ln:]
        leafids=[]
        for i,m in enumerate(doc['materials']):
            if 'leaf' in m.get('name','').lower():m['alphaMode']='MASK';m['alphaCutoff']=.4;m['doubleSided']=True;leafids.append(i)
        for n in doc['nodes']:
            if 'mesh' in n:n.setdefault('extras',{})['rmmo_leaf_backlight']=[.14 if p.get('material') in leafids else 0. for p in doc['meshes'][n['mesh']]['primitives']]
        enc=json.dumps(doc,separators=(',',':')).encode();enc+=b' '*((-len(enc))%4)
        path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(enc)+len(binary))+struct.pack('<II',len(enc),0x4e4f534a)+enc+struct.pack('<II',len(binary),0x004e4942)+binary)
    result=dict(row);result.update(path=str(path),source_blend=str(mother),source_bytes=path.stat().st_size,
                                   sha256=digest(path),stored_triangles=tris,bounds_godot=bounds,baseline_sha256=row['sha256'],
                                   reference_revision='20261013',review_state='CPU built; native/GPU review pending')
    return result

def main():
    OUT.mkdir(exist_ok=True);MAPS.mkdir(exist_ok=True);(OUT/'models').mkdir(exist_ok=True)
    original={r['path']:digest(r['path']) for r in MANIFEST['assets']}
    assert all(original[r['path']]==r['sha256'] for r in MANIFEST['assets'])
    rows=repair_street();rows.append(repair_tree())
    assert all(digest(p)==sha for p,sha in original.items()),'Original assets must remain unchanged'
    result={k:v for k,v in MANIFEST.items() if k!='assets'};result['assets']=rows;result['baseline_manifest']=str(BASE/'manifest.json')
    result['status']='Repaired candidate; not published';result['production_map_modified']=False
    (OUT/'manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    REPORT['original_source_shas_preserved']=original;REPORT['assets']=[{'id':r['id'],'sha256':r['sha256'],'triangles':r['stored_triangles']} for r in rows]
    (OUT/'repair_report.json').write_text(json.dumps(REPORT,ensure_ascii=False,indent=2),encoding='utf8')
    print('STREET_REFERENCE_REPAIRED',json.dumps(REPORT['changes']),flush=True)

if __name__=='__main__':main()
