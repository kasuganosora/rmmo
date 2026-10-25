extends SceneTree
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const MB=1024*1024
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;print("FAIL ",label)
func texture(bytes:int)->Texture2D:
	var value:=ImageTexture.create_from_image(Image.create(4,4,false,Image.FORMAT_RGBA8))
	# Logical accounting stress; the separate GPU test measures actual memory.
	value.set_meta("runtime_upload_bytes",bytes);return value
func exact()->int:
	var values:Dictionary={}
	for t:Texture2D in Paint._textures.values():values[t.get_instance_id()]=t
	for m:StandardMaterial3D in Paint._materials.values():
		for field:String in Paint.TEXTURE_PROPERTIES:
			var t:Texture2D=m.get(field)
			if t!=null:values[t.get_instance_id()]=t
	var sum:=0
	for t:Texture2D in values.values():sum+=int(t.get_meta("runtime_upload_bytes"))
	return sum
func put_material(key:String,value:StandardMaterial3D)->void:
	if not Paint._materials.has(key) and Paint._materials.size()>=128:
		var oldest:String=Paint._materials.keys()[0];Paint._materials.erase(oldest);Paint._cache_use.erase("m:"+oldest)
	Paint._materials[key]=value;Paint._touch_cache("m:",key)
	Paint._remember_weak(Paint._material_refs,key,value);Paint._trim_after_insert(value)
func put_texture(key:String,value:Texture2D)->void:
	if not Paint._textures.has(key) and Paint._textures.size()>=64:Paint._textures.erase(Paint._textures.keys()[0])
	Paint._textures[key]=value;Paint._touch_cache("t:",key)
	Paint._remember_weak(Paint._texture_refs,key,value);Paint._trim_after_insert(value)
func state()->Array:return [Paint._textures.keys(),Paint._materials.keys(),exact()]
func install_lone()->WeakRef:
	# Unwind the VM's argument temporaries before checking the final owner.
	var lone:=texture(MB);var watch:WeakRef=weakref(lone);put_texture("lone",lone);return watch
func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var textures:Array=[];var materials:Array=[]
	for i:int in 32:textures.append(texture(MB))
	for i:int in 160:
		var m:=StandardMaterial3D.new()
		for j:int in Paint.TEXTURE_PROPERTIES.size():m.set(Paint.TEXTURE_PROPERTIES[j],textures[(i+j)%32])
		materials.append(m)
	var trials:Array=[];var reference:Dictionary={}
	Paint.texture_profile_enabled=true
	for budget:int in [64*MB,5*MB,0]:
		for enabled:bool in [false,true,true,false]:
			Paint.refresh_sources();Paint.incremental_cache_budget_enabled=enabled;Paint.cache_byte_budget=budget
			Paint.TextureCache.reset_profile()
			var states:Array=[];var spans:Array=[];var total:=0
			for i:int in 320:
				var began:=Time.get_ticks_usec()
				if i%4==0:
					var at:=i%textures.size();put_texture(str(at),textures[at])
				else:put_material(str(i%160),materials[i%160])
				var us:=Time.get_ticks_usec()-began;spans.append(us);total+=us
				var actual:=exact()
				check(actual<=budget,"hot budget at every insertion, including zero")
				if enabled:check(Paint._cache_upper_bytes>=actual,"union is a conservative bound after every eviction")
				states.append(state())
			if not reference.has(budget):reference[budget]=states
			else:check(states==reference[budget],"same hot membership/order and costs as full trim after every insertion")
			spans.sort();var row:={"incremental":enabled,"budget":budget,"total_us":total,"max_us":spans[-1],"p95_us":spans[303],"work":Paint.TextureCache.profile_snapshot("paint.cache.").counters}
			trials.append(row);print("CACHE_BENCH ",JSON.stringify(row))
	Paint.incremental_cache_budget_enabled=true;Paint.cache_byte_budget=64*MB;Paint.refresh_sources()
	put_material("live",materials[0]);Paint._textures.clear();Paint._materials.clear()
	put_texture("live_again",textures[0])
	check(Paint.retained_texture("live_again")==textures[0] and Paint._cache_upper_bytes>=exact(),"direct cache removals and shared aliases stay conservative")
	var mutable:=StandardMaterial3D.new();mutable.albedo_texture=textures[0];put_material("mutable",mutable)
	var large:=texture(96*MB);mutable.albedo_texture=large
	check(not Paint._cache_estimate_valid,"changing a cached material invalidates its texture accounting")
	Paint._trim_changed_cache()
	check(exact()<=Paint.cache_byte_budget and mutable.albedo_texture==large,"changed live material is preserved while hot ownership is trimmed")
	var changing:=texture(MB);put_texture("changing",changing)
	changing.set_meta("runtime_upload_bytes",96*MB);changing.update(Image.create(4,4,false,Image.FORMAT_RGBA8))
	check(not Paint._cache_estimate_valid,"in-place texture changes invalidate previously counted upload costs")
	Paint._trim_changed_cache();check(exact()<=Paint.cache_byte_budget,"changed texture cost is fully reconciled")
	Paint._textures.raw=large;Paint.trim_cached_resources()
	check(exact()<=Paint.cache_byte_budget,"explicit trim reconciles an unregistered legacy dictionary insertion")
	Paint.cache_byte_budget=0;Paint._trim_changed_cache()
	check(exact()==0,"tightened budget applies without a new upload")
	Paint.residency_budget_enabled=false;put_texture("disabled",textures[0])
	Paint.residency_budget_enabled=true;put_texture("reenabled",textures[1])
	check(exact()==0,"reenabling accounting reconciles disabled-mode inserts")
	Paint.cache_byte_budget=64*MB;Paint.refresh_sources()
	for i:int in 1800:put_material(str(i),StandardMaterial3D.new())
	check(Paint._cache_use.size()<=256 and Paint._cache_accounted.size()<=1024,"scalar bookkeeping remains bounded for textureless cache churn")
	var ticket:=texture(MB);var before_bytes:=Paint._cache_upper_bytes
	Paint.remember_texture_owner("ticket_only",ticket)
	check(not Paint._textures.has("ticket_only") and Paint.retained_texture("ticket_only")==ticket and Paint._cache_upper_bytes==before_bytes,"job-owned ticket handoff reuses weak ownership without touching the hot budget")
	# Signals and integer accounting must not introduce a new resource owner.
	var watch:=install_lone()
	Paint.refresh_sources();check(watch.get_ref()==null,"accounting and change subscriptions do not retain a discarded GPU resource")
	Paint.texture_profile_enabled=false
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(trials,"  "))
	print("INCREMENTAL_CACHE checks=",checks," failures=",failures);quit(1 if failures else 0)
