extends "res://tools/test_incremental_material_cache.gd"
## Fixed-work reproduction of texture replacement at a full hot-cache budget.
## Logical upload costs are synthetic; they are not measured GPU memory.

func put_runtime_texture(key:String,value:Texture2D)->void:
	var retired_id:=0
	if not Paint._textures.has(key) and Paint._textures.size()>=64:
		var oldest:String=Paint._textures.keys()[0]
		if Paint.capacity_eviction_accounting_enabled:retired_id=Paint._textures[oldest].get_instance_id()
		Paint._textures.erase(oldest);Paint._cache_use.erase("t:"+oldest)
	Paint._textures[key]=value;Paint._touch_cache("t:",key)
	Paint._remember_weak(Paint._texture_refs,key,value);Paint._trim_after_insert(value,retired_id)

func run()->void:
	check(DisplayServer.get_name()!="headless","private real renderer is present")
	if DisplayServer.get_name()=="headless":quit(1);return
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var textures:Array=[];var materials:Array=[]
	for i:int in 72:textures.append(texture(4*MB))
	for i:int in 24:
		var material:=StandardMaterial3D.new()
		material.albedo_texture=textures[32+i]
		material.normal_texture=textures[32+(i+1)%24]
		materials.append(material)
	Paint.texture_profile_enabled=true;Paint.incremental_cache_budget_enabled=true
	var trials:Array=[];var reference:Array=[]
	for enabled:bool in [false,true,true,false]:
		Paint.capacity_eviction_accounting_enabled=enabled
		Paint.refresh_sources();Paint.cache_byte_budget=256*MB
		for i:int in 64:put_runtime_texture(str(i),textures[i])
		for i:int in materials.size():put_material("m%d"%i,materials[i])
		# Start with an exact baseline after material insertions. A material added
		# later invalidates the snapshot and must fall back to a complete trim.
		Paint.trim_cached_resources()
		check(exact()==Paint.cache_byte_budget,"fixture fills the hot budget with shared materials")
		Paint.TextureCache.reset_profile();var elapsed:=0;var states:Array=[]
		for i:int in range(64,72):
			var start:=Time.get_ticks_usec()
			put_runtime_texture(str(i),textures[i])
			elapsed+=Time.get_ticks_usec()-start
			check(exact()==Paint.cache_byte_budget and Paint._cache_upper_bytes>=exact(),"each capacity replacement preserves the exact hot budget")
			check(not Paint._textures.has(str(i-64)) and Paint._textures[str(i)]==textures[i],"each insertion keeps the original FIFO capacity eviction and exact owner")
			states.append(owner_state())
		var counters:Dictionary=Paint.TextureCache.profile_snapshot("paint.cache.").counters
		var scans:int=int(counters.get("paint.cache.full_scans",0))
		if reference.is_empty():reference=states
		else:check(states==reference,"every insertion preserves legacy hot keys, order and exact unique cost")
		var row:Dictionary={"enabled":enabled,"insertions":8,"elapsed_us":elapsed,"full_scans":scans,"work":counters}
		trials.append(row);print("CACHE_CAPACITY_PRESSURE ",JSON.stringify(row))
		check(scans<=1 if enabled else scans==8,"same-size FIFO replacements use the selected legacy or incremental accounting path")
	for kind:String in ["material_owner","texture_alias","raw_material_replacement","raw_texture_replacement","silent_texture_cost","material_only_cost","silent_material_slot","stale_recency"]:
		fallback_case(kind,textures,materials)
	lifetime_case(textures)
	Paint.refresh_sources();Paint.cache_byte_budget=256*MB;Paint.texture_profile_enabled=false;Paint.capacity_eviction_accounting_enabled=true
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(trials,"  "))
	print("MATERIAL_CACHE_PRESSURE checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func fallback_case(kind:String,textures:Array,materials:Array)->void:
	var baseline:Array=[]
	var raw_replacement:=StandardMaterial3D.new();raw_replacement.albedo_texture=textures[0]
	var raw_texture:=texture(12*MB)
	var shared:=StandardMaterial3D.new();shared.albedo_texture=textures[0]
	for enabled:bool in [false,true]:
		Paint.refresh_sources();Paint.cache_byte_budget=256*MB;Paint.capacity_eviction_accounting_enabled=enabled
		for i:int in 64:put_runtime_texture(str(i),textures[i])
		for i:int in materials.size():put_material("m%d"%i,materials[i])
		if kind=="material_owner":put_material("shared_oldest",shared)
		if kind=="material_only_cost":Paint._textures["32"]=textures[33]
		Paint.trim_cached_resources();Paint.TextureCache.reset_profile()
		match kind:
			"texture_alias":Paint._textures["63"]=textures[0]
			"raw_material_replacement":Paint._materials["m0"]=raw_replacement
			"raw_texture_replacement":Paint._textures["63"]=raw_texture
			"silent_texture_cost":textures[32].set_meta("runtime_upload_bytes",8*MB)
			"material_only_cost":
				textures[32].set_meta("runtime_upload_bytes",12*MB);textures[64].set_meta("runtime_upload_bytes",8*MB)
			"silent_material_slot":
				materials[0].set_block_signals(true);materials[0].albedo_texture=raw_texture;materials[0].set_block_signals(false)
				check(Paint._cache_estimate_valid,"blocked material signals leave the prior estimate apparently valid")
			"stale_recency":Paint._cache_use["t:removed_raw"]=1
		put_runtime_texture("64",textures[64])
		var counters:Dictionary=Paint.TextureCache.profile_snapshot("paint.cache.").counters
		check(int(counters.get("paint.cache.full_scans",0))>=1,kind+": uncertain ownership or cost falls back to full scan")
		check(exact()<=Paint.cache_byte_budget,kind+": fallback immediately restores the hot budget")
		var snapshot:Array=[owner_state(),Paint._cache_use.keys()]
		if baseline.is_empty():baseline=snapshot
		else:check(snapshot==baseline,kind+": fallback matches legacy membership, order, cost and recency")
		if kind=="silent_texture_cost":textures[32].set_meta("runtime_upload_bytes",4*MB)
		if kind=="material_only_cost":textures[32].set_meta("runtime_upload_bytes",4*MB);textures[64].set_meta("runtime_upload_bytes",4*MB)
		if kind=="silent_material_slot":
			materials[0].set_block_signals(true);materials[0].albedo_texture=textures[32];materials[0].set_block_signals(false)

func owner_state()->Array:
	var hot_textures:Dictionary={};var hot_materials:Dictionary={}
	for key:String in Paint._textures:hot_textures[key]=Paint._textures[key].get_instance_id()
	for key:String in Paint._materials:hot_materials[key]=Paint._materials[key].get_instance_id()
	return [state(),hot_textures,hot_materials]

func install_unshared_first()->WeakRef:
	var value:=texture(4*MB);var result:WeakRef=weakref(value);put_runtime_texture("first",value);return result

func lifetime_case(textures:Array)->void:
	Paint.refresh_sources();Paint.cache_byte_budget=256*MB;Paint.capacity_eviction_accounting_enabled=true
	var weak:=install_unshared_first()
	for i:int in 63:put_runtime_texture(str(i),textures[i])
	Paint.trim_cached_resources();put_runtime_texture("new",textures[64])
	check(weak.get_ref()==null,"FIFO accounting retains no strong reference to the retired texture")
