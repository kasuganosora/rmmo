extends SceneTree
## CPU-only fixtures. No renderer, model loading, or formal map writes.
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Snapshot=preload("res://scripts/world3d/document_source_snapshot.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Pose=preload("res://scripts/world3d/pose_save.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
var folder:=""
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS: " if ok else "FAIL: ",label)
	if ok:passed+=1
	else:failures+=1
func write(path:String,data:Dictionary)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
func record(id:String)->Dictionary:
	return {"uuid":id,"kind":"box","surface_id":"block","collision":"block","position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"surface_paint":[{"mesh":"","geometry":"cpu","surface":0,"face":0,"scale":[1,1],"offset":[0,0],"rotation":0,"mapping":"uv","material":{"name":"stone","color":[.7,.7,.7,1],"roughness":.9}}]}
func fixture(name_:String,records:Array)->Dictionary:
	var path:=folder.path_join(name_+".gltf");var saved:=Store.write_records(records,path,Paths.external_root())
	if not saved.ok:check(false,"fixture writer "+str(saved.reason));return {}
	var data:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"extras":{"rmmo_format":"rmmo_gltf_map","rmmo_version":2,"rmmo_storage":"references_v1","rmmo_records":saved.records,"rmmo_resource_dependencies":saved.dependencies}}]}
	write(path,data);return {"path":path,"data":data}
func begin(path:String,mcp:bool=true)->RefCounted:
	var value:=Cursor.new();value.begin_snapshot(Snapshot.read_file(path),mcp);return value
func drain(value:RefCounted)->void:
	var deadline:=Time.get_ticks_msec()+15000
	while not value.done and Time.get_ticks_msec()<deadline:
		value.advance(1)
		if not value.done:await process_frame
	check(value.done,"sliced transaction terminates")
func to_phase(value:RefCounted,phase:String)->void:
	var deadline:=Time.get_ticks_msec()+15000
	while not value.done and value._phase!=phase and Time.get_ticks_msec()<deadline:
		value.advance(1)
		if not value.done:await process_frame
	check(not value.done and value._phase==phase,"reached "+phase+" before publication")
func prefab_payload()->Dictionary:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	var data:={"materials":[{"null":true}],"meshes":[{"surfaces":[arrays],"materials":[0],"bounds":AABB(Vector3.ZERO,Vector3(1,1,0)),"box_size":Vector3.ZERO}],"entries":[[["fixture"],[0,0]]],"specs":[]}
	var bytes:=var_to_bytes(data)
	return {"version":1,"sha256":Prefab.Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
func run()->void:
	create_timer(60).timeout.connect(func():print("REFERENCE_CURSOR_TIMEOUT");quit(1))
	folder=Paths.cache_directory("reference_cursor_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var a:=record("a");var b:=record("b");a.editor_hidden=true;b.editor_locked=true;b.position=[2,3,4];b.rotation=[0,90,0]
	var main:=fixture("main",[a,b]);var compact:Array=main.data.nodes[0].extras.rmmo_records
	check(compact[0].rmmo_ref.sha256==compact[1].rmmo_ref.sha256,"distinct state and pose share only immutable definition")
	var sliced:=begin(main.path);await drain(sliced)
	var sync:=begin(main.path);while not sync.done:sync.advance()
	check(sliced.document!=null and sync.document!=null and Pose.same(sliced.document.records,[a,b]) and Pose.same(sliced.document.records,sync.document.records),"sync and sliced preserve every instance state and pose")
	check(sliced.metrics.verified_paint_ids==2 and sliced.metrics.common_records==2 and sliced.metrics.document_records==2,"identities do not skip instance business validators")
	var malformed:Dictionary=main.data.duplicate(true);malformed.nodes[0].extras.rmmo_records[1].rmmo_state.fixture={"id":"door","kind":"door","pivot":[0,0,0],"angle":90,"open":2}
	write(main.path,malformed);var invalid:=begin(main.path);await drain(invalid)
	check(invalid.document==null,"shared definition cannot bypass invalid fixture state")
	var extra:=record("extra");extra.surface_paint[0].material.color=[2,1,1,1];extra.rmmo_ref=compact[0].rmmo_ref
	malformed=main.data.duplicate(true);malformed.nodes.append({"extras":{"rmmo_records":[extra]}});write(main.path,malformed)
	invalid=begin(main.path);await drain(invalid)
	check(invalid.document==null and "surface" in invalid.error,"non-root records cannot borrow trusted paint identity")
	var outside:=record("outside");outside.kind="asset";outside.asset_path="C:/outside/no-model.glb"
	check(not Cursor.asset_record_issue(outside,{}).is_empty(),"static API still rejects outside model path without private cache")
	var outside_file:=fixture("outside",[outside]);invalid=begin(outside_file.path);await drain(invalid)
	check(invalid.document==null,"v2 root still rejects outside model path")
	var old:Dictionary=main.data.duplicate(true);old.nodes[0].extras={"rmmo_format":"rmmo_gltf_map","rmmo_version":1,"rmmo_records":[a,b]};write(main.path,old)
	var legacy:=Cursor.new();legacy.begin_document(main.path,{},true,Callable(),true);await drain(legacy)
	check(legacy.document!=null and legacy._verified_paint_ids.is_empty() and not legacy.metrics.has("prefab_warm"),"explicit legacy path retains non-identity validation")
	var prefab:=record("prefab_a");prefab.erase("surface_paint");prefab.house_prefab=prefab_payload();prefab.prefab_materials=[];prefab.prefab_locked=true
	prefab.building={"id":"h","part":"wall","role":"wall","floor":0,"floor_y":0}
	var second:=prefab.duplicate(true);second.uuid="prefab_b";second.building.part="wall_b"
	var frozen:=fixture("prefab",[prefab,second])
	# Stop at nodes: warm work already ran on the reference worker; no instance
	# validator or owner lookup has yet touched the intentionally minimal fixture.
	var prepared:=begin(frozen.path);await to_phase(prepared,"nodes")
	check(prepared.metrics.prefab_warm.unique==1 and prepared.metrics.prefab_warm.decoded==1 and Prefab._decoded.has(prefab.house_prefab.sha256),"single reference worker warms unique CPU prefab once before node validation")
	prepared=null
	var corrupt:=prefab.duplicate(true);corrupt.house_prefab.data=Marshalls.raw_to_base64(PackedByteArray([1,2,3]))
	var corrupt_map:=fixture("bad_prefab",[corrupt]);invalid=begin(corrupt_map.path);await drain(invalid)
	check(invalid.document==null and "building" in invalid.error,"worker warm-up never authorizes invalid embedded payload")
	var paths_clean:bool=await path_swap_test()
	if not paths_clean:quit(1);return
	Io._remove_tree(folder)
	print("REFERENCE_CURSOR_VALIDATION_FINISHED passed=%d failures=%d"%[passed,failures]);quit(0 if failures==0 else 1)
func path_swap_test()->bool:
	var models:=folder.path_join("models");var target:=folder.path_join("target")
	DirAccess.make_dir_recursive_absolute(models);DirAccess.make_dir_recursive_absolute(target)
	var rows:Array=[]
	for i in 5:
		var item:=record("asset_%d"%i);item.kind="asset";item.asset_path=models.path_join("missing.glb");rows.append(item)
	var map:=fixture("path_swap",rows);var cursor:=begin(map.path);await to_phase(cursor,"signature")
	check(cursor._asset_paths.size()==1,"repeated model paths share one operation-local permission result")
	cursor.advance();check(cursor.document!=null,"path authority check does not introduce model existence rejection")
	cursor=begin(map.path);await to_phase(cursor,"signature")
	var mcp_only:=Cursor.new();mcp_only.begin_map_validation(map.path,JSON.parse_string(FileAccess.get_file_as_string(map.path)))
	var deadline:=Time.get_ticks_msec()+15000
	while not mcp_only.done and mcp_only.metrics.common_records<rows.size() and Time.get_ticks_msec()<deadline:
		mcp_only.advance(1)
		if not mcp_only.done:await process_frame
	check(not mcp_only.done and mcp_only._asset_paths.size()==1,"MCP-only validator also retains a private path scope before completion")
	# Only remove the verified empty fixture directory. The junction itself is
	# unlinked non-recursively before the temporary workspace is ever cleaned.
	check(models.begins_with(folder+"/") and DirAccess.remove_absolute(models)==OK,"empty temporary model directory removed")
	var output:Array=[]
	var command:="$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path '%s' -Target '%s' | Out-Null"%[models.replace("'","''"),target.replace("'","''")]
	var code:=OS.execute("powershell.exe",["-NoProfile","-NonInteractive","-Command",command],output,true,false)
	check(code==0,"temporary junction fixture created")
	if code==0:
		cursor.advance()
		check(cursor.document==null and "outside" in cursor.error,"sliced cached path changed to junction rejects before publication")
		await drain(mcp_only)
		check("outside" in mcp_only.error,"MCP-only final validation also rechecks changed path authority")
		var cleanup:=OS.execute("powershell.exe",["-NoProfile","-NonInteractive","-Command","[IO.Directory]::Delete('%s')"%models.replace("'","''")],output,true,false)
		if cleanup!=0:push_error("Junction cleanup failed; refusing recursive fixture cleanup");return false
	return true
