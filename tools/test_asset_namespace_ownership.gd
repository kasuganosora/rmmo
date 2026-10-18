extends SceneTree
const Residency=preload("res://scripts/world3d/asset_residency.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func parts(root_id:String,count:int)->Array:
	var result:Array=[]
	for i:int in count:
		# Two map instances can legitimately carry the same model-local IDs.
		result.append({"uuid":root_id+"__mesh%d"%i,"ground_batch_record":{"uuid":"authored_part%d"%i,"kind":"asset"}})
	return result
func scenario(same_model:bool)->void:
	var service:=Residency.new()
	var path_a:="models/a.glb";var path_b:="models/a.glb" if same_model else "models/b.glb"
	service._record_paths={"map_a":path_a,"map_b":path_b}
	var a:=parts("map_a",2151);var b:=parts("map_b",2151)
	var began:=Time.get_ticks_usec();service.observe(a);service.observe(b);var observe_us:=Time.get_ticks_usec()-began
	var before:Dictionary={"namespaces":service._namespace_specs.size(),"record_paths":service._record_paths.size(),"model_a_instances":service._model_namespaces[path_a].size()}
	var a_ids:Array=[];var b_ids:Array=[]
	for spec:Dictionary in a:a_ids.append(spec.uuid)
	for spec:Dictionary in b:b_ids.append(spec.uuid)
	began=Time.get_ticks_usec();service.forget_specs(a_ids);var forget_a_us:=Time.get_ticks_usec()-began
	var correct_a:bool=service.model_in_use(path_a)==same_model and service.model_in_use(path_b)
	service.forget_specs(b_ids)
	var released:=not service.model_in_use(path_a) and not service.model_in_use(path_b) and service._namespace_specs.is_empty() and service._spec_namespaces.is_empty()
	print("ASSET_NAMESPACE_OWNERSHIP ",JSON.stringify({"same_model":same_model,"parts_per_instance":2151,"before":before,"observe_us":observe_us,"forget_first_us":forget_a_us,"first_release_correct":correct_a,"all_released":released}))
	if not "--record-control" in OS.get_cmdline_user_args():
		check(before.namespaces==2 and before.record_paths==2,"only declared map instances own resource namespaces")
		check(before.model_a_instances==(2 if same_model else 1),"model accounting keeps exact map instance counts")
		check(correct_a,"retiring one instance retains only the remaining model owners")
		check(released,"identical authored part IDs across models leave no stale residency")
	service.free()
func run()->void:
	scenario(false);scenario(true)
	print("ASSET_NAMESPACE_OWNERSHIP failures=",failures);quit(1 if failures else 0)
