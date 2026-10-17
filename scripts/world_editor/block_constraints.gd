extends RefCounted
## Planning reservations only. Manual placement and native collision rules remain independent.
const Data=preload("res://scripts/world3d/city_layout.gd")
const Blocks=preload("res://scripts/world3d/city_blocks.gd")
const Water=preload("res://scripts/world3d/waterway_plan.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const APPROACH:=10.0
const MAX_MASKS:=4096
const Support=preload("res://scripts/world_editor/residential_support.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")

static func mask(kind:String,id:String,polygon:Array,low:float,high:float,sources:Array)->Dictionary:
	return {"kind":kind,"id":id,"polygon":Blocks.serialize(polygon),"min_y":low,"max_y":high,"source_ids":sources}

static func corridor(kind:String,id:String,a:Vector3,b:Vector3,width:float,sources:Array)->Dictionary:
	var start:=Vector2(a.x,a.z);var finish:=Vector2(b.x,b.z)
	var side:=Vector2(-(finish-start).y,(finish-start).x).normalized()*width*.5
	return mask(kind,id,[start-side,finish-side,finish+side,start+side],minf(a.y,b.y)-.2,maxf(a.y,b.y)+3.,sources)

static func bridge_heads(rows:Array,id:String,a:Vector3,b:Vector3,width:float,sources:Array)->void:
	var direction:=Vector3(b.x-a.x,0,b.z-a.z).normalized()
	rows.append(corridor("bridge_access",id+"_start",a-direction*APPROACH,a,width,sources))
	rows.append(corridor("bridge_access",id+"_end",b,b+direction*APPROACH,width,sources))

static func collect(doc)->Dictionary:
	if not Data.valid(doc.map_meta):return Data.fail("街区规划源数据无效")
	var data:=Data.resolve(doc.map_meta);var rows:Array=[];var by_id:Dictionary={}
	for r:Dictionary in doc.records:by_id[r.uuid]=r
	for region:Dictionary in data.get("waterways",[]):
		var s:Dictionary=region.settings
		var points:Array=s.points.map(func(p):return Vector2(p[0],p[1]))
		var outer:=Water.outline(points,s.width*.5+s.bank_width)
		if outer.is_empty():return Data.fail("无法确定河道及岸线范围："+s.id)
		rows.append(mask("river",s.id,outer,-100000.,100000.,region.parts.map(func(p):return p.id)))
		for bridge:Dictionary in s.bridges:
			var port:=preload("res://scripts/world3d/road_bridges.gd").geometry(s,bridge)
			# Legacy flat bridges lack bridge_mesh; modern bridges are handled from their actual pose below.
			if bridge.get("prefab_id","legacy_flat")=="legacy_flat":
				# Legacy decks have no endpoint semantics. Trust their recipe only
				# while the actual deck geometry still matches; appearance edits are harmless.
				var deck:Dictionary=by_id.get(port.deck_id,{})
				var expected:=Water.slab(port.deck_id,Water.triangles(Water.bridge_polygon(points,bridge,s.width*.5+s.bank_width)),s.bank_height+.025,s.bank_height-.35,"bridge_deck",[])
				for field:String in ["kind","position","rotation","size","channel_mesh"]:
					if Data.token(deck.get(field))!=Data.token(expected.get(field)):return Data.fail("旧平桥几何缺失或已改动，无法可靠预留桥头："+str(port.deck_id))
				bridge_heads(rows,port.deck_id,Data.vec(port.endpoints[0]),Data.vec(port.endpoints[1]),bridge.width,port.part_ids)
	for layer:Dictionary in doc.map_meta.get("terrain_rivers",[]):
		var curve:=preload("res://scripts/world3d/terrain_river_profile.gd").prepare(layer.request)
		if not curve.ok:return curve
		var path:=PackedVector2Array(curve.path.map(func(p):return Vector2(p[0],p[1])))
		var radius:float=layer.request.get("width",8.)*.5+layer.request.get("bank_width",4.)
		var outlines:=Geometry2D.offset_polyline(path,radius,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND)
		if outlines.is_empty():return Data.fail("无法确定地形河流及岸坡范围："+str(layer.request.id))
		for i in outlines.size():rows.append(mask("river",str(layer.request.id)+"_"+str(i),Array(outlines[i]),-100000.,100000.,layer.request.terrain_ids))
	for r:Dictionary in doc.records:
		if not r.has("bridge_mesh"):continue
		var d:Dictionary=r.bridge_mesh
		var pose:=Transform3D(Basis.from_euler(Data.vec(r.rotation)*PI/180).scaled(Data.vec(r.size)),Data.vec(r.position))
		var a:Vector3=pose*Vector3(-d.length*.5,-d.get("rise",0.)*.5,0)
		var b:Vector3=pose*Vector3(d.length*.5,d.get("rise",0.)*.5,0)
		bridge_heads(rows,r.uuid,a,b,float(d.width)*pose.basis.z.length(),[r.uuid])
	for region:Dictionary in data.get("fortifications",[]):
		for gate:Dictionary in region.settings.gates:
			if gate.get("kind","land")!="land":continue
			var pivots:Array[Vector3]=[];var members:Array=[]
			for part:Dictionary in region.parts:
				var r:Dictionary=by_id.get(part.id,{})
				if r.get("fixture",{}).get("id","")!=gate.id:continue
				members.append(r)
				var pose:=Transform3D(Basis.from_euler(Data.vec(r.rotation)*PI/180),Data.vec(r.position))
				var pivot:Vector3=pose*Data.vec(r.fixture.pivot)
				if not pivots.any(func(p):return p.distance_to(pivot)<.001):pivots.append(pivot)
			if pivots.size()!=2:return Data.fail("城门实际门轴缺失或不唯一，无法预留通道："+str(gate.id))
			var center:Vector3=(pivots[0]+pivots[1])*.5
			var side:=Vector3(pivots[1].x-pivots[0].x,0,pivots[1].z-pivots[0].z)
			if side.length()<.1:return Data.fail("城门实际门轴退化："+str(gate.id))
			var normal:=Vector3(-side.z,0,side.x).normalized()
			var bounds:=Geometry.bounds(members);center.y=bounds.position.y
			var half:float=APPROACH+float(region.settings.thickness)*.5
			var entry:=corridor("gate_access",str(region.settings.id)+"/"+str(gate.id),center-normal*half,center+normal*half,side.length(),members.map(func(r):return r.uuid))
			entry.max_y=maxf(float(entry.max_y),bounds.end.y)
			rows.append(entry)
	if rows.size()>MAX_MASKS:return Data.fail("街区规划避让范围超过 4096 项，请分区处理")
	return {"ok":true,"reservations":rows,"approach_length":APPROACH}

static func conflict(polygon:Array,low:float,high:float,rows:Array)->Dictionary:
	var poly:=Blocks.unpack(polygon)
	for row:Dictionary in rows:
		if high<=float(row.min_y) or low>=float(row.max_y):continue
		if Blocks.overlaps(poly,Blocks.unpack(row.polygon)):return row
	return {}

static func flat_ground(doc,polygon:Array,level:float)->bool:
	# This planar generator requires continuous, same-height ground. Subtract
	# complete polygons, not a few corner samples; holes remain uncovered.
	var pending:Array=[Support.clean(polygon)];var work:=0
	if pending[0].is_empty():return false
	for r:Dictionary in doc.records:
		if r.get("kind")!="box" or r.has("building") or r.has("road_mesh") or r.has("terrain_volume") or r.get("collision","")=="none" or r.get("surface_id","") not in ["ground","grass","dirt","stone","sand"]:continue
		if absf(r.rotation[0])+absf(r.rotation[2])>.0001:continue
		for shape:Dictionary in Foot.record_shapes(r):
			var top:float=shape.get("top_max_y",shape.bounds.end.y);var bottom:float=shape.get("top_min_y",top)
			if absf(top-level)>.005 or absf(bottom-level)>.005:continue
			var cover:Array=[]
			for p:Vector2 in shape.polygon:cover.append([float(p.x),float(p.y)])
			cover=Support.clean(cover)
			var next:Array=[]
			for piece:Array in pending:
				work+=1
				if work>100000:return false
				next.append_array(Support.subtract(piece,cover))
			pending=next
			if pending.is_empty():return true
	return false
