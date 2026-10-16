"""CPU-only v3 sewn-binding geometry correction; never rebakes source textures.

Only CanopyTrim is exported. The original master, all other meshes, the shared
builder, materials, UVs and catalogue stay untouched. Four assets are processed
serially by Blender background mode.
"""
import bpy, bmesh, json, hashlib, math
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ART=Path('D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016')
OUT=ART/'v4_canopy_trim'
# Sub-millimetre seam clearance keeps a sewn binding against the cloth and
# respects the original outside envelope; this is not a floating cover plate.
TARGET_GAP=.0004

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def tree_for(obj):
    return BVHTree.FromPolygons([obj.matrix_world@v.co for v in obj.data.vertices], [tuple(f.vertices) for f in obj.data.polygons])

def connected_groups(mesh):
    parents=list(range(len(mesh.vertices)))
    def root(i):
        while parents[i]!=i:parents[i]=parents[parents[i]];i=parents[i]
        return i
    for edge in mesh.edges:
        a,b=[root(i) for i in edge.vertices];parents[b]=a
    groups={}
    for i in range(len(parents)):groups.setdefault(root(i),[]).append(i)
    return list(groups.values())

def uv_signature(mesh):
    layer=mesh.uv_layers['GameAtlas']
    return sorted((loop.vertex_index,*layer.data[loop.index].uv[:]) for loop in mesh.loops)

def bounds(objects):
    points=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
    return [[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]

def run_asset(asset):
    source=ART/'v3'/asset/'runtime_baked.blend';source_sha=sha(source)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    trim=bpy.data.objects['CanopyTrim'];cloth=bpy.data.objects['CanopyCloth']
    tree=tree_for(cloth);world=trim.matrix_world;inv=world.inverted()
    outputs=[o for o in bpy.context.scene.objects if o.type=='MESH' and not o.hide_render]
    original_bounds=bounds(outputs);uv_before=uv_signature(trim.data)
    original_positions=[world@v.co for v in trim.data.vertices]
    vertex_outward={};components=[]
    for indices in connected_groups(trim.data):
        points=[world@trim.data.vertices[i].co for i in indices]
        span=[max(p[k] for p in points)-min(p[k] for p in points) for k in range(3)]
        axis=1 if span[0]>span[1] else 0
        normal=Vector((0,0,0));normal[axis]=1 if sum(p[axis] for p in points)>0 else -1
        for i in indices:vertex_outward[i]=normal
        ids=set(indices);faces=[f for f in trim.data.polygons if f.vertices[0] in ids]
        components.append((indices,faces,normal))
    def gap(point,normal):
        hit,_,_,_=tree.ray_cast(point+normal*.05,-normal,.1)
        return (point-hit).dot(normal) if hit is not None else None
    def sample_faces(faces,normal,dense=False):
        samples=[]
        for face in faces:
            vi=list(face.vertices)
            for tri in [(vi[0],vi[j],vi[j+1]) for j in range(1,len(vi)-1)]:
                p=[world@trim.data.vertices[i].co for i in tri]
                weights=[(1,0,0),(0,1,0),(0,0,1),(.5,.5,0),(.5,0,.5),(0,.5,.5),(1/3,1/3,1/3)]
                if dense:
                    weights += [(i/6,j/6,1-(i+j)/6) for i in range(7) for j in range(7-i)]
                for w in weights:
                    d=gap(p[0]*w[0]+p[1]*w[1]+p[2]*w[2],normal)
                    if d is not None:samples.append((d,tri))
        return samples
    before=[d for _,faces,n in components for d,_ in sample_faces(faces,n,True)]
    # Conform only insufficient-clearance vertices; do not float whole ribbons
    # by the worst corner deficit. Midpoint constraints catch deformed quads.
    for indices,faces,n in components:
        for i in indices:
            point=world@trim.data.vertices[i].co;d=gap(point,n)
            if d is not None and d<TARGET_GAP:
                trim.data.vertices[i].co=inv@(point+n*(TARGET_GAP-d))
        for iteration in range(8):
            corrections={}
            for d,tri in sample_faces(faces,n,True):
                if d<TARGET_GAP-2e-5:
                    for i in tri:corrections[i]=max(corrections.get(i,0),TARGET_GAP-d)
            if not corrections:break
            for i,shift in corrections.items():
                point=world@trim.data.vertices[i].co
                trim.data.vertices[i].co=inv@(point+n*shift)
    # The old ribbons had mixed front/back winding. Face reversal preserves
    # each vertex's authored UV and produces consistent outward shading frames.
    component_face_indices=[(indices,[f.index for f in faces],n) for indices,faces,n in components]
    bm=bmesh.new();bm.from_mesh(trim.data);bm.verts.ensure_lookup_table();bm.faces.ensure_lookup_table()
    flipped=0
    for face in bm.faces:
        n=vertex_outward[face.verts[0].index]
        if face.normal.dot(n)<0:face.normal_flip();flipped+=1
    bm.normal_update();bm.to_mesh(trim.data);bm.free();trim.data.update()
    # MeshPolygon RNA references become invalid after BMesh replaces the mesh.
    components=[(indices,[trim.data.polygons[i] for i in face_indices],n) for indices,face_indices,n in component_face_indices]
    assert uv_signature(trim.data)==uv_before, 'UV associations changed while correcting winding'
    assert not trim.data.has_custom_normals, 'Unexpected frozen custom normals need separate conversion'
    trim.data.calc_tangents(uvmap='GameAtlas')
    after=[d for _,faces,n in components for d,_ in sample_faces(faces,n,True)]
    new_bounds=bounds(outputs)
    assert all(abs(a-b)<1e-6 for row0,row1 in zip(original_bounds,new_bounds) for a,b in zip(row0,row1)), (original_bounds,new_bounds)
    assert min(after)>=TARGET_GAP-5e-5, min(after)
    overlaps=tree.overlap(tree_for(trim))
    assert len(overlaps)==0, 'Remaining cloth/trim geometric intersection'
    assert all(face.normal.dot(vertex_outward[face.vertices[0]])>0 for face in trim.data.polygons)
    shifts=[(world@v.co-original_positions[v.index]).length for v in trim.data.vertices]
    out=OUT/asset;out.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT');trim.hide_set(False);trim.hide_render=False;trim.select_set(True);bpy.context.view_layer.objects.active=trim
    trim['rmmo_trim_clearance_revision']=1
    bpy.ops.export_scene.gltf(filepath=str(out/'delta.glb'),export_format='GLB',use_selection=True,export_extras=True,export_animations=False,export_tangents=True)
    trim.data.calc_loop_triangles()
    report={'asset':asset,'source':str(source),'source_sha256':source_sha,'source_unchanged':sha(source)==source_sha,'delta_sha256':sha(out/'delta.glb'),
            'patch_sha256':sha(__file__),'only_exported_group':'CanopyTrim','triangles':len(trim.data.loop_triangles),'components':len(components),
            'minimum_gap_before_m':min(before),'penetrating_samples_before':sum(d<0 for d in before),'minimum_gap_after_m':min(after),'penetrating_samples_after':sum(d<0 for d in after),
            'dense_samples_after':len(after),'intersection_pairs_after':len(overlaps),'faces_corrected_outward':flipped,
            'moved_vertices':sum(d>1e-6 for d in shifts),'maximum_vertex_shift_m':max(shifts),'uv_vertex_associations_identical':True,
            'old_bounds':original_bounds,'new_bounds':new_bounds,'outer_bounds_unchanged':True,'textures_rebaked':False,'shadow_settings_changed':False,'gpu_executed':False,'visual_accepted':False}
    (out/'cpu_report.json').write_text(json.dumps(report,indent=2))
    print('TRIM_PATCH '+json.dumps(report),flush=True)
    return report

if __name__=='__main__':
    OUT.mkdir(exist_ok=True)
    rows=[run_asset(asset) for asset in ['pottery','scroll','potion','ore']]
    (OUT/'manifest.json').write_text(json.dumps(rows,indent=2))
