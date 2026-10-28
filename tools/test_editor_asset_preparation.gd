extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Job=preload("res://scripts/world_editor/load_job.gd")
const Neighbors=preload("res://scripts/world3d/terrain_neighbors.gd")
const Regions=preload("res://scripts/world3d/terrain_regions.gd")

func terrain_vertices(id:String)->PackedVector3Array:
	return editor._view.get_node(id).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

func terrain_mask(id:String)->PackedByteArray:
	return editor._view.get_node(id).get_active_material(0).get_meta("ground_mask_image").get_data()

func write_fixture(path:String,bytes:PackedByteArray)->bool:
	# Chained temporary FileAccess values can outlive the expression/coroutine
	# suspension. Publish the complete file before any synchronous/worker import.
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_buffer(bytes);file.flush()
	var written_ok:=file.get_error()==OK
	file.close()
	return written_ok and FileAccess.get_file_as_bytes(path)==bytes

func write_native_fixture(path:String)->bool:
	# Closed static GLB in the converter's supported format. This fixture has
	# real triangle bounds and no exporter-specific glTF extension.
	var binary:=PackedFloat32Array([0,0,0,1,0,0,0,1,0.5]).to_byte_array()
	var data:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"Fixture","mesh":0}],"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}],"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,0],"max":[1,1,0.5]}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":binary.size()}],"buffers":[{"byteLength":binary.size()}]}
	var json:=JSON.stringify(data).to_utf8_buffer()
	while json.size()%4:json.append(32)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_32(0x46546c67);file.store_32(2);file.store_32(28+json.size()+binary.size())
	file.store_32(json.size());file.store_32(0x4e4f534a);file.store_buffer(json)
	file.store_32(binary.size());file.store_32(0x004e4942);file.store_buffer(binary);file.flush()
	var ok:=file.get_error()==OK;file.close();return ok

func run()->void:
	Engine.max_fps=60
	Job.parallel_preparation_enabled=not OS.get_cmdline_user_args().has("--without-parallel-preparation")
	create_timer(90).timeout.connect(func():quit(2))
	var directory:=Paths.cache_directory("asset_prepare_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var manager:=root.get_node("AssetManager");var old_root:String=manager.content_root_override;manager.content_root_override=directory
	var asset_path:=directory.path_join("fixture.glb")
	check(write_native_fixture(asset_path),"tiny supported model fixture exported")
	var original:=FileAccess.get_file_as_bytes(asset_path)
	check(original.size()>20 and original.slice(0,4).get_string_from_ascii()=="glTF","exported fixture contains a complete binary GLB")
	var native:=preload("res://scripts/world3d/compiled_asset_cache.gd").build(asset_path)
	var first_footprint:Dictionary=Library._compile_footprint(asset_path) if native.get("ok",false) else {}
	check(native.get("ok",false) and first_footprint.get("ok",false),"first source explicitly converted to native")
	if not native.get("ok",false) or not first_footprint.get("ok",false):
		print("NATIVE_FIXTURE_FAILURE ",JSON.stringify({"build":native,"footprint":first_footprint}));manager.content_root_override=old_root;quit(1);return
	var doc:=Doc.new();var first:String=doc.add_asset({"asset_path":asset_path},Vector3.ZERO)
	var second:String=doc.add_asset({"asset_path":asset_path},Vector3(5,0,0))
	var terrain_id:String=doc.add_box("ground",Vector3(20,0,0),Vector3(8,1,8))
	doc._find(terrain_id).terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-8.,"heights":[0.,0.,0.,0.,.1,0.,0.,0.,0.],"holes":[false,false,false,false]}
	var region_args:={"id":"garden","terrain_ids":[terrain_id],"polygon":[[18,-2],[22,-2],[22,2],[18,2]],"material_id":"builtin:white","feather":1.}
	var region=preload("res://scripts/world_editor/terrain_region_tools.gd").prepare(doc.records,region_args,preload("res://scripts/world_editor/surface_material_library.gd").new(),func(_r):return true)
	check(region.ok,"initial terrain region fixture prepared")
	if not region.ok:quit(1);return
	doc.records[2]=region.records[0]
	var next_asset_path:=directory.path_join("second_fixture.glb")
	if not write_fixture(next_asset_path,original):check(false,"second fixture bytes persisted before editor open");quit(1);return
	check(FileAccess.get_sha256(next_asset_path)==FileAccess.get_sha256(asset_path),"second fixture is closed and byte-identical before synchronous editor build")
	native=preload("res://scripts/world3d/compiled_asset_cache.gd").build(next_asset_path)
	var second_footprint:Dictionary=Library._compile_footprint(next_asset_path) if native.get("ok",false) else {}
	check(native.get("ok",false) and second_footprint.get("ok",false),"second source explicitly converted to native")
	if not native.get("ok",false) or not second_footprint.get("ok",false):
		print("NATIVE_FIXTURE_FAILURE ",JSON.stringify({"build":native,"footprint":second_footprint}));manager.content_root_override=old_root;quit(1);return
	check(DirAccess.remove_absolute(asset_path)==OK and DirAccess.remove_absolute(next_asset_path)==OK,"editor fixture removes both import sources after conversion")
	var third:String=doc.add_asset({"asset_path":next_asset_path},Vector3(10,0,0))
	var path:=directory.path_join("map.gltf");check(doc.save(path)==OK,"isolated asset and terrain map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	check(not editor._view.get_node(third).has_meta("missing_asset"),"second fixture also succeeds in initial synchronous editor build")
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP server started")
	var discovery:=await rpc("tools/list")
	var names:Array=discovery.get("result",{}).get("tools",[]).map(func(tool):return tool.name)
	check("open_world" in names and "editor_state" in names,"HTTP discovery retains current 3D loading and state tools")
	Library._scenes.clear()
	var before:Dictionary=doc._find(first).duplicate(true)
	await call_tool("open_world",{"path":path})
	var units:Dictionary=editor._load_job.state().timings.build.units
	check(units.get("asset_parse_worker",{}).get("count",0)==2,"one background parse per distinct path despite repeated instances")
	var lookahead:Dictionary=editor._load_job.state().timings.asset_lookahead
	check(lookahead.unique_paths==2 and lookahead.started==2 and lookahead.consumed==2 and lookahead.peak_unconsumed<=4,"bounded lookahead consumes both unique model paths")
	check(editor._load_job._preparation==null and editor._load_job._asset_paths.is_empty(),"completed preparation releases queue and pending paths")
	var state:=await call_tool("editor_state")
	var capability:Dictionary=state.load.capabilities
	check(capability.metadata_ready and capability.viewport_ready and capability.query_ready and capability.editable and capability.policy=="full_document_gate","HTTP state reports distinct metadata, viewport and query capabilities only after full load")
	check(state.load.timings.preparation.ledger.reserved_bytes==0,"HTTP completed load retains no preparation byte leases")
	check(not editor._view.get_node(third).has_meta("missing_asset"),"next unique model is published normally after lookahead")
	check(units.get("terrain_neighbors_worker",{}).get("count",0)==1,"terrain preparation ran in private worker")
	check(units.get("terrain_arrays_worker",{}).get("count",0)==1 and units.get("terrain_masks_worker",{}).get("total_ms",0)>0,"terrain geometry and region mask were prepared off main")
	check(editor._load_job._thread==null,"completed preparation joined its worker")
	var a:Node3D=editor._view.get_node(first);var b:Node3D=editor._view.get_node(second)
	check(not a.has_meta("missing_asset") and not b.has_meta("missing_asset") and a.get_child(0)!=b.get_child(0),"prepared scene creates independent selectable instances")
	check(equivalent(editor._doc._find(first),before),"background preparation does not mutate records")
	var sync:=Neighbors.new();sync.update(editor._doc.records)
	var actual:Dictionary=editor._doc.terrain_neighbors.data[terrain_id];var expected:Dictionary=sync.data[terrain_id]
	check(actual.signature==expected.signature and actual.normals==expected.normals and actual.image.get_data()==expected.image.get_data(),"worker terrain signature normals and height image equal synchronous path")
	check(editor._doc.load_surface_arrays.is_empty() and not actual.has("region_mask") and editor._load_job._terrain_surfaces.is_empty() and editor._load_job._terrain_masks.is_empty(),"load-only geometry and mask caches are absent after scene construction")
	var original_vertices:=terrain_vertices(terrain_id)
	await call_tool("sculpt_terrain",{"id":terrain_id,"mode":"raise","points":[[20,0]],"radius":3.,"strength":1.})
	check(terrain_vertices(terrain_id)!=original_vertices,"HTTP sculpt rebuilds changed terrain geometry after prepared load")
	var raised_vertices:=terrain_vertices(terrain_id)
	await call_tool("undo");check(terrain_vertices(terrain_id)==original_vertices,"terrain undo restores original geometry")
	await call_tool("redo");check(terrain_vertices(terrain_id)==raised_vertices,"terrain redo restores changed geometry")
	var old_mask:=terrain_mask(terrain_id)
	await call_tool("paint_terrain_region",region_args.merged({"polygon":[[19,-2],[23,-2],[23,2],[19,2]],"feather":2.},true))
	var new_mask:=terrain_mask(terrain_id)
	check(new_mask!=old_mask and new_mask==Regions.mask(editor._doc._find(terrain_id)).get_data(),"region edits regenerate exact mask instead of reusing load snapshot")
	await call_tool("undo");check(terrain_mask(terrain_id)==old_mask,"region undo restores original mask")
	await call_tool("redo");check(terrain_mask(terrain_id)==new_mask,"region redo restores updated mask")
	await call_tool("save_world")
	await call_tool("open_world",{"path":path})
	check(terrain_vertices(terrain_id)==raised_vertices and terrain_mask(terrain_id)==new_mask,"edited terrain geometry and region survive save reopen")
	check(not editor._load_job.state().timings.build.units.has("asset_parse_worker"),"cached asset skips redundant background parse")
	# A missing native index must not fall back to an authoring source.
	Library._scenes.clear()
	var index:=preload("res://scripts/world3d/compiled_asset_cache.gd").index_path(asset_path,directory)
	var index_bytes:=FileAccess.get_file_as_bytes(index)
	check(not index_bytes.is_empty() and DirAccess.remove_absolute(index)==OK,"fixture removes first native index")
	await call_tool("open_world",{"path":path})
	check(editor._view.get_node(first).has_meta("missing_asset") and not Library._scenes.has(asset_path),"missing native product uses recoverable placeholder without raw fallback")
	if not write_fixture(index,index_bytes):check(false,"native index repair failed");quit(1);return
	await call_tool("open_world",{"path":path})
	check(not editor._view.get_node(first).has_meta("missing_asset") and editor._load_job.state().timings.build.units.asset_parse_worker.count==1,"repaired native index is read on next load")
	var retained:Node3D=editor._view
	await call_tool("open_world",{"path":directory.path_join("absent.gltf")},false)
	check(editor._view==retained and not editor._load_job.active,"illegal open leaves the completed view available")
	var drainer:=preload("res://scripts/world3d/asset_worker_drainer.gd").for_tree(self)
	var job:=Job.new();root.add_child(job);job._thread=Thread.new();job._thread.start(Job._parse_native_asset.bind(asset_path,directory,Library.native_candidate(asset_path,directory)));var owned_thread:Thread=job._thread
	job.free()
	var deadline:=Time.get_ticks_msec()+10000
	while owned_thread.is_started() and Time.get_ticks_msec()<deadline:await process_frame
	check(not owned_thread.is_started(),"tree-owned drainer eventually joins an abandoned private parser")
	Library._scenes.erase(asset_path)
	var pending_job:=Job.new();root.add_child(pending_job)
	pending_job._begin_asset_lookahead([{"kind":"asset","asset_path":asset_path},{"kind":"asset","asset_path":asset_path}])
	var queue:Node=pending_job._preparation
	var lease:RefCounted=queue.ledger
	check(queue.rows.size()==1 and pending_job._asset_paths.size()==1,"lookahead deduplicates before any scene build")
	var drained_before:int=drainer.drained
	pending_job.free()
	deadline=Time.get_ticks_msec()+10000
	while lease.count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(lease.count()==0 and drainer.drained>=drained_before and not Library._scenes.has(asset_path),"exit drains unconsumed lookahead without publishing a shared scene")
	editor.queue_free();await settle()
	manager.content_root_override=old_root
	print("EDITOR_ASSET_PREPARATION_FAILED=",failed);quit(1 if failed else 0)
