extends RefCounted
const Data=preload("res://scripts/world3d/city_layout.gd")
const Scatter=preload("res://scripts/world3d/vegetation_scatter.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Zones=preload("res://scripts/world3d/planning_zones.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Street=preload("res://scripts/world_editor/building_street.gd")
var editor: Node3D
var overlay_plan: Dictionary={}
var _bounds_cache: Dictionary={}

func regions() -> Array: return Data.resolve(editor._doc.map_meta).get("vegetation",[])
func entries(query: String="") -> Array:
	var all: Array=editor._assets.search(query).duplicate()
	for library in editor._shared_assets: all.append_array(library.search(query))
	var result: Array=[]; var seen:={}
	for entry in all:
		var path: String=entry.get("asset_path","")
		if entry.has("prefab_path") or entry.has("auto_family") or path.get_extension().to_lower()!="glb" or seen.has(path): continue
		seen[path]=true; result.append(entry)
	return result
func catalog(query: String="", offset: int=0, limit: int=100) -> Dictionary:
	var all:=entries(query); var rows: Array=[]
	for region in regions():
		var changed: Array=[]
		for part in region.parts:
			if Data.token(editor._doc._find(part.id))!=part.signature: changed.append(part.id)
		rows.append({"settings":region.settings,"count":region.parts.size(),"modified_or_missing":changed})
	return {"ok":true,"regions":rows,"assets":all.slice(offset,offset+limit).map(func(e):return {"asset_id":e.asset_path,"name":e.label,"category":e.get("category","")}),"asset_total":all.size()}

func owned(region: Dictionary, verify: bool=true) -> Dictionary:
	var excluded:={}
	for part in region.get("parts",[]):
		var record: Dictionary=editor._doc._find(part.id)
		if not record.is_empty() and not editor._record_editable(record): return Data.fail("散布物件包含隐藏、锁定或隔层成员，请先解除保护")
		if verify and (record.is_empty() or Data.token(record)!=part.signature): return Data.fail("植被已被手动修改或删除；请撤销修改，或解除区域关联以保留现场")
		excluded[part.id]=true
	return {"ok":true,"ids":excluded}

func prepare(args: Dictionary) -> Dictionary:
	var error:=Scatter.S.validate(args,Scatter.request_schema())
	if not error.is_empty(): return Data.fail(error)
	var old: Dictionary={}
	for region in regions():
		if region.settings.id==args.id: old=region
	var settings:=Scatter.defaults(); settings.merge(old.get("settings",{}),true); settings.merge(args,true); settings.erase("plan_token")
	if not Scatter.valid_settings(settings): return Data.fail("散布区域需为有效简单多边形，宽深不超过 1000 米、包围面积不超过 25 万平方米，缩放范围和素材 ID 不重复")
	if old.is_empty() and regions().size()>=128: return Data.fail("最多保存 128 个散布区域")
	var ownership:=owned(old)
	if not ownership.ok: return ownership
	var assets: Array=[]; var hashes: Array=[]; var by_id:={}
	for entry in entries(): by_id[entry.asset_path]=entry
	for id in settings.asset_ids:
		if not by_id.has(id) or not Data.Paths.allowed(id) or not FileAccess.file_exists(id): return Data.fail("散布素材不在当前资源库、已丢失或超出资源根")
		var hash_:=FileAccess.get_sha256(id); hashes.append(hash_)
		if not _bounds_cache.has(hash_):
			var node=Library.Io.load_scene(id) as Node3D
			if node==null: return Data.fail("散布模型无法读取")
			var bounds:=Library.bounds_of(node); node.free()
			if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x<.01 or bounds.size.y<.01 or bounds.size.z<.01: return Data.fail("散布模型缺少有效三维包围盒")
			if _bounds_cache.size()>=32: _bounds_cache.clear()
			_bounds_cache[hash_]=bounds
		var asset: Dictionary=by_id[id].duplicate(true); var bounds: AABB=_bounds_cache[hash_]
		asset.bounds_position=Data.xyz(bounds.position); asset.bounds_size=Data.xyz(bounds.size); assets.append(asset)
	var token:=Data.token([settings,Data.resolve(editor._doc.map_meta),editor._doc.records,editor._authoring.settings,hashes])
	if args.has("plan_token") and args.plan_token!=token: return Data.fail("散布预览后地图、参数、楼层或素材发生变化，请重新预览")
	var polygon:=Scatter.polygon(settings.polygon)
	var allowed: Array=[polygon] if settings.boundary_margin==0 else Array(Geometry2D.offset_polygon(polygon,-settings.boundary_margin))
	if allowed.is_empty(): return Data.fail("区域太窄，无法留出边界退让")
	var supports: Array=[]; var obstacles: Array=[]; var grouped:={}
	var region_box:=AABB(Vector3(polygon[0].x,settings.height,polygon[0].y),Vector3.ZERO)
	for p in polygon: region_box=region_box.expand(Vector3(p.x,settings.height,p.y))
	for record in editor._doc.records:
		if ownership.ids.has(record.uuid): continue
		var shapes:=Foot.record_shapes(record)
		if record.has("building"):
			var id: String=record.building.id
			if not grouped.has(id): grouped[id]=[]
			grouped[id].append(record)
			continue
		for shape in shapes:
			var b: AABB=shape.bounds
			if b.end.x<region_box.position.x or b.position.x>region_box.end.x or b.end.z<region_box.position.z or b.position.z>region_box.end.z: continue
			# Only an actual horizontal ground box at the requested level provides support.
			if Foot.level_ground(record,shape,settings.height):
				supports.append(shape.polygon); continue
			obstacles.append(shape)
	for group in grouped.values(): obstacles.append_array(Foot.components(group,Vector3.ZERO,Basis.IDENTITY))
	obstacles.append_array(Zones.obstacles(editor._doc.map_meta,"vegetation"))
	var graph: Dictionary=Data.resolve(editor._doc.map_meta).roads; var analysis:=Data.analyze(graph)
	if not analysis.ok: return analysis
	var paths: Array=[]
	for edge in graph.edges:
		var points: Array=analysis.paths[edge.id]
		var low:=INF; var high:=-INF
		for p in points: low=minf(low,p.y); high=maxf(high,p.y)
		paths.append({"points":points,"radius":maxf(edge.width_start,edge.width_end)*.5,"low":low-.5,"high":high+3})
	var records: Array=[]; var placements: Array=[]; var used: Array=[]; var points: Array[Vector2]=[]
	var skipped:={"boundary":0,"unsupported":0,"occupied":0,"road":0,"spacing":0,"floor":0}
	var attempts:=0; var checks:=0
	for candidate in Scatter.candidates(settings):
		if records.size()>=settings.count: break
		attempts+=1
		var asset: Dictionary=assets[candidate.asset]; var scale_: float=candidate.scale
		var basis:=Basis(Vector3.UP,deg_to_rad(candidate.yaw))
		var local_center:=Data.vec(asset.bounds_position)+Data.vec(asset.bounds_size)*.5
		var centered:=basis*Vector3(local_center.x,0,local_center.z)*scale_
		var position:=Vector3(candidate.point.x,settings.height-float(asset.bounds_position[1])*scale_,candidate.point.y)-centered
		var record:={"uuid":"vegetation_"+settings.id.sha256_text().left(16)+"_"+str(candidate.slot),"kind":"asset","surface_id":"model","asset_path":asset.asset_path,"label":asset.label,"category":asset.get("category",""),"bounds_position":asset.bounds_position,"bounds_size":asset.bounds_size,"position":Data.xyz(position),"rotation":[0,candidate.yaw,0],"size":[scale_,scale_,scale_],"collision":"block" if settings.collision else "none"}
		var shape:=Foot.record_shape(record)
		if not Scatter.inside(shape.polygon,allowed): skipped.boundary+=1; continue
		if not Scatter.inside(shape.polygon,supports): skipped.unsupported+=1; continue
		if not editor._authoring.Settings.contains(record,editor._authoring.settings): skipped.floor+=1; continue
		var blocked:=false
		for point in points:
			if point.distance_to(candidate.point)<settings.spacing: blocked=true; break
		if blocked or Foot.batches_overlap([shape],used): skipped.spacing+=1; continue
		for path in paths:
			if shape.bounds.end.y<=path.low or shape.bounds.position.y>=path.high: continue
			checks+=path.points.size()
			if checks>2000000: return Data.fail("散布道路检查超过预算，请缩小区域或减少目标数量")
			if Street.intersects_road([shape],path.points,path.radius): blocked=true; break
		if blocked: skipped.road+=1; continue
		for obstacle in obstacles:
			checks+=1
			if checks>2000000: return Data.fail("散布碰撞检查超过预算，请缩小区域或减少目标数量")
			if Foot.overlaps(shape,obstacle): blocked=true; break
		if blocked: skipped.occupied+=1; continue
		if editor._doc.has_uuid(record.uuid) and not ownership.ids.has(record.uuid): return Data.fail("生成物件 ID 被独立物件占用，请使用新的区域 ID")
		records.append(record); used.append(shape); points.append(candidate.point)
		placements.append({"id":record.uuid,"asset_id":asset.asset_path,"position":record.position,"rotation":record.rotation,"scale":scale_,"polygon":Array(shape.polygon).slice(0,shape.polygon.size()-1).map(func(p):return [p.x,p.y])})
	if editor._doc.records.size()-ownership.ids.size()+records.size()>100000: return Data.fail("生成后超过地图物件上限")
	var manifest:={"version":1,"settings":settings,"parts":records.map(func(r):return {"id":r.uuid,"signature":Data.token(r)})}
	return {"ok":true,"settings":settings,"count":records.size(),"requested":settings.count,"shortfall":settings.count-records.size(),"attempts":attempts,"skipped":skipped,"placements":placements,"records":records,"manifest":manifest,"excluded":ownership.ids,"plan_token":token}

func summary(args: Dictionary) -> Dictionary:
	var result:=prepare(args)
	for key in ["records","manifest","excluded"]: result.erase(key)
	return result
func generate(args: Dictionary) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var result:=prepare(args)
	if not result.ok: return result
	var data:=Data.resolve(editor._doc.map_meta); var list: Array=data.get("vegetation",[]).duplicate(true); var previous: Dictionary={}
	for region in list:
		if region.settings.id==args.id: previous=region
	if Data.token(previous)==Data.token(result.manifest): return {"ok":true,"changed":false,"count":result.count,"ids":result.records.map(func(r):return r.uuid)}
	list=list.filter(func(r):return r.settings.id!=args.id); list.append(result.manifest); data.vegetation=list
	if not Data.valid({"editor_layout":data}): return Data.fail("植被散布记录无效")
	editor._doc.checkpoint_recovery()
	editor._doc.records=editor._doc.records.filter(func(r):return not result.excluded.has(r.uuid))
	editor._doc.records.append_array(result.records); editor._doc.map_meta.editor_layout=data
	editor._dirty=true; overlay_plan={}; editor._rebuild()
	return {"ok":true,"changed":true,"count":result.count,"shortfall":result.shortfall,"ids":result.records.map(func(r):return r.uuid)}
func remove(id: String, keep_objects: bool) -> Dictionary:
	var ready: Dictionary=editor._city.guard()
	if not ready.ok: return ready
	var old: Dictionary={}; var data:=Data.resolve(editor._doc.map_meta)
	for region in regions():
		if region.settings.id==id: old=region
	if old.is_empty(): return Data.fail("散布区域不存在")
	var ownership:=owned(old,not keep_objects)
	if not ownership.ok: return ownership
	editor._doc.checkpoint_recovery()
	if not keep_objects: editor._doc.records=editor._doc.records.filter(func(r):return not ownership.ids.has(r.uuid))
	data.vegetation=regions().filter(func(r):return r.settings.id!=id); editor._doc.map_meta.editor_layout=data
	editor._dirty=true; overlay_plan={}; editor._rebuild()
	return {"ok":true,"kept_objects":keep_objects}
