extends SceneTree
const Index=preload("res://scripts/world3d/navigation_surface_index.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	create_timer(30).timeout.connect(func():quit(2))
	var mesh:=NavigationMesh.new()
	# Non-planar polygon: the engine uses a triangle fan, not one fitted plane.
	mesh.set_vertices(PackedVector3Array([Vector3(-10,0,-10),Vector3(10,1,-10),Vector3(10,3,10),Vector3(-10,0,10),Vector3(-8,6,-8),Vector3(-8,6,8),Vector3(8,6,8),Vector3(8,6,-8)]))
	mesh.add_polygon(PackedInt32Array([0,1,2,3]));mesh.add_polygon(PackedInt32Array([4,5,6,7]))
	var vertices:=mesh.get_vertices();vertices.append_array(PackedVector3Array([Vector3(14,0,-5),Vector3(22,2,-5),Vector3(14,0,5)]))
	mesh.set_vertices(vertices);mesh.add_polygon(PackedInt32Array([8,9,10]))
	var map:=NavigationServer3D.map_create();NavigationServer3D.map_set_active(map,true)
	var region:=NavigationServer3D.region_create();NavigationServer3D.region_set_use_async_iterations(region,false)
	NavigationServer3D.region_set_map(region,map);NavigationServer3D.region_set_navigation_mesh(region,mesh)
	while NavigationServer3D.map_get_iteration_id(map)==0 or NavigationServer3D.region_get_iteration_id(region)==0:await physics_frame
	# An initially empty map iteration can precede asynchronous map publication.
	while NavigationServer3D.map_get_closest_point(map,Vector3(0,6,0)).distance_to(Vector3(0,6,0))>.01:await physics_frame
	var index:=Index.build(mesh);var rng:=RandomNumberGenerator.new();rng.seed=712983
	var accepted:=0;var failures:=0
	for i in 6000:
		var point:=Vector3(rng.randf_range(-12,24),rng.randf_range(-.5,6.5),rng.randf_range(-12,12))
		var horizontal:=rng.randf_range(.05,.65);var vertical:=rng.randf_range(.05,.8)
		var support:Vector3=index.support(point,minf(horizontal,vertical))
		if not support.is_finite():continue
		accepted+=1
		var nearest:=NavigationServer3D.map_get_closest_point(map,point)
		if Vector2(nearest.x-point.x,nearest.z-point.z).length()>horizontal or absf(nearest.y-point.y)>vertical:
			failures+=1;print("FAIL false support ",point," ",support," ",nearest)
	if accepted<100:failures+=1
	if index.support(Vector3(0,4.5,0),.2).is_finite():failures+=1
	if index.support(Vector3(12,0,0),.2).is_finite():failures+=1
	if index.support(Vector3(-7,.5,4),.2).is_finite():failures+=1
	if not index.support(Vector3(16,.55,0),.2).is_finite():failures+=1
	# An edge on x=16 lies in the neighbouring cell for x=15.9; include a
	# negative-coordinate corner and stacked floor separation as well.
	var edge_mesh:=NavigationMesh.new()
	edge_mesh.set_vertices(PackedVector3Array([Vector3(16,0,0),Vector3(20,0,0),Vector3(16,0,4),Vector3(-20,3,-20),Vector3(-16,3,-20),Vector3(-16,3,-16)]))
	edge_mesh.add_polygon(PackedInt32Array([0,1,2]));edge_mesh.add_polygon(PackedInt32Array([3,4,5]))
	var edge_index:=Index.build(edge_mesh)
	for point:Vector3 in [Vector3(15.9,.05,1),Vector3(15.9,.05,-.1),Vector3(-15.9,3.05,-15.9)]:
		if not edge_index.support(point,.2).is_finite():failures+=1;print("FAIL missing edge/corner certificate ",point)
	for point:Vector3 in [Vector3(15.81,.19,-.19),Vector3(16,1,1),Vector3(-15.9,0,-15.9)]:
		if edge_index.support(point,.2).is_finite():failures+=1;print("FAIL invalid sphere/floor certificate ",point)
	for radius:float in [NAN,INF,0.,-1.]:
		if edge_index.support(Vector3(16,0,1),radius).is_finite():failures+=1
	NavigationServer3D.free_rid(region);NavigationServer3D.free_rid(map)
	print("NAVIGATION_SURFACE_INDEX samples=6000 accepted=",accepted," false_positives=",failures)
	quit(1 if failures else 0)
