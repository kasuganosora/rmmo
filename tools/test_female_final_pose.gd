extends SceneTree
const Body=preload("res://scripts/char/female_axis_body.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
class PoseModifier extends SkeletonModifier3D:
	var rotations:Dictionary={}
	func _process_modification_with_delta(_delta:float)->void:
		var sk:=get_skeleton()
		for index:int in rotations:sk.set_bone_pose_rotation(index,rotations[index])

func _initialize()->void:call_deferred("run")
func max_error(a:PackedVector3Array,b:PackedVector3Array)->float:
	var error:=0.0
	assert(a.size()==b.size())
	for i in a.size():error=maxf(error,a[i].distance_to(b[i]))
	return error
func run()->void:
	# Axis skinning must not switch to a different Euler branch at 90/180 degrees.
	for order in 6:
		var previous:=Vector3.ZERO
		for degrees in range(0,201,5):
			var expected:=Vector3(.1,.2,.3)
			expected["XYZ".find(Body.ORDERS[order][1])]=deg_to_rad(degrees)
			var rotation:=Body.ordered_basis(expected,Body.ORDERS[order])
			var actual:=Body.continuous_angles(rotation,order,previous)
			# This sweep keeps the outer angles fixed even through gimbal lock.
			assert(Body.ordered_basis(actual,Body.ORDERS[order]).is_equal_approx(rotation))
			assert(actual.distance_to(expected)<.0001)
			previous=actual
	var body:=Body.new();root.add_child(body);body.initialize()
	assert(body.enable_compute())
	var mixed:Dictionary={"rShldr":Vector3(12,8,-65),"rForeArm":Vector3(20,-65,10),"chest":Vector3(10,15,-7),"head":Vector3(12,-20,8),"lThigh":Vector3(-45,8,3)}
	body.use_compute=false;body.set_angles(mixed)
	var reference:=body.posed_points.duplicate()
	var modifier:=PoseModifier.new()
	for node:Dictionary in body.nodes:
		var index:int=node.skeleton_index
		modifier.rotations[index]=body.skeleton.get_bone_pose_rotation(index)
	var hand_index:=body.skeleton.find_bone("rHand")
	var hand_reference:=body.get_solved_bone_pose(hand_index)
	body.use_compute=true;body.set_angles({})
	var rest_points:=body.posed_points.duplicate()
	assert(max_error(rest_points,reference)>.05,"Fixture must visibly change the body")
	var attachment:=BoneAttachment3D.new();attachment.bone_name="rHand";body.skeleton.add_child(attachment)
	body.skeleton.add_child(modifier)
	for frame in 4:await process_frame
	var error:=max_error(body.posed_points,reference)
	assert(error<.00001,"Final modifier rotation must deform full AND partial axis weights")
	assert(body.get_solved_bone_pose(hand_index).is_equal_approx(hand_reference))
	assert(attachment.transform.is_equal_approx(hand_reference),"Attachment and body must use the same final pose")
	assert(body.angles_by_name.is_empty(),"Modifier must not rewrite requested input pose")
	# Cloth must read the saved final joints after Godot restores animation input.
	assert(body.get_solved_bone_pose(hand_index).is_equal_approx(hand_reference))
	modifier.active=false
	for frame in 4:await process_frame
	assert(max_error(body.posed_points,rest_points)<.00001,"Disabling modifier must restore body")
	# Animation-like direct bone writes (without set_angles) must also update.
	var idx:=body.skeleton.find_bone("rForeArm")
	body.skeleton.set_bone_pose_rotation(idx,modifier.rotations[idx])
	for frame in 3:await process_frame
	assert(max_error(body.posed_points,rest_points)>.01)
	var before:=body.posed_points.duplicate()
	body.skeleton.set_bone_pose_scale(idx,Vector3(1.1,1,1))
	assert(not body.sync_final_pose() and not body.pose_sync_error.is_empty())
	assert(max_error(body.posed_points,before)==0,"Unsupported transforms must fail atomically")
	body.set_angles({})
	assert(body.pose_sync_error.is_empty())
	var output:=FileAccess.open(Art.review_path("character_3d/final_pose_sync_report.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed":true,"modifier_cpu_gpu_max_error_m":error,"attachment_matches":true,"input_unchanged":true,"reset_and_direct_write":true,"unsupported_scale_atomic":true},"\t"));output.close()
	body.free();print("PASS final modifier / direct skeleton / CPU-GPU / attachment / reset / scale rejection");quit()
