extends SceneTree
## Run in an isolated generated project; never switch the game's physics backend.
## Capability probe, not real garment acceptance. Rigid and free-fall controls
## distinguish absent self/peer response from a solver that never advanced.
var rows:Array=[]
func _initialize()->void:call_deferred("run")
func patch(y:float,size:float)->Dictionary:
	var points:=PackedVector3Array();var indices:=PackedInt32Array()
	for z in 5:
		for x in 5:points.append(Vector3((float(x)/4-.5)*size,y,(float(z)/4-.5)*size))
	for z in 4:
		for x in 4:
			var a:=z*5+x;indices.append_array(PackedInt32Array([a,a+5,a+1,a+1,a+5,a+6]))
	return {"points":points,"indices":indices}
func soft(world:Node3D,points:PackedVector3Array,indices:PackedInt32Array,pins:int)->SoftBody3D:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_INDEX]=indices
	var normals:=PackedVector3Array();normals.resize(points.size());normals.fill(Vector3.UP);arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var body:=SoftBody3D.new();body.mesh=mesh;body.simulation_precision=16;body.linear_stiffness=.8;body.pressure_coefficient=0
	world.add_child(body)
	for i in pins:body.set_point_pinned(i,true)
	return body
func run()->void:
	print("BUILTIN backend=",ProjectSettings.get_setting("physics/3d/physics_engine")," server=",PhysicsServer3D.get_class()," engine=",Engine.get_version_info())
	for mode in ["free_fall","rigid","self","peer"]:
		var world:=Node3D.new();root.add_child(world)
		var lower:=patch(1.0,2.0);var upper:=patch(1.15,.6)
		var offset:=0;var fixed:SoftBody3D;var falling:SoftBody3D
		if mode=="self":
			var points:PackedVector3Array=lower.points.duplicate();points.append_array(upper.points)
			var indices:PackedInt32Array=lower.indices.duplicate()
			for index:int in upper.indices:indices.append(index+25)
			falling=soft(world,points,indices,25);fixed=falling;offset=25
		else:
			falling=soft(world,upper.points,upper.indices,0)
			if mode=="peer":fixed=soft(world,lower.points,lower.indices,25)
			if mode=="rigid":
				var obstacle:=StaticBody3D.new();var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(4,.1,4)
				shape.shape=box;obstacle.add_child(shape);obstacle.position.y=.95;world.add_child(obstacle)
		var minimum:=INF;var final_minimum:=INF;var pin_error:=0.0;var finite:=true
		var trace:Array=[]
		for frame in 90:
			await physics_frame
			# Query after the physics step has flushed its results.
			await process_frame
			final_minimum=INF
			for i in 25:
				var point:=falling.get_point_transform(i+offset)
				finite=finite and point.is_finite();final_minimum=minf(final_minimum,point.y)
				if fixed:pin_error=maxf(pin_error,fixed.get_point_transform(i).distance_to(lower.points[i]))
			minimum=minf(minimum,final_minimum)
			if frame%10==0:trace.append({"frame":frame,"minimum_y":final_minimum})
		var passed:bool=finite and pin_error<.00001 and (final_minimum<.7 if mode=="free_fall" else minimum>=.997)
		var row:Dictionary={"mode":mode,"supported_in_probe":passed,"minimum_y":minimum,"final_minimum_y":final_minimum,"pin_error":pin_error,"finite":finite,"trace":trace}
		rows.append(row);print(JSON.stringify(row))
		world.free()
		for frame in 2:await physics_frame
	var file:=FileAccess.open("res://probe_result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"backend":ProjectSettings.get_setting("physics/3d/physics_engine"),"server":PhysicsServer3D.get_class(),"version":Engine.get_version_info(),"cases":rows},"\t"));file.close()
	quit(0 if rows[0].supported_in_probe and rows[1].supported_in_probe else 2)
