extends "res://tools/test_stream_index_retire.gd"
const Stream=preload("res://scripts/world3d/world_stream.gd")
class Host:
	extends Node3D
	var _navigation:Node
class Queue:
	extends Node
	var _active:=true
	var pending:Array=[]
	var _demands:Dictionary={}
	var _prepared_paths:Dictionary={}
	var _jobs:Dictionary={}
	var runtime_fixture_states:Dictionary={}
	var _doc:=preload("res://scripts/world3d/world_document.gd").new()
	func requeue_reference(entry:Dictionary)->bool:
		pending.append({"record":entry.compact_record});return true
	func requeue_references(entries:Array)->int:
		for entry:Dictionary in entries:requeue_reference(entry)
		return entries.size()
	static func _intersects(a:AABB,b:AABB)->bool:
		return a.position.x<=b.end.x and a.end.x>=b.position.x and a.position.z<=b.end.z and a.end.z>=b.position.z
func run()->void:
	var host:=Host.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map)
	var queue:=Queue.new();map.add_child(queue)
	queue._doc.load_box_meshes={};queue._doc.load_material_pool={};queue._doc.load_surface_arrays={}
	var service:=preload("res://scripts/world3d/native_residency.gd").new()
	service._host=host;service._map=map;service._queue=queue;service.grace_msec=10
	map.add_child(service);service.set_process(false)
	var library:Array=[]
	for i:int in 32:
		var ids:Array=[]
		for part:int in (8 if i==15 else 1):
			var id:="unit%d_part%d"%[i,part];ids.append(id)
			library.append(spec(id,Vector2i(100,0),Vector2i(100,0),{"kind":"box"}))
		service._units[str(i)]={"entries":[{"compact_record":{"uuid":str(i)},"asset_path":""}],"bounds":AABB(Vector3(3200,0,0),Vector3.ONE),"kind":"all"}
		service._resident[str(i)]={"ids":ids,"outside_since":0 if i<15 else -1}
	map.set_meta("stream_library",library)
	var index:Dictionary=Index.build(library)
	for key:String in index:map.set_meta(key,index[key])
	map.set_meta("stream_chunk",Vector2i.ZERO)
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new();host.add_child(nav);host._navigation=nav
	nav.configure_streaming_geometry(func(_clip:AABB):return {"ok":true,"error":""})
	nav.map=NavigationServer3D.map_create();nav.ready_for_queries=true;nav.set_process(false)
	check(nav.append_specs(library).ok,"real navigation owns all independent far units before scheduling")
	var arrays:Array=[PackedVector3Array([Vector3.ONE])]
	var context:Dictionary={"normals":{"prepared":true}}
	queue._doc.load_surface_arrays={"0":[],"preparing":arrays}
	queue._doc.terrain_neighbors.data={"0":{},"preparing":context}
	var held_value:Dictionary={"values":{"roughness":.75}}
	var unused_value:Dictionary={"values":{"roughness":.25}}
	var held:Material=StandardMaterial3D.new();var unused:Material=StandardMaterial3D.new()
	var held_watch:WeakRef=weakref(held);var unused_watch:WeakRef=weakref(unused)
	queue._doc.load_material_pool[[held_value]]=held;queue._doc.load_material_pool[[unused_value]]=unused
	held=null;unused=null
	queue._jobs={"preparing":{"result":{"prefab_cpu":{"prepared":{"data":{"materials":[held_value]}}}}}}
	service.poll(100)
	check(queue._doc.load_surface_arrays.has("preparing") and is_same(queue._doc.load_surface_arrays.preparing,arrays) and not queue._doc.load_surface_arrays.has("0"),"unloading one unit preserves another admitted job's exact prepared arrays")
	check(queue._doc.terrain_neighbors.data.has("preparing") and is_same(queue._doc.terrain_neighbors.data.preparing,context) and not queue._doc.terrain_neighbors.data.has("0"),"unloading one unit preserves unrelated prepared terrain seams")
	check(held_watch.get_ref()!=null and unused_watch.get_ref()==null,"retirement releases unused hot materials while retaining admitted material preparation")
	check(not service._resident.has("0") and service._resident["15"].outside_since==100,"successful small retirement still observes the end of the same bounded slice")
	service.poll(120)
	service.poll(140)
	check(not service._resident.has("15"),"large cold unit retires after its grace instead of waiting for all earlier small units")
	check(service.profile.scanned_units==48,"successful retirement never truncates bounded observation accounting")
	check(not nav._spec_ids.has("unit15_part7") and not map.get_meta("stream_by_id").has("unit15_part7"),"priority keeps the actual atomic navigation and index retirement transaction")
	var protected_id:="20";var before:int=service.profile.retired_units
	queue._demands={"source":{"clip":service._units[protected_id].bounds,"kind":"all"}}
	for i:int in 8:service.poll(1000+i*100)
	check(service._resident.has(protected_id) and service._resident[protected_id].outside_since==-1 and service.profile.retired_units==before,"live demand remains protected regardless of size or overdue age")
	host.free();await process_frame
	print("NATIVE_RETIREMENT_SCHEDULING checks=",checks," failures=",failures);quit(1 if failures else 0)
