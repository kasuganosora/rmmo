extends RefCounted
## Fixed attic window, cut through both sides of the native front gable.
## Reuses convex roof prisms so baking, collision, painting and roof hiding keep
## their existing contracts; no decal, Boolean runtime mesh or rawmesh payload.
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const Prism=preload("res://scripts/world3d/roof_mesh.gd")
const SEGMENTS:=32
const CUT_RADIUS:=.60
const INNER_RADIUS:=.56
const OUTER_RADIUS:=.75

static func issue(p:Dictionary)->String:
	if not p.get("gable_oculus",false):return ""
	if p.get("layout") not in ["townhouse","hall"] or p.get("roof_solver")!="unified" or p.get("style")!="plaster" or p.get("roof")!="gable" or p.get("roof_axis")!="depth" or p.get("compound")!="none":
		return "山墙圆窗需要中世纪浅灰泥住宅、统一双坡屋面、山墙朝街且无附属翼楼"
	var rise:float=float(p.width)*.5*tan(deg_to_rad(float(p.roof_pitch)))-.14
	var above_eave:float=rise*.45
	if above_eave-OUTER_RADIUS<.12 or (rise-above_eave)*cos(deg_to_rad(float(p.roof_pitch)))-OUTER_RADIUS<.12:
		return "山墙圆窗与檐口或斜屋面净距不足 0.12 米，请增加房屋宽度或屋顶坡度"
	return ""

static func apply(plan:Dictionary)->Dictionary:
	var p:Dictionary=plan.parameters
	if not p.get("gable_oculus",false):return {"ok":true}
	var error:=issue(p)
	if not error.is_empty():return {"ok":false,"error":error}
	var floor_:int=int(p.floors)
	var eave_y:float=floor_*float(p.floor_height)+.32
	var front:float=-float(p.depth)/2.-(float(p.jetty) if floor_>1 else 0.)
	var rise:float=float(p.width)*.5*tan(deg_to_rad(float(p.roof_pitch)))-.14
	var center:=Vector2(0,eave_y+rise*.45)
	var mask:Array=[]
	for i in SEGMENTS:mask.append(center+Vector2(cos(TAU*i/SEGMENTS),sin(TAU*i/SEGMENTS))*CUT_RADIUS)
	var result:Array=[];var removed_area:=0.;var hit_count:=0
	for r:Dictionary in plan.records:
		if not str(r.get("building",{}).get("part","")).begins_with("roof/gable0/patch") or r.get("roof_mesh",{}).get("semantic")!="gable":
			result.append(r);continue
		var points:Array=[];var pos:=Poly.vec(r.position);var size:=Poly.vec(r.size)
		for v:Array in r.roof_mesh.polygon:
			var at:=pos+Poly.vec(v)*size
			if absf(at.z-front)>.001:return {"ok":false,"error":"山墙圆窗定位未落在主屋正面，已取消生成"}
			points.append(Vector2(at.x,at.y))
		var pieces:=Poly.subtract(points,mask);var retained_area:=0.
		for i in pieces.size():
			var poly:Array=pieces[i];retained_area+=Poly.area(poly)
			var polygon:Array=[]
			for v:Vector2 in poly:polygon.append([v.x,v.y,front])
			var part:String=str(r.building.part)+"/oculus%d"%i
			var piece:=Prism.record(part,polygon,Poly.vec(r.roof_mesh.extrusion)*size,r.color,floor_,r.building.floor_y,"gable")
			if not Prism.valid(piece):return {"ok":false,"error":"山墙圆窗裁切出现退化面，已取消生成"}
			result.append(piece)
		removed_area+=Poly.area(points)-retained_area;hit_count+=1
	var expected:=Poly.area(mask)
	if hit_count==0 or absf(removed_area-expected)>.0001:
		return {"ok":false,"error":"山墙圆窗不能完整穿过正面山墙，已取消生成","removed_area":removed_area,"expected_area":expected}
	# Pale stone outer surround and a separate dark timber rebate match the
	# accepted town round-window component. Their stepped faces avoid coplanar
	# overlap with one another and with the plaster gable.
	for i in SEGMENTS:
		var a:=Vector2(cos(TAU*i/SEGMENTS),sin(TAU*i/SEGMENTS))
		var b:=Vector2(cos(TAU*(i+1)/SEGMENTS),sin(TAU*(i+1)/SEGMENTS))
		var stone_poly:Array=[]
		for v:Vector2 in [center+a*OUTER_RADIUS,center+b*OUTER_RADIUS,center+b*.61,center+a*.61]:stone_poly.append([v.x,v.y,front-.045])
		var stone:=Prism.record("roof/oculus/stone_ring%d"%i,stone_poly,Vector3(0,0,.26),[.64,.59,.47],floor_,eave_y,"gable")
		stone.building.role="stone_trim";result.append(stone)
		var polygon:Array=[]
		for v:Vector2 in [center+a*.62,center+b*.62,center+b*INNER_RADIUS,center+a*INNER_RADIUS]:polygon.append([v.x,v.y,front-.065])
		var frame:=Prism.record("roof/oculus/frame%d"%i,polygon,Vector3(0,0,.29),[.27,.19,.12],floor_,eave_y,"gable")
		frame.building.role="frame";result.append(frame)
	# A fixed glazed oculus uses a real disc and crossed mullions. Its collision
	# belongs to the window, never an uncut plaster wall hidden behind the pane.
	var glass_poly:Array=[]
	for i in SEGMENTS:
		var v:=center+Vector2(cos(TAU*i/SEGMENTS),sin(TAU*i/SEGMENTS))*(INNER_RADIUS+.005)
		glass_poly.append([v.x,v.y,front+.075])
	var glass:=Prism.record("roof/oculus/glass",glass_poly,Vector3(0,0,.025),[.29,.39,.38],floor_,eave_y,"gable")
	glass.building.role="window";result.append(glass)
	for vertical:bool in [false,true]:
		var size:=Vector3(.045,INNER_RADIUS*2,.055) if vertical else Vector3(INNER_RADIUS*2,.045,.055)
		result.append({"uuid":"roof_oculus_mullion_%s"%vertical,"kind":"box","surface_id":"block","position":[center.x,center.y,front+.055],"rotation":[0,0,0],"size":Poly.arr(size),"color":[.27,.19,.12],"editor_name":"roof/oculus/mullion_%s"%vertical,"building":{"part":"roof/oculus/mullion_%s"%vertical,"floor":floor_,"floor_y":eave_y,"role":"frame"}})
	for r:Dictionary in result:
		if r.has("roof_mesh") and not Prism.valid(r):return {"ok":false,"error":"山墙圆窗原生棱柱无效，已取消生成"}
	plan.records=result
	plan.openings.append({"id":"gable_oculus","type":"window","shape":"circle","wall":"roof/gable0","axis":"x","fixed":front+.1,"u":0.,"floor_y":0.,"bottom":center.y-INNER_RADIUS,"width":INNER_RADIUS*2,"height":INNER_RADIUS*2,"room":"attic","fixed_window":true})
	return {"ok":true}
