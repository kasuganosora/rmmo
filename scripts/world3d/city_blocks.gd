extends RefCounted
## Bounded planar faces and conservative frontage rectangles. Unused space stays empty.
const Data=preload("res://scripts/world3d/city_layout.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const Street=preload("res://scripts/world_editor/building_street.gd")

static func settings_schema() -> Dictionary:
	return Data.object({"lot_width":Data.S.number(8,32),"lot_depth":Data.S.number(12,40),"setback":Data.S.number(.5,10),"gap":Data.S.number(.5,8),"style":Data.choice(["medieval","urban_village","standard"]),"seed":Data.S.number(0,2147483647,true),"max_buildings":Data.S.number(1,16,true)})
static func defaults() -> Dictionary:
	return {"lot_width":12.0,"lot_depth":18.0,"setback":2.0,"gap":1.5,"style":"medieval","seed":1,"max_buildings":8}
static func request_schema() -> Dictionary:
	var p:Dictionary=settings_schema().properties
	p.block_ids=Data.array(Data.text(80),64,1); p.plan_token=Data.text(64)
	return Data.object(p)
static func signed_area(poly: Array) -> float:
	var total:=0.0
	for i in range(1,poly.size()-1): total+=(poly[i]-poly[0]).cross(poly[i+1]-poly[0])
	return total*.5
static func serialize(poly: Array) -> Array:
	return poly.map(func(p): return [p.x,p.y])
static func unpack(poly: Array) -> Array:
	return poly.map(func(p): return Vector2(p[0],p[1]))

static func extract(graph: Dictionary) -> Dictionary:
	var checked:=Data.analyze(graph)
	if not checked.ok: return checked
	for warning in checked.diagnostics:
		if warning.code!="grade_separated_crossing": return Data.fail("请先拆分交叉点并解决道路诊断："+str(warning.code))
	var edges:={}; var adjacency:={}; var paths:={}
	for edge in graph.edges:
		if edge.kind!="ground": continue
		var path: Array=checked.paths[edge.id]
		for p in path:
			if absf(p.y-path[0].y)>.001: return Data.fail("街区划分暂只支持水平地面道路")
		edges[edge.id]=edge; paths[edge.id]=path
		for node in [edge.from,edge.to]:
			if not adjacency.has(node): adjacency[node]=[]
			adjacency[node].append(edge.id)
	# Remove graph bridges (including cul-de-sacs and links between disjoint cycles).
	var cyclic:={}
	for id in edges:
		var edge: Dictionary=edges[id]; var seen:={edge.from:true}; var queue: Array=[edge.from]; var cursor:=0
		while cursor<queue.size() and not seen.has(edge.to):
			var node: String=queue[cursor]; cursor+=1
			for candidate in adjacency[node]:
				if candidate==id: continue
				var e: Dictionary=edges[candidate]; var next: String=e.to if e.from==node else e.from
				if not seen.has(next): seen[next]=true; queue.append(next)
		if seen.has(edge.to): cyclic[id]=true
	var halves:={}; var outgoing:={}
	for id in cyclic:
		var edge: Dictionary=edges[id]
		for reverse in [false,true]:
			var path: Array=paths[id].duplicate(); var key: String=id+("/r" if reverse else "/f")
			if reverse: path.reverse()
			var from: String=edge.to if reverse else edge.from; var to: String=edge.from if reverse else edge.to
			var d: Vector3=path[1]-path[0]
			halves[key]={"edge":id,"from":from,"to":to,"path":path,"angle":atan2(d.z,d.x),"reverse":id+("/f" if reverse else "/r")}
			if not outgoing.has(from): outgoing[from]=[]
			outgoing[from].append(key)
	for node in outgoing: outgoing[node].sort_custom(func(a,b):return halves[a].angle<halves[b].angle)
	var visited:={}; var blocks: Array=[]; var keys:=halves.keys(); keys.sort()
	for start in keys:
		if visited.has(start): continue
		var key: String=start; var boundary: Array=[]; var polygon: Array=[]; var node_ids:={}; var simple:=true
		while not visited.has(key):
			visited[key]=true; boundary.append(key)
			var half: Dictionary=halves[key]
			if node_ids.has(half.from): simple=false
			node_ids[half.from]=true
			for p in half.path.slice(0,-1): polygon.append(Vector2(p.x,p.z))
			var row: Array=outgoing[half.to]; key=row[posmod(row.find(half.reverse)-1,row.size())]
		if key!=start or not simple or polygon.size()<3 or signed_area(polygon)<16: continue
		if polygon.size()>4096: return Data.fail("单街区轮廓过密，请简化曲线")
		# First visited half-edge is lexicographically smallest: stable under array reordering.
		var id: String="block_"+JSON.stringify(boundary).sha256_text().left(20)
		var frontage: Array=[]; var protected:=false
		for half_id in boundary:
			var half: Dictionary=halves[half_id]; var edge: Dictionary=edges[half.edge]
			frontage.append({"id":half_id.replace("/","_"),"edge_id":half.edge,"path":half.path.map(func(p):return Data.xyz(p)),"radius":maxf(edge.width_start,edge.width_end)*.5})
			protected=protected or edge.get("locked",false) or edge.get("hidden",false) or checked.nodes[half.from].get("locked",false) or checked.nodes[half.from].get("hidden",false)
		blocks.append({"id":id,"polygon":serialize(Poly.clean(polygon)),"height":halves[start].path[0].y,"area":signed_area(polygon),"frontages":frontage,"protected":protected})
	if blocks.size()>128: return Data.fail("街区超过 128 个，请分区规划")
	return {"ok":true,"blocks":blocks,"ignored_bridge_edges":graph.edges.size()-edges.size(),"open_edges":edges.size()-cyclic.size()}

static func inside(poly: Array, boundary: Array) -> bool:
	# Difference, rather than corners alone, catches concave notches through a lot.
	var outside:=Geometry2D.clip_polygons(PackedVector2Array(poly),PackedVector2Array(boundary))
	var area:=0.0
	for piece in outside: area+=Poly.area(Array(piece))
	return area<.001
static func overlaps(a: Array,b: Array) -> bool:
	for p in Geometry2D.intersect_polygons(PackedVector2Array(a),PackedVector2Array(b)):
		if Poly.area(Array(p))>.001: return true
	return false
static func point_on(path: Array, distance_: float) -> Dictionary:
	for i in path.size()-1:
		var length_: float=path[i].distance_to(path[i+1])
		if distance_<=length_ or i==path.size()-2:
			return {"point":path[i].lerp(path[i+1],clampf(distance_/length_,0,1)),"tangent":(path[i+1]-path[i]).normalized()}
		distance_-=length_
	return {}
static func source_token(block: Dictionary, settings: Dictionary) -> String:
	# Seed/style only change vacant houses; parcel geometry remains stable.
	return Data.token([block.polygon,block.frontages,settings.lot_width,settings.lot_depth,settings.setback,settings.gap])

static func lots(block: Dictionary, blocks: Array, graph: Dictionary, settings: Dictionary) -> Dictionary:
	var polygon:=unpack(block.polygon); var lots_: Array=[]; var skipped:=0; var occupied: Array=[]
	var nodes:={}
	for node in graph.nodes: nodes[node.id]=node
	var roads: Array=[]
	for edge in graph.edges:
		if edge.kind=="ground": roads.append({"path":Data.samples(edge,nodes),"radius":maxf(edge.width_start,edge.width_end)*.5})
	for front in block.frontages:
		var path: Array=front.path.map(func(p):return Vector2(p[0],p[2])); var length_:=0.0
		for i in path.size()-1: length_+=path[i].distance_to(path[i+1])
		var stride: float=settings.lot_width+settings.gap
		var count:=floori(length_/stride)
		if count>256: return Data.fail("单段临街地块超过 256 个，请拆分道路")
		for i in count:
			var sample:=point_on(path,(length_-count*stride)*.5+(i+.5)*stride)
			var t: Vector2=sample.tangent; var n:=Vector2(-t.y,t.x)
			var center: Vector2=sample.point+n*(front.radius+settings.setback)
			var a: Vector2=center-t*settings.lot_width*.5; var b: Vector2=center+t*settings.lot_width*.5
			var poly: Array=[a,b,b+n*settings.lot_depth,a+n*settings.lot_depth]
			var valid:=inside(poly,polygon)
			# Nested disconnected loops are holes in the enclosing district.
			for other in blocks:
				if other.id!=block.id and other.area<block.area and absf(other.height-block.height)<.001 and overlaps(poly,unpack(other.polygon)): valid=false; break
			if valid:
				for road in roads:
					if absf(road.path[0].y-block.height)>.001: continue
					var closed:=PackedVector2Array(poly); closed.append(poly[0])
					if Street.intersects_road([{"polygon":closed}],road.path,road.radius+.05): valid=false; break
			if valid:
				for previous in occupied:
					if overlaps(poly,previous): valid=false; break
			if not valid: skipped+=1; continue
			occupied.append(poly)
			lots_.append({"id":"lot_"+(block.id+front.id+"_"+str(i)).sha256_text().left(20),"block_id":block.id,"edge_id":front.edge_id,"polygon":serialize(poly),"position":[center.x,block.height,center.y],"yaw":rad_to_deg(atan2(-t.y,t.x)),"street":[sample.point.x,block.height,sample.point.y],"status":"vacant"})
			if lots_.size()>512: return Data.fail("单街区超过 512 地块，请分区")
	return {"ok":true,"lots":lots_,"skipped_corners":skipped}
