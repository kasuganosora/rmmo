extends RefCounted
## Main owns the private library until this CPU job finishes. The exact map
## byte observation still runs synchronously on main immediately before publish.
const Index=preload("res://scripts/world3d/stream_index.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
static func prepare(library:Array,dependencies:Dictionary,path:String,content_root:String,worker_limit:int,trusted_package:bool=false)->Dictionary:
	var index_started:=Time.get_ticks_usec()
	var index:Dictionary=Index.build(library)
	var index_elapsed:=Time.get_ticks_usec()-index_started
	var started:=Time.get_ticks_usec()
	var valid:bool=trusted_package or Store.verify_dependencies(dependencies,path,content_root,worker_limit)
	var elapsed:=Time.get_ticks_usec()-started
	Trace.elapsed("game.final_reference_dependencies",started,{"resources":0 if trusted_package else dependencies.size(),"trusted_package":trusted_package})
	return {"index":index,"dependencies_valid":valid,"dependency_us":elapsed,"index_us":index_elapsed}
