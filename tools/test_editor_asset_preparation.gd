extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Job=preload("res://scripts/world_editor/load_job.gd")
const Neighbors=preload("res://scripts/world3d/terrain_neighbors.gd")
const Regions=preload("res://scripts/world3d/terrain_regions.gd")

func terrain_vertices(id:String)->PackedVector3Array:
	return editor._view.get_node(id).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

func terrain_mask(id:String)->PackedByteArray:
	return editor._view.get_node(id).get_active_material(0).get_meta("ground_mask_image").get_data()

func run()->void:
	Engine.max_fps=60
	create_timer(90).timeout.connect(func():quit(2))
	var directory:=Paths.cache_directory("asset_prepare_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var asset_path:=directory.path_join("fixture.glb")
	var model:=Node3D.new();model.name="Fixture"
	var mesh:=MeshInstance3D.new();mesh.name="Mesh";mesh.mesh=BoxMesh.new();mesh.owner=null
	model.add_child(mesh);mesh.owner=model
	check(Io.save_scene(model,asset_path)==OK,"tiny model fixture exported")
	model.free()
	var original:=FileAccess.get_file_as_bytes(asset_path)
	var doc:=Doc.new();var first:String=doc.add_asset({"asset_path":asset_path},Vector3.ZERO)
	var second:String=doc.add_asset({"asset_path":asset_path},Vector3(5,0,0))
	var terrain_id:String=doc.add_box("ground",Vector3(20,0,0),Vector3(8,1,8))
	doc._find(terrain_id).terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-8.,"heights":[0.,0.,0.,0.,.1,0.,0.,0.,0.],"holes":[false,false,false,false]}
	var region_args:={"id":"garden","terrain_ids":[terrain_id],"polygon":[[18,-2],[22,-2],[22,2],[18,2]],"material_id":"builtin:white","feather":1.}
	var region=preload("res://scripts/world_editor/terrain_region_tools.gd").prepare(doc.records,region_args,preload("res://scripts/world_editor/surface_material_library.gd").new(),func(_r):return true)
	check(region.ok,"initial terrain region fixture prepared")
	if not region.ok:quit(1);return
	doc.records[2]=region.records[0]
	var path:=directory.path_join("map.gltf");check(doc.save(path)==OK,"isolated asset and terrain map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP server started")
	Library._scenes.clear()
	var before:Dictionary=doc._find(first).duplicate(true)
	await call_tool("open_world",{"path":path})
	var units:Dictionary=editor._load_job.state().timings.build.units
	check(units.get("asset_parse_worker",{}).get("count",0)==1,"one background parse for repeated asset")
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
	# Deliberately broken bytes produce expected native parser diagnostics.
	Library._scenes.clear()
	FileAccess.open(asset_path,FileAccess.WRITE).store_string("invalid glb")
	await call_tool("open_world",{"path":path})
	check(editor._view.get_node(first).has_meta("missing_asset") and not Library._scenes.has(asset_path),"failed background import uses normal missing placeholder without negative cache")
	FileAccess.open(asset_path,FileAccess.WRITE).store_buffer(original)
	await call_tool("open_world",{"path":path})
	check(not editor._view.get_node(first).has_meta("missing_asset") and editor._load_job.state().timings.build.units.asset_parse_worker.count==1,"repaired resource is parsed on next load")
	var retained:Node3D=editor._view
	await call_tool("open_world",{"path":directory.path_join("absent.gltf")},false)
	check(editor._view==retained and not editor._load_job.active,"illegal open leaves the completed view available")
	var job:=Job.new();root.add_child(job);job._thread=Thread.new();job._thread.start(Job._parse_asset.bind(asset_path));var owned_thread:Thread=job._thread
	job.free();check(not owned_thread.is_started(),"freeing job joins an outstanding private parser")
	editor.queue_free();await settle()
	print("EDITOR_ASSET_PREPARATION_FAILED=",failed);quit(1 if failed else 0)
