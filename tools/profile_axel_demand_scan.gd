extends "res://tools/profile_axel_game_pipeline.gd"
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
var benchmarked:=false
func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:Dictionary=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_demand_scan.gd"]=FileAccess.get_sha256("res://tools/profile_axel_demand_scan.gd")
	return result
func finish(code:int)->void:
	if not benchmarked and code==0 and is_instance_valid(mesh_map):
		benchmarked=true;benchmark()
	await super.finish(code)
func snapshot(queue:Deferred)->Dictionary:
	var paths:Dictionary={};var first:Dictionary={};var ids:Array=[]
	for row:Dictionary in queue._demanded:ids.append(row.record.uuid)
	for path:String in queue._demanded_by_path:
		paths[path]=[]
		for row:Dictionary in queue._demanded_by_path[path]:paths[path].append(row.record.uuid)
	for path:String in queue._path_first:first[path]=queue._path_first[path].record.uuid
	return {"ids":ids,"paths":paths,"first":first,"rank":queue._demanded_rank.duplicate(),"priority":queue._demanded_priority.duplicate(),"dispatch":queue._dispatch_paths.duplicate()}
func benchmark()->void:
	var source:Node=mesh_map.get_node("DeferredAssets")
	var probe:=Deferred.new()
	# An off-tree, nonprocessing scheduler shares read-only item owners. It never
	# admits jobs, retires sources or changes the live map's tickets.
	probe.pending=source.pending.duplicate();probe._reference_index=source._reference_index
	probe._runtime_building_records=source._runtime_building_records.duplicate()
	probe._runtime_building_supports=source._runtime_building_supports.duplicate()
	probe.instance_errors=source.instance_errors.duplicate()
	probe._index_pending()
	var saved:=Deferred.typed_demand_scan_enabled
	var origin:=Vector3(report.requested_spawn[0],report.requested_spawn[1],report.requested_spawn[2])
	report.demand_scan_benchmark={"pending":probe.pending.size(),"large":probe._large_pending.size(),"spatial_cells":probe._pending_index.size(),"trials":[],"note":"ABBA synchronous refreshes on the same actual pending items; all production radii and exact safety ticket; indexing, equality checks and cold priming excluded from timing"}
	for offset:float in [0.,32.,128.,512.,2048.]:
		var at:=origin+Vector3(offset,0,offset)
		probe.prioritize(at);probe.ensure_geometry(AABB(at-Vector3(2,1,2),Vector3(4,2,4)),"player_collision")
		Deferred.typed_demand_scan_enabled=false;probe._demand_revision+=1;probe._refresh_demanded()
		var expected:=snapshot(probe)
		Deferred.typed_demand_scan_enabled=true;probe._demand_revision+=1;probe._refresh_demanded()
		check(snapshot(probe)==expected,"actual scheduler ordered results agree at offset %.0f"%offset)
		for turn:int in 16:
			var enabled:=turn%4 in [1,2];Deferred.typed_demand_scan_enabled=enabled
			probe._demand_revision+=1
			var before_candidates:=int(probe.profile.get("typed_full_scan_candidates",0))
			var before_unfiltered:=int(probe.profile.get("typed_full_scan_unfiltered",0))
			var before_prefilter:=int(probe.profile.get("typed_full_scan_prefilter_tests",0))
			var began:=Time.get_ticks_usec();probe._refresh_demanded();var elapsed:=Time.get_ticks_usec()-began
			report.demand_scan_benchmark.trials.append({"offset":offset,"enabled":enabled,"refresh_us":elapsed,"demanded":probe._demanded.size(),"typed_candidates":int(probe.profile.get("typed_full_scan_candidates",0))-before_candidates,"unfiltered_candidates":int(probe.profile.get("typed_full_scan_unfiltered",0))-before_unfiltered,"prefilter_tests":int(probe.profile.get("typed_full_scan_prefilter_tests",0))-before_prefilter})
			check(snapshot(probe)==expected,"actual refresh keeps exact ranks/paths/heads %.0f/%d"%[offset,turn])
	Deferred.typed_demand_scan_enabled=saved
	probe.free()
