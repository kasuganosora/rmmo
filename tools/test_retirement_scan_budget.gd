extends "res://tools/test_stream_index_retire.gd"
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
func calls(trace:Dictionary,label:String)->int:
	for row:Dictionary in trace.stats:
		if row.label==label:return row.count
	return 0
func run()->void:
	Trace.methods_enabled=true
	Trace.method_labels={"method.stream_index.validate_owned_retire":true,"method.stream_index._retire_plan":true}
	var library:Array=[]
	for i:int in 2200:library.append(spec("keep_%d"%i,Vector2i.ZERO,Vector2i.ZERO,{"kind":"box"}))
	library.append(spec("far",Vector2i(100,0),Vector2i(100,0),{"kind":"asset"}))
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",library)
	var data:Dictionary=Index.build(library)
	for key:String in data:map.set_meta(key,data[key])
	map.set_meta("stream_chunk",Vector2i.ZERO)
	Trace.start();Stream.legacy_retirement_validation_enabled=true
	var old:Dictionary=Stream.can_retire_specs(map,["keep_0"],true)
	var old_trace:=Trace.stop()
	check(not old.ok and old.error=="source_pinned" and calls(old_trace,"method.stream_index.validate_owned_retire")==1,"previous pinned native preflight scans the whole directory")
	Stream.legacy_retirement_validation_enabled=false;Trace.start()
	var current:Dictionary=Stream.can_retire_specs(map,["keep_0"],true)
	var current_trace:=Trace.stop()
	check(current==old and calls(current_trace,"method.stream_index.validate_owned_retire")==0,"pinned source is refused identically with zero whole-directory validation calls")
	check(library.size()==2201 and map.get_meta("stream_by_id").size()==2201,"pinned refusal changes no geometry or index ownership")
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new()
	nav.configure_streaming_geometry(func(_clip:AABB):return {"ok":true,"error":""})
	nav.map=NavigationServer3D.map_create();root.add_child(nav);nav.set_process(false)
	check(nav.append_specs(library).ok,"real navigation source catalogue accepts fixture")
	Trace.start()
	var refused:Dictionary=Stream.retire_specs(map,["far"],false,nav)
	var refused_trace:=Trace.stop()
	check(not refused.ok and refused.error=="source_in_use" and nav._spec_ids.has("far") and map.get_meta("stream_by_id").has("far"),"busy navigation refuses the transaction without removing either owner")
	check(calls(refused_trace,"method.stream_index._retire_plan")==1,"busy owner handshake performs only one complete integrity validation")
	nav.ready_for_queries=true;Trace.start()
	var retired:Dictionary=Stream.retire_specs(map,["far"],false,nav)
	var retired_trace:=Trace.stop()
	check(retired.ok and retired.removed==1 and not nav._spec_ids.has("far") and not map.get_meta("stream_by_id").has("far"),"same synchronous transaction removes both navigation and map ownership")
	check(calls(retired_trace,"method.stream_index._retire_plan")==1,"successful retirement validates the complete directory once rather than three times")
	var invalid:Dictionary=Stream.retire_specs(map,["missing"],false,nav)
	check(not invalid.ok and library.size()==2200 and nav._spec_ids.size()==2200,"invalid identity still fails without changing either owner")
	var a:Dictionary=spec("shared_a");var b:Dictionary=spec("shared_b");b.mesh=a.mesh
	check(nav.append_specs([a,b]).ok,"shared immutable navigation geometry appends under independent UUIDs")
	var geometry_id:int=a.mesh.get_instance_id();var faces:PackedVector3Array=a.mesh.get_faces()
	nav._faces[geometry_id]=faces
	check(nav.try_retire_specs(["shared_a"]).ok and nav._faces.has(geometry_id),"retiring one navigation owner preserves the other owner's cached faces")
	check(nav.try_retire_specs(["shared_b"]).ok and not nav._faces.has(geometry_id),"retiring the last geometry owner drops its face cache")
	a=spec("shape_a");b=spec("shape_b");b.mesh=a.mesh;nav.append_specs([a,b])
	geometry_id=a.mesh.get_instance_id();nav._faces[geometry_id]=faces
	var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces);a.shape=shape
	var shape_id:=shape.get_instance_id();nav._faces[shape_id]=faces
	var soup:=NavigationMeshSourceGeometryData3D.new()
	check(nav._add_source(soup,a),"real navigation consumption rebinds a subsequently prepared concave shape")
	check(nav.try_retire_specs(["shape_a"]).ok and not nav._faces.has(shape_id) and nav._faces.has(geometry_id),"shape retirement releases its cache without discarding the surviving mesh owner's faces")
	check(nav.try_retire_specs(["shape_b"]).ok and not nav._faces.has(geometry_id),"remaining mesh owner subsequently releases its face cache")
	var usage:=preload("res://scripts/world3d/asset_residency.gd").new()
	usage._record_paths={"native":"shared.glb","prop":"shared.glb"}
	usage.observe([{"uuid":"native__part","ground_batch_record":{"kind":"box","uuid":"native__part","building":{}}},{"uuid":"prop__part","ground_batch_record":{"kind":"asset","uuid":"prop"}}])
	usage.forget_specs(["prop__part"])
	check(usage.model_in_use("shared.glb"),"pinned native owner still protects a model shared with an ordinary prop")
	usage.forget_specs(["native__part"])
	check(not usage.model_in_use("shared.glb"),"shared transaction removes the final native namespace from scalar source usage")
	usage.observe([{"uuid":"unknown","ground_batch_record":{"kind":"asset"}}])
	check(usage.model_in_use("unrelated.glb"),"unknown imported ownership conservatively blocks cache eviction")
	usage.forget_specs(["unknown"])
	check(not usage.model_in_use("unrelated.glb"),"retiring unknown ownership releases that conservative guard")
	usage._remember_traits({"uuid":"bridge","kind":"asset","bridge_mesh":{}})
	usage.observe([{"uuid":"bridge__mesh","ground_batch_record":{"kind":"asset","uuid":"bridge"}}])
	check(not usage.model_in_use("unrelated.glb"),"known procedural bridge geometry has no external model owner and cannot block unrelated eviction")
	usage.free()
	var queue:=preload("res://scripts/world3d/deferred_asset_loader.gd").new();queue._map=map
	queue._reference_index={"models":{}}
	var records:Array=[{"uuid":"keep"},{"uuid":"a"},{"uuid":"already"},{"uuid":"b"}]
	map.set_meta("extras",{"rmmo_records":records});queue._runtime_record_ids={"a":records[1],"b":records[3],"keep":records[0]}
	queue.pending=[{"record":{"uuid":"already"}}]
	var entries:Array=[]
	for id:String in ["a","already","a","b"]:entries.append({"compact_record":{"uuid":id},"asset_path":"","group_id":"building:pair","record_index":1,"bounds":AABB(Vector3.ZERO,Vector3.ONE)})
	var runtime_bounds:=AABB(Vector3(-3,0,-3),Vector3(6,1,6));queue._runtime_building_records.a=runtime_bounds
	var revision:int=queue._demand_revision
	check(queue.requeue_references(entries)==2 and queue.pending.map(func(item):return item.record.uuid)==["already","a","b"],"batch requeue deduplicates old/new identities and preserves accepted order")
	check(is_same(records,map.get_meta("extras").rmmo_records) and records.map(func(record):return record.uuid)==["keep","already"] and queue._runtime_record_ids.keys()==["keep"],"batch requeue compacts runtime author handoff once without changing array identity or unrelated records")
	check(queue.pending[1].bounds==runtime_bounds and queue.pending[1].reference_entry.bounds!=runtime_bounds and queue.pending[1].path=="reference:building:pair" and queue._demand_revision==revision+1,"batch requeue preserves immutable proof bounds, learned demand bounds, native path and one invalidation")
	revision=queue._demand_revision
	check(not queue.requeue_reference(entries[0]) and queue._demand_revision==revision,"duplicate single-reference compatibility call remains a side-effect-free no-op")
	queue.free()
	map.free();nav.free();await process_frame
	Trace.methods_enabled=false;Trace.method_labels.clear()
	print("RETIREMENT_SCAN_BUDGET checks=",checks," failures=",failures);quit(1 if failures else 0)
