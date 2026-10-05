extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Batch=preload("res://scripts/world3d/fortification_collision_batcher.gd")
var failed:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: failed+=1; push_error(message)
	else: print("PASS: ",message)
func run() -> void:
	create_timer(240).timeout.connect(func():quit(2))
	var raw:=Doc.authoritative_extras("D:/code/rmmo_runtime/cache/world3d/medieval_town_walls/map.gltf")
	var doc:=Doc.new(); var host:=Node3D.new(); root.add_child(host)
	var entries: Array=[]; var center:=Vector3(393.4,0,-508.2)
	for record in raw.extras.rmmo_records:
		if not Batch.candidate(record): continue
		var at:=Vector3(record.position[0],0,record.position[2])
		if at.distance_to(center)>38: continue
		var visual: MeshInstance3D=doc._mesh(record); host.add_child(visual)
		var entry:=Batch.entry(visual.mesh,visual.global_transform,record.uuid,visual.get_meta("extras")); entry.cpu.collision_faces(); entry.cpu.geometry_key(); entries.append(entry)
	var batch:=Batch.new(); host.add_child(batch)
	var cold: Array=[]; var warm: Array=[]
	for i in 5:
		batch.clear(); var start:=Time.get_ticks_usec(); batch.sync(entries); cold.append((Time.get_ticks_usec()-start)/1000.)
		batch.sync([]); await physics_frame
		start=Time.get_ticks_usec(); batch.sync(entries); warm.append((Time.get_ticks_usec()-start)/1000.)
		await physics_frame
	var state:=batch.stats(); cold.sort(); warm.sort()
	check(state.shape_cache_hits>0,"revisit reuses cooked concave collision resources")
	check(state.bodies>0 and state.shape_cache_groups<=64 and state.shape_cache_triangles<=262144,"residency cache stays bounded")
	check(warm[2]<cold[2],"revisit costs less than recooking the same collision geometry")
	batch.clear(); check(batch.stats().shape_cache_groups==0 and batch.stats().bodies==0,"document reset releases active and cached physics resources")
	var cube:=BoxMesh.new()
	for i in 70: batch.sync([Batch.entry(cube,Transform3D(Basis.IDENTITY,Vector3(i*64,0,0)),"eviction",{})])
	check(batch.stats().shape_cache_groups==64,"recent shape cache evicts old spatial groups")
	var misses: int=batch.cache_misses
	batch.sync([Batch.entry(cube,Transform3D.IDENTITY,"eviction",{})])
	check(batch.cache_misses==misses+1,"evicted shape rebuilds instead of using stale geometry")
	batch.clear()
	var report:={"sources":entries.size(),"cold_median_ms":cold[2],"warm_median_ms":warm[2],"cold_ms":cold,"warm_ms":warm,"stats":state,"failures":failed}
	var file:=FileAccess.open("D:/code/rmmo_runtime/review_artifacts/medieval_town_walls/collision_residency.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("COLLISION_RESIDENCY_RESULT ",JSON.stringify(report)); quit(1 if failed else 0)
