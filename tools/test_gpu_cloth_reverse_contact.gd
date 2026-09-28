extends SceneTree
var bytes:=PackedByteArray()
var ready:=false
func _initialize()->void:call_deferred("run")
func receive(value:PackedByteArray)->void:bytes=value;ready=true
func read_gpu(solver:Node)->void:call_deferred("receive",solver._rd.buffer_get_data(solver._positions_buffer))
func collider(y:float)->PackedVector3Array:
 if OS.get_cmdline_user_args().has("--edge-only"):return PackedVector3Array([Vector3(-2,y,0),Vector3(2,y,0),Vector3(2,y,.02)])
 return PackedVector3Array([Vector3(-.03,y,0),Vector3(.03,y,0),Vector3(0,y,.04)])
func run()->void:
 if preload("res://tools/gpu_shader_review_manifest.gd").collect().is_empty():quit(2);return
 var downward:=OS.get_cmdline_user_args().has("--downward")
 var end_height:=.9 if downward else 1.1
 var scene:=Node3D.new();root.add_child(scene)
 var points:=PackedVector3Array([Vector3(-1,1,-1),Vector3(1,1,-1),Vector3(0,1,1)])
 var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
 arrays[Mesh.ARRAY_COLOR]=PackedColorArray([Color.RED,Color.RED,Color.RED]);arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
 if OS.get_cmdline_user_args().has("--flip-winding"):arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,2,1])
 var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 var target:=MeshInstance3D.new();target.mesh=mesh;target.name="Cloth";scene.add_child(target)
 var solver=load("res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd").new()
 solver.target_mesh=NodePath("../Cloth");solver.external_surface_input=true;solver.external_triangle_count=1
 solver.external_reverse_contacts=not OS.get_cmdline_user_args().has("--without-reverse")
 solver.self_contact_mass_balance=OS.get_cmdline_user_args().has("--mass-balance")
 if OS.get_cmdline_user_args().has("--self-contact"):
  solver.self_collide=true;solver.continuous_self_contacts=true;solver.self_edge_contacts=true
  solver.self_contact_iterations=4;solver.self_contact_structural_projection=true
  solver.peer_collider_voxel_resolution=0
 if OS.get_cmdline_user_args().has("--edge-only") and not OS.get_cmdline_user_args().has("--without-edges"):
  solver.external_collision_edges=PackedInt32Array([0,1,1,2,2,0])
 solver.substeps=1;solver.solver_iterations=12;solver.gravity=Vector3.ZERO;solver.max_travel_distance=0;solver.damping=1
 solver.body_collider_thickness=.006;scene.add_child(solver);solver.set_process(false)
 for frame in 4:await process_frame
 assert(solver.set_external_frame(points,collider(1.2 if downward else .8)));assert(solver.warm_start())
 for frame in 3:await process_frame
 assert(solver.set_external_frame(points,collider(end_height)));solver._simulate(1.0/60.0)
 for frame in 3:await process_frame
 RenderingServer.call_on_render_thread(read_gpu.bind(solver))
 while not ready:await process_frame
 var floats:=bytes.to_float32_array();var actual:=PackedVector3Array()
 for i in 3:actual.append(Vector3(floats[i*4],floats[i*4+1],floats[i*4+2]))
 var normal:Vector3=(actual[1]-actual[0]).cross(actual[2]-actual[0])
 var minimum_gap:=INF
 var probes:=PackedVector3Array([Vector3(0,end_height,.01)]) if OS.get_cmdline_user_args().has("--edge-only") else collider(end_height)
 for point:Vector3 in probes:
  var plane_y:float=actual[0].y-(normal.x*(point.x-actual[0].x)+normal.z*(point.z-actual[0].z))/normal.y
  minimum_gap=minf(minimum_gap,(point.y-plane_y) if downward else (plane_y-point.y))
 print("REVERSE FACE minimum vertical clearance=",minimum_gap)
 scene.free()
 for frame in 4:await process_frame
 if minimum_gap<.003:push_error("Collider crossed the interior of the cloth face");quit(2)
 else:print("PASS reverse face interior contact");quit()
