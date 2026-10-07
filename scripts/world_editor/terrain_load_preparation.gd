extends RefCounted
## Private CPU-only payloads for one immutable editor load. The caller publishes
## them only while constructing that record, then restores the document context.
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Regions=preload("res://scripts/world3d/terrain_regions.gd")

static func prepare(records:Array,context:RefCounted)->Dictionary:
	var started:=Time.get_ticks_usec();var buckets:Array=[];var count:=0
	for i in 4:buckets.append({"records":[],"result":{}})
	for record:Dictionary in records:
		if record.has("terrain_mesh"):buckets[count%4].records.append(record);count+=1
	var workers:Array[Thread]=[]
	for bucket:Dictionary in buckets:
		if bucket.records.is_empty():continue
		var task:=func():bucket.result=_prepare_bucket(bucket.records,context)
		var worker:=Thread.new()
		if count>1 and worker.start(task,Thread.PRIORITY_LOW)==OK:workers.append(worker)
		else:task.call()
	for worker:Thread in workers:worker.wait_to_finish()
	var result:={"surfaces":{},"masks":{},"arrays_us":0,"masks_us":0,"worker_elapsed_sum_us":0}
	for bucket:Dictionary in buckets:
		if bucket.result.is_empty():continue
		result.surfaces.merge(bucket.result.surfaces);result.masks.merge(bucket.result.masks)
		result.arrays_us+=bucket.result.arrays_us;result.masks_us+=bucket.result.masks_us
		result.worker_elapsed_sum_us+=bucket.result.elapsed_us
	result.elapsed_us=Time.get_ticks_usec()-started
	return result

static func _prepare_bucket(records:Array,context:RefCounted)->Dictionary:
	var surfaces:Dictionary={};var masks:Dictionary={}
	var started:=Time.get_ticks_usec();var arrays_us:=0;var masks_us:=0
	for record:Dictionary in records:
		if not record.has("terrain_mesh"):continue
		var id:=str(record.uuid);var mark:=Time.get_ticks_usec()
		surfaces[id]=Terrain.arrays(record,context.data.get(id,{}))
		arrays_us+=Time.get_ticks_usec()-mark
		if record.has("terrain_regions"):
			mark=Time.get_ticks_usec();masks[id]=Regions.mask(record)
			masks_us+=Time.get_ticks_usec()-mark
	return {"surfaces":surfaces,"masks":masks,"elapsed_us":Time.get_ticks_usec()-started,"arrays_us":arrays_us,"masks_us":masks_us}
