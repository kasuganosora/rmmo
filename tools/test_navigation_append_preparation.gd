extends SceneTree
const Nav=preload("res://scripts/world3d/world_navigation.gd")
const CANDIDATE:="res://scripts/world3d/world_navigation.gd"
const CONTROL:="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/world_navigation_before_append_bounds.gd"
var failures:=0
class CountedMesh extends Mesh:
	var reads:=0
	func _get_aabb()->AABB:reads+=1;return AABB(Vector3.ZERO,Vector3.ONE)
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func fixture(script:Script)->Node:
	var nav:Node=script.new();root.add_child(nav);nav.set_process(false);nav.set_physics_process(false)
	nav.streaming_geometry=true;nav.map=NavigationServer3D.map_create();return nav
func row(id:String,mesh:Mesh,extra:Dictionary={})->Dictionary:
	return {"uuid":id,"mesh":mesh,"transform":Transform3D(Basis.IDENTITY,Vector3(id.length(),1,3)),"extras":extra}
func snapshot(nav:Node)->Dictionary:
	return {"specs":nav._specs.duplicate(),"ids":nav._spec_ids.duplicate(),"doors":nav._doors.duplicate(),"bounds":nav._bounds,"has_bounds":nav._has_bounds,"geometry":nav._spec_geometry.duplicate(),"users":nav._geometry_users.duplicate(),"faces":nav._faces.duplicate(),"profile":nav.loading_profile.duplicate(true)}
func run()->void:
	var candidate:Script=load(CANDIDATE)
	var control:Script=load(CONTROL) if FileAccess.file_exists(CONTROL) else Nav
	var mesh:=CountedMesh.new();var shared:=BoxMesh.new()
	var rows:Array=[row("solid",mesh),row("none",mesh,{"rmmo_collision":"none"}),row("door",mesh,{"fixture":{"kind":"door"}}),row("hostile",mesh,{"hostile":true}),row("ally",mesh,{"ally":true}),row("shared",shared)]
	rows[5].collision_mesh=mesh
	var old:=fixture(control);var improved:=fixture(candidate)
	mesh.reads=0;var before:Dictionary=old.append_specs(rows);var old_reads:=mesh.reads
	mesh.reads=0;var after:Dictionary=improved.append_specs(rows);var new_reads:=mesh.reads
	check(before==after and snapshot(old)==snapshot(improved),"bulk publication preserves source order, doors, bounds and exact geometry-user accounting")
	check(new_reads==5 and (not FileAccess.file_exists(CONTROL) or new_reads<old_reads),"validated bounds are read once per mesh-bearing source instead of again during commit")
	check(improved._specs.size()==6 and improved._doors.size()==1 and improved._geometry_users=={mesh.get_instance_id():6} and improved._bounds==AABB(Vector3(5,.5,2.5),Vector3(1.5,1.5,1.5)),"mixed collision roles keep exactly one door, six geometry users and the expected solid bounds")
	for additions:Array in [[row("new",mesh),rows[0]],[row("new",mesh),{"uuid":"bad"}]]:
		var old_state:=snapshot(old);var new_state:=snapshot(improved)
		check(old.append_specs(additions)==improved.append_specs(additions) and snapshot(old)==old_state and snapshot(improved)==new_state,"late invalid/duplicate rows fail before modifying any source, bounds or geometry users")
	old.free();improved.free()
	improved=fixture(candidate)
	for field:String in ["shape","collision_mesh"]:
		var invalid:=row("bad_"+field,mesh);invalid[field]=17
		var unchanged:=snapshot(improved)
		var result:Dictionary=improved.append_specs([row("prefix",mesh),invalid])
		check(not result.ok and result.reason=="invalid_spec" and snapshot(improved)==unchanged,"malformed "+field+" is rejected atomically before source geometry bookkeeping")
	improved.free()
	print("NAVIGATION_APPEND_PREPARATION bounds_reads=",old_reads,"->",new_reads," failures=",failures);quit(1 if failures else 0)
