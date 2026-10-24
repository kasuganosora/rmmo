extends SceneTree
## This suite explicitly exercises the optional verification path, including
## concurrent package corruption. Normal gameplay trusts authored packages.
## CPU-only regression for rebuilding the derived directory before resource
## preparation on its first visit. Author maps/models/images are all temporary.
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Helper=preload("res://tools/test_map_dependency_index.gd")
const HouseHelper=preload("res://tools/test_reference_chunk_loading.gd")
const ModelHelper=preload("res://tools/test_asset_bounds_manifest.gd")
class Probe extends "res://scripts/world3d/map_loader.gd":
	var texture_requests:Array=[]
	var model_requests:Array=[]
	var textures_started:=false
	var assets_started:=false
	var validation_passes:=0
	var reject_selected:=false
	var change_after_selected:=false
	var cancel_after_selected:=false
	func _start_texture_prefetch(dependencies:Variant)->void:
		textures_started=true;texture_requests=dependencies.duplicate(true)
	func _prepare_record_assets()->void:
		assets_started=true
		for record:Dictionary in _record_meta.rmmo_records:
			if record.kind=="asset":model_requests.append(record.asset_path)
	func _valid_records(extra:Dictionary,paint_ids:Array=[],warm_prefabs:bool=true)->bool:
		validation_passes+=1
		var valid:bool=super._valid_records(extra,paint_ids,warm_prefabs)
		if validation_passes==2:
			if change_after_selected:
				var file:=FileAccess.open(_path,FileAccess.READ_WRITE);file.seek_end();file.store_string(" ");file.close()
			if cancel_after_selected:_cancelled=true
			if reject_selected:return false
		return valid
var passed:=0
var failures:=0
var folder:=""
var content_root:=""
var helper:SceneTree
var created:Array[String]=[]
var fixture_names:Array[String]=[]
var pngs:Array[String]=[]
var models:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if value:passed+=1
	else:failures+=1
func fixture(name_:String,invalid_far:bool=false,invalid_owner:bool=false)->Dictionary:
	var records:Array=[]
	for i in 3:
		var record:Dictionary=helper.box(["near","far","global"][i],[0,500,900][i])
		record.surface_paint=[{"mesh":"","geometry":"test","surface":0,"face":0,"scale":[1,1],"offset":[0,0],"rotation":0,"mapping":"uv","material":{"name":"cpu paint","color":[1,1,1,1],"roughness":.8,"texture_path":pngs[i]}}]
		if i==2:record.future_behavior={"unknown":true}
		if i==1 and invalid_far:record.wind_response={"profile":"invalid"}
		records.append(record)
	for i in 2:
		records.append({"uuid":["near_model","far_model"][i],"kind":"asset","asset_path":models[i],"position":[0 if i==0 else 700,0,4],"rotation":[0,0,0],"size":[1,1,1],"surface_id":"model","collision":"none"})
	var metadata:={"building_instances":{}}
	var houses:=HouseHelper.new();houses.append_house(records,metadata,"near_house",31);houses.append_house(records,metadata,"far_house",800);houses.free()
	if invalid_owner:metadata.building_instances.far_house.parts.floor="missing_floor"
	var result:Dictionary=helper.fixture(name_,records,metadata)
	fixture_names.append(name_)
	return result
func parse(path:String,reject_selected:bool=false,change_after_selected:bool=false,cancel_after_selected:bool=false)->Probe:
	var probe:=Probe.new();probe.near_first=true;probe._path=path;probe._content_root=content_root;probe._entry_origin=Vector3(0,.9,0)
	probe.reject_selected=reject_selected;probe.change_after_selected=change_after_selected;probe.cancel_after_selected=cancel_after_selected
	probe._parse();return probe
func dispose(probe:Probe)->void:probe._exit_tree();probe.free()
func ids(probe:Probe)->Array:
	var result:Array=[]
	for record:Dictionary in probe._record_meta.get("rmmo_records",[]):result.append(record.uuid)
	return result
func texture_paths(probe:Probe)->Array:
	var result:Array=[]
	for request:Array in probe.texture_requests:result.append(request[0])
	result.sort();return result
func empty_selection(probe:Probe)->bool:
	return probe._dependency_index.is_empty() and probe._dependency_proof==null and probe._entry_plan.is_empty() and probe._selected_record_indices.is_empty() and probe._deferred_assets.is_empty() and probe._deferred_ids.is_empty() and probe._mesh_cache_selection.is_empty() and probe._full_reference_dependencies.is_empty()
func full_fallback(probe:Probe)->bool:
	return probe._error==OK and ids(probe).size()==9 and texture_paths(probe).size()==3 and probe.model_requests.size()==2 and probe._build_dependency_index and empty_selection(probe)
func run()->void:
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=true
	create_timer(90).timeout.connect(func():print("COLD_REFERENCE_INDEX_TIMEOUT");quit(2))
	content_root=Paths.external_root();folder=Paths.cache_directory("cold_reference_index_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	helper=Helper.new();helper.folder=folder;helper.content_root=content_root
	for name_ in ["near","far","global"]:
		var path:=folder.path_join(name_+".png");var image:=Image.create(2,2,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE);image.save_png(path);pngs.append(path);created.append(path)
	var model_helper:=ModelHelper.new()
	for name_ in ["near","far"]:
		var path:=folder.path_join(name_+".glb");model_helper.write(path,model_helper.data());models.append(path);created.append(path)
	model_helper.free()
	var old_pipeline:bool=Loader.entry_pipeline_enabled;var old_rebuild:bool=Loader.cold_index_rebuild_enabled
	Loader.entry_pipeline_enabled=false;Loader.cold_index_rebuild_enabled=true
	var f:=fixture("cold");var sha:=FileAccess.get_sha256(f.path)
	check(not FileAccess.file_exists(Index.cache_path(f.path,content_root)),"cold fixture has no derived directory")
	var p:=parse(f.path)
	if p._error!=OK:print("COLD_PARSE_ERROR ",p._error," ",p._failure_reason," ",p._profile)
	var selected_ids:Array=["near","global","near_model","near_house_floor","near_house_door"]
	check(p._error==OK and ids(p)==selected_ids,"first cold visit prepares only core/global and complete intersecting building")
	check(p.validation_passes==2 and p._profile.get("reference_index_rebuilt_before_models",false) and not p._profile.get("reference_index_hit",true),"full strict validation precedes proof-backed selected validation on cold miss")
	var expected_textures:Array=[pngs[0],pngs[2]];expected_textures.sort()
	check(texture_paths(p)==expected_textures and p.model_requests==[models[0]],"far-only image and model requests do not reach preparation")
	check(p._author_reference_meta.rmmo_records.size()==9 and p._record_order.size()==9 and p._record_meta.building_instances.size()==2 and p._author_reference_meta==f.extras,"complete author order and building metadata survive runtime selection")
	check(p._deferred_ids.keys()==["far","far_model","far_house_floor","far_house_door"] and p._deferred_assets[0].draw_order==65536,"deferred references preserve exact original order and full far group")
	check(not p._build_dependency_index and p._dependency_proof!=null and p._reference_dependencies.size()<p._full_reference_dependencies.size() and p._full_reference_dependencies==f.extras.rmmo_resource_dependencies,"selected closure and full publication closure stay separate; subset cannot overwrite directory")
	var selection_key:String=p._mesh_cache_selection
	check(not selection_key.is_empty() and p._profile.get("mesh_cache_scope")=="selected_reference_closure","cold selected cook cache has its own exact compact-record identity")
	check(p._profile.get("reference_full_paint_identity_count")==9 and p._profile.get("paint_identity_count")==5 and p._reference_integrity() and FileAccess.get_sha256(f.path)==sha,"paint identity alignment and complete SHA guards preserved without author writes")
	var far_path:String=folder.path_join(f.extras.rmmo_records[1].rmmo_ref.uri);var original:=FileAccess.get_file_as_bytes(far_path);var corrupt:=original.duplicate();corrupt[-1]^=1;helper.write_bytes(far_path,corrupt)
	check(not p._reference_integrity(),"final publication still detects mutation of a cold-validated far-only resource")
	helper.write_bytes(far_path,original);dispose(p)
	p=parse(f.path)
	check(p._error==OK and p._profile.get("reference_index_hit",false) and not p._profile.get("reference_index_rebuilt_before_models",true) and p.validation_passes==1 and ids(p)==selected_ids and p._mesh_cache_selection==selection_key,"next warm visit uses the same selection and cook identity directly")
	dispose(p)
	var cache:String=Index.cache_path(f.path,content_root);var cache_bytes:=FileAccess.get_file_as_bytes(cache);corrupt=cache_bytes.duplicate();corrupt[-1]^=1;helper.write_bytes(cache,corrupt)
	p=parse(f.path)
	check(p._error==OK and p._profile.get("reference_index_rebuilt_before_models",false) and ids(p)==selected_ids,"corrupt derived directory recovers local preparation on the same visit")
	dispose(p)
	var payload:Dictionary=bytes_to_var(cache_bytes.slice(49));payload.generator="0".repeat(64);helper.replace_payload(cache,payload)
	p=parse(f.path)
	check(p._error==OK and p._profile.get("reference_index_rebuilt_before_models",false) and ids(p)==selected_ids,"stale derived generation rebuilds before model/image preparation")
	dispose(p)
	var disabled:=fixture("disabled");Loader.cold_index_rebuild_enabled=false;p=parse(disabled.path);Loader.cold_index_rebuild_enabled=true
	check(full_fallback(p) and p._profile.get("reference_index_rebuild_reason")=="disabled","control switch retains complete correct fallback without partial selection")
	dispose(p)
	var rejected:=fixture("rejected");p=parse(rejected.path,true)
	check(full_fallback(p) and p._profile.get("reference_index_rebuild_reason")=="selected_validation_failed","failed selected validation restores full textures, ownership state and preparation")
	dispose(p)
	var blocked:=fixture("blocked");var blocked_cache:String=Index.cache_path(blocked.path,content_root);DirAccess.make_dir_recursive_absolute(blocked_cache)
	p=parse(blocked.path)
	check(full_fallback(p) and str(p._profile.get("reference_index_rebuild_reason","")).begins_with("build:"),"derived directory publication failure retains the full correct fallback")
	dispose(p);DirAccess.remove_absolute(blocked_cache)
	var bad:=fixture("invalid_far",true);p=parse(bad.path)
	check(p._error!=OK and not p.assets_started and not p.textures_started and not FileAccess.file_exists(Index.cache_path(bad.path,content_root)),"invalid far business record fails before directory build or any preparation")
	dispose(p)
	bad=fixture("invalid_owner",false,true);p=parse(bad.path)
	check(p._error!=OK and not p.assets_started and not p.textures_started and not FileAccess.file_exists(Index.cache_path(bad.path,content_root)),"invalid far building ownership cannot hide behind local selection")
	dispose(p)
	var changed:=fixture("changed");p=parse(changed.path,false,true)
	check(p._error==ERR_BUSY and not p.assets_started and not p.textures_started,"source change during directory rebuild fails before model/image preparation")
	dispose(p)
	var cancelled:=fixture("cancelled");p=parse(cancelled.path,false,false,true)
	check(p._error==ERR_SKIP and not p.assets_started and not p.textures_started and empty_selection(p),"cancellation during selected validation rolls back unpublished selection and stops preparation")
	dispose(p)
	Loader.entry_pipeline_enabled=old_pipeline;Loader.cold_index_rebuild_enabled=old_rebuild
	created.append_array(helper.created);helper.free()
	for path:String in created:
		if Paths.allowed(path,content_root) and FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	for name_:String in fixture_names:DirAccess.remove_absolute(folder.path_join(name_+".gltf.resources"))
	DirAccess.remove_absolute(folder)
	print("COLD_REFERENCE_INDEX passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
