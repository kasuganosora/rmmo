extends "res://tools/test_material_cache_pressure.gd"
## Fixed shared-owner budget pressure. Every inserted texture keeps the old
## candidate alive through a material, forcing real eviction and LRU ordering.

func run()->void:
	check(DisplayServer.get_name()!="headless","private real renderer is present")
	if DisplayServer.get_name()=="headless":quit(1);return
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var textures:Array=[];var materials:Array=[]
	for i:int in 72:textures.append(texture(4*MB))
	for i:int in 24:
		var material:=StandardMaterial3D.new();material.albedo_texture=textures[i];materials.append(material)
	Paint.texture_profile_enabled=true;Paint.incremental_cache_budget_enabled=true;Paint.capacity_eviction_accounting_enabled=false
	var trials:Array=[];var reference:Array=[]
	for enabled:bool in [false,true,true,false]:
		Paint.native_cache_sort_enabled=enabled
		Paint.refresh_sources();Paint.cache_byte_budget=256*MB
		for i:int in 64:put_runtime_texture(str(i),textures[i])
		for i:int in materials.size():put_material("m%d"%i,materials[i])
		Paint.trim_cached_resources();Paint.TextureCache.reset_profile()
		var elapsed:=0;var states:Array=[]
		for i:int in range(64,72):
			var started:=Time.get_ticks_usec();put_runtime_texture(str(i),textures[i]);elapsed+=Time.get_ticks_usec()-started
			check(exact()<=Paint.cache_byte_budget,"actual hot texture union never exceeds budget")
			states.append(owner_state())
		var counters:Dictionary=Paint.TextureCache.profile_snapshot("paint.cache.").counters
		var sorts:int=int(counters.get("paint.cache.sort_candidates",0))
		check(sorts>0,"fixture performs real budget eviction and ordering")
		if reference.is_empty():reference=states
		else:check(states==reference,"every eviction retains exact hot order and owner identity")
		var row:Dictionary={"enabled":enabled,"insertions":8,"elapsed_us":elapsed,"work":counters}
		trials.append(row);print("CACHE_EVICTION_ORDER ",JSON.stringify(row))
		check((int(counters.get("paint.cache.native_sort_calls",0))>0) if enabled else (int(counters.get("paint.cache.scripted_sort_calls",0))>0),"unique recency ordering uses the selected native or scripted comparator")
	tie_case(textures,materials)
	random_order_cases()
	integer_boundary_cases()
	kernel_benchmark()
	Paint.refresh_sources();Paint.cache_byte_budget=256*MB;Paint.texture_profile_enabled=false;Paint.capacity_eviction_accounting_enabled=true;Paint.native_cache_sort_enabled=true
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(trials,"  "))
	print("MATERIAL_CACHE_EVICTION_ORDER checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func tie_case(textures:Array,materials:Array)->void:
	var reference:Array=[]
	for enabled:bool in [false,true]:
		Paint.refresh_sources();Paint.cache_byte_budget=256*MB;Paint.native_cache_sort_enabled=enabled
		for i:int in 64:put_runtime_texture(str(i),textures[i])
		for i:int in materials.size():put_material("m%d"%i,materials[i])
		Paint.trim_cached_resources()
		# Simulate two legacy owners lacking recency. Preserve the old unstable
		# tie semantics instead of introducing an arbitrary secondary key.
		Paint._cache_use.erase("t:1");Paint._cache_use.erase("t:2")
		Paint.TextureCache.reset_profile();put_runtime_texture("64",textures[64])
		var counters:Dictionary=Paint.TextureCache.profile_snapshot("paint.cache.").counters
		check(exact()<=Paint.cache_byte_budget,"legacy duplicate recency still respects the budget")
		if enabled:check(int(counters.get("paint.cache.native_sort_tie_fallbacks",0))>0 and int(counters.get("paint.cache.scripted_sort_calls",0))>0,"duplicate recency explicitly falls back to the original comparator")
		if reference.is_empty():reference=owner_state()
		else:check(owner_state()==reference,"tie fallback preserves old hot membership, order and owner identity")

func random_order_cases()->void:
	var rng:=RandomNumberGenerator.new();rng.seed=0x514cc3
	for trial:int in 64:
		var rows:Array=[];var count:int=1+(trial*37)%192
		for i:int in count:rows.append({"kind":"t:","key":str(i),"use":i*13-500})
		for i:int in range(count-1,0,-1):
			var j:int=rng.randi_range(0,i);var swap:Dictionary=rows[i];rows[i]=rows[j];rows[j]=swap
		if trial%4==0 and count>1:rows[1].use=rows[0].use
		var old:Array=rows.duplicate(true);var current:Array=rows.duplicate(true)
		Paint.native_cache_sort_enabled=false;Paint._sort_cache_candidates(old)
		Paint.native_cache_sort_enabled=true;Paint._sort_cache_candidates(current)
		check(current==old,"native and legacy order match for deterministic shuffled/tied case "+str(trial))

func kernel_benchmark()->void:
	var rows:Array=[]
	for i:int in 128:rows.append({"kind":"t:","key":str(i),"use":(i*73)%128})
	var expected:Array=[];var results:Array=[]
	Paint.texture_profile_enabled=false
	for enabled:bool in [false,true,true,false]:
		Paint.native_cache_sort_enabled=enabled
		var started:=Time.get_ticks_usec();var sorted:Array=[]
		for turn:int in 500:
			sorted=rows.duplicate();Paint._sort_cache_candidates(sorted)
		var elapsed:=Time.get_ticks_usec()-started
		if expected.is_empty():expected=sorted
		else:check(sorted==expected,"fixed sort kernel preserves the exact candidate order")
		results.append({"enabled":enabled,"sorts":500,"rows_per_sort":rows.size(),"elapsed_us":elapsed})
	print("CACHE_SORT_KERNEL ",JSON.stringify(results))

func integer_boundary_cases()->void:
	var values:Array=[-9223372036854775807-1,-9007199254740993,-9007199254740992,-1,0,1,9007199254740992,9007199254740993,9223372036854775807]
	var input:Array=[]
	for i:int in values.size():input.push_front({"kind":"t:","key":str(i),"use":values[i]})
	var original:Array=input.duplicate(true);var current:Array=input.duplicate(true)
	Paint.native_cache_sort_enabled=false;Paint._sort_cache_candidates(original)
	Paint.native_cache_sort_enabled=true;Paint._sort_cache_candidates(current)
	check(current==original,"signed int64 boundaries and adjacent values beyond double precision preserve exact order")
	check(current[4].use==0 and current[5].use==1,"one missing-recency zero sorts identically without a tie")
