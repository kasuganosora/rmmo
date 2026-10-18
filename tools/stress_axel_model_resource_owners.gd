extends "res://tools/stress_model_resource_owners.gd"
## Same ownership benchmark, using the unchanged largest production GLB.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const SOURCE:="D:/code/rmmo_runtime/packs/default/assets/7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd.glb"
var source_sha:=""
var preparations:Array=[]
func fixture(_count:int,_with_scene:bool)->Dictionary:
	var worker:=Thread.new();var began:=Time.get_ticks_usec()
	var token:=Drainer.CancelToken.new()
	check(worker.start(Deferred.prepare_scene.bind(SOURCE,source_sha,token,{},true,"D:/code/rmmo_runtime",true,2,true))==OK,"actual largest GLB preparation worker starts")
	# Construction is excluded from the isolated handoff measurement. Pump the
	# rendering command queue while the private off-tree worker creates RIDs.
	while worker.is_alive():RenderingServer.force_sync();OS.delay_msec(1)
	var packet:Dictionary=worker.wait_to_finish()
	var owners:Owners=packet.get("resource_owners")
	check(packet.get("error", "failed")=="" and owners!=null and owners.packed!=null,"actual largest GLB produces a complete typed packet")
	if owners==null:quit(1);return {}
	var visual_count:int=owners.visuals.size();var unique:Dictionary={}
	var watches:Array=[weakref(owners.document),weakref(owners.state),weakref(owners.packed)]
	for resource:Resource in owners.visuals:
		unique[resource.get_instance_id()]=true
		# Shared white materials legitimately belong to the probe's global cache.
		if resource is Mesh or resource is Skin:watches.append(weakref(resource))
	preparations.append({"prepare_us":Time.get_ticks_usec()-began,"visual_references":visual_count,"unique_visual_resources":unique.size(),"gltf_nodes":owners.state.nodes.size(),"gltf_meshes":owners.state.meshes.size(),"packed_nodes":owners.packed.get_state().get_node_count(),"captured_meshes":packet.get("captured_meshes",0)})
	packet.erase("resource_owners");Drainer.dispose_result(packet)
	return {"owners":owners,"watches":watches}
func run()->void:
	check(DisplayServer.get_name()!="headless","actual GLB benchmark uses GPU backend")
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	source_sha=FileAccess.get_sha256(SOURCE)
	check(not source_sha.is_empty(),"largest production GLB exists")
	for turn:int in 4:await measure(2151,turn in [1,2],true,true)
	check(trials.size()==4,"all actual GLB ABBA trials complete")
	check(FileAccess.get_sha256(SOURCE)==source_sha,"actual production GLB bytes unchanged")
	var report:Dictionary={"checks":checks,"failures":failures,"trials":trials,"preparations":preparations,"source":SOURCE,"source_sha":source_sha,"engine":Engine.get_version_info(),"note":"Actual largest axel_town model, raw white CPU/GPU preparation. ABBA same handoff benchmark; construction recorded separately, not game-frame timing. No persistent cache or source writes."}
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("ACTUAL_MODEL_OWNER_STRESS checks=",checks," failures=",failures);quit(1 if failures else 0)
