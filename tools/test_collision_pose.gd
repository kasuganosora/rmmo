extends SceneTree
## Pure CPU pose parity against the actual engine setter used by WorldDocument.
const Prepare=preload("res://scripts/world3d/collision_instance_preparation.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
var failed:=0
var checked:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checked+=1
	if not value:failed+=1
	print("PASS " if value else "FAIL ",label)
func engine_pose(record:Dictionary)->Transform3D:
	var holder:=Node3D.new();holder.position=Index._vec(record.position)
	holder.rotation_degrees=Index._vec(record.rotation);holder.scale=Index._vec(record.size)
	var result:=holder.transform;holder.free();return result
func run()->void:
	# Exact authored values from the failing town's bridge_grass_0001.
	var town:Dictionary={"position":[303.5948,.162508,146.8144],"rotation":[0,-145.475509643555,0],"size":[1.01459228992462,1.01459228992462,1.01459228992462]}
	var old:=Transform3D(Basis.from_euler(Index._vec(town.rotation)*PI/180.0).scaled_local(Index._vec(town.size)),Index._vec(town.position))
	check(old!=engine_pose(town),"original two-rounding conversion deterministically differs at the real town pose")
	check(Prepare.record_pose(town)==engine_pose(town),"canonical conversion matches actual engine setter bit for bit")
	var random:=RandomNumberGenerator.new();random.seed=20261011
	var exact:=true
	for at:int in 256:
		var record:Dictionary={"position":[random.randf_range(-1000,1000),random.randf_range(-50,50),random.randf_range(-1000,1000)],"rotation":[random.randf_range(-360,360),random.randf_range(-360,360),random.randf_range(-360,360)],"size":[random.randf_range(.01,5),random.randf_range(.01,5),random.randf_range(.01,5)]}
		exact=exact and Prepare.record_pose(record)==engine_pose(record)
	check(exact,"all-axis rotation and nonuniform scale match 256 actual Node3D setters exactly")
	var moved:Dictionary=town.duplicate(true);moved.position[0]+=.0001
	check(Prepare.record_pose(moved)!=Prepare.record_pose(town),"real submillimetre authored movement remains distinct without any tolerance")
	var turned:Dictionary=town.duplicate(true);turned.rotation[1]+=.0001
	check(Prepare.record_pose(turned)!=Prepare.record_pose(town),"real small authored rotation remains distinct without any tolerance")
	print("COLLISION_POSE checks=",checked," failures=",failed)
	quit(1 if failed else 0)
