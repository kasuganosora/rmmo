extends SceneTree
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	check(Prefab._meshes.is_empty() and Prefab._render_meshes.is_empty(),"isolated CPU cache fixture starts without author resources")
	var a:="a".repeat(64);var b:="b".repeat(64);var c:="c".repeat(64)
	var shared:Mesh=Cpu.new();var other:Mesh=Cpu.new();var orphan:Mesh=Cpu.new()
	var shared_watch:WeakRef=weakref(shared);var other_watch:WeakRef=weakref(other);var orphan_watch:WeakRef=weakref(orphan)
	Prefab._meshes[a]={"mesh":shared,"source":shared}
	Prefab._meshes[a+":paint:variant"]={"mesh":shared,"source":shared}
	Prefab._meshes[b]={"mesh":shared,"source":shared}
	Prefab._meshes[c]={"mesh":other,"source":other}
	Prefab._render_meshes={"same-content":shared,"other-content":other,"orphan":orphan}
	shared=null;other=null;orphan=null
	Prefab.evict_geometry({a:true})
	check(not Prefab._meshes.has(a) and not Prefab._meshes.has(a+":paint:variant") and Prefab._meshes.has(b),"retirement removes only the selected prefab definition and its paint variants")
	check(Prefab._render_meshes.has("same-content") and Prefab._render_meshes["same-content"]==shared_watch.get_ref(),"another live prefab keeps its shared render-cache identity for future reuse")
	check(not Prefab._render_meshes.has("orphan") and orphan_watch.get_ref()==null,"independently orphaned render owners still release")
	Prefab.evict_geometry({b:true})
	check(shared_watch.get_ref()==null and Prefab._render_meshes.size()==1,"the final prefab alias releases shared geometry without retaining a render orphan")
	check(Prefab._meshes.has(c) and other_watch.get_ref()!=null,"unrelated live geometry survives both retirements")
	Prefab.evict_geometry({c:true})
	check(Prefab._meshes.is_empty() and Prefab._render_meshes.is_empty() and other_watch.get_ref()==null,"all final CPU geometry owners release")
	print("PREFAB_CACHE_ALIAS_LIFETIME checks=",checks," failures=",failures);quit(1 if failures else 0)
