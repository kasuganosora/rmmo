"""User-approved baked-black coating on the hall lantern's metalwork."""
import bpy

FINISHES = {
    'Guild patinated lantern metal': ('Guild baked black lantern metal', (.009, .010, .012), .36),
    'Guild dark recessed metal': ('Guild baked black lantern recess', (.005, .006, .007), .43),
}


def apply_lantern_finish(parts):
    changed = []
    for obj in parts:
        if obj.type != 'MESH': continue
        for index, old in enumerate(obj.data.materials):
            if old is None: continue
            match = next((k for k in FINISHES if old.name == k or old.name.startswith(k+'.')), None)
            if match is None: continue
            name, color, roughness = FINISHES[match]
            mat = bpy.data.materials.get(name)
            if mat is None:
                mat = bpy.data.materials.new(name); mat.use_nodes = True
                mat.diffuse_color = (*color, 1)
                p = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
                p.inputs['Base Color'].default_value = (*color, 1)
                # Opaque baked coating has a mostly dielectric surface over metal.
                p.inputs['Metallic'].default_value = .15
                p.inputs['Roughness'].default_value = roughness
                p.inputs['Coat Weight'].default_value = .18
                p.inputs['Coat Roughness'].default_value = .30
                mat['finish'] = 'baked_black_coated_metal_user_20261011'
            obj.data.materials[index] = mat
            changed.append((obj.name,index,name))
    return changed
