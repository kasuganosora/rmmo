extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func release_mesh(surfaces:Array,faces:PackedVector3Array,key:String)->void:
	var mesh:=Cpu.new();mesh.surfaces=surfaces;mesh._collision_faces=faces
	if not key.is_empty():mesh.set_geometry_key(key)
func run()->void:
	# Retain coverage of the diagnostic/fallback threshold path independently.
	Retirement.batched_geometry_release_enabled=false
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK])
	var surfaces:Array=[arrays];var before:=var_to_bytes(surfaces)
	var key:=Cpu.geometry_signature(surfaces)
	var cache:RefCounted=Retirement._geometry_sizes;var scans:int=cache.scans;var hits:int=cache.hits
	release_mesh(surfaces,PackedVector3Array(),key)
	check(cache.scans==scans+1,"first final CPU owner scans geometry once")
	var faces:=PackedVector3Array();faces.resize(750000)
	release_mesh(surfaces,faces,key)
	check(cache.hits==hits+1,"another final owner reuses the exact immutable geometry size")
	var service:Node=root.get_node_or_null("ResourceRetirement")
	check(service!=null and service.pending.size()==1,"lazy collision faces retain their own size and trigger background release")
	if service!=null:
		check(service.pending[0].logical_bytes==(faces.size()+3)*(24 if OS.has_feature("double") else 12),"queued logical bytes include this owner's current collision soup")
	var deadline:=Time.get_ticks_msec()+10000
	while service!=null and not service.pending.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(service!=null and service.pending.is_empty() and service.known.is_empty(),"background retirement joins and releases all ticket owners")
	check(var_to_bytes(surfaces)==before and faces.size()==750000,"borrowers' arrays remain intact")
	scans=cache.scans;release_mesh(surfaces,PackedVector3Array(),"")
	check(cache.scans==scans+1,"unkeyed mutable/diagnostic mesh is measured each time")
	Retirement.geometry_size_reuse_enabled=false;scans=cache.scans
	release_mesh(surfaces,PackedVector3Array(),key)
	check(cache.scans==scans+1,"diagnostic control uses original per-owner size scan")
	print("GEOMETRY_SIZE_RETIREMENT failures=",failures);quit(1 if failures else 0)
