extends "res://tools/test_world3d_city_layout.gd"
const Library = preload("res://scripts/world_editor/asset_library.gd")

func run() -> void:
	Engine.max_fps=60; root.size=Vector2i(1440,960); root.content_scale_size=root.size
	directory=Paths.cache_directory("editor_navigation_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	for i in 120: doc.add_box_silent("block",Vector3(i%12,1,i/12),Vector3.ONE)
	check(doc.save(path)==OK,"temporary load fixture saved")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=null; session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false
	editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); editor._safety.enabled=false
	check(editor._load_job.active and editor._load_job._layer.visible,"initial opening immediately shows load overlay")
	var frames:=0; var phases: Array=[]
	while editor._load_job.active and frames<1800:
		phases.append(editor._load_job.phase); frames+=1; await process_frame
	check(editor._load_job.result.get("ok",false) and frames>=2 and "read" in phases and "build" in phases,"initial load presents staged progress across frames")
	check(editor._doc.records.size()==120 and not root.gui_disable_input,"initial load restores document and input")
	await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"navigation HTTP server starts")
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,0,0],"yaw":35.,"pitch":-45.,"distance":30.})
	var snapshot: Dictionary=editor._doc.recovery_snapshot(); var history: int=editor._doc._undo.size()
	var camera: Vector3=editor._camera.position; var center: Vector3=editor._orbit_center
	await call_tool("move_editor_camera",{"offset":[1,2,3]})
	check(editor._camera.position.is_equal_approx(camera+Vector3(1,2,3)) and editor._orbit_center.is_equal_approx(center+Vector3(1,2,3)),"HTTP camera offset moves camera and center together")
	await atomic_reject("move_editor_camera",{"offset":[1,2]})
	var mouse:=InputEventMouseButton.new(); mouse.button_index=MOUSE_BUTTON_MIDDLE; mouse.pressed=true; mouse.position=editor._canvas.get_global_rect().get_center()
	editor._input(mouse)
	var key:=InputEventKey.new(); key.physical_keycode=KEY_W; key.pressed=true
	var mode: int=editor._transform_mode; var origin: Vector3=editor._camera.position
	editor._input(key); editor._camera_navigation._process(.016)
	check(editor._camera.position.distance_to(origin)>0 and is_equal_approx(editor._camera.position.y,origin.y) and editor._transform_mode==mode,"middle + W moves horizontally without activating gizmo shortcut")
	key.pressed=false; editor._input(key); key.physical_keycode=KEY_UP; key.pressed=true
	origin=editor._camera.position; editor._input(key); editor._camera_navigation._process(.016)
	check(editor._camera.position.y>origin.y and is_equal_approx(editor._camera.position.x,origin.x) and is_equal_approx(editor._camera.position.z,origin.z),"middle + up moves only vertically")
	mouse.pressed=false; editor._input(mouse); origin=editor._camera.position; editor._camera_navigation._process(.05)
	check(editor._camera.position==origin and editor._camera_navigation.keys.is_empty(),"middle release stops all navigation")
	mouse.pressed=true; editor._input(mouse); editor._input(key); editor._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not editor._camera_navigation.held and editor._camera_navigation.keys.is_empty(),"focus loss clears navigation state")
	check(equivalent(snapshot,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"camera navigation leaves map and undo untouched")
	var broken:=directory.path_join("broken.gltf"); FileAccess.open(broken,FileAccess.WRITE).store_string("{")
	var old_doc=editor._doc
	var faces: Dictionary=editor._material_tool.list_faces("obj_1")
	check(faces.ok and not faces.faces.is_empty(),"material selection fixture has paintable faces")
	var selected_face: Dictionary={"ok":true,"id":"obj_1","target":faces.faces[0].target}
	editor._material_tool.selected=selected_face.duplicate(true)
	var job:=await call_tool("open_world",{"path":broken,"background":true})
	check(job.pending,"background open returns pending job")
	while editor._load_job.active: await process_frame
	check(not editor._load_job.result.ok and editor._doc==old_doc and editor._path==path and not root.gui_disable_input,"failed asynchronous open retains original document and unlocks input")
	check(editor._material_tool.selected==selected_face,"failed open preserves the original material selection")
	await call_tool("open_world",{"path":path})
	check(editor._doc.records.size()==120 and not editor._load_job.active,"default HTTP open waits until scene and batches are ready")
	check(editor._material_tool.selected.is_empty(),"successful open clears material selection even when UUID and geometry match")
	await check_thumbnail_repair()
	await check_large_autosave()
	editor.queue_free(); await settle(); print("EDITOR_NAVIGATION_LOADING failures=",failed); quit(0 if failed==0 else 1)

func check_thumbnail_repair() -> void:
	var source:=Node3D.new(); var mesh:=MeshInstance3D.new(); mesh.mesh=BoxMesh.new(); source.add_child(mesh)
	var model:=directory.path_join("old_import.glb")
	check(preload("res://scripts/world3d/gltf_map_io.gd").save_scene(source,model)==OK,"thumbnail fixture model saved"); source.free()
	editor._assets=Library.new(directory.path_join("assets")); var imported: Dictionary=editor._assets.import_file(model)
	check(imported.ok and not FileAccess.file_exists(imported.entry.thumbnail_path),"simulate historical import without PNG")
	editor._query=imported.entry.label; editor._refresh_palette(); await settle()
	for i in 300:
		if FileAccess.file_exists(imported.entry.thumbnail_path): break
		await process_frame
	check(FileAccess.file_exists(imported.entry.thumbnail_path) and editor._thumbnails.lookup(imported.entry)!=editor._thumbnails.placeholder,"visible missing import automatically gains cached thumbnail")
	var loads: int=editor._thumbnails.model_load_count
	editor._thumbnails.cache.clear(); editor._update_visible_thumbnails()
	for i in 40: await process_frame
	check(editor._thumbnails.model_load_count==loads,"revisiting cached thumbnails never loads the model again")
	var before: Dictionary=editor._doc.recovery_snapshot()
	await atomic_reject("repair_asset_thumbnails",{"asset_ids":[model,"unavailable"]})
	await call_tool("repair_asset_thumbnails",{"asset_ids":[imported.entry.asset_path]})
	for i in 180:
		if editor._thumbnails._imports.is_empty() and not editor._thumbnails._busy: break
		await process_frame
	var assets:=await call_tool("list_assets",{"query":"old_import"})
	check(assets.assets[0].thumbnail.status=="ready" and equivalent(before,editor._doc.recovery_snapshot()),"HTTP repair produces persisted PNG without changing map")

func check_large_autosave() -> void:
	var snapshot: Dictionary=editor._doc.recovery_snapshot()
	var disk_hash:=FileAccess.get_sha256(editor._path)
	editor._doc.map_meta.audit_blob="payload".repeat(5000000)
	editor._dirty=true; editor._safety.enabled=true
	editor._safety.tick()
	check(editor._safety.state().active,"large autosave encodes in a worker")
	editor._doc.map_meta.audit_blob="edit after snapshot"
	var frames:=0
	while editor._safety.state().active and frames<1800: frames+=1; await process_frame
	var storage=editor._safety.store; var id: String=storage.own_id(editor._path)
	var restored: Dictionary=storage.read(id)
	print("LARGE_DRAFT ",JSON.stringify({"frames":frames,"ok":restored.ok,"error":restored.get("error",""),"version":restored.get("header",{}).get("version"),"length":str(restored.get("state",{}).get("map_meta",{}).get("audit_blob","")).length()}))
	check(frames>1 and restored.ok and restored.header.version==2 and restored.state.map_meta.audit_blob.length()==35000000,"large compressed draft retains immutable snapshot while editor continues")
	check(editor._doc.map_meta.audit_blob=="edit after snapshot" and FileAccess.get_sha256(editor._path)==disk_hash,"background draft preserves newer edits and formal map")
	var file_path: String=storage.file_for(id); var valid_bytes:=FileAccess.get_file_as_bytes(file_path)
	var corrupted:=FileAccess.open(file_path,FileAccess.READ_WRITE); corrupted.seek_end(); corrupted.store_8(1); corrupted.close()
	check(not storage.read(id).ok,"compressed draft rejects trailing corruption")
	FileAccess.open(file_path,FileAccess.WRITE).store_buffer(valid_bytes)
	editor._doc.map_meta.audit_blob="payload".repeat(5000000); editor._safety.tick()
	while editor._safety._preparing: await process_frame
	check(editor._safety._draft_thread!=null,"formal save overlaps an actual background writer")
	editor._safety.saved(editor._path)
	while editor._safety.state().active: await process_frame
	check(not FileAccess.file_exists(file_path),"formal-save completion suppresses stale in-flight draft publication")
	editor._doc.apply_recovery(snapshot); editor._dirty=false; editor._safety.enabled=false
