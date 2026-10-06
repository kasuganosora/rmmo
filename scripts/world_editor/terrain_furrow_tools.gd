extends RefCounted
const Data=preload("res://scripts/world3d/terrain_furrows.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
static func prepare(records: Array,args: Dictionary,editable: Callable) -> Dictionary:
	var error:=Terrain.S.validate(args,Data.schemas())
	if not error.is_empty(): return Terrain.fail(error)
	var updates: Array=[]; var seen:={}; var triangles:=0
	for id in args.terrain_ids:
		if seen.has(id): return Terrain.fail("重复地形 ID")
		seen[id]=true
		var matches:=records.filter(func(r):return r.uuid==id)
		if matches.size()!=1 or not editable.call(matches[0]): return Terrain.fail("请显示、解锁并选择当前楼层的关联地形")
		var record: Dictionary=matches[0]
		if not record.has("terrain_mesh") or record.has("surface_paint") or absf(record.rotation[0])>.00001 or absf(record.rotation[2])>.00001: return Terrain.fail("垄沟需要无手刷三角面覆盖的水平地形，支持 Y 旋转")
		var next:=record.duplicate(true); var found:=false
		for region in next.get("terrain_regions",{}).get("regions",[]):
			if region.id!=args.id: continue
			found=true
			if args.get("enabled",true):
				var angle: float=args.get("angle",0.); var axis:=Vector2(cos(deg_to_rad(angle)),sin(deg_to_rad(angle)))
				region.furrows={"spacing":args.get("spacing",1.6),"height":args.get("height",.18),"angle":wrapf(angle+record.rotation[1],-180.,180.),"phase":Vector2(record.position[0],record.position[2]).dot(axis),"margin":args.get("margin",2.)}
				region.furrows.setback=args.get("setback",0.)
			else: region.erase("furrows")
		if not found: return Terrain.fail("所列地形没有这个地表区域")
		if next==record: continue
		if not Data.Regions.valid(next): return Terrain.fail("无效的农田参数")
		var built:=Data.generate(next)
		if not built.ok: return built
		triangles+=built.triangles
		if triangles>120000: return Terrain.fail("单次垄沟超过 12 万三角面预算，请分批处理")
		var previous:=Data.generate(record)
		var touched: PackedVector3Array=built.vertices.duplicate()
		if previous.ok: touched.append_array(previous.vertices)
		if not touched.is_empty():
			var world:=Terrain.transform(next); var points: Array[Vector3]=[]
			for v in touched: points.append(world*v); points.append(world*(v+Vector3.UP*.15))
			var area:=Foot.from_points(points)
			for other in records:
				if other.has("terrain_mesh"): continue
				if not Foot.batches_overlap([area],[Foot.record_shape(other)]): continue
				var obstacles:=Foot.record_shapes(other)
				if not Foot.batches_overlap([area],obstacles): continue
				# Broad hulls can cover an empty corner or the lane between two
				# fields. Test only actual raised triangles before rejecting.
				for i in range(0,touched.size(),3):
					var triangle: Array[Vector3]=[]
					for j in 3: triangle.append(world*touched[i+j]); triangle.append(world*(touched[i+j]+Vector3.UP*.15))
					if Foot.batches_overlap([Foot.from_points(triangle)],obstacles): return Terrain.fail("农田垄沟会侵入现有道路、物件或移除其承托，请缩小区域："+str(other.get("name",other.uuid)))
		updates.append(next)
	return {"ok":true,"changed":not updates.is_empty(),"records":updates,"triangles":triangles}
static func apply(editor: Node3D,args: Dictionary) -> Dictionary:
	var guard: Dictionary=editor._gameplay.guard()
	if not guard.ok: return guard
	return preload("res://scripts/world_editor/river_material_tools.gd").commit(editor,prepare(editor._doc.records,args,editor._record_editable))
