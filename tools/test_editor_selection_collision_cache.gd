extends "res://tools/test_world3d_city_layout.gd"
const Cpu = preload("res://scripts/world3d/ground_cpu_mesh.gd")

func run() -> void:
	Engine.max_fps=60
	directory=Paths.cache_directory("selection_collision_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	var first: String=doc.add_box("block",Vector3(-3,0,0),Vector3.ONE)
	var second: String=doc.add_box("block",Vector3(3,0,0),Vector3.ONE)
	check(doc.save(path)==OK,"temporary selection fixture saved")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=doc; session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); editor._safety.enabled=false; await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real HTTP selection/event server")
	var panel: VBoxContainer=editor._event_panel
	check(not panel.is_visible_in_tree(),"event tab starts hidden")
	var original_children: Array=panel.form.get_children()
	var start:=Time.get_ticks_usec()
	for i in 12:
		editor._selection_tools.ids.assign([first if i%2==0 else second])
		panel.refresh()
	print("HIDDEN_EVENT_REFRESH_12_MS=",(Time.get_ticks_usec()-start)/1000.)
	check(panel.form.get_children()==original_children,"hidden selection changes do not build event controls")
	await call_tool("set_event_template",{"id":second,"template":"dialogue","parameters":{"name":"Latest hidden selection","text":"Hidden MCP update"}})
	check(panel.form.get_children()==original_children,"hidden HTTP event edit does not build event controls")
	var snapshot: Dictionary=doc.recovery_snapshot()
	await atomic_reject("set_event_template",{"id":"missing","parameters":{"text":"No write"}})
	var event_page: Node=panel.get_parent()
	editor._dock_tabs.current_tab=event_page.get_index()
	await settle()
	check(panel.is_visible_in_tree() and panel.form.values().get("text")=="Hidden MCP update","showing event tab displays latest hidden HTTP edit")
	var visible_children: Array=panel.form.get_children()
	panel.refresh()
	check(panel.form.get_children()==visible_children,"unchanged visible selection preserves controls")
	editor._dock_tabs.current_tab=0; await settle()
	await call_tool("undo"); await call_tool("redo")
	check(equivalent(snapshot.records,doc.records),"hidden event undo/redo preserves document")
	editor._dock_tabs.current_tab=event_page.get_index(); await settle()
	check(panel.form.values().get("text")=="Hidden MCP update","show after hidden undo/redo is current")
	await call_tool("save_world")
	await call_tool("open_world",{"path":path})
	check(editor._doc._find(second).event_template.parameters.text=="Hidden MCP update","hidden event survives save/reopen")
	await collision_checks()
	editor.queue_free(); await settle()
	print("EDITOR_SELECTION_COLLISION_FAILED=",failed)
	quit(1 if failed else 0)

func triangle_mesh() -> ArrayMesh:
	var mesh:=ArrayMesh.new()
	# Separated, asymmetrical triangles in two surfaces detect face reordering.
	for x in [0.,3.]:
		var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(x,0,0),Vector3(x+2,0,0),Vector3(x,0,2),Vector3(x+2,0,2)])
		arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,1,3,2])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func add_visual(mesh: Mesh, id: String, offset: Vector3) -> StaticBody3D:
	var visual:=MeshInstance3D.new(); visual.name=id; visual.mesh=mesh; visual.position=offset
	editor._view.add_child(visual); editor._add_bodies(visual)
	return editor._bodies_by_uuid[id][0]

func collision_checks() -> void:
	var mesh:=triangle_mesh()
	var cpu: Mesh=Cpu.capture(mesh)
	var legacy: ConcavePolygonShape3D=cpu.create_trimesh_shape()
	var start:=Time.get_ticks_usec()
	var bodies: Array=[]
	for i in 24: bodies.append(add_visual(mesh,"test_collider_%d"%i,Vector3(i*8,20,0)))
	print("SHARED_COLLIDER_CREATE_24_MS=",(Time.get_ticks_usec()-start)/1000.)
	var shape: ConcavePolygonShape3D=bodies[0].get_child(0).shape
	check(bodies.all(func(body):return body.get_child(0).shape==shape),"same source shares immutable concave shape")
	check(bodies[0]!=bodies[1] and bodies[0].transform!=bodies[1].transform,"each visual retains an independent picking body")
	check(shape.get_faces()==legacy.get_faces(),"direct CPU faces preserve exact legacy triangle ordering")
	var legacy_body:=StaticBody3D.new(); legacy_body.position=Vector3(0,40,0)
	var legacy_child:=CollisionShape3D.new(); legacy_child.shape=legacy; legacy_body.add_child(legacy_child); editor.add_child(legacy_body)
	await physics_frame; await physics_frame
	var state:=editor.get_world_3d().direct_space_state
	for point in [Vector3(.3,0,.4),Vector3(1.6,0,1.4),Vector3(3.2,0,.4),Vector3(4.6,0,1.4)]:
		var a:=PhysicsRayQueryParameters3D.create(point+Vector3(0,24,0),point+Vector3(0,16,0))
		var b:=PhysicsRayQueryParameters3D.create(point+Vector3(0,44,0),point+Vector3(0,36,0))
		var hit: Dictionary=state.intersect_ray(a); var old: Dictionary=state.intersect_ray(b)
		check(not hit.is_empty() and not old.is_empty() and hit.get("face_index")==old.get("face_index") and hit.collider==bodies[0],"ray face index and independent body match legacy")
	var material:=StandardMaterial3D.new(); mesh.surface_set_material(0,material)
	var after_material:=add_visual(mesh,"test_material_changed",Vector3(0,60,0))
	check(after_material.get_child(0).shape!=shape,"mesh changed invalidates cached capture including material changes")
	check(after_material.get_child(0).shape.get_faces()==shape.get_faces(),"material invalidation keeps collision faces unchanged")
	mesh.clear_surfaces()
	var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3(8,0,0),Vector3(0,0,8)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var after_geometry:=add_visual(mesh,"test_geometry_changed",Vector3(0,80,0))
	check(after_geometry.get_child(0).shape.get_faces().size()==3 and shape.get_faces().size()==12,"source geometry mutation creates new shape without altering existing bodies")
	var box:=BoxMesh.new(); box.size=Vector3(2,3,4)
	var box_a:=add_visual(box,"test_box_a",Vector3(0,100,0)); var box_b:=add_visual(box,"test_box_b",Vector3(0,110,0))
	box_a.get_child(0).shape.size=Vector3.ONE
	check(box_a.get_child(0).shape!=box_b.get_child(0).shape and box_b.get_child(0).shape.size==Vector3(2,3,4),"box collider sizes remain independent")
	var painted:=MeshInstance3D.new(); painted.name="test_paint_source"; painted.mesh=triangle_mesh(); painted.position=Vector3(0,120,0)
	painted.set_meta("paint_source",mesh); editor._view.add_child(painted); editor._add_bodies(painted)
	check(editor._bodies_by_uuid.test_paint_source[0].get_child(0).shape.get_faces()==after_geometry.get_child(0).shape.get_faces(),"painted visual uses authored paint_source for picking")
	editor._rebuild()
	check(editor._picking_shapes._entries.is_empty() and editor._bodies_by_uuid.size()==2,"rebuild releases scene cache and removes old picking bodies")
	benchmark_dense_shapes()

func benchmark_dense_shapes() -> void:
	var mesh:=Cpu.new()
	var vertices:=PackedVector3Array()
	for z in 48:
		for x in 48:
			vertices.append_array(PackedVector3Array([Vector3(x,0,z),Vector3(x+1,0,z),Vector3(x,0,z+1),Vector3(x+1,0,z),Vector3(x+1,0,z+1),Vector3(x,0,z+1)]))
	var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices
	mesh.surfaces=[arrays]; mesh.materials=[null]; mesh.bounds=AABB(Vector3.ZERO,Vector3(48,0,48))
	var old: Array=[]; var start:=Time.get_ticks_usec()
	for i in 24: old.append(mesh.create_trimesh_shape())
	var old_us:=Time.get_ticks_usec()-start
	var cache=preload("res://scripts/world_editor/picking_shape_cache.gd").new()
	var shared: Array=[]; start=Time.get_ticks_usec()
	for i in 24: shared.append(cache.shape_for(mesh))
	var new_us:=Time.get_ticks_usec()-start
	print("DENSE_4608_TRIANGLES_24_SHAPES_MS_OLD=",old_us/1000.," NEW=",new_us/1000.)
	check(shared.all(func(shape):return shape==shared[0]) and shared[0].get_faces()==old[0].get_faces(),"dense shape benchmark preserves exact legacy faces")
