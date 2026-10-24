extends RefCounted
## Explicit tributary dependencies. Only a declared terminal mouth may share
## another river's bed; the receiving water remains the sole surface owner.
const T=preload("res://scripts/world3d/terrain_surface.gd")
const Profile=preload("res://scripts/world3d/terrain_river_profile.gd")
const Channel=preload("res://scripts/world3d/channel_surface.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const City=preload("res://scripts/world3d/layout_identity.gd")

static func valid_links(meta:Dictionary)->bool:
	var by_id:Dictionary={}
	for layer:Dictionary in meta.get("terrain_rivers",[]):by_id[layer.id]=layer
	for layer:Dictionary in by_id.values():
		var seen:Dictionary={};var current:Dictionary=layer
		while current.request.has("outlet"):
			var target:String=current.request.outlet.river_id
			if target==current.id or seen.has(target) or not by_id.has(target):return false
			seen[target]=true;current=by_id[target]
	return true

static func dependency_error(id:String,layers:Array)->String:
	for layer:Dictionary in layers:
		if layer.request.get("outlet",{}).get("river_id","")==id:return "河道 "+layer.id+" 仍汇入此河道，请先移除或改接支流"
	return ""

static func bounds(poly:Array)->Rect2:
	var result:=Rect2(poly[0],Vector2.ZERO)
	for p:Vector2 in poly:result=result.expand(p)
	return result

static func prepare(editor:Node3D,args:Dictionary,layers:Array,records:Array)->Dictionary:
	if not args.has("outlet"):return {"ok":true,"enabled":false}
	var target_id:String=args.outlet.river_id;var target:Dictionary={}
	if target_id==args.id:return T.fail("支流不能汇入自身")
	for layer:Dictionary in layers:
		if layer.id==target_id:target=layer
	if target.is_empty():return T.fail("汇入目标河道不存在")
	# Validate the proposed graph before any restored bed or water is committed.
	var proposed:Array=layers.filter(func(layer):return layer.id!=args.id)
	proposed.append({"id":args.id,"request":args})
	if not valid_links({"terrain_rivers":proposed}):return T.fail("河道汇流关系不能形成循环")
	var source:=Profile.prepare(args);var receiver:=Profile.prepare(target.request)
	if not source.ok:return source
	if not receiver.ok:return receiver
	var end:=Vector2(source.path.back()[0],source.path.back()[1])
	var half:float=target.request.get("width",8.)*.5
	var source_half:float=args.get("width",8.)*.5
	var mouth:=Profile.sample(end,receiver.path,receiver.levels)
	if mouth.distance>half*.25:return T.fail("支流末端必须进入目标河道中心区域")
	var level:float=mouth.level
	if absf(float(source.levels.back())-level)>.0001:return T.fail("汇流口两侧水位必须一致")
	var overlap_radius:float=half+source_half
	var radius:float=overlap_radius+target.request.get("bank_width",4.)+args.get("bank_width",4.)
	var tangent:=Vector2(receiver.path[mouth.segment+1][0]-receiver.path[mouth.segment][0],receiver.path[mouth.segment+1][1]-receiver.path[mouth.segment][1]).normalized()
	var approach:=(end-Vector2(source.path[source.path.size()-2][0],source.path[source.path.size()-2][1])).normalized()
	if absf(tangent.dot(approach))>.9:return T.fail("支流应从岸侧汇入，不能沿目标河道重复铺水")
	var entered:=false;var outside:=false
	for i in source.path.size():
		var p:=Vector2(source.path[i][0],source.path[i][1]);var station:=Profile.sample(p,receiver.path,receiver.levels)
		if station.distance<=radius:
			if p.distance_to(end)>radius+2.:return T.fail("支流只能在末端汇流口共享目标河床")
		if station.distance<=overlap_radius:
			entered=true
			if absf(float(source.levels[i])-level)>.0001 or absf(float(station.level)-level)>.0001:return T.fail("汇流重叠范围须先降至相同的平缓水位")
		else:
			if entered:return T.fail("支流不能穿出目标河道后再次汇入")
			outside=true
	if not outside:return T.fail("支流必须具有目标河道外的独立来水段")
	var indexed:Dictionary={}
	for record:Dictionary in records:indexed[record.uuid]=record
	# A declared mouth permits a new owned delta, never adoption of hand edits.
	# Check only the receiving river's changed samples at this mouth: another
	# legitimate tributary elsewhere must not prevent an independent junction.
	for item:Dictionary in target.terrains:
		var current:Dictionary=indexed.get(item.after.uuid,{})
		if current.is_empty():return T.fail("目标河道河床已删除")
		var stride:=int(item.after.terrain_mesh.columns)+1
		for at in item.after.terrain_mesh.heights.size():
			var before:float=item.before.terrain_mesh.heights[at];var after:float=item.after.terrain_mesh.heights[at]
			if absf(before-after)<.00000001:continue
			var p:=T.transform(item.after)*T.point(item.after,at%stride,at/stride)
			if Vector2(p.x,p.z).distance_to(end)>radius+.0001:continue
			if not editor._record_editable(current) or not current.has("terrain_mesh") or current.position!=item.after.position or current.rotation!=item.after.rotation or current.size!=item.after.size:return T.fail("目标汇流口河床已锁定、隐藏或改变变换")
			if current.terrain_mesh.columns!=item.after.terrain_mesh.columns or current.terrain_mesh.rows!=item.after.terrain_mesh.rows or current.terrain_mesh.heights.size()!=item.after.terrain_mesh.heights.size():return T.fail("目标汇流口地形网格已改变")
			if absf(float(current.terrain_mesh.heights[at])-after)>=.00000001:return T.fail("目标汇流口所属河床采样已手改或被其他支流使用")
	var masks:Array=[]
	for part:Dictionary in target.water:
		var record:Dictionary=indexed.get(part.id,{})
		if record.is_empty() or not editor._record_editable(record) or City.token(record)!=part.signature:return T.fail("目标河道水面已锁定、隐藏、删除或手改")
		var pose:=T.transform(record)
		for local:Array in Channel.local_polygons(record):
			var poly:Array=[];var heights:Array=[]
			for point:Vector3 in local:
				var p:=pose*point;poly.append(Vector2(p.x,p.z));heights.append(p.y)
			var box:=bounds(poly)
			if not box.grow(radius).has_point(end):continue
			if heights.any(func(y):return absf(float(y)-level)>.0001):return T.fail("接收河道的汇流口水面必须等高")
			if Geometry2D.is_polygon_clockwise(PackedVector2Array(poly)):poly.reverse()
			masks.append({"polygon":poly,"bounds":box})
	if masks.is_empty():return T.fail("汇流口未找到目标河道的实际水面")
	return {"ok":true,"enabled":true,"target_id":target_id,"end":end,"radius":radius,"level":level,"masks":masks}

static func allows(context:Dictionary,layer_id:String,record:Dictionary,at:int)->bool:
	if not context.get("enabled",false) or context.target_id!=layer_id:return false
	var stride:=int(record.terrain_mesh.columns)+1
	var p:=T.transform(record)*T.point(record,at%stride,at/stride)
	return Vector2(p.x,p.z).distance_to(context.end)<=float(context.radius)+.0001

static func clip_water(result:Dictionary,context:Dictionary)->Dictionary:
	if not context.get("enabled",false):return result
	var water:Array=[];var work:=0;var removed_area:=0.
	for record:Dictionary in result.water:
		var next:=record.duplicate(true);var polys:Array=[];var levels:Array=[]
		var pose:=T.transform(record);var inverse:=pose.affine_inverse()
		for local:Array in Channel.local_polygons(record):
			var polygon:Array=[];var heights:Array=[]
			for p:Vector3 in local:
				var world:=pose*p;polygon.append(Vector2(world.x,world.z));heights.append(world.y)
			var triangle:Array=[];var triangle_levels:Array=[]
			for i in range(1,polygon.size()-1):
				if absf((polygon[i]-polygon[0]).cross(polygon[i+1]-polygon[0]))>.000001:
					triangle=[polygon[0],polygon[i],polygon[i+1]];triangle_levels=[heights[0],heights[i],heights[i+1]];break
			if triangle.is_empty():return T.fail("汇流口水面退化")
			var fragments:Array=[polygon];var box:=bounds(polygon)
			for mask:Dictionary in context.masks:
				if not box.intersects(mask.bounds,true):continue
				var clipped:Array=[]
				for fragment:Array in fragments:
					work+=fragment.size()*mask.polygon.size()
					if work>1000000:return T.fail("汇流裁切超过预算，请简化河口")
					clipped.append_array(Poly.subtract(fragment,mask.polygon))
				fragments=clipped
				if fragments.size()>512:return T.fail("汇流裁切过密，请简化河口")
			var remaining:=0.
			for fragment:Array in fragments:
				if Poly.area(fragment)<.00001:continue
				remaining+=Poly.area(fragment)
				var raw:Array=[];var elevation:Array=[]
				for p:Vector2 in fragment:
					var local_point:=inverse*Vector3(p.x,Profile.triangle_level(p,triangle,triangle_levels),p.y)
					raw.append([local_point.x/record.size[0],local_point.z/record.size[2]]);elevation.append(local_point.y)
				polys.append(raw);levels.append(elevation)
			removed_area+=maxf(0,Poly.area(polygon)-remaining)
		if polys.is_empty():continue
		next.channel_mesh.polygons=polys;next.channel_mesh.elevations=levels
		if not Channel.valid(next):return T.fail("汇流裁切水面超出原生几何约束")
		water.append(next)
	if water.is_empty() or removed_area<.01:return T.fail("支流末端未与目标实际水面形成有效汇流")
	result.water=water;result.outlet=context
	return result
