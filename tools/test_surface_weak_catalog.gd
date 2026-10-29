extends SceneTree
## CPU-only identity/cleanup stress. Empty resources require no pixel IO or GPU.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const LIVE_COUNT=4352
const JOIN_COUNT=512
const DEAD_COUNT=8192
var checks:=0
var failures:=0
var rows:Array=[]

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func resource(kind:String)->Resource:
	return ImageTexture.new() if kind=="texture" else StandardMaterial3D.new()
func catalog_for(kind:String)->Dictionary:
	return Paint._texture_refs if kind=="texture" else Paint._material_refs
func resolve(catalog:Dictionary,key:String)->Resource:
	return catalog[key].get_ref() if catalog.has(key) else null
func dead_reference(kind:String)->WeakRef:
	return weakref(resource(kind))
func large_live(kind:String)->WeakRef:
	var catalog:=catalog_for(kind);catalog.clear()
	var owners:Array[Resource]=[]
	for i:int in LIVE_COUNT:owners.append(resource(kind))
	Paint.TextureCache.reset_profile()
	var began:=Time.get_ticks_usec()
	for i:int in LIVE_COUNT:Paint._remember_weak(catalog,str(i),owners[i])
	var registration_us:=Time.get_ticks_usec()-began
	var missing:=0
	for i:int in LIVE_COUNT:
		if resolve(catalog,str(i))!=owners[i]:missing+=1
	check(catalog.size()==LIVE_COUNT and missing==0,kind+" retains every live identity above 4096")
	var joined:Array[Resource]=[];var duplicates:=0
	began=Time.get_ticks_usec()
	for i:int in JOIN_COUNT:
		var value:=resolve(catalog,str(i))
		if value==null:
			duplicates+=1;value=resource(kind);Paint._remember_weak(catalog,str(i),value)
		joined.append(value)
	var join_us:=Time.get_ticks_usec()-began
	check(duplicates==0,kind+" later join reuses identities without duplicate construction")
	var all_weak:=true
	for value:Variant in catalog.values():
		if not value is WeakRef:all_weak=false
	check(all_weak,kind+" catalog retains only WeakRef entries")
	check(Paint._textures.is_empty() and Paint._materials.is_empty(),kind+" weak registration does not add strong hot owners")
	rows.append({"kind":kind,"live":LIVE_COUNT,"missing_after_registration":missing,"join_requests":JOIN_COUNT,"duplicate_constructions":duplicates,"registration_us":registration_us,"join_us":join_us,"work":Paint.TextureCache.profile_snapshot("paint.cache.weak_").counters})
	return weakref(owners[0]) # Caller checks after this frame releases all fixture owners.
func dead_cleanup(kind:String)->void:
	var catalog:=catalog_for(kind);catalog.clear()
	var dead:=dead_reference(kind)
	check(dead.get_ref()==null,kind+" fixture dead owner has already retired")
	for i:int in DEAD_COUNT:catalog["dead_"+str(i)]=dead
	var owner:=resource(kind)
	Paint.TextureCache.reset_profile()
	Paint._remember_weak(catalog,"live",owner)
	var removed:=DEAD_COUNT+1-catalog.size()
	check(removed>0 and removed<=8,kind+" one insertion inspects a bounded dead prefix")
	for i:int in ceili(float(DEAD_COUNT+1)/8.):Paint._remember_weak(catalog,"live",owner)
	check(catalog.size()==1 and resolve(catalog,"live")==owner,kind+" repeated bounded cleanup eventually retires all dead entries")
	# A live prefix must rotate so dead entries behind it cannot starve.
	catalog.clear()
	for i:int in 64:catalog["front_"+str(i)]=weakref(owner)
	for i:int in 32:catalog["tail_"+str(i)]=dead
	for i:int in 16:Paint._remember_weak(catalog,"live",owner)
	check(catalog.size()==65,kind+" live prefix rotates and small dead tail is reclaimed")
	var prefix_ok:=true
	for value:Variant in catalog.values():
		if value.get_ref()!=owner:prefix_ok=false
	check(prefix_ok,kind+" live prefix identity remains exact")
	# No retained cursor may refer to a dictionary generation cleared externally.
	catalog.clear();Paint._remember_weak(catalog,"after_clear",owner)
	check(catalog.size()==1 and resolve(catalog,"after_clear")==owner,kind+" external clear is immediately safe")
	var replacement:=resource(kind)
	Paint._remember_weak(catalog,"after_clear",replacement)
	check(catalog.size()==1 and resolve(catalog,"after_clear")==replacement,kind+" same-key replacement keeps only the new identity")
	rows.append({"kind":kind,"dead":DEAD_COUNT,"first_call_removed":removed,"cleanup_work":Paint.TextureCache.profile_snapshot("paint.cache.weak_").counters})
	catalog.clear()
func replacement_lifetime(kind:String)->Array:
	var catalog:=catalog_for(kind);catalog.clear()
	var original:=resource(kind);var replacement:=resource(kind)
	var old_watch:WeakRef=weakref(original);var new_watch:WeakRef=weakref(replacement)
	Paint._remember_weak(catalog,"same",original)
	Paint._remember_weak(catalog,"same",replacement)
	return [old_watch,new_watch]
func run()->void:
	Paint.refresh_sources();Paint.texture_profile_enabled=true
	for kind:String in ["texture","material"]:
		var watched:=large_live(kind)
		check(watched.get_ref()==null,kind+" catalog cannot prolong the final external owner's lifetime")
		dead_cleanup(kind)
		var replaced:=replacement_lifetime(kind)
		check(replaced[0].get_ref()==null and replaced[1].get_ref()==null,kind+" replacing a key retains neither old nor new owner")
	Paint.refresh_sources();Paint.texture_profile_enabled=false
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"  "))
	print("SURFACE_WEAK_CATALOG checks=",checks," failures=",failures)
	quit(1 if failures else 0)
