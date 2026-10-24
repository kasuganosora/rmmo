extends SceneTree
const House=preload("res://scripts/world3d/house_prefab.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func entry(materials:Array[Material])->Dictionary:
	var mesh:=Cpu.new();mesh.materials=materials
	return {"mesh":mesh,"source":mesh}
func publish(key:String,value:Dictionary,geometry:String="geometry")->void:
	House._cache_geometry(key,value,[geometry],{"meshes":[{}],"entries":[["fixture",[0,0]]]})
func _initialize()->void:
	House.material_owner_reuse_enabled=not "--legacy" in OS.get_cmdline_user_args()
	var plain:=StandardMaterial3D.new();plain.albedo_color=Color(.3,.4,.5)
	var mats:Array[Material]=[plain,plain,plain,plain]
	var first:=entry(mats);publish("first",first)
	var timings:Array=[]
	for trial:int in 4:
		var began:=Time.get_ticks_usec();var same:=true
		for i:int in 1000:
			var current:=entry(mats);publish("repeat_%d"%i,current);same=same and is_same(current.mesh,first.mesh)
		timings.append(Time.get_ticks_usec()-began);check(same,"repeated immutable material owners share the exact CPU mesh")
	var blue:=StandardMaterial3D.new();blue.albedo_color=Color.BLUE
	var different:=entry([blue,plain,plain,plain]);publish("different",different)
	check(not is_same(different.mesh,first.mesh),"different live material does not alias the old mesh")
	var clone:Material=plain.duplicate();var equivalent:=entry([clone,clone,clone,clone]);publish("equivalent",equivalent)
	check(is_same(equivalent.mesh,first.mesh),"different owners with equal material values still use canonical content sharing")
	var geometry:=entry(mats);publish("geometry_change",geometry,"changed")
	check(not is_same(geometry.mesh,first.mesh),"material owner reuse never aliases changed geometry")
	House._meshes.clear();House._render_meshes.clear()
	var next:=entry(mats);publish("new_scope",next)
	check(not is_same(next.mesh,first.mesh),"cache clearing cannot resurrect a mesh retained by an older scope")
	var weak:WeakRef=weakref(next.mesh);House._meshes.clear();House._render_meshes.clear();next.clear()
	check(weak.get_ref()==null,"owner lookup retains no mesh after authoritative caches release it")
	print("PREFAB_MATERIAL_OWNERS ",JSON.stringify({"trials_us":timings,"scans":House.material_identity_scans,"reuses":House.material_identity_reuses,"failures":failures}));quit(1 if failures else 0)
