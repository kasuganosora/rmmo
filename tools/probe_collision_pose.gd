extends SceneTree
## Read-only CPU comparison of authored instance poses against Node3D setters.
const Prepare=preload("res://scripts/world3d/collision_instance_preparation.gd")
func _initialize()->void:run.call_deferred()
static func vector(value:Array)->Vector3:return Vector3(value[0],value[1],value[2])
static func error(a:Transform3D,b:Transform3D)->float:
	var result:=a.origin.distance_to(b.origin)
	for at:int in 3:
		for axis:int in 3:result=maxf(result,absf(a.basis[at][axis]-b.basis[at][axis]))
	return result
func run()->void:
	var path:="D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf"
	if not OS.get_cmdline_user_args().is_empty():path=OS.get_cmdline_user_args()[0]
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var current_differences:=0;var scalar_differences:=0;var combined_differences:=0;var max_error:=0.;var samples:=0
	for record:Dictionary in data.nodes[0].extras.rmmo_records:
		var holder:=Node3D.new();holder.position=vector(record.position);holder.rotation_degrees=vector(record.rotation);holder.scale=vector(record.size)
		var current:=Transform3D(Basis.from_euler(vector(record.rotation)*PI/180.0).scaled_local(vector(record.size)),vector(record.position))
		var degrees:=vector(record.rotation)
		var scalar:=Transform3D(Basis.from_euler(Vector3(deg_to_rad(degrees.x),deg_to_rad(degrees.y),deg_to_rad(degrees.z))).scaled_local(vector(record.size)),vector(record.position))
		var combined:=Prepare.record_pose(record)
		if current!=holder.transform:
			current_differences+=1;max_error=maxf(max_error,error(current,holder.transform))
			if samples<8 and holder.position.distance_to(Vector3(321.2,.9,160.3))<60:
				print(JSON.stringify({"uuid":record.uuid,"rotation":record.rotation,"size":record.size,"max_basis_error":error(current,holder.transform),"scalar_error":error(scalar,holder.transform),"combined_error":error(combined,holder.transform),"actual_rotation":holder.rotation,"scalar_rotation":Vector3(deg_to_rad(degrees.x),deg_to_rad(degrees.y),deg_to_rad(degrees.z)),"actual":holder.transform,"current":current}));samples+=1
		if scalar!=holder.transform:scalar_differences+=1
		if combined!=holder.transform:combined_differences+=1
		holder.free()
	print(JSON.stringify({"record_count":data.nodes[0].extras.rmmo_records.size(),"current_differences":current_differences,"scalar_differences":scalar_differences,"combined_differences":combined_differences,"max_basis_error":max_error}))
	quit(0 if combined_differences==0 else 1)
