extends SceneTree
## Pure CPU lifecycle/queue regression: no model reads, Mesh or GPU resources.
const Queue=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Directory=preload("res://scripts/world3d/map_dependency_index.gd")
const Native=preload("res://scripts/world3d/native_residency.gd")
const Ordinary=preload("res://scripts/world3d/asset_residency.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Pending=preload("res://scripts/world3d/pending_catalogue_preparation.gd")
class Host extends Node:
	var _navigation:Node
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func terrain(id:String,x:float)->Dictionary:
	return {"uuid":id,"kind":"box","position":[x,0.,0.],"rotation":[0.,0.,0.],"size":[60.,1.,60.],"surface_id":"ground","collision":"walk","terrain_mesh":{"version":1,"columns":2,"rows":2,"floor":-8.,"heights":[0.,0.,0.,0.,0.,0.,0.,0.,0.],"holes":[false,false,false,false]}}
func row(record:Dictionary,at:int,reason:String="")->Dictionary:
	var result:=Directory._classify(record,"",{}, {},true) if reason.is_empty() else {"classification":"local","reason":reason,"bounds_known":true,"bounds":AABB(Vector3(-30,-8,-30),Vector3(60,8,60)),"terrain_halo":0.,"asset_path":""}
	result.uuid=record.uuid;result.order=at;result.group_id="";result.memory_bytes=65536
	result.chunk_min=Stream.chunk_key(result.bounds.position);result.chunk_max=Stream.chunk_key(result.bounds.end)
	return result
func entry(index:Dictionary,at:int)->Dictionary:
	var r:Dictionary=index.rows[at]
	return {"record_index":at,"compact_record":index.extras.rmmo_records[at],"bounds":r.bounds,"classification":r.classification,"reason":r.reason,"asset_path":r.asset_path,"group_id":r.group_id,"memory_bytes":r.memory_bytes}
func ids(queue:Node)->Array:
	queue._refresh_demanded();var result:Array=queue._demanded_by_id.keys();result.sort();return result
func reset_membership(queue:Node)->void:
	queue._demand_membership.clear();queue._typed_pending.clear();queue._typed_pending_buildings=-1;queue._demand_revision+=1
func spec(r:Dictionary)->Dictionary:
	return {"uuid":r.uuid,"chunk":r.chunk_min,"chunk_min":r.chunk_min,"chunk_max":r.chunk_max,"ground_batch_record":{"uuid":r.uuid,"terrain_mesh":{}},"render_bounds":{"chunk_min":r.chunk_min,"chunk_max":r.chunk_max},"extras":{}}
func run()->void:
	var saved_typed:=Queue.typed_demand_scan_enabled;var saved_incremental:=Queue.incremental_pending_index_enabled
	var records:Array=[terrain("axel_terrain_00_00",0),terrain("terrain_far",1400),terrain("terrain_return",-500),{"uuid":"road"},{"uuid":"bridge"},{"uuid":"ordinary_global"},{"uuid":"ordinary_model"}]
	var rows:Array=[]
	for i in records.size():
		records[i].rmmo_ref={"uri":str(i)+".rmres","sha256":"a".repeat(64),"length":32,"version":1}
		rows.append(row(records[i],i,["","","","native_road","native_bridge","native_box","unknown_geometry"][i]))
	var index:={"ok":true,"rows":rows,"extras":{"rmmo_records":records},"groups":{},"models":{}}
	var origin:=Vector3(156.,8.4,209.);var away:=origin+Vector3(2048.,0.,0.)
	var cell:=Stream.chunk_key(origin);var center:=Vector3((cell.x+.5)*32.,0.,(cell.y+.5)*32.)
	var player_clip:=AABB(center-Vector3(128,100000,128),Vector3(256,200000,256))
	var cold:=Directory.select(index,[player_clip])
	check(cold.ok and cold.record_indices.has(0) and cold.record_indices.has(1) and cold.record_indices.has(2),"cold global selection initially includes all terrain")
	var source:=spec(rows[0])
	check(Stream._draws(source,Stream._ring_at(cell,Stream.RENDER_RADIUS)),"missing return tile is inside the actual landscape draw contract")
	check(not Queue._intersects(rows[0].bounds,player_clip) and not Stream._overlaps(source,Stream._ring_at(cell,Stream.COLLISION_RADIUS)),"same tile is outside player demand and near collision ring")
	var host:=Host.new();var map:=Node3D.new();host.add_child(map)
	var queue:=Queue.new();map.add_child(queue);queue._map=map;queue._reference_index=index
	map.set_meta("extras",{"rmmo_records":[]});map.set_meta("stream_library",[source]);queue._index_pending()
	var service:=Native.new();map.add_child(service);service.configure(host,map,queue);service.grace_msec=10
	check(service._resident.has("record:axel_terrain_00_00"),"cold publication is observed as resident terrain")
	queue.prioritize(away);service._retirement_candidates(100)
	var expired:=service._retirement_candidates(111)
	check(expired.has("record:axel_terrain_00_00"),"terrain outside far draw and hysteresis becomes a retirement candidate")
	# The real scene/index retirement is covered by GPU tests. Exercise its
	# exact compact-record handoff here after removing this resident owner.
	service._resident.erase("record:axel_terrain_00_00");service._retired["record:axel_terrain_00_00"]=true
	check(queue.requeue_references([entry(index,0)])==1,"retired terrain returns through the production incremental requeue")
	check(ids(queue).is_empty(),"retired origin tile stays unloaded while far away")
	queue.prioritize(origin)
	check(ids(queue)==["axel_terrain_00_00"],"same focus requests the terrain that cold entry displayed")
	check(queue._demands.has("terrain_render") and queue._demands.terrain_render.kind=="terrain" and queue._demands.terrain_render.priority==10,"terrain has a low-priority dedicated far-view ticket")
	var requests:=queue._reference_requests(queue.pending[0].path)
	check(requests.size()==1 and requests[0].compact_record.uuid=="axel_terrain_00_00","return request contains the exact retired compact terrain owner")
	check(queue._demands.player.clip==player_clip and Stream.COLLISION_RADIUS==2,"terrain demand does not enlarge player/physics residency")
	var radius:=Stream.BUILDING_RENDER_RADIUS;var corner:=Vector3((cell.x-radius)*32.,-100000,(cell.y-radius)*32.)
	var view:=AABB(corner,Vector3((2*radius+1)*32.,200000,(2*radius+1)*32.))
	queue.requeue_references([entry(index,1),entry(index,3),entry(index,4),entry(index,5),entry(index,6)])
	queue._demands.clear();queue.set_demand("terrain_only",view,10,"terrain")
	check(queue._demands.has("terrain_only"),"terrain is accepted by the public demand API")
	# Keep the old implementation exercising its missing kind filter, so the
	# baseline records exclusion failures as well as the missing public ticket.
	queue._demands["terrain_only"]={"kind":"terrain","clip":view,"priority":10}
	for mode:Array in [[false,true],[true,false],[true,true]]:
		Queue.typed_demand_scan_enabled=mode[0];Queue.incremental_pending_index_enabled=mode[1];reset_membership(queue)
		check(ids(queue)==["axel_terrain_00_00"],"terrain excludes road, bridge, generic global and out-of-range terrain in scan mode "+str(mode))
	Queue.typed_demand_scan_enabled=true;Queue.incremental_pending_index_enabled=true;reset_membership(queue);ids(queue)
	var partitions:=int(queue.profile.get("typed_partition_builds",0));var scans:=int(queue.profile.get("typed_full_scan_prefilter_tests",0))
	check(queue.requeue_references([entry(index,2)])==1 and ids(queue)==["axel_terrain_00_00","terrain_return"],"incremental requeue adds a newly returning terrain to the typed catalogue")
	check(int(queue.profile.get("typed_partition_builds",0))==partitions and int(queue.profile.get("typed_full_scan_prefilter_tests",0))==scans,"terrain requeue never rebuilds or scans the whole kind catalogue")
	queue.set_demand("near_only",player_clip,0);queue.set_demand_scope(["near_only"])
	check(ids(queue).is_empty(),"transfer demand scope can suppress background terrain tickets")
	queue.set_demand_scope([]);queue.release_demand("near_only")
	check(ids(queue)==["axel_terrain_00_00","terrain_return"],"restoring scope restores only in-range terrain")
	# Dedicated far-view demand must not accidentally pin every ordinary asset.
	var unit:Dictionary=service._units["record:axel_terrain_00_00"]
	check(service._needed(unit),"terrain residency recognizes its typed demand")
	for reason:String in ["native_road","native_bridge","native_box","unknown_geometry"]:
		check(not service._needed({"kind":"all","entries":[{"reason":reason}],"bounds":rows[0].bounds}),"terrain ticket does not pin native/ordinary reason "+reason)
	var assets:=Ordinary.new();assets._host=host;assets._deferred=queue
	check(not assets._needed({"bounds":rows[0].bounds}),"terrain ticket does not pin ordinary model residency")
	var edge_unit:={"kind":"all","entries":[{"reason":"terrain_context_global"}],"bounds":AABB(Vector3(view.end.x+63.,0.,0.),Vector3.ONE)}
	check(service._needed(edge_unit),"terrain retains the existing 64 metre exit hysteresis")
	edge_unit.bounds.position.x=view.end.x+65.
	check(not service._needed(edge_unit),"terrain beyond exit hysteresis remains retireable")
	var prepared:=Pending.prepare(queue.pending)
	check(prepared.kinds.items("terrain").size()==3 if "terrain" in prepared.kinds.KINDS else false,"parser-prepared catalogue includes exactly terrain rows")
	# Publication pruning also updates the incremental kind owner.
	var removed:Dictionary=queue._pending_by_record_id["terrain_return"];queue._unindex_pending_item(removed);queue.pending.erase(removed)
	reset_membership(queue)
	check(ids(queue)==["axel_terrain_00_00"],"removed terrain cannot survive in the typed catalogue")
	assets.free();host.free()
	Queue.typed_demand_scan_enabled=saved_typed;Queue.incremental_pending_index_enabled=saved_incremental
	print("TERRAIN_RETURN_DEMAND ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
