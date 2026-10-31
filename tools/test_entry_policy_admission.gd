extends SceneTree
## A known unannotated asset already requires the full entry gate. Policy
## selection should not build an unused whole-map authority catalogue first.
const Policy=preload("res://scripts/world3d/entry_stage_policy.gd")
const Authority=preload("res://scripts/world3d/local_entry_authority.gd")
const Transaction=preload("res://scripts/world3d/building_entry_transaction.gd")
class CountingAuthority extends Authority:
	var registrations:=0
	func register_root(map_ref:String,revision:String,map_root:Node)->Dictionary:
		registrations+=1
		return super.register_root(map_ref,revision,map_root)
class Directory extends Node:
	var _reference_index:Dictionary={}
var checks:=0
var failures:Array=[]
var result:Dictionary={}
var baseline:=false
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func fixture(meta:Dictionary,index:Dictionary={})->Node3D:
	var map_root:=Node3D.new();map_root.set_meta("extras",meta)
	if not index.is_empty():
		map_root.set_meta("author_reference_extras",meta);map_root.set_meta("runtime_record_subset",true)
		var deferred:=Directory.new();deferred.name="DeferredAssets";deferred._reference_index=index;map_root.add_child(deferred)
	return map_root
func run()->void:
	baseline="--baseline" in OS.get_cmdline_user_args()
	var record:Dictionary={"uuid":"tree","position":[0,0,0],"rotation":[0,0,0],"size":[2,4,2],"rmmo_state":{}}
	var meta:Dictionary={"rmmo_records":[record]}
	var row:Dictionary={"uuid":"tree","bounds_known":true,"bounds":AABB(Vector3(-1,0,-1),Vector3(2,4,2)),"asset_path":"test-native-product"}
	var map_root:=fixture(meta,{"rows":[row]});var before:=var_to_bytes(meta)
	var authority:=CountingAuthority.new()
	var selected:Dictionary=Policy.select(authority,map_root,"map","revision")
	check(selected=={"mode":"full","reason":"unresolved_volumes"},"unannotated directory asset keeps complete waiting policy")
	if not baseline:check(authority.registrations==0 and authority._maps.is_empty(),"known full-wait fallback does not construct an unused authority catalogue")
	check(var_to_bytes(meta)==before,"policy leaves complete author snapshot unchanged")
	# Explicit protocol entry still performs authority registration and denies
	# unresolved membership. The optimization only selects the full wait policy.
	var forced:=Transaction.new();var started:Dictionary=forced.begin(authority,map_root,"session","world","map","revision",Vector3(0,1,0),"forced",true)
	check(not started.ok and authority.registrations==1 and authority.registered_root_current("map","revision",map_root),"forced building entry still registers and denies unknown interior")
	forced=null
	row.asset_path=""
	selected=Policy.select(authority,map_root,"map","changed")
	check(selected.mode=="staged" and authority.registered_root_current("map","changed",map_root),"next selection sees changed metadata and builds the required authority catalogue")
	map_root.free()
	# An annotation must reach the existing authority checks, whether authored
	# directly or stored in the compact state. Do not reject all imported assets.
	for compact:bool in [false,true]:
		var annotated:Dictionary=record.duplicate(true)
		if compact:annotated.rmmo_state.model_building={}
		else:annotated.model_building={}
		map_root=fixture({"rmmo_records":[annotated]},{"rows":[{"uuid":"tree","bounds_known":true,"bounds":row.bounds,"asset_path":"annotated"}]})
		authority=CountingAuthority.new();selected=Policy.select(authority,map_root,"map","revision")
		check(authority.registrations==1 and selected.mode=="full" and selected.reason=="invalid_imported_building","annotated source preserves authority validation "+str(compact))
		map_root.free()
	map_root=fixture({"rmmo_records":[]});authority=CountingAuthority.new()
	check(Policy.select(authority,map_root,"map","revision").mode=="staged" and authority.registrations==1,"no-directory map keeps ordinary catalogue construction")
	map_root.free()
	# Optional real-map fixture: read a copied, SHA-recorded directory payload,
	# without invoking model import, renderer uploads or the game loader.
	var path:="";var directory:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):path=arg.trim_prefix("--map=")
		if arg.begins_with("--directory="):directory=arg.trim_prefix("--directory=")
	if not path.is_empty():
		var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		meta=data.nodes[0].extras
		var file:=FileAccess.open(directory,FileAccess.READ);check(file.get_buffer(9).get_string_from_ascii()=="RMMODEPS1","real fixture directory header")
		var size:=file.get_64();file.get_buffer(32);var index:Dictionary=bytes_to_var(file.get_buffer(size));file.close()
		check(index.source_sha256==FileAccess.get_sha256(path),"directory belongs to the frozen map revision")
		map_root=fixture(meta,index);before=var_to_bytes(meta)
		var elapsed:Array=[];var registrations:=0
		for i in 8:
			authority=CountingAuthority.new();var begin:=Time.get_ticks_usec()
			selected=Policy.select(authority,map_root,str(meta.map_ref),index.source_sha256)
			elapsed.append(Time.get_ticks_usec()-begin);registrations+=authority.registrations
			check(selected.mode=="full" and selected.reason=="unresolved_volumes","real map retains full waiting policy "+str(i))
		if not baseline:check(registrations==0,"repeated real-map full entry never builds an unused catalogue")
		check(var_to_bytes(meta)==before,"real author snapshot remains byte exact")
		result.real={"times_us":elapsed,"registrations":registrations,"records":meta.rmmo_records.size(),"rows":index.rows.size(),"buildings":meta.building_instances.size(),"map_sha":FileAccess.get_sha256(path),"directory_sha":FileAccess.get_sha256(directory)}
		map_root.free()
	result.checks=checks;result.failures=failures
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ENTRY_POLICY_ADMISSION ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
