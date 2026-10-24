extends RefCounted
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
static func optimized_pack(cache:Dictionary,digest:String,generator:String,library:Array=[])->Dictionary:
	var materials:Array=[];var meshes:Array=[];var entries:Array=[]
	var material_ids:Dictionary={};var mesh_ids:Dictionary={}
	var cache_keys:Array=cache.keys();var cache_values:Array=cache.values()
	for cache_at:int in cache_keys.size():
		var key:Array=cache_keys[cache_at];var cached:Dictionary=cache_values[cache_at]
		var ids:Array=[];var supported:=true
		for field in ["mesh","source"]:
			var mesh:Mesh=cached[field]
			var mid:=mesh.get_instance_id()
			if not mesh_ids.has(mid):
				var cpu:Mesh=Cpu.capture(mesh);var slots:Array=[]
				for material:Material in cpu.materials:
					var id:=material.get_instance_id() if material!=null else 0
					if not material_ids.has(id):
						var value:=Cook.material_data(material)
						if value.is_empty():supported=false;break
						material_ids[id]=materials.size();materials.append(value)
					slots.append(material_ids[id])
				if not supported:break
				mesh_ids[mid]=meshes.size()
				mesh_ids[cpu.get_instance_id()]=meshes.size()
				var packed_mesh:Dictionary={"surfaces":cpu.surfaces,"materials":slots,"bounds":cpu.bounds,"box_size":cpu.box_size}
				if cpu.lods.any(func(levels):return not levels.is_empty()):packed_mesh.lods=cpu.lods
				meshes.append(packed_mesh)
			ids.append(mesh_ids[mid])
		if supported:entries.append([key,ids])
	var specs:Array=[];var skipped:=""
	for spec:Dictionary in library:
		if spec.get("material_override")!=null or spec.surface_overrides.any(func(value):return value!=null) or not mesh_ids.has(spec.mesh.get_instance_id()):skipped="render:"+str(spec.uuid);specs.append({"fallback":true,"uuid":spec.uuid});continue
		var copy:=spec.duplicate()
		for field in ["mesh","collision_mesh","ground_batch_record","render_bounds","render_supports","render_dependents","render_building"]:copy.erase(field)
		var row:={"spec":copy,"mesh":mesh_ids[spec.mesh.get_instance_id()],"batch":spec.has("ground_batch_record")}
		var collision:Mesh=spec.get("collision_mesh")
		if collision is BoxMesh:row.box=collision.size
		elif collision!=null:
			if not mesh_ids.has(collision.get_instance_id()):skipped="collision:"+str(spec.uuid);specs.append({"fallback":true,"uuid":spec.uuid});continue
			row.collision=mesh_ids[collision.get_instance_id()]
		specs.append(row)
	return {"digest":digest,"generator":generator,"materials":materials,"meshes":meshes,"entries":entries,"specs":specs,"specs_skip_reason":skipped}
