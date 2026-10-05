extends RefCounted
## Project town-wall rules, not universal historical dimensions.
const MIN_SPACING=50.0
const GATE_GAP=10.0
static func radius(s: Dictionary) -> float:
	if s.get("wall_access",false): return maxf(s.thickness*1.6,s.height*.6)
	return s.thickness*(1.0 if s.shape=="ellipse" else sqrt(2.0))
static func gates(s: Dictionary) -> Array:
	var out: Array=[]
	for g in s.gates:
		var p: Vector2
		if s.shape=="ellipse":
			var a:=deg_to_rad(g.angle)
			var delta:=asin(g.width*.5/Vector2(-s.radius_x*sin(a),s.radius_z*cos(a)).length())
			# Use the actual gate chord midpoint, as the ring geometry does.
			p=Vector2(s.center_x,s.center_z)+(Vector2(s.radius_x*cos(a),s.radius_z*sin(a))*cos(delta)).rotated(-deg_to_rad(s.rotation))
		else:
			var index:=int(g.segment); var next: int=(index+1)%s.points.size()
			p=Vector2(s.points[index][0],s.points[index][1]).lerp(Vector2(s.points[next][0],s.points[next][1]),g.t)
		out.append({"id":g.id,"center":p,"width":g.width})
	return out
static func zones(towers: Array,doors: Array,r: float) -> Array:
	var out: Array=[]
	for i in towers.size(): out.append({"kind":"tower_center_exclusion","id":"tower_%d"%i,"center":[towers[i].x,towers[i].y],"radius":MIN_SPACING})
	for door in doors: out.append({"kind":"tower_gate_exclusion","id":door.id,"center":[door.center.x,door.center.y],"radius":r+door.width*.5+GATE_GAP})
	return out
static func validate(towers: Array,doors: Array,r: float) -> Dictionary:
	var z:=zones(towers,doors,r)
	for i in towers.size():
		for j in range(i+1,towers.size()):
			var d: float=towers[i].distance_to(towers[j])
			if d<MIN_SPACING-.001: return {"ok":false,"error":"普通塔楼 %d / %d 中心距 %.1f 米，小于 50 米禁放距离；减少塔数、扩大范围或拉开路径节点"%[i+1,j+1,d],"layout_zones":z}
		for door in doors:
			var gap: float=towers[i].distance_to(door.center)-r-door.width*.5
			if gap<GATE_GAP-.001: return {"ok":false,"error":"塔楼 %d 距城门 %s 的保守净距 %.1f 米，小于 10 米；移动城门或塔楼（双塔门楼需独立配方）"%[i+1,door.id,gap],"layout_zones":z}
	return {"ok":true,"layout_zones":z}
static func cross_validate(towers: Array,doors: Array,r: float,other_towers: Array,other_doors: Array,other_r: float) -> Dictionary:
	for p in towers:
		for q in other_towers:
			if p.distance_to(q)<MIN_SPACING-.001: return {"ok":false,"error":"新塔楼进入已有城墙塔楼的 50 米禁放区；不能通过拆成多组绕过间距规则"}
		for g in other_doors:
			if p.distance_to(g.center)-r-g.width*.5<GATE_GAP-.001: return {"ok":false,"error":"新塔楼进入已有城门的 10 米净距保护区"}
	for p in other_towers:
		for g in doors:
			if p.distance_to(g.center)-other_r-g.width*.5<GATE_GAP-.001: return {"ok":false,"error":"新城门进入已有塔楼的 10 米净距保护区"}
	return {"ok":true}
static func record_centers(records: Array) -> Array:
	var out: Array=[]
	for r in records:
		if r.has("prefab_tower_center"):
			out.append(Vector2(r.prefab_tower_center[0],r.prefab_tower_center[1]));continue
		if r.get("fortification",{}).get("role","") in ["tower_stair","corner_tower"]: out.append(Vector2(r.position[0],r.position[2]))
	return out
