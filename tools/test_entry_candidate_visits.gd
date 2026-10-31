extends SceneTree
## The spatial directory is conservative: rejected candidates may be present
## in many cells. Each synchronous query must inspect each identity only once.
const Stream=preload("res://scripts/world3d/world_stream.gd")
class CountedMesh extends "res://scripts/world3d/ground_cpu_mesh.gd":
	var queries:=0
	func _get_aabb()->AABB:
		queries+=1
		return bounds
var checks:=0
var failures:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func run()->void:
	var map_root:=Node3D.new()
	var mesh:=CountedMesh.new();mesh.bounds=AABB(-Vector3.ONE,Vector3.ONE*2)
	var by_id:Dictionary={};var index:Dictionary={}
	var identifiers:Array=[]
	for i in 64:
		var id:="far_%d"%i;identifiers.append(id)
		by_id[id]={"uuid":id,"mesh":mesh,"transform":Transform3D(Basis.IDENTITY,Vector3(200+i,0,200)),"extras":{}}
	by_id.near={"uuid":"near","mesh":mesh,"transform":Transform3D(Basis.IDENTITY,Vector3(20,0,20)),"extras":{}}
	identifiers.insert(16,"near")
	for z in 3:
		for x in 3:index[Vector2i(x,z)]=identifiers.duplicate()
	map_root.set_meta("stream_index",index);map_root.set_meta("stream_by_id",by_id)
	var clip:=AABB(Vector3(0,-10,0),Vector3(64,20,64))
	var times:Array=[]
	for i in 32:
		var begin:=Time.get_ticks_usec();var selected:Array=Stream._entry_candidates(map_root,clip);times.append(Time.get_ticks_usec()-begin)
		check(selected.size()==1 and selected[0].uuid=="near","conservative cells preserve exact live geometry selection "+str(i))
	var observed:=mesh.queries
	if not "--baseline" in OS.get_cmdline_user_args():check(observed==65*32,"rejected and selected identities each read mesh bounds once per query")
	by_id.far_0.transform.origin=Vector3(30,0,30)
	var moved:Array=Stream._entry_candidates(map_root,clip)
	check(moved.size()==2 and moved[0].uuid=="far_0" and moved[1].uuid=="near","next query observes moved geometry and original first-encounter order")
	var collision:=CountedMesh.new();collision.bounds=AABB(Vector3(-220,-1,-201),Vector3(80,2,80))
	by_id.far_1.collision_mesh=collision
	var supported:Array=Stream._entry_candidates(map_root,clip)
	check(supported.size()==3 and supported[1].uuid=="far_1","collision-only overlap still includes an otherwise distant visual")
	by_id.far_0.transform.origin=Vector3(200,0,200);by_id.far_1.erase("collision_mesh")
	check(Stream._entry_candidates(map_root,clip).size()==1,"moving and removing support take effect on the next synchronous query")
	map_root.free()
	var report:Dictionary={"checks":checks,"failures":failures,"identities":65,"cells":9,"queries":32,"mesh_bounds_reads":observed,"times_us":times}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ENTRY_CANDIDATE_VISITS ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
