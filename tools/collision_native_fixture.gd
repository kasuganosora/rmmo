extends RefCounted
## Isolated collision-test producer. Only setup imports authoring GLB. Tests
## switch complete, actually generated publications; consumers retain no GLB.
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Native=preload("res://scripts/world3d/native_model_product.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Snapshot=preload("res://scripts/world3d/document_source_snapshot.gd")

static func index_build(path:String,root:String,records:Array)->Dictionary:
	# The runtime directory uses the published native package. Global strict
	# rmres/map mutation diagnostics remain enabled independently by the suite.
	return Index.build(path,root,records,"",Store.READ_WORKERS,Snapshot.RETAIN_LIMIT,true)

static func index_read(path:String,root:String)->Dictionary:
	return Index.read_for_loading(path,root,"",Snapshot.RETAIN_LIMIT,Index.MAX_BYTES,Store.READ_WORKERS,true)

static func publish(path:String,root:String)->Dictionary:
	var built:=Compiled.build(path)
	if not built.get("ok",false):return {"ok":false,"stage":"compile","details":built}
	var measured:=Footprint.build(path,root)
	if not measured.get("ok",false):return {"ok":false,"stage":"footprint","details":measured}
	var model:=Native.read(path,root)
	if model.is_empty():return {"ok":false,"stage":"native_metadata"}
	var files:Dictionary={}
	for filename:String in [Compiled.index_path(path,root),Footprint.descriptor_path(path,root),Footprint.building_descriptor_path(path,root)]:
		var bytes:=FileAccess.get_file_as_bytes(filename)
		if bytes.is_empty():return {"ok":false,"stage":"published_file","path":filename}
		files[filename]=bytes
	return {"ok":true,"model":model,"files":files,"source_sha":model.native_source_sha,"payload_sha":model.native_candidate.payload_sha}

static func install(snapshot:Dictionary)->bool:
	# Called only while the fixture worker is gated, or from its own explicit
	# cancellation callback before its next identity observation. No other load
	# uses these fresh files; real SCN bytes and source/payload bindings survive.
	if not snapshot.get("ok",false):return false
	for path:String in snapshot.files:
		if not write_bytes(path,snapshot.files[path]):return false
	return true

static func write_bytes(path:String,bytes:PackedByteArray)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_buffer(bytes);file.flush()
	var error:=file.get_error();file.close()
	return error==OK

static func structural_scene(extra:Dictionary,dynamic_kind:String="")->PackedScene:
	# Real SceneState input to the offline absence analyzer. Unsupported dynamic
	# node classes remain in the SCN; malformed glTF JSON is never a substitute.
	var root:=Node3D.new();root.name="AbsenceContract";root.set_meta("extras",extra)
	var dynamic:Node
	if dynamic_kind=="animations":dynamic=AnimationPlayer.new()
	elif dynamic_kind=="skins":dynamic=Skeleton3D.new()
	if dynamic!=null:
		dynamic.name="Dynamic";root.add_child(dynamic);dynamic.owner=root
	var packed:=PackedScene.new();var code:=packed.pack(root);root.free()
	return packed if code==OK else null
