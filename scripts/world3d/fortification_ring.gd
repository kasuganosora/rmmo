extends RefCounted
## Sampled offset curves produce shared-edge convex slabs, never overlapping box chains.
const Data=preload("res://scripts/world3d/city_layout.gd")
const Channel=preload("res://scripts/world3d/channel_surface.gd")
var plan: RefCounted
var s: Dictionary
var center: Vector2
var radii: Vector2
var turn: float

func point(angle: float,offset:=0.0) -> Vector2:
	var p:=Vector2(radii.x*cos(angle),radii.y*sin(angle))
	var n:=Vector2(cos(angle)/radii.x,sin(angle)/radii.y).normalized()
	return center+(p+n*offset).rotated(turn)
func tangent(angle: float) -> Vector2: return Vector2(-radii.x*sin(angle),radii.y*cos(angle)).rotated(turn)
func slab(part: String,polygons: Array,bottom: float,top: float,role: String) -> void:
	var bounds:=Rect2(polygons[0][0],Vector2.ZERO)
	for poly in polygons:
		for p in poly: bounds=bounds.expand(p)
	var c:=bounds.get_center(); var size_:=Vector3(bounds.size.x,top-bottom,bounds.size.y)
	var r: Dictionary=plan.box(part,Vector3(c.x,(bottom+top)*.5,c.y),size_,0,role)
	r.channel_mesh={"uv_origin":r.position.duplicate(),"polygons":[]}
	for poly in polygons: r.channel_mesh.polygons.append(poly.map(func(p):return [(p.x-c.x)/size_.x,(p.y-c.y)/size_.z]))
func band(part: String,lo: float,hi: float,inside: float,outside: float,bottom: float,top: float,role: String) -> void:
	if hi-lo<.000001: return
	var count: int=maxi(1,ceili((hi-lo)/minf(deg_to_rad(3),2.0/maxf(radii.x,radii.y))))
	var patches: Array=[]; var chunk:=0
	for i in count:
		var a:=lerpf(lo,hi,float(i)/count); var b:=lerpf(lo,hi,float(i+1)/count)
		patches.append([point(a,outside),point(b,outside),point(b,inside),point(a,inside)])
		if patches.size()==6 or i==count-1:
			slab("%s_%d"%[part,chunk],patches,bottom,top,role); chunk+=1; patches=[]
func intervals(lo: float,hi: float) -> Array:
	if lo<0: return [[0.0,hi],[lo+TAU,TAU]]
	if hi>TAU: return [[lo,TAU],[0.0,hi-TAU]]
	return [[lo,hi]]
func build(owner: RefCounted) -> Dictionary:
	plan=owner; s=plan.settings; center=Vector2(s.center_x,s.center_z); radii=Vector2(s.radius_x,s.radius_z); turn=-deg_to_rad(s.rotation)
	if minf(radii.x,radii.y)*minf(radii.x,radii.y)/maxf(radii.x,radii.y)<s.thickness*2: return Data.fail("椭圆过扁，短轴处曲率无法容纳墙厚和塔楼")
	var outline: Array=[]; var length_:=0.0
	for i in 256:
		var p:=point(TAU*i/256); outline.append([p.x,p.y]); length_+=p.distance_to(point(TAU*(i+1)/256))
	if length_>1000: return Data.fail("单组环形城墙最长 1000 米，请减小半径")
	var gates: Array=[]; var openings: Array=[]; var tower_points: Array=[]
	if s.corner_towers:
		for i in int(s.tower_count): tower_points.append(point(TAU*(i+.5)/s.tower_count))
		for i in tower_points.size():
			if tower_points[i].distance_to(tower_points[(i+1)%tower_points.size()])<s.thickness*2+.5: return Data.fail("环形塔楼间距不足，请减少塔楼数量、减小墙厚或增大半径")
	var y: float=s.base_height; var top: float=y+s.height; var half: float=s.thickness*.5
	for gate in s.gates:
		var angle:=deg_to_rad(gate.angle); var delta:=asin(gate.width*.5/tangent(angle).length())
		var a:=point(angle-delta); var b:=point(angle+delta); var c: Vector2=(a+b)*.5
		for tower in tower_points:
			if tower.distance_to(c)<gate.width*.5+s.thickness*1.5: return Data.fail("环形城门距塔楼太近，请调整城门角度或塔楼数量")
		for previous in gates:
			if Vector2(previous.center[0],previous.center[2]).distance_to(c)<(previous.width+gate.width)*.5+1: return Data.fail("环形城门彼此太近或重叠")
		for span in intervals(angle-delta,angle+delta): openings.append({"lo":span[0],"hi":span[1],"gate":gate})
		var direction: Vector2=(b-a).normalized(); var normal:=Vector2(-direction.y,direction.x); var id: String=gate.id.sha256_text().left(10)
		for side in [-1,1]:
			var p: Vector2=c+direction*side*gate.width*.25-normal*(half+.12)
			var r: Dictionary=plan.box("door_%s_%s"%[id,str(side).replace("-","m")],Vector3(p.x,y+gate.height*.5,p.y),Vector3(gate.width*.5-.06,gate.height-.1,.18),-rad_to_deg(direction.angle()),"door")
			r.fixture={"id":gate.id,"kind":"door","pivot":[side*gate.width*.25,0,0],"angle":-side*100.0,"open":gate.open}
		gates.append({"id":gate.id,"center":[c.x,y,c.y],"width":gate.width,"height":gate.height,"open":gate.open,"angle":gate.angle})
	openings.sort_custom(func(a,b):return a.lo<b.lo)
	var start:=0.0; var index:=0
	for opening in openings:
		if opening.lo<start-.000001: return Data.fail("环形城门洞口重叠")
		band("arc_%d"%index,start,opening.lo,-half,half,y-s.foundation,top,"wall")
		band("lintel_%d"%index,opening.lo,opening.hi,-half,half,y+opening.gate.height,top,"gate_lintel")
		start=opening.hi; index+=1
	band("arc_%d"%index,start,TAU,-half,half,y-s.foundation,top,"wall")
	if s.battlements:
		for side in [-1,1]:
			var offset: float=side*(half-.2); var label_: String=str(side).replace("-","m")
			band("parapet_"+label_,0,TAU,offset-.2,offset+.2,top,top+.45,"parapet")
			var count:=ceili(length_/2.4)
			for i in count:
				var angle: float=TAU*(i+.5)/count; var delta: float=TAU/count*.25
				band("merlon_%s_%d"%[label_,i],angle-delta,angle+delta,offset-.2,offset+.2,top+.45,top+1.15,"battlement")
	# Round solid towers, offset from cardinal directions to leave natural gate sites.
	var ring_center:=center; var ring_radii:=radii; var ring_turn:=turn
	for i in tower_points.size():
		center=tower_points[i]; radii=Vector2.ONE*s.thickness; turn=0
		var poly: Array=[]
		for j in 24: poly.append(point(TAU*j/24))
		var tower_top: float=top+1.8
		slab("tower_%d"%i,[poly],y-s.foundation,tower_top,"corner_tower")
		if s.battlements:
			band("tower_parapet_%d"%i,0,TAU,-.4,0,tower_top,tower_top+.45,"parapet")
			for j in 10: band("tower_merlon_%d_%d"%[i,j],TAU*j/10,TAU*(j+.5)/10,-.4,0,tower_top+.45,tower_top+1.15,"battlement")
	center=ring_center; radii=ring_radii; turn=ring_turn
	if plan.records.size()>4096: return Data.fail("环形城墙构件超过 4096，请缩小半径或减少塔楼 / 垛口")
	for r in plan.records:
		if not Channel.valid(r): return Data.fail("环形墙体生成了无效网格，请调整半径和墙厚")
	return {"ok":true,"records":plan.records,"length":length_,"gates":gates,"outline":outline}
