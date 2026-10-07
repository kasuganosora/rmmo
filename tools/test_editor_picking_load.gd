extends "res://tools/test_world3d_mcp.gd"
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Prepare=preload("res://scripts/world_editor/picking_load_preparation.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
var saw_picking:=false

func dense_mesh()->ArrayMesh:
	var mesh:=ArrayMesh.new()
	for offset in [0.,200.]:
		var vertices:=PackedVector3Array();var indices:=PackedInt32Array()
		for z in 48:
			for x in 128:
				var first:=vertices.size()
				vertices.append_array(PackedVector3Array([Vector3(offset+x,0,z),Vector3(offset+x+1,0,z),Vector3(offset+x,0,z+1),Vector3(offset+x+1,0,z+1)]))
				indices.append_array(PackedInt32Array([first,first+1,first+2,first+1,first+3,first+2]))
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_INDEX]=indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func observe()->void:
	if editor._load_job.phase=="picking":
		saw_picking=true
		editor._load_job._paint()
		check(editor._load_job._label.text.contains("准备拾取碰撞"),"picking progress uses localized label")

func run()->void:
	create_timer(90).timeout.connect(func():quit(2));Engine.max_fps=60
	var mesh:=dense_mesh();var snapshot:=Prepare.snapshot(mesh)
	check(not snapshot.is_empty() and not is_same(snapshot.surfaces,snapshot.cpu.surfaces) and not is_same(snapshot.surfaces[0],snapshot.cpu.surfaces[0]),"worker snapshot owns nested array containers")
	var worker:=Thread.new();worker.start(Prepare.extract.bind(snapshot.surfaces))
	while worker.is_alive():await process_frame
	var prepared:Dictionary=worker.wait_to_finish()
	check(snapshot.cpu._collision_faces.is_empty(),"private worker leaves live CPU cache untouched")
	check(Prepare.publish(snapshot,prepared.faces) and snapshot.cpu.collision_faces()==prepared.faces,"main publishes exact ordered triangle soup")
	var stale:=Prepare.snapshot(dense_mesh())
	stale.source.surface_set_material(0,StandardMaterial3D.new())
	check(not Prepare.publish(stale,prepared.faces) and Cpu.capture(stale.source)._collision_faces.is_empty(),"source changed during preparation rejects stale publication")
	var directory:=Paths.cache_directory("picking_load_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var asset_path:=directory.path_join("dense.glb");var model:=Node3D.new();model.name="Dense"
	var visual:=MeshInstance3D.new();visual.name="DenseMesh";visual.mesh=mesh;model.add_child(visual);visual.owner=model
	check(Io.save_scene(model,asset_path)==OK,"temporary dense model exported");model.free()
	var doc:=Doc.new();var id:String=doc.add_asset({"asset_path":asset_path},Vector3.ZERO)
	var path:=directory.path_join("map.gltf");check(doc.save(path)==OK,"temporary picking map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var tcp:=TCPServer.new()
	while tcp.listen(port,"127.0.0.1")!=OK:port+=1
	tcp.stop();check(editor.start_mcp(port).ok,"real HTTP picking server")
	Library._scenes.clear();process_frame.connect(observe)
	await call_tool("open_world",{"path":path});process_frame.disconnect(observe)
	var state:=await call_tool("editor_state")
	check(saw_picking and state.load.phase=="complete" and editor._load_job._thread==null,"HTTP load completes after observed picking phase and worker join")
	check(editor._load_job.state().timings.build.units.picking_faces_prepare.count==1,"large imported mesh expands once off main")
	var body:StaticBody3D=editor._bodies_by_uuid[id][0]
	var shape:ConcavePolygonShape3D=body.get_child(0).shape
	var legacy:=StaticBody3D.new();legacy.position.y=10
	var imported:MeshInstance3D=body.get_meta("visual")
	var legacy_source:Mesh=imported.get_meta("paint_source",imported.mesh)
	var child:=CollisionShape3D.new();child.shape=legacy_source.create_trimesh_shape();legacy.add_child(child);editor.add_child(legacy)
	check(shape.get_faces()==child.shape.get_faces(),"prepared shape exactly matches legacy surface and index order")
	await physics_frame;await physics_frame
	for point in [Vector3(.3,0,.4),Vector3(1.6,0,1.4),Vector3(200.2,0,.4),Vector3(201.6,0,1.4)]:
		var a:=PhysicsRayQueryParameters3D.create(point+Vector3(0,4,0),point-Vector3(0,4,0));a.hit_back_faces=true
		var b:=PhysicsRayQueryParameters3D.create(point+Vector3(0,14,0),point+Vector3(0,6,0));b.hit_back_faces=true
		var hit:=editor.get_world_3d().direct_space_state.intersect_ray(a);var old:=editor.get_world_3d().direct_space_state.intersect_ray(b)
		check(not hit.is_empty() and not old.is_empty() and hit.collider==body and hit.face_index==old.face_index,"exact native ray face index matches legacy")
	legacy.free()
	await call_tool("set_object_transform",{"id":id,"position":[0,2,0]})
	await call_tool("undo");await call_tool("redo")
	check(editor._doc._find(id).position==[0.,2.,0.] and editor._bodies_by_uuid[id][0].get_child(0).shape==shape,"HTTP move undo redo keeps prepared shape and independent body")
	await subtree_checks()
	editor.queue_free();await settle();print("EDITOR_PICKING_LOAD_FAILED=",failed);quit(1 if failed else 0)

func subtree_checks()->void:
	var container:=Node3D.new();editor._view.add_child(container)
	for mode in ["hidden","floor","fort","visible"]:
		var parent:=MeshInstance3D.new();parent.name="parent_"+mode;parent.mesh=BoxMesh.new();container.add_child(parent)
		var child:=MeshInstance3D.new();child.name="child_"+mode;child.mesh=BoxMesh.new();parent.add_child(child)
		if mode=="hidden":parent.hide()
		if mode=="floor":parent.set_meta("editor_floor_excluded",true)
		if mode=="fort":parent.set_meta("ground_batch_record",{"kind":"box","fortification":{}})
	await editor._load_job._add_record_bodies(container,"subtree",Time.get_ticks_usec(),"subtree")
	for mode in ["hidden","floor","fort"]:check(not editor._bodies_by_uuid.has("child_"+mode) and not editor._bodies_by_uuid.has("parent_"+mode),"sliced traversal preserves excluded subtree: "+mode)
	check(editor._bodies_by_uuid.has("parent_visible") and editor._bodies_by_uuid.has("child_visible"),"sliced traversal publishes visible parent and child separately")
