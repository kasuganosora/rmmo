extends RefCounted
const F=preload("res://scripts/world3d/fortification_data.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
const Spacing=preload("res://scripts/world3d/fortification_spacing.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
var records: Array=[]
var settings: Dictionary={}
var prefix: String
static func point_distance(p: Vector2,a: Vector2,b: Vector2) -> float:
	return p.distance_to(a.lerp(b,clampf((p-a).dot(b-a)/(b-a).length_squared(),0,1)))
func box(part: String,center: Vector3,size: Vector3,yaw: float,role: String="wall") -> Dictionary:
	var r:={"uuid":prefix+"_"+part,"kind":"box","surface_id":"block","position":Data.xyz(center),"rotation":[0,yaw,0],"size":Data.xyz(size),"color":[.53,.50,.44] if role!="door" else [.28,.19,.11],"collision":"block","editor_group":prefix,"editor_group_name":settings.name,"editor_name":settings.name+" · "+role,"fortification":{"id":settings.id,"part":part,"role":role}}
	records.append(r); return r
func hinges(door: Dictionary) -> void:
	if settings.style!="medieval_stone": return
	var basis:=Basis.from_euler(Data.vec(door.rotation)*PI/180)
	var pivot: Vector3=Data.vec(door.position)+basis*Data.vec(door.fixture.pivot)
	for module in ["hinge","hinge_mount"]:
		var r:=box(door.fortification.part+"_"+module,pivot,Vector3(.28,door.size[1],.36),door.rotation[1],module)
		if module=="hinge":
			r.fixture=door.fixture.duplicate(true); r.fixture.pivot=[0,0,0]
func strip(part: String,a: Vector2,b: Vector2,bottom: float,top: float,width: float,role: String="wall") -> void:
	if a.distance_to(b)<.01: return
	if (settings.wall_access and role=="wall" and a.distance_to(b)>12) or (settings.follow_terrain and role in ["wall","parapet"] and a.distance_to(b)>4):
		var n:=ceili(a.distance_to(b)/(4. if settings.follow_terrain else 12.))
		for i in n: strip(part+"_chunk%d"%i,a.lerp(b,float(i)/n),a.lerp(b,float(i+1)/n),bottom,top,width,role)
		return
	var center: Vector2=(a+b)*.5; box(part,Vector3(center.x,(top+bottom)*.5,center.y),Vector3(a.distance_to(b),top-bottom,width),-rad_to_deg((b-a).angle()),role)

func top_strip(part:String,a:Vector2,b:Vector2,bottom:float,top:float,width:float,role:String,origin:Vector2,tangent:Vector2,openings:Array)->void:
	# Split only explicitly elevated water crossings. No parapet or merlon
	# may straddle their jamb and keep the region's unrelated elevation.
	var length:float=a.distance_to(b);var start:float=(a-origin).dot(tangent);var cuts:Array=[0.0,length]
	var elevated:Array=openings.filter(func(o):return o.gate.get("kind","land")=="water" and o.gate.has("base_height"))
	if elevated.is_empty():strip(part,a,b,bottom,top,width,role);return
	for opening:Dictionary in elevated:
		for edge:float in [opening.lo,opening.hi]:
			var at:float=edge-start
			if at>.00001 and at<length-.00001:cuts.append(at)
	cuts.sort()
	for i in cuts.size()-1:
		if cuts[i+1]-cuts[i]<.00001:continue
		var center:float=start+(cuts[i]+cuts[i+1])*.5;var offset:=0.0
		for opening:Dictionary in elevated:
			if center>=opening.lo and center<=opening.hi:offset=float(opening.gate.base_height)-float(settings.base_height);break
		strip(part+"_level%d"%i,a+tangent*cuts[i],a+tangent*cuts[i+1],bottom+offset,top+offset,width,role)
func build(value: Dictionary,curved:bool=false) -> Dictionary:
	if value.get("shape","path")=="spline":
		var resolved:=preload("res://scripts/world3d/fortification_spline.gd").resolve(value)
		if not resolved.ok:return resolved
		return build(resolved.settings,true)
	settings=F.defaults().merged(value,true); records=[]; prefix="wall_"+settings.id.sha256_text().left(16)
	if not F.valid_settings(settings): return Data.fail("城墙或城门参数无效，门洞顶需低于墙顶至少 0.5 米")
	if settings.has("tower_indices"): settings.tower_indices=settings.tower_indices.map(func(v):return int(v))
	if settings.shape=="ellipse": return preload("res://scripts/world3d/fortification_access.gd").new().apply(self,preload("res://scripts/world3d/fortification_ring.gd").new().build(self))
	var points: Array=settings.points.map(func(p):return Vector2(p[0],p[1])); var segments: int=points.size()-(0 if settings.closed else 1); var length_:=0.0; var paths: Array=[]; var gates: Array=[]
	for i in segments:
		var a: Vector2=points[i]; var b: Vector2=points[(i+1)%points.size()]; var length: float=a.distance_to(b)
		if length<(.5 if curved else settings.thickness*3): return Data.fail("城墙线段太短，至少为墙厚的三倍")
		length_+=length
		for other in paths:
			if i-other.index<=1 or settings.closed and other.index==0 and i==segments-1: continue
			if Geometry2D.segment_intersects_segment(a,b,other.a,other.b)!=null: return Data.fail("城墙中心线不能自交")
			var distance: float=minf(minf(point_distance(a,other.a,other.b),point_distance(b,other.a,other.b)),minf(point_distance(other.a,a,b),point_distance(other.b,a,b)))
			if (not curved or a.distance_to(other.b)>settings.thickness*4) and distance<settings.thickness*(3 if settings.corner_towers else 1.5): return Data.fail("非相邻墙段或角塔太近，请拉开路径")
		if i>0 and (a-paths[-1].a).normalized().dot((b-a).normalized())<-.5: return Data.fail("城墙折角过尖，请放宽转角")
		paths.append({"a":a,"b":b,"index":i})
	if settings.closed and (points[0]-points[-1]).normalized().dot((points[1]-points[0]).normalized())<-.5: return Data.fail("城墙闭合处折角过尖，请放宽转角")
	if length_>(5000 if settings.has("tower_indices") else 1000): return Data.fail("单组城墙最长 1000 米；指定塔楼节点的描图路径支持 5000 米")
	var layout:={"ok":true,"layout_zones":[]}
	if settings.layout_version==1 and settings.tower_layout=="automatic":
		layout=Spacing.validate(points.filter(func(p):return not settings.has("tower_indices") or points.find(p) in settings.tower_indices) if settings.corner_towers else [],Spacing.gates(settings),Spacing.radius(settings))
		if not layout.ok: return layout
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
			if gate.get("kind","land")=="water":
				water_opening(gate,a+tangent*opening.lo,a+tangent*opening.hi)
			else:strip("lintel_"+id,a+tangent*opening.lo,a+tangent*opening.hi,y+gate.height,top,settings.thickness,"gate_lintel")
			for side in ([] if gate.get("kind","land")=="water" else [-1,1]):
				var c: Vector2=center+tangent*side*gate.width*.25-normal*(half+.12)
				var r:=box("door_%s_%s"%[id,str(side).replace("-","m")],Vector3(c.x,y+gate.height*.5,c.y),Vector3(gate.width*.5-.06,gate.height-.1,.18),-rad_to_deg(tangent.angle()),"door")
				r.fixture={"id":gate.id,"kind":"door","pivot":[side*gate.width*.25,0,0],"angle":-side*100.0,"open":gate.open}
				hinges(r)
			gates.append({"id":gate.id,"center":[center.x,gate.get("base_height",y),center.y],"width":gate.width,"height":gate.height,"open":gate.open}); start=opening.hi
		strip("s%d_end"%path.index,a+tangent*start,b,y-settings.foundation,top,settings.thickness)
		# Continuous inner/outer parapets with evenly spaced raised merlons.
		if settings.battlements:
			for side in [-1,1]:
				var offset: Vector2=normal*side*(half-.2)
				top_strip("parapet_%d_%s"%[path.index,str(side).replace("-","m")],a+offset,b+offset,top,top+.45,.4,"parapet",a,tangent,openings)
				var count: int=maxi(2,ceili(length/2.4))
				for j in count:
					var c: Vector2=a.lerp(b,(j+.5)/count)+offset; var span: float=length/count*.5
					top_strip("merlon_%d_%s_%d"%[path.index,str(side).replace("-","m"),j],c-tangent*span*.5,c+tangent*span*.5,top+.45,top+1.15,.4,"battlement",a,tangent,openings)
	for i in points.size():
		var p: Vector2=points[i]
		if settings.corner_towers and (not settings.has("tower_indices") or i in settings.tower_indices):
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
	if records.size()>8192: return Data.fail("城墙构件超过 8192，请缩短路径或关闭垛口")
	return preload("res://scripts/world3d/fortification_access.gd").new().apply(self,{"ok":true,"records":records,"length":length_,"gates":gates,"layout_zones":layout.layout_zones})

func water_opening(gate:Dictionary,a:Vector2,b:Vector2)->void:
	var tangent:Vector2=(b-a).normalized();var normal:=Vector2(-tangent.y,tangent.x)
	var id:String=gate.id.sha256_text().left(10);var y:float=gate.get("base_height",settings.base_height);var top:float=y+settings.height;var half:float=settings.thickness*.5
	var bays:=maxi(1,ceili(gate.width/8.));var pier:=1.;var span:float=(gate.width-(bays-1)*pier)/bays
	for bay in bays:
		var lo:float=0.0+bay*(span+pier);var hi:float=lo+span
		strip("water_arch_%s_%d"%[id,bay],a+tangent*lo,a+tangent*hi,y+gate.height,top,settings.thickness,"gate_lintel")
		records[-1].water_gate={"version":1}
		if bay<bays-1:strip("water_pier_%s_%d"%[id,bay],a+tangent*hi,a+tangent*(hi+pier),y-gate.get("water_depth",4.),top,settings.thickness,"wall")
		if gate.get("grille",false):
			var leaf_width:float=span*.5-.06;var gate_bottom:float=y-gate.get("water_depth",4.)+.05;var gate_top:float=y+gate.height-.10;var gh:float=gate_top-gate_bottom
			for side in [-1,1]:
				var first:=records.size();var mid:Vector2=a+tangent*((lo+hi)*.5+side*span*.25)-normal*(half+.14)
				var center_y:float=(gate_bottom+gate_top)*.5;var bars:=ceili(leaf_width/.32)
				for bar in bars+1:
					var p:Vector2=mid+tangent*lerpf(-leaf_width*.5,leaf_width*.5,float(bar)/bars)
					box("water_grille_%s_%d_%d_bar%d"%[id,bay,side,bar],Vector3(p.x,center_y,p.y),Vector3(.08,gh,.10),-rad_to_deg(tangent.angle()),"water_grille")
				for rail in 4:
					box("water_grille_%s_%d_%d_rail%d"%[id,bay,side,rail],Vector3(mid.x,gate_bottom+.1+(gh-.2)*rail/3.,mid.y),Vector3(leaf_width,.12,.14),-rad_to_deg(tangent.angle()),"water_grille")
				var pivot:Vector2=mid+tangent*side*span*.25
				var bundle:={"records":records};Fixtures.attach(bundle,first,gate.id,"door",Vector3(pivot.x,center_y,pivot.y),-side*100.,gate.open)
				for hinge in 3:
					box("water_hinge_%s_%d_%d_%d"%[id,bay,side,hinge],Vector3(pivot.x,gate_bottom+.4+(gh-.8)*hinge*.5,pivot.y),Vector3(.24,.30,.30),0,"water_grille")
