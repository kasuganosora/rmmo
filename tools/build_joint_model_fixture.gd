extends SceneTree
## CPU-only validation fixture writer. No model, mesh, texture or native cache builds.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Writer=preload("res://scripts/world3d/reference_map_save.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Pose=preload("res://scripts/world3d/pose_save.gd")
var report:Dictionary={"checks":[],"failures":[],"fixtures":{}}
var output:=""

func _initialize()->void:
	_run.call_deferred()

func check(value:bool,label:String)->bool:
	report.checks.append({"label":label,"ok":value})
	if not value:report.failures.append(label)
	print("PASS " if value else "FAIL ",label)
	return value

func finish()->void:
	report.passed=report.failures.is_empty()
	if not output.is_empty():
		var f:=FileAccess.open(output,FileAccess.WRITE)
		if f!=null:f.store_string(JSON.stringify(report,"\t",false,true));f.close()
	quit(0 if report.passed else 1)

func read_json(path:String)->Dictionary:
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func replace_asset_paths(value:Variant,mapping:Dictionary,changes:Array,location:String)->void:
	if value is Dictionary:
		for key in value:
			if key=="asset_path" and value[key] is String:
				var canonical:String=value[key].replace("\\","/").simplify_path()
				if mapping.has(canonical):
					changes.append({"location":location+"/asset_path","before":value[key],"after":mapping[canonical]})
					value[key]=mapping[canonical]
			else:replace_asset_paths(value[key],mapping,changes,location+"/"+str(key))
	elif value is Array:
		for i in value.size():replace_asset_paths(value[i],mapping,changes,location+"/"+str(i))

func _run()->void:
	var spec_path:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--spec="):spec_path=arg.trim_prefix("--spec=")
	if not check(DisplayServer.get_name()=="headless","CPU-only headless fixture process"):finish();return
	if not check(Paths.allowed(spec_path) and FileAccess.file_exists(spec_path),"input specification confined to content root"):finish();return
	var spec:=read_json(spec_path)
	var directory:String=spec.root
	if not check(Paths.allowed(directory) and directory.get_file().begins_with("joint_model_validation_20261011_"),"unique joint fixture root"):finish();return
	output=directory.path_join("map_fixture_report.json")
	var source:String=spec.source
	if not check(FileAccess.get_sha256(source)==spec.source_sha256,"formal source SHA before CPU read"):finish();return
	var data:=read_json(source)
	var extras:Dictionary=data.nodes[0].extras
	if not check(extras.rmmo_version==2 and extras.rmmo_storage=="references_v1","reference-map v2 input"):finish();return
	var hydrated:=Store.read_records(extras.rmmo_records,source,Paths.external_root(),extras.rmmo_resource_dependencies)
	if not check(hydrated.ok,"production Store verifies and hydrates source reference closure"):finish();return
	var original:Array=hydrated.records
	var metadata:Dictionary=extras.duplicate(true)
	for key in metadata.keys():
		if str(key).begins_with("rmmo_"):metadata.erase(key)
	if not check(original.size()==4437 and metadata.building_instances.size()==61,"4437 records and 61 houses"):finish();return
	var unique:Dictionary={}
	for record:Dictionary in original:
		if record.get("kind")=="asset":unique[record.asset_path]=true
	report.original_asset_paths=unique.keys()
	report.source=source;report.source_sha256=spec.source_sha256
	report.source_reference_definitions=extras.rmmo_resource_dependencies.size()
	# Baseline has been copied byte-for-byte with only the declared adjacent .rmres closure.
	var baseline:String=directory.path_join("baseline/map.gltf")
	if not check(FileAccess.get_sha256(baseline)==spec.source_sha256,"baseline map byte identity"):finish();return
	var baseline_hydrated:=Store.read_records(extras.rmmo_records,baseline,Paths.external_root(),extras.rmmo_resource_dependencies)
	if not check(baseline_hydrated.ok and Pose.same(baseline_hydrated.records,original),"baseline adjacent dependencies reopen exactly"):finish();return
	report.fixtures.baseline={"map":baseline,"sha256":FileAccess.get_sha256(baseline),"records":original.size(),"houses":metadata.building_instances.size(),"changed_instances":0,"dependencies":extras.rmmo_resource_dependencies.size()}
	baseline_hydrated.clear()
	for mode:String in ["preferred","combined"]:
		var mapping:Dictionary=spec.mappings.get(mode,{})
		if mapping.is_empty():continue
		var doc=Doc.new();doc.records=original.duplicate(true);doc.map_meta=metadata.duplicate(true)
		var changes:Array=[];var meta_changes:Array=[];var changed_ids:Array=[];var changed_paths:Dictionary={}
		for record:Dictionary in doc.records:
			var before:=changes.size()
			replace_asset_paths(record,mapping,changes,"records/"+record.uuid)
			if changes.size()>before:
				changed_ids.append(record.uuid)
				for change:Dictionary in changes.slice(before):changed_paths[change.before]=int(changed_paths.get(change.before,0))+1
		replace_asset_paths(doc.map_meta,mapping,meta_changes,"map_meta")
		if not check(changed_paths.size()==mapping.size(),mode+" all requested model types present"):finish();return
		var reverse:Dictionary={}
		for key in mapping:reverse[mapping[key]]=key
		var restored:Array=doc.records.duplicate(true);var restored_meta:Dictionary=doc.map_meta.duplicate(true);var ignored:Array=[]
		replace_asset_paths(restored,reverse,ignored,"records");replace_asset_paths(restored_meta,reverse,ignored,"map_meta")
		if not check(Pose.same(restored,original) and Pose.same(restored_meta,metadata),mode+" only explicit asset_path substitutions; UUID pose collision wind paint houses preserved"):finish();return
		if not check(doc.validate_save()==OK,mode+" production document CPU save validation"):finish();return
		var target:String=directory.path_join(mode+"/map.gltf")
		var saved:=Writer.save(target,null,doc.records,doc.map_meta,Paths.external_root(),Io)
		if not check(saved.error==OK and saved.images_written==0,mode+" atomic reference save without model or image export"):finish();return
		var reopened:=read_json(target)
		var after:Dictionary=reopened.nodes[0].extras
		var reread:=Store.read_records(after.rmmo_records,target,Paths.external_root(),after.rmmo_resource_dependencies)
		if not check(reread.ok and Pose.same(reread.records,doc.records),mode+" production reference reopen equals full author records"):finish();return
		var reopened_meta:Dictionary=after.duplicate(true)
		for key in reopened_meta.keys():
			if str(key).begins_with("rmmo_" ):reopened_meta.erase(key)
		if not check(Pose.same(reopened_meta,doc.map_meta),mode+" metadata dependency references reopen exactly"):finish();return
		if not check(Pose.same(reopened.nodes.slice(1),data.nodes.slice(1)),mode+" all glTF placement proxy UUIDs and transforms unchanged"):finish();return
		report.fixtures[mode]={"map":target,"sha256":FileAccess.get_sha256(target),"records":doc.records.size(),"houses":doc.map_meta.building_instances.size(),"changed_instances":changed_ids.size(),"changed_ids":changed_ids,"changed_paths":changed_paths,"metadata_changes":meta_changes,"dependencies":after.rmmo_resource_dependencies.size(),"save":saved}
		reread.clear();doc=null
	if not check(FileAccess.get_sha256(source)==spec.source_sha256,"formal map SHA unchanged after fixture publication"):finish();return
	finish()
