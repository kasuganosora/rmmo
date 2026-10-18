extends SceneTree
## Independent reproduction of streaming work unrelated to the changed content.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Fort=preload("res://scripts/world3d/fortification_collision_batcher.gd")
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
class CountCutaway extends "res://scripts/world3d/building_cutaway.gd":
	var scans:=0
	func _instances(scene:Node)->Dictionary:
		scans+=1
		return super._instances(scene)
var failures:=0
var checks:=0
var receipt:Dictionary={}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func spec(id:String,position:Vector3,wall:bool=false)->Dictionary:
	var box:=BoxMesh.new();box.size=Vector3(1,2,1)
	var mesh:=Cpu.capture(box)
	var pose:=Transform3D(Basis.IDENTITY,position)
	var bounds:=pose*mesh.get_aabb()
	var record:={"uuid":id,"kind":"box","surface_id":"block","position":[position.x,position.y,position.z],"rotation":[0,0,0],"size":[1,2,1]}
	if wall:record.fortification={"id":"test_wall","part":id}
	return {"uuid":id,"mesh":mesh,"transform":pose,"position":position,"rotation":Vector3.ZERO,"chunk":Stream.chunk_key(position),"chunk_min":Stream.chunk_key(bounds.position),"chunk_max":Stream.chunk_key(bounds.end),"extras":{"rmmo_collision":"block" if wall else "none","surface_id":"block"},"ground_batch_record":record,"material_override":null,"surface_overrides":[],"cast_shadow":GeometryInstance3D.SHADOW_CASTING_SETTING_ON}
func scene_for(library:Array)->Node3D:
	var scene:=Node3D.new();root.add_child(scene)
	scene.set_meta("stream_library",library)
	var data:=Index.build(library)
	for key:String in data:scene.set_meta(key,data[key])
	return scene
func settle_stream(scene:Node3D,origin:Vector3,budget:int=1)->int:
	var calls:=0
	while calls<1000:
		Stream.sync(scene,scene,origin,budget);calls+=1
		if scene.has_meta("stream_chunk") and scene.get_meta("stream_chunk")==Stream.chunk_key(origin) and scene.get_meta("stream_append_pending",[]).is_empty():break
	return calls
func ray(scene:Node3D,position:Vector3)->Dictionary:
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(position+Vector3.UP*5,position-Vector3.UP*5))
func physics()->void:
	await physics_frame;await physics_frame;await process_frame
func run()->void:
	await test_collision()
	test_cutaway()
	receipt.checks=checks;receipt.failures=failures
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file:=FileAccess.open(arg.trim_prefix("--out="),FileAccess.WRITE)
			if file!=null:file.store_string(JSON.stringify(receipt,"\t"))
	print("BLIND_MAP_RENDER_FINISHED checks=",checks," failures=",failures)
	quit(1 if failures else 0)
func test_collision()->void:
	var library:Array=[]
	for i in 3:library.append(spec("wall_%d"%i,Vector3(4+i*2,1,4),true))
	var scene:=scene_for(library)
	Stream.sync(scene,scene,Vector3.ZERO)
	var batch=scene.get_node("FortificationCollisionBatches")
	await physics()
	check(batch.stats().source_objects==3,"three wall sources have real collision")
	check(Fort.hit_uuid(ray(scene,Vector3(4,1,4)))=="wall_0","exact collision ray retains source identity")
	var body:Variant=batch.body_for("wall_0")
	var shape:Shape3D=body.get_child(0).shape
	var faces:PackedVector3Array=shape.get_faces()
	var additions:Array=[]
	for i in 24:additions.append(spec("prop_%d"%i,Vector3(4+i*.2,1,12)))
	check(Stream.append_specs(scene,additions).ok,"append ordinary scenery through production index transaction")
	var before:int=batch.sync_count
	var began:=Time.get_ticks_usec()
	var slices:=settle_stream(scene,Vector3.ZERO)
	receipt.collision={"unrelated_slices":slices,"unrelated_syncs":batch.sync_count-before,"elapsed_us":Time.get_ticks_usec()-began}
	check(slices>=24 and slices<1000,"ordinary scenery completes across bounded stream slices")
	check(batch.sync_count==before,"ordinary scenery never rescans unchanged wall collision")
	check(batch.body_for("wall_0")==body and body.get_child(0).shape==shape and shape.get_faces()==faces,"unrelated publication preserves exact body, shape and triangle bytes")
	Stream.sync(scene,scene,Vector3(33,0,0))
	check(batch.sync_count==before,"crossing a cell without changing wall physics skips collision regrouping")
	Stream.sync(scene,scene,Vector3(256,0,0))
	check(batch.stats().source_objects==0 and batch.stats().bodies==0,"departure removes wall bodies immediately")
	Stream.sync(scene,scene,Vector3.ZERO)
	await physics()
	check(batch.stats().source_objects==3 and Fort.hit_uuid(ray(scene,Vector3(4,1,4)))=="wall_0","return restores wall collision and face identity")
	var wall:=spec("wall_new",Vector3(12,1,4),true)
	check(Stream.append_specs(scene,[wall]).ok,"append a new collision source")
	before=batch.sync_count;settle_stream(scene,Vector3.ZERO)
	await physics()
	check(batch.sync_count>before and batch.stats().source_objects==4,"changed wall sources synchronize before residency settles")
	check(Fort.hit_uuid(ray(scene,Vector3(12,1,4)))=="wall_new","new wall has an actual physics body")
	for x in [256.,0.,-256.,33.]:Stream.sync(scene,scene,Vector3(x,0,0),1)
	settle_stream(scene,Vector3.ZERO)
	check(batch.stats().source_objects==4,"interrupted departure and return retain all demanded wall collision")
	# Recreating the derived service must not inherit the previous service's clean state.
	batch.free();scene.remove_meta("stream_chunk");scene.remove_meta("stream_target")
	Stream.sync(scene,scene,Vector3.ZERO)
	batch=scene.get_node("FortificationCollisionBatches")
	check(batch.stats().source_objects==4,"replacement collision service reconstructs all retained sources")
	scene.free()
func test_cutaway()->void:
	var scene:=Node3D.new();root.add_child(scene)
	var records:Array=[]
	for i in 10000:records.append({"uuid":"author_prop_%d"%i,"kind":"asset"})
	scene.set_meta("author_reference_extras",{"rmmo_records":records})
	var observer:=CountCutaway.new();observer.map_root=scene
	var plain:=spec("arriving_prop",Vector3.ZERO)
	var began:=Time.get_ticks_usec()
	for i in 30:observer.append_specs(scene,[plain])
	receipt.cutaway={"ordinary_batches":30,"authored_records":records.size(),"catalog_scans":observer.scans,"elapsed_us":Time.get_ticks_usec()-began}
	check(observer.scans==0,"ordinary asset batches never enumerate the authored building catalog")
	check(observer.buildings.is_empty() and observer.hidden.is_empty(),"ordinary batches leave cutaway presentation unchanged")
	var part:={"uuid":"house_part","position":[0.,2.,0.],"size":[4.,4.,4.],"building":{"id":"house","part":"wall","role":"wall","floor":0,"floor_y":0.}}
	scene.set_meta("extras",{"building_instances":{"house":{"parameters":Blueprint.defaults(),"position":[0.,0.,0.],"yaw":0.,"version":1,"parts":{"wall":"house_part"}}}})
	observer.append_specs(scene,[{"uuid":"house_part","ground_batch_record":part}])
	check(observer.buildings.has("house") and observer.buildings.house.parts.has("house_part"),"real building arrivals still discover and register their parts")
	var scans:int=observer.scans
	observer.append_specs(scene,[plain]);observer.append_records(scene,[])
	check(observer.scans==scans and observer.buildings.house.parts.size()==1,"unrelated and empty batches preserve existing building membership without rescanning")
	part=part.duplicate(true);part.position[1]=6.
	observer.append_specs(scene,[{"uuid":"house_part","ground_batch_record":part}])
	check(observer.buildings.house.parts.house_part.position[1]==6.,"later building changes remain observable")
	scene.free()
