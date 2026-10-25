extends RefCounted
## One expensive operation per turn; retained GPU owners are always complete.
## CPU Images stay in the existing admitted packet. Temporary publication
## scopes borrow those Images without extending their ownership lifetime.
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const FAILED:=-1
const READY:=0
const PROGRESS:=1

static func begin_record_scope(record:Dictionary,packet:Dictionary,owners:Dictionary,state:Dictionary)->Dictionary:
	var prefab=load("res://scripts/world3d/house_prefab.gd")
	var scope:Dictionary=prefab.begin_texture_publication(record,null,packet,state)
	if not scope.ok:return scope
	# The job owns complete textures until the real record binds them, including
	# shader-only height maps. A zero hot-cache budget must not lose this work.
	for key:String in owners:
		var texture:Texture2D=owners[key]
		var expected:String=packet.get("sources",{}).get(Paint.texture_source_path(key),"")
		if not expected.is_empty() and texture.get_meta("runtime_source_sha256","")!=expected:continue
		if Paint.residency_budget_enabled:
			if not Paint._texture_refs.has(key) or Paint._texture_refs[key].get_ref()!=texture:Paint._remember_weak(Paint._texture_refs,key,texture)
		else:
			if not Paint._textures.has(key) and Paint._textures.size()>=64:Paint._textures.erase(Paint._textures.keys()[0])
			Paint._textures[key]=texture
	return scope

static func end_record_scope(scope:Dictionary)->void:
	load("res://scripts/world3d/house_prefab.gd").end_texture_publication(scope)

static func step_record_prepared(record:Dictionary,validation:Variant,owners:Dictionary,packet:Dictionary,state:Dictionary)->int:
	var scope:=begin_record_scope(record,packet,owners,state)
	if not scope.ok:return FAILED
	var result:=READY
	for definition:Dictionary in Paint.definitions(record):
		if not Paint.material_valid(definition,false,"",validation):result=FAILED;break
		for field:String in Paint.MAP_FIELDS:
			var path:String=definition.get(field,"")
			var key:String=Paint.definition_texture_key(definition,field)
			if key.is_empty():continue
			# A source identity does not admit every variant or format. Keep the
			# existing final binding fallback for work outside this worker packet.
			if not packet.get("images",{}).has(key) and not packet.get("resident_textures",{}).has(key):
				if not state.has("unprepared_keys"):state.unprepared_keys={}
				if state.unprepared_keys.size()<256 and not state.unprepared_keys.has(key):
					state.unprepared_keys[key]=true
					if Paint.texture_profile_enabled:Paint.TextureCache._profile_count("paint.texture.unprepared_slice_skip")
				continue
			var texture:Texture2D=Paint.retained_texture(key)
			if texture!=null:owners[key]=texture;continue
			texture=Paint.texture(definition,field)
			if texture==null:result=FAILED;break
			owners[key]=texture;result=PROGRESS;break
		if result!=READY:break
	end_record_scope(scope)
	return result

static func step_prepared(record:Dictionary,materials:Array,validation:Variant,pool:Dictionary,texture_tickets:Dictionary,packet:Dictionary,scope_state:Variant=null)->int:
	# Use the same source-generation and resident-ticket gates as final prefab
	# publication. No CPU Image escapes into the temporary global handoff.
	var prefab=load("res://scripts/world3d/house_prefab.gd")
	var scope:Dictionary=prefab.begin_texture_publication(record,pool,packet,scope_state,materials)
	if not scope.ok:texture_tickets.clear();return FAILED
	var result:=READY
	# A packet can invalidate the former prefab material generation. Check the
	# cache AFTER installing it, so replacement textures are sliced as well.
	if not prefab._meshes.has(record.house_prefab.sha256):result=step(materials,validation,pool,texture_tickets)
	else:texture_tickets.clear()
	prefab.end_texture_publication(scope)
	return result

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
				var key:String=Paint.definition_texture_key(value.paint,field)
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
