extends RefCounted
const T=preload("res://scripts/world3d/terrain_surface.gd")
const W=preload("res://scripts/world3d/waterway_data.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const Road=preload("res://scripts/world3d/road_plan.gd")
const Layer=preload("res://scripts/world3d/terrain_river_layer.gd")
const Profile=preload("res://scripts/world3d/terrain_river_profile.gd")
const Outlet=preload("res://scripts/world3d/terrain_river_outlet.gd")
const Batch=preload("res://scripts/world3d/terrain_stroke_batch.gd")
static func schema()->Dictionary:
	return Layer.request_schema()
static func defaults()->Dictionary:
	return {"id":"natural_river","width":8.,"bank_width":4.,"water_level":-1.,"depth":2.,"curved":true,"natural_materials":true}
static func distance(p:Vector2,path:Array)->float:
	var best:=INF
	for i in path.size()-1:
		var a:=Vector2(path[i][0],path[i][1]);var b:=Vector2(path[i+1][0],path[i+1][1]);var d:=b-a
		best=minf(best,p.distance_to(a+d*clampf((p-a).dot(d)/maxf(.000001,d.length_squared()),0,1)))
	return best
static func build(editor:Node3D,args:Dictionary,records:Array)->Dictionary:
	var indexed:Dictionary={}
	for r:Dictionary in records:indexed[r.uuid]=r
	var guard:Dictionary=editor._gameplay.guard()
	if not guard.ok:return guard
	var error:=T.S.validate(args,schema())
	if not error.is_empty():return T.fail(error)
	if not str(args.id).is_valid_identifier():return T.fail("河道 ID 无效")
	var prefix:="river_"+str(args.id)+"_"
	if records.any(func(r):return str(r.uuid).begins_with(prefix)):return T.fail("发现同名未关联水面，请先改用其他 ID")
	var curve:=Profile.prepare(args)
	if not curve.ok:return curve
	var path:Array=curve.path;var half:float=args.get("width",8.)*.5;var bank:float=args.get("bank_width",4.);var level:float=args.water_level;var depth:float=args.get("depth",2.)
	var terrain_ids:Array=args.terrain_ids.duplicate();var entries:Array=[];var seen:Dictionary={};var work:=0;var touched:Dictionary={}
	# Include compatible neighbors within the carving radius before changing any
	# sample. Both copies of a shared edge must use the same world-space recipe.
	for id:String in args.terrain_ids:
		var seed:Dictionary=indexed.get(id,{})
		if not seed.has("terrain_mesh"):return T.fail("地形不存在")
		for neighbor:Dictionary in preload("res://scripts/world3d/terrain_stroke_batch.gd").connected(records,seed):
			if neighbor.uuid in terrain_ids:continue
			var near:=false;var pose:=T.transform(neighbor)
			for z in int(neighbor.terrain_mesh.rows)+1:
				for x in int(neighbor.terrain_mesh.columns)+1:
					if x>0 and z>0 and x<int(neighbor.terrain_mesh.columns) and z<int(neighbor.terrain_mesh.rows):continue
					var p:=pose*T.point(neighbor,x,z)
					if distance(Vector2(p.x,p.z),path)<=half+bank:near=true;break
				if near:break
			if near:terrain_ids.append(neighbor.uuid)
	if terrain_ids.size()>64:return T.fail("河道最多同时修改 64 块地形，请分段生成")
	for id:String in terrain_ids:
		if seen.has(id):return T.fail("地形 ID 重复")
		seen[id]=true
		var previous:Dictionary=indexed.get(id,{})
		if not previous.has("terrain_mesh") or not editor._record_editable(previous) or previous.has("surface_paint"):return T.fail("请选择可编辑且无手刷面的高度地形")
		if absf(previous.rotation[0])+absf(previous.rotation[2])>.0001:return T.fail("河床地形不能沿 X/Z 倾斜")
		var next:=previous.duplicate(true);var data:Dictionary=next.terrain_mesh;var pose:=T.transform(next);var cells:Dictionary={}
		touched[id]={}
		work+=(int(data.rows)+1)*(int(data.columns)+1)*path.size()
		if work>4000000:return T.fail("河床采样超过单次预算，请缩短中心线或分段生成")
		for z in int(data.rows)+1:
			for x in int(data.columns)+1:
				var at:=z*(int(data.columns)+1)+x;var p:Vector3=pose*T.point(next,x,z);var station:=Profile.sample(Vector2(p.x,p.z),path,curve.levels);var d:float=station.distance
				if d>half+bank:continue
				# Equal-height samples can still depend on another river's bed.
				# Track the whole footprint, not only numerically changed heights.
				touched[id][at]=true
				var local_level:float=station.level
				var target:float=local_level-depth
				if d>half*.55:
					var blend:=smoothstep(half*.55,half+bank,d)
					target=lerpf(local_level-depth,p.y,blend)
				var y:float=(minf(p.y,target)-next.position[1])/next.size[1]
				if is_equal_approx(y,data.heights[at]):continue
				data.heights[at]=y
				for dz in [z-1,z]:
					for dx in [x-1,x]:
						if dx>=0 and dz>=0 and dx<int(data.columns) and dz<int(data.rows):cells[dz*int(data.columns)+dx]=true
		if not T.valid(next):return T.fail("河床低于地形底床，请减小深度")
		if not cells.is_empty():entries.append({"record":next,"cells":cells.keys()})
	for i in entries.size():
		for j in range(i+1,entries.size()):
			var a:Dictionary=indexed[entries[i].record.uuid];var b:Dictionary=indexed[entries[j].record.uuid]
			var batch=preload("res://scripts/world3d/terrain_stroke_batch.gd")
			if batch.adjacent(a,b):
				var joined:Dictionary=batch.join_edges(a,b,entries[i].record,entries[j].record)
				if not joined.ok:return joined
	# Validate the completed result against all adjacent terrains, including a
	# coarse neighbour whose grid missed the narrow carving footprint entirely.
	# Sequential joins must not leave a previously continuous T junction split.
	var joined_records:Dictionary={}
	for entry:Dictionary in entries:
		joined_records[entry.record.uuid]=entry.record
		var original:Dictionary=indexed[entry.record.uuid]
		for at in entry.record.terrain_mesh.heights.size():
			if not Layer.same(original.terrain_mesh.heights[at],entry.record.terrain_mesh.heights[at]):touched[entry.record.uuid][at]=true
	for entry:Dictionary in entries:
		var original:Dictionary=indexed[entry.record.uuid]
		for neighbor:Dictionary in records:
			if neighbor.uuid==original.uuid or not neighbor.has("terrain_mesh") or not Batch.adjacent(original,neighbor):continue
			var joined:=Batch.validate_edge_continuity(original,neighbor,entry.record,joined_records.get(neighbor.uuid,neighbor))
			if not joined.ok:return joined
	# Mitered ribbon has shared banks and rejects folds before any edit.
	var left:Array=[];var right:Array=[]
	for i in path.size():
		var p:=Vector2(path[i][0],path[i][1]);var before:=Vector2(path[maxi(0,i-1)][0],path[maxi(0,i-1)][1]);var after:=Vector2(path[mini(i+1,path.size()-1)][0],path[mini(i+1,path.size()-1)][1])
		var d:Vector2=(after-before).normalized();var normal:=Vector2(-d.y,d.x)
		left.append(p-normal*half);right.append(p+normal*half)
	var water:Array=[];var bins:Dictionary={};var height_bins:Dictionary={};var changed:Dictionary={}
	for entry:Dictionary in entries:changed[entry.record.uuid]=entry.record
	var terrains:Array=terrain_ids.map(func(id):return changed.get(id,indexed.get(id,{})))
	# Adapt the horizontal water footprint to the shared projection budget.
	# Fine editable banks must not require lowering terrain detail to fit water.
	var water_cell:=32.0
	for terrain:Dictionary in terrains:
		water_cell=minf(water_cell,8.0*minf(float(terrain.size[0])/terrain.terrain_mesh.columns,float(terrain.size[2])/terrain.terrain_mesh.rows))
	water_cell=maxf(2.0,water_cell)
	for i in path.size()-1:
		var polygon:Array=[left[i],left[i+1],right[i+1],right[i]]
		var polygon_levels:Array=[curve.levels[i],curve.levels[i+1],curve.levels[i+1],curve.levels[i]]
		if Geometry2D.is_polygon_clockwise(PackedVector2Array(polygon)):polygon.reverse();polygon_levels.reverse()
		for j in polygon.size():
			if (polygon[(j+1)%4]-polygon[j]).cross(polygon[(j+2)%4]-polygon[(j+1)%4])<-.0001:return T.fail("河弯太急，岸线折回；请加大弯曲半径")
		for j in range(0,i-1):
			if Geometry2D.segment_intersects_segment(left[i],left[i+1],left[j],left[j+1])!=null or Geometry2D.segment_intersects_segment(right[i],right[i+1],right[j],right[j+1])!=null:return T.fail("河岸自交，请调整路径或宽度")
		var bounds:=Rect2(polygon[0],Vector2.ZERO)
		for p:Vector2 in polygon:bounds=bounds.expand(p)
		for z in range(floori(bounds.position.y/water_cell),floori(bounds.end.y/water_cell)+1):
			for x in range(floori(bounds.position.x/water_cell),floori(bounds.end.x/water_cell)+1):
				var pieces:Array=[[polygon[0],polygon[1],polygon[2]],[polygon[0],polygon[2],polygon[3]]] if curve.profile else [polygon]
				for piece_index in pieces.size():
					var clipped:=Road.intersection(pieces[piece_index],Poly.rect([x*water_cell,z*water_cell,(x+1)*water_cell,(z+1)*water_cell]))
					if clipped.size()<3 or Poly.area(clipped)<.00001:continue
					var key:=Vector2i(x,z)
					if not bins.has(key):bins[key]=[];height_bins[key]=[]
					bins[key].append(clipped)
					if curve.profile:
						var vertex_levels:Array=[polygon_levels[0],polygon_levels[1],polygon_levels[2]] if piece_index==0 else [polygon_levels[0],polygon_levels[2],polygon_levels[3]]
						var heights:Array=[]
						for point:Vector2 in clipped:heights.append(Profile.triangle_level(point,pieces[piece_index],vertex_levels))
						height_bins[key].append(heights)
	for key:Vector2i in bins:
		var center:=Vector3((key.x+.5)*water_cell,level-.01,(key.y+.5)*water_cell);var polys:Array=[]
		for polygon:Array in bins[key]:polys.append(polygon.map(func(p):return [(p.x-center.x)/water_cell,(p.y-center.z)/water_cell]))
		var r:Dictionary={"uuid":prefix+str(water.size()),"kind":"box","position":[center.x,center.y,center.z],"rotation":[0,0,0],"size":[water_cell,.02,water_cell],"surface_id":"water","collision":"none","color":[.13,.27,.31],"editor_group":prefix,"editor_group_name":args.id,"channel_mesh":{"polygons":polys,"uv_origin":[center.x,center.y,center.z]},"water_depth_effect":{"absorption":.9,"shallow_color":[.13,.27,.31],"deep_color":[.055,.14,.205]}}
		if curve.profile:
			var elevations:Array=[]
			for heights:Array in height_bins[key]:elevations.append(heights.map(func(y):return float(y)-center.y))
			r.channel_mesh.elevations=elevations
		var coverage:=preload("res://scripts/world3d/terrain_projection.gd").fit(r,terrains,0,100.)
		if not coverage.ok:return T.fail("河流水面地形校验失败："+str(coverage.get("error","不能跨过洞口或边缘")))
		if not preload("res://scripts/world3d/channel_surface.gd").valid(r):return T.fail("河段过长或采样过密，请拆分中心线")
		if not editor._authoring.Settings.contains(r,editor._authoring.settings):return T.fail("河流水面超出当前楼层")
		if preload("res://scripts/world_editor/building_footprint.gd").batches_overlap(preload("res://scripts/world_editor/building_footprint.gd").record_shapes(r),preload("res://scripts/world3d/planning_zones.gd").obstacles(editor._doc.map_meta)):return T.fail("河流侵入保留区或保留通道")
		water.append(r)
	if water.is_empty() or entries.is_empty():return T.fail("路径未挖出可用河床")
	if records.size()+water.size()>100000:return T.fail("河道生成后超过地图物件上限")
	# Native river material preparation shares the same PBR validation as the UI.
	if args.get("natural_materials",true):
		var all:Array=entries.map(func(e):return e.record)+water
		for r:Dictionary in all:r.erase("terrain_slope_blend")
		var appearance:=preload("res://scripts/world_editor/river_material_tools.gd").prepare(all,{"terrain_ids":entries.map(func(e):return e.record.uuid),"water_ids":water.map(func(r):return r.uuid),"water_level":level,"sand_material_id":"pack:default:terrain/natural_sand/material","rock_material_id":"pack:default:terrain/icelandic_jagged_slate/material"},editor._material_tool.library,func(_r):return true)
		if not appearance.ok:return appearance
		for replacement:Dictionary in appearance.records:
			for entry:Dictionary in entries:
				if entry.record.uuid==replacement.uuid:entry.record=replacement
			for i in water.size():
				if water[i].uuid==replacement.uuid:water[i]=replacement
	return {"ok":true,"entries":entries,"water":water,"samples":path.size(),"touched":touched}

static func ownership_conflict(result:Dictionary,layers:Array,args:Dictionary)->String:
	for layer:Dictionary in layers:
		if layer.id==args.id:continue
		for item:Dictionary in layer.terrains:
			var id:String=item.after.uuid
			if not result.touched.has(id):continue
			for at in result.touched[id]:
				if not Layer.same(item.before.terrain_mesh.heights[at],item.after.terrain_mesh.heights[at]) and not Outlet.allows(result.get("outlet",{}),layer.id,item.after,at):return "河床采样已属于河道 "+layer.id+"；请修改同一河道的中心线或避开已有河床"
			# Appearance is stored once per terrain, not once per channel. Two
			# layers may not independently restore the same material, even when
			# their generated values happen to be identical.
			if args.get("natural_materials",true) and result.entries.any(func(e):return e.record.uuid==id):
				for field:String in Layer.APPEARANCE_FIELDS:
					if not Layer.same(item.before.get(field),item.after.get(field)):return "地形河岸材质已属于河道 "+layer.id+"；请沿用该河道或关闭新河道的自然材质"
	return ""

static func restoration_conflict(editor:Node3D,owner:String,layers:Array,restored:Dictionary)->String:
	# Older maps may already contain layers whose identical-height overlap did
	# not record a delta in the later river. Refuse to remove the earlier bed
	# while that later river still relies on it; removing the later layer first
	# remains possible without inventing missing history.
	for layer:Dictionary in layers:
		if layer.id==owner:continue
		var used:Array=layer.request.terrain_ids+layer.terrains.map(func(item):return item.after.uuid)
		var curve:Dictionary={}
		for id:String in restored:
			if id not in used:continue
			var current:Dictionary=editor._doc._find(id);var next:Dictionary=restored[id]
			var expected:Dictionary=current
			for item:Dictionary in layer.terrains:
				if item.after.uuid==id:expected=item.after;break
			if layer.request.get("natural_materials",true):
				for field:String in Layer.APPEARANCE_FIELDS:
					if not Layer.same(current.get(field),next.get(field)) and not Layer.same(expected.get(field),next.get(field)):return "河道 "+layer.id+" 仍依赖此河岸材质，请先移除后建河道"
			if curve.is_empty():
				curve=preload("res://scripts/world3d/spline_route.gd").sample(layer.request.points,2.,false,.5 if layer.request.get("curved",true) else 0.)
				if not curve.ok:return "已有河道中心线数据无效"
			var radius:float=layer.request.get("width",8.)*.5+layer.request.get("bank_width",4.)
			var pose:=T.transform(current);var stride:=int(current.terrain_mesh.columns)+1
			for at in current.terrain_mesh.heights.size():
				if Layer.same(current.terrain_mesh.heights[at],next.terrain_mesh.heights[at]):continue
				if Layer.same(expected.terrain_mesh.heights[at],next.terrain_mesh.heights[at]):continue
				var p:=pose*T.point(current,at%stride,at/stride)
				if distance(Vector2(p.x,p.z),curve.points)<=radius:return "河道 "+layer.id+" 仍依赖此河床，请先移除后建河道"
	return ""

static func catalog(editor:Node3D)->Dictionary:
	if not Layer.valid(editor._doc.map_meta):return {"ok":false,"error":"河道恢复图层无效","rivers":[]}
	return {"ok":true,"rivers":editor._doc.map_meta.get("terrain_rivers",[]).map(func(layer):return layer.request.duplicate(true))}

static func apply(editor:Node3D,args:Dictionary,preview:=false,remove:=false)->Dictionary:
	var guard:Dictionary=editor._gameplay.guard()
	if not guard.ok:return guard
	var error:=T.S.validate(args,W.obj({"id":W.text(80)},["id"]) if remove else schema())
	if not error.is_empty():return T.fail(error)
	if not str(args.id).is_valid_identifier():return T.fail("河道 ID 无效")
	if not Layer.valid(editor._doc.map_meta):return T.fail("河道恢复图层无效")
	var layers:Array=editor._doc.map_meta.get("terrain_rivers",[]).duplicate(true);var old:Dictionary={}
	for layer:Dictionary in layers:
		if layer.id==args.get("id",""):old=layer
	if remove and old.is_empty():return T.fail("河道不存在或旧河道没有恢复图层")
	if old.is_empty() and layers.size()>=64:return T.fail("河道图层最多 64 组")
	var dependent:=Outlet.dependency_error(str(args.id),layers)
	if not dependent.is_empty():return T.fail(dependent)
	var records:Array=editor._doc.records.duplicate(true);var water_ids:Array=[];var restored:Dictionary={}
	for part:Dictionary in old.get("water",[]):
		var current:Dictionary=editor._doc._find(part.id)
		if not editor._record_editable(current) or preload("res://scripts/world3d/city_layout.gd").token(current)!=part.signature:return T.fail("河道水面已锁定、隐藏、删除或手改")
		water_ids.append(part.id)
	records=records.filter(func(r):return r.uuid not in water_ids)
	for item:Dictionary in old.get("terrains",[]):
		var current:Dictionary=editor._doc._find(item.after.uuid)
		if not current.has("terrain_mesh") or not editor._record_editable(current):return T.fail("河道地形已删除、锁定或隐藏")
		var recovered:=preload("res://scripts/world3d/terrain_river_layer.gd").restore(current,item.before,item.after)
		if not recovered.ok:return recovered
		if editor._doc.validate_save_record(recovered.record)!=OK or not T.Paint.missing([recovered.record]).is_empty():return T.fail("河道恢复数据或材质依赖无效")
		for i in records.size():
			if records[i].uuid==current.uuid:records[i]=recovered.record
		restored[current.uuid]=recovered.record
	var dependency:=restoration_conflict(editor,str(args.id),layers,restored)
	if not dependency.is_empty():return T.fail(dependency)
	var outlet:Dictionary={"ok":true,"enabled":false} if remove else Outlet.prepare(editor,args,layers,records)
	if not outlet.ok:return outlet
	var result:Dictionary={"ok":true,"entries":[],"water":[],"samples":0} if remove else build(editor,args,records)
	if not result.ok:return result
	if not remove:
		result=Outlet.clip_water(result,outlet)
		if not result.ok:return result
		var conflict:=ownership_conflict(result,layers,args)
		if not conflict.is_empty():return T.fail(conflict)
	var next_layer:Dictionary={"version":1,"id":args.id,"request":args.duplicate(true),"terrains":[],"water":[]}
	for entry:Dictionary in result.entries:
		var before:Dictionary=records.filter(func(r):return r.uuid==entry.record.uuid)[0]
		next_layer.terrains.append({"before":before.duplicate(true),"after":entry.record.duplicate(true)})
		restored[entry.record.uuid]=entry.record
	var entries:Array=[]
	for next:Dictionary in restored.values():
		var previous:Dictionary=editor._doc._find(next.uuid);var cells:Array=[]
		for z in int(next.terrain_mesh.rows):
			for x in int(next.terrain_mesh.columns):
				if T.cell(previous,x,z)!=T.cell(next,x,z):cells.append(z*int(next.terrain_mesh.columns)+x)
		entries.append({"record":next,"cells":cells})
	var ids:Array=restored.keys()+water_ids
	ids.append_array(preload("res://scripts/world_editor/terrain_follow_tools.gd").affected(editor._doc.records,restored.keys()).map(func(r):return r.uuid))
	ids.append_array(preload("res://scripts/world_editor/terrain_follow_tools.gd").fort_ids(editor,entries))
	var bridge_contact_cache:Dictionary={}
	for entry:Dictionary in entries:
		var checked:Dictionary=editor._terrain.validate_change(editor._doc._find(entry.record.uuid),entry,ids,bridge_contact_cache)
		if not checked.ok:return checked
	var followed:=preload("res://scripts/world_editor/terrain_follow_tools.gd").prepare(editor,entries)
	if not followed.ok:return followed
	entries.append_array(followed.entries)
	for r:Dictionary in result.water:next_layer.water.append({"id":r.uuid,"signature":preload("res://scripts/world3d/city_layout.gd").token(r)})
	layers=layers.filter(func(layer):return layer.id!=args.id)
	if not remove:layers.append(next_layer)
	var metadata:Dictionary=followed.map_meta;metadata.terrain_rivers=layers
	if not preload("res://scripts/world3d/terrain_river_layer.gd").valid(metadata):return T.fail("河道恢复图层无效")
	if preview:return {"ok":true,"changed_terrains":restored.size(),"water_chunks":result.water.size(),"samples":result.samples,"updated":not old.is_empty()}
	editor._doc.checkpoint_recovery()
	editor._doc.records=editor._doc.records.filter(func(r):return r.uuid not in water_ids and r.uuid not in followed.get("removed",[]))
	for entry:Dictionary in entries:
		var previous:Dictionary=editor._doc._find(entry.record.uuid)
		if previous.is_empty():editor._doc.records.append(entry.record)
		else:editor._doc.records[editor._doc.records.find(previous)]=entry.record
		if entry.record.uuid not in ids:ids.append(entry.record.uuid)
	for r:Dictionary in result.water:editor._doc.records.append(r);ids.append(r.uuid)
	ids.append_array(followed.get("removed",[]))
	editor._doc.map_meta=metadata;editor._commit_records(ids)
	return {"ok":true,"ids":ids,"water_ids":result.water.map(func(r):return r.uuid),"samples":result.samples,"updated":not old.is_empty(),"removed":remove}
