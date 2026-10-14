"""Only the four reference stones and their assembly; preserve the other six SHAs.

Broad approach crowns remain on X; weathered shoulders on Y recover the S12
natural silhouette. Uses the existing owned non-stratified rock PBR maps.
"""
import bpy, json, shutil, math, hashlib, sys
import numpy as np
from pathlib import Path

sys.path.insert(0,str(Path(__file__).parent))
import repair_required_street_assets_20261013 as common

OUT=common.OUT
SOURCE=OUT/'street_assets_master_reviewed.blend'
LIB=Path('D:/code/rmmo_runtime/packs/default/assets/materials/terrain/natural_rock_02')

def material():
    mat=bpy.data.materials.new('S12 natural weathered rock | reviewed shoulders 20261013');mat.use_nodes=True
    bs=common.principal(mat)
    for file,socket in [('texture.png','Base Color'),('roughness.png','Roughness'),('normal.png','Normal')]:
        target=common.MAPS/('stepping_stone_'+file);shutil.copy2(LIB/file,target)
        im=bpy.data.images.load(str(target),check_existing=False);im.colorspace_settings.name='sRGB' if socket=='Base Color' else 'Non-Color';im.pack()
        if socket=='Normal':
            # The owned Unreal source explicitly declares DirectX normals.
            # glTF/Blender uses +Y tangent normals; preserve X/Z, invert green.
            pixels=np.empty(len(im.pixels),dtype=np.float32);im.pixels.foreach_get(pixels)
            pixels.reshape(-1,4)[:,1]=1-pixels.reshape(-1,4)[:,1]
            im.pixels.foreach_set(pixels);im.filepath_raw=str(target);im.file_format='PNG';im.save();im.pack()
        tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
        if socket=='Normal':
            nm=mat.node_tree.nodes.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.28
            mat.node_tree.links.new(tex.outputs['Color'],nm.inputs['Color']);mat.node_tree.links.new(nm.outputs['Normal'],bs.inputs[socket])
        else:mat.node_tree.links.new(tex.outputs['Color'],bs.inputs[socket])
    mat['provenance']=str(LIB/'material.json')
    return mat

def main():
    manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf8'))
    changed=[r for r in manifest['assets'] if r['id'].startswith('s12_water_step')]
    kept={r['path']:common.digest(r['path']) for r in manifest['assets'] if r not in changed}
    rollback=OUT/'rollback/stone_cap_v1';rollback.mkdir(parents=True,exist_ok=True)
    for path in [SOURCE,OUT/'manifest.json',*[Path(r['path']) for r in changed]]:
        dest=rollback/path.name
        if not dest.exists():shutil.copy2(path,dest)
    bpy.ops.wm.open_mainfile(filepath=str(rollback/SOURCE.name))
    mat=material();groups={}
    for row in changed:
        objects=list(bpy.data.collections[row['id']].objects);groups[row['id']]=objects
        for ob in objects:
            if ob.type!='MESH' or len(ob.data.vertices)!=241:continue
            h=ob.data.vertices[240].co.z-.003
            for i in range(40):
                a=math.tau*i/40
                edge=ob.data.vertices[200+i].co.copy();edge.x/=1.020;edge.y/=1.020
                ripple=ob.data.vertices[200+i].co.z-h
                # The 0.6m central walking strip/approach lips stay intact.
                shoulder=max(0.,min(1.,(abs(math.sin(a))-.64)/.36))
                shoulder=shoulder*shoulder*(3-2*shoulder)
                chip=.5+.5*math.sin(7*a+.4)
                for ring,z,factor in [(3,h-.035-shoulder*.135,1.012+shoulder*.015*chip),
                                      (4,h-.009-shoulder*.068,1.018-shoulder*.035),
                                      (5,h-shoulder*.017,1.020-shoulder*(.17+.045*chip))]:
                    v=ob.data.vertices[ring*40+i];v.co.x=edge.x*factor;v.co.y=edge.y*factor;v.co.z=z+ripple
            ob.data.update()
            ob.data.materials.clear();ob.data.materials.append(mat)
            # Same metric footprint, varied UV origin per original shape; no
            # stretch across changed shoulders or inherited cliff strata.
            common.assign_uv(ob,tile=1.5)
            ob['reference_revision']='20261013_stone_shoulders'
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE),compress=True)
    replacements={r['id']:common.export(r,groups[r['id']],SOURCE) for r in changed}
    manifest['assets']=[replacements.get(r['id'],r) for r in manifest['assets']]
    manifest['stone_material_source']=str(LIB/'material.json')
    manifest['stone_reference_revision']='S12 irregular shallow side shoulders and grey non-stratified rock; original X approach support retained'
    assert all(common.digest(p)==sha for p,sha in kept.items())
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    (OUT/'stone_shoulders_report.json').write_text(json.dumps({'changed':list(replacements),'unchanged_sha':kept,'backup':str(rollback),'material_source':str(LIB/'material.json'),'status':'current geometry and material; CPU/native/GPU review required'},ensure_ascii=False,indent=2),encoding='utf8')
    print('STONE_SHOULDERS_DONE',list(replacements),flush=True)

if __name__=='__main__':main()
