extends SceneTree
const Residency=preload("res://scripts/world3d/asset_residency.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture()->Node:
	var service:=Residency.new()
	for ns:String in ["guild","kept","other"]:
		var path:="shared" if ns!="other" else "other_path"
		service._record_paths[ns]=path;service._namespace_specs[ns]={}
		if not service._model_namespaces.has(path):service._model_namespaces[path]={}
		service._model_namespaces[path][ns]=true
		for i:int in 2200 if ns=="guild" else 16:
			var id:="%s__%d"%[ns,i];service._spec_namespaces[id]=ns;service._namespace_specs[ns][id]=true
	service._unknown_asset_specs.unknown=true
	return service
func control(service:Node,ids:Array)->void:
	for id:String in ids:
		service._unknown_asset_specs.erase(id)
		if not service._spec_namespaces.has(id):continue
		var uuid:String=service._spec_namespaces[id];service._spec_namespaces.erase(id)
		service._namespace_specs[uuid].erase(id)
		if not service._namespace_specs[uuid].is_empty():continue
		service._namespace_specs.erase(uuid)
		var path:String=service._record_paths[uuid];service._model_namespaces[path].erase(uuid)
		if service._model_namespaces[path].is_empty():service._model_namespaces.erase(path)
	service._profile_usage()
func snapshot(s:Node)->Array:return [s._spec_namespaces,s._namespace_specs,s._model_namespaces,s._unknown_asset_specs]
func _initialize()->void:
	var ids:Array=[]
	for i:int in 2200:ids.append("guild__%d"%i)
	var a:=fixture();var b:=fixture()
	for selected:Array in [ids.slice(0,100)+["other__0","unknown","missing","guild__0"],ids,["kept__0"],b._spec_namespaces.keys()]:
		control(a,selected);b.forget_specs(selected)
		check(snapshot(a)==snapshot(b),"partial/complete/mixed/duplicate retirement preserves exact model ownership")
		check(a.model_in_use("shared")==b.model_in_use("shared"),"retained instance still protects shared model")
	check(int(b.profile.get("retirement_namespace_checks",0))==6,"ownership checks run once per touched namespace, including interleaved partial retirements")
	a.free();b.free()
	var timings:Array=[]
	for round_:int in 4:
		var total:=0
		for repeat:int in 30:
			var s:=fixture();var began:=Time.get_ticks_usec();s.forget_specs(ids);total+=Time.get_ticks_usec()-began;s.free()
		timings.append(total)
	print("RETIREMENT_NAMESPACE_WORK ",JSON.stringify({"trials_us":timings,"retirements":30,"ids":ids.size(),"failures":failures}));quit(1 if failures else 0)
