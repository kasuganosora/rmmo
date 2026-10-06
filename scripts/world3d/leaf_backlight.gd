extends RefCounted
## Explicit per-surface optical metadata; never infer leaves from names.
## Godot's backlight is a realtime approximation of thin-leaf transmission.
static func apply(root: Node) -> void:
	for mesh in preload("res://scripts/world3d/surface_materials.gd").meshes(root):
		var raw:Variant=mesh.get_meta("extras",{}).get("rmmo_leaf_backlight")
		if not raw is Array or raw.size()!=mesh.mesh.get_surface_count():continue
		var valid:=true
		for value in raw:
			if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)) or float(value)<0. or float(value)>1.:valid=false;break
		if not valid:continue
		for slot in raw.size():
			if float(raw[slot])==0.:continue
			var source:=mesh.get_active_material(slot) as StandardMaterial3D
			if source==null:continue
			var material:=source.duplicate() as StandardMaterial3D
			material.backlight_enabled=true
			var amount:=float(raw[slot])
			material.backlight=Color(amount,amount,amount).linear_to_srgb()
			mesh.set_surface_override_material(slot,material)
