extends RefCounted
const F=preload("res://scripts/world3d/fortification_data.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
var records: Array=[]
var settings: Dictionary={}
var prefix: String
static func point_distance(p: Vector2,a: Vector2,b: Vector2) -> float:
	return p.distance_to(a.lerp(b,clampf((p-a).dot(b-a)/(b-a).length_squared(),0,1)))
func box(part: String,center: Vector3,size: Vector3,yaw: float,role: String="wall") -> Dictionary:
	var r:={"uuid":prefix+"_"+part,"kind":"box","surface_id":"block","position":Data.xyz(center),"rotation":[0,yaw,0],"size":Data.xyz(size),"color":[.53,.50,.44] if role!="door" else [.28,.19,.11],"collision":"block","editor_group":prefix,"editor_group_name":settings.name,"editor_name":settings.name+" · "+role,"fortification":{"id":settings.id,"part":part,"role":role}}
	records.append(r); return r
func strip(part: String,a: Vector2,b: Vector2,bottom: float,top: float,width: float,role: String="wall") -> void:
	if a.distance_to(b)<.01: return
	var center: Vector2=(a+b)*.5; box(part,Vector3(center.x,(top+bottom)*.5,center.y),Vector3(a.distance_to(b),top-bottom,width),-rad_to_deg((b-a).angle()),role)
func build(value: Dictionary) -> Dictionary:
	settings=F.defaults().merged(value,true); records=[]; prefix="wall_"+settings.id.sha256_text().left(16)
	if not F.valid_settings(settings): return Data.fail("城墙或城门参数无效，门洞顶需低于墙顶至少 0.5 米")
	if settings.shape=="ellipse": return preload("res://scripts/world3d/fortification_ring.gd").new().build(self)
	var points: Array=settings.points.map(func(p):return Vector2(p[0],p[1])); var segments: int=points.size()-(0 if settings.closed else 1); var length_:=0.0; var paths: Array=[]; var gates: Array=[]
	for i in segments:
		var a: Vector2=points[i]; var b: Vector2=points[(i+1)%points.size()]; var length: float=a.distance_to(b)
		if length<settings.thickness*3: return Data.fail("城墙线段太短，至少为墙厚的三倍")
		length_+=length
		for other in paths:
			if i-other.index<=1 or settings.closed and other.index==0 and i==segments-1: continue
			if Geometry2D.segment_intersects_segment(a,b,other.a,other.b)!=null: return Data.fail("城墙中心线不能自交")
			var distance: float=minf(minf(point_distance(a,other.a,other.b),point_distance(b,other.a,other.b)),minf(point_distance(other.a,a,b),point_distance(other.b,a,b)))
			if distance<settings.thickness*(3 if settings.corner_towers else 1.5): return Data.fail("非相邻墙段或角塔太近，请拉开路径")
		if i>0 and (a-paths[-1].a).normalized().dot((b-a).normalized())<-.5: return Data.fail("城墙折角过尖，请放宽转角")
		paths.append({"a":a,"b":b,"index":i})
	if settings.closed and (points[0]-points[-1]).normalized().dot((points[1]-points[0]).normalized())<-.5: return Data.fail("城墙闭合处折角过尖，请放宽转角")
	if length_>1000: return Data.fail("单组城墙最长 1000 米，请分段生成")
	var y: float=settings.base_height; var top: float=y+settings.height; var half: float=settings.thickness*.5
	for path in paths:
		var a: Vector2=path.a; var b: Vector2=path.b; var tangent: Vector2=(b-a).normalized(); var normal:=Vector2(-tangent.y,tangent.x); var length: float=a.distance_to(b)
		var openings: Array=[]
		for gate in settings.gates:
			if gate.segment!=path.index: continue
			var lo: float=gate.t*length-gate.width*.5; var hi: float=gate.t*length+gate.width*.5
			var end_margin: float=settings.thickness*1.5 if settings.corner_towers else settings.thickness
			if lo<end_margin or hi>length-end_margin: return Data.fail("城门距墙端 / 角塔太近")
			openings.append({"lo":lo,"hi":hi,"gate":gate})
		openings.sort_custom(func(l,r):return l.lo<r.lo)
		var start:=0.0
		for opening in openings:
			if opening.lo<start+.5: return Data.fail("城门彼此太近或重叠")
			var gate: Dictionary=opening.gate; var id: String=gate.id.sha256_text().left(10); var center: Vector2=a+tangent*gate.t*length
			strip("s%d_%s"%[path.index,id],a+tangent*start,a+tangent*opening.lo,y-settings.foundation,top,settings.thickness)
			strip("lintel_"+id,a+tangent*opening.lo,a+tangent*opening.hi,y+gate.height,top,settings.thickness,"gate_lintel")
			for side in [-1,1]:
				var c: Vector2=center+tangent*side*gate.width*.25-normal*(half+.12)
				var r:=box("door_%s_%s"%[id,str(side).replace("-","m")],Vector3(c.x,y+gate.height*.5,c.y),Vector3(gate.width*.5-.06,gate.height-.1,.18),-rad_to_deg(tangent.angle()),"door")
				r.fixture={"id":gate.id,"kind":"door","pivot":[side*gate.width*.25,0,0],"angle":-side*100.0,"open":gate.open}
			gates.append({"id":gate.id,"center":[center.x,y,center.y],"width":gate.width,"height":gate.height,"open":gate.open}); start=opening.hi
		strip("s%d_end"%path.index,a+tangent*start,b,y-settings.foundation,top,settings.thickness)
		# Continuous inner/outer parapets with evenly spaced raised merlons.
		if settings.battlements:
			for side in [-1,1]:
				var offset: Vector2=normal*side*(half-.2)
				strip("parapet_%d_%s"%[path.index,str(side).replace("-","m")],a+offset,b+offset,top,top+.45,.4,"parapet")
				var count: int=maxi(2,ceili(length/2.4))
				for j in count:
					var c: Vector2=a.lerp(b,(j+.5)/count)+offset; var span: float=length/count*.5
					strip("merlon_%d_%s_%d"%[path.index,str(side).replace("-","m"),j],c-tangent*span*.5,c+tangent*span*.5,top+.45,top+1.15,.4,"battlement")
	for i in points.size():
		var p: Vector2=points[i]
		if settings.corner_towers:
			var width: float=settings.thickness*2; var tower_top: float=top+1.8
			box("tower_%d"%i,Vector3(p.x,(tower_top+y-settings.foundation)*.5,p.y),Vector3(width,tower_top-y+settings.foundation,width),0,"corner_tower")
			if settings.battlements:
				for side in 4:
					var n:=Vector2(cos(side*PI*.5),sin(side*PI*.5)); var tangent:=Vector2(-n.y,n.x); var c: Vector2=p+n*(width*.5-.2)
					strip("tower_parapet_%d_%d"%[i,side],c-tangent*width*.5,c+tangent*width*.5,tower_top,tower_top+.45,.4,"parapet")
					for j in 3:
						var at: Vector2=c+tangent*(j-1)*width/3
						strip("tower_merlon_%d_%d_%d"%[i,side,j],at-tangent*width/12,at+tangent*width/12,tower_top+.45,tower_top+1.15,.4,"battlement")
		else: box("joint_%d"%i,Vector3(p.x,(top+y-settings.foundation)*.5,p.y),Vector3(settings.thickness,top-y+settings.foundation,settings.thickness),0,"joint")
	if records.size()>4096: return Data.fail("城墙构件超过 4096，请缩短路径或关闭垛口")
	return {"ok":true,"records":records,"length":length_,"gates":gates}
