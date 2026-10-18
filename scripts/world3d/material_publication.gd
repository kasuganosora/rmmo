extends RefCounted
## Complete cache entries, one expensive operation per turn. No Images,
## material cursors or partially built resources survive in a scheduler job.
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const FAILED:=-1
const READY:=0
const PROGRESS:=1

static func step(materials:Array,validation:Variant,pool:Dictionary,texture_tickets:Variant=null)->int:
	# A running job retains complete textures for its current material. This
	# prevents a small hot-cache budget evicting earlier slots on every turn.
	# The job's existing admitted texture workspace covers this handoff; the
	# scheduler clears it after assembly, failure, cancellation and owner exit.
	var tickets:Dictionary={} if texture_tickets==null else texture_tickets
	for value:Dictionary in materials:
		if pool.has([value]):continue
		if value.has("paint") and not preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:
			if not Paint.material_valid(value.paint,false,"",validation):tickets.clear();return FAILED
			for field:String in Paint.MAP_FIELDS:
				var path:String=value.paint.get(field,"")
				var key:String=path if not path.is_empty() else (str(value.paint.get("pattern","")) if field=="texture_path" else "")
				if field=="normal_path" and value.paint.get("normal_format","opengl")=="directx":key+="|flip_y" if not key.is_empty() else ""
				if key.is_empty():continue
				var cached:Texture2D=Paint.retained_texture(key)
				if cached!=null:tickets[key]=cached;continue
				# Use the ordinary source/path/codec/SHA gates. Its complete immutable
				# GPU texture enters the same bounded LRU as a synchronous restore;
				# all temporary CPU image/buffer owners die before this call returns.
				var texture:Texture2D=Paint.texture(value.paint,field)
				if texture==null:tickets.clear();return FAILED
				tickets[key]=texture
				return PROGRESS
		# Restore exactly one full material through Cook's shared implementation,
		# including vertex tint, null slots and strict stored-property validation.
		if not Cook.restore_material(value,validation,pool):tickets.clear();return FAILED
		tickets.clear()
		return PROGRESS
	tickets.clear()
	return READY
