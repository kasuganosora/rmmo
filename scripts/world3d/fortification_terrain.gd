extends RefCounted
const T=preload("res://scripts/world3d/terrain_surface.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
static func height(terrains:Array,p:Vector3)->float:
	var result:=-INF
	for r:Dictionary in terrains:
		var pose:=T.transform(r);var local:Vector3=pose.affine_inverse()*p;var value:=T.sample(r,local)
		if is_finite(value):result=maxf(result,(pose*Vector3(local.x,value,local.z)).y)
	return result
static func water_jambs(settings:Dictionary)->Dictionary:
	if settings.is_empty():return {"ok":true,"jambs":[]}
	var resolved:=preload("res://scripts/world3d/fortification_spline.gd").resolve(settings)
	if not resolved.ok:return resolved
	var s:Dictionary=resolved.settings;var jambs:Array=[]
	for gate:Dictionary in s.gates:
		if gate.get("kind","land")!="water" or not gate.has("base_height"):continue
		var a:Vector2;var b:Vector2
		if s.shape=="ellipse":
			var ring=preload("res://scripts/world3d/fortification_ring.gd").new()
			ring.center=Vector2(s.center_x,s.center_z);ring.radii=Vector2(s.radius_x,s.radius_z);ring.turn=-deg_to_rad(s.rotation)
			var angle:float=deg_to_rad(gate.angle);var delta:float=asin(gate.width*.5/ring.tangent(angle).length())
			a=ring.point(angle-delta);b=ring.point(angle+delta)
		else:
			var i:=int(gate.segment);var p:=Vector2(s.points[i][0],s.points[i][1]);var q:=Vector2(s.points[(i+1)%s.points.size()][0],s.points[(i+1)%s.points.size()][1]);var direction:Vector2=(q-p).normalized()
			a=p.lerp(q,gate.t)-direction*gate.width*.5;b=p.lerp(q,gate.t)+direction*gate.width*.5
		var d:Vector2=(b-a).normalized();var n:=Vector2(-d.y,d.x)
		for p:Vector2 in [a,b]:jambs.append({"id":gate.id,"point":p,"direction":d,"normal":n,"half":s.thickness*.5,"base":float(gate.base_height)})
	return {"ok":true,"jambs":jambs}
static func jamb_height(jambs:Array,p:Vector3)->float:
	for jamb:Dictionary in jambs:
		var delta:Vector2=Vector2(p.x,p.z)-jamb.point
		if absf(delta.dot(jamb.direction))<.02 and absf(delta.dot(jamb.normal))<=jamb.half+.05:return jamb.base
	return NAN
static func fit(records:Array,terrains:Array,base:float,foundation:float,settings:Dictionary={})->Dictionary:
	var banks:=water_jambs(settings)
	if not banks.ok:return banks
	# An elevated arch is not a license to suspend its dry-bank jambs.
	# Match both banks before fitting adjacent walls to the exact deck datum.
	for jamb:Dictionary in banks.jambs:
		for offset:float in [-jamb.half,0.,jamb.half]:
			var at:Vector2=jamb.point+jamb.normal*offset;var h:=height(terrains,Vector3(at.x,0,at.y))
			if not is_finite(h) or absf(h-jamb.base)>.12:return Data.fail("水关 %s 的两岸墙脚须有与局部岸基准一致的承托台地（高差 ≤ 0.12 米），请先整坡"%jamb.id)
	var next:Array=records.duplicate(true);var rigid:Dictionary={};var regex:=RegEx.new();regex.compile("^(access_tower_[0-9]+|tower_(?:parapet_|merlon_)?[0-9]+|(?:door|lintel)_[a-zA-Z0-9]+)")
	for r:Dictionary in next:
		var match_:RegExMatch=regex.search(r.fortification.part)
		if match_==null:continue
		var key:=match_.get_string(1)
		key=key.replace("tower_parapet_","tower_").replace("tower_merlon_","tower_").replace("door_","gate_").replace("lintel_","gate_")
		if not rigid.has(key):rigid[key]={"records":[],"height":-INF,"low":INF}
		rigid[key].records.append(r)
		for p:Vector3 in preload("res://scripts/world_editor/selection_geometry.gd").corners(r):
			var h:=height(terrains,p)
			if not is_finite(h):return Data.fail("城楼或城门缺少完整地形承托")
			rigid[key].height=maxf(rigid[key].height,h)
			rigid[key].low=minf(rigid[key].low,h)
	var moved:Dictionary={}
	for group:Dictionary in rigid.values():
		if group.height-group.low>.12:return Data.fail("城门和城楼需局部平整的承托台地（高差 ≤ 0.12 米），请先整平；墙段可随坡地延伸")
		for r:Dictionary in group.records:r.position[1]+=group.height-base;moved[r.uuid]=true
	var water_parts:Array=next.filter(func(r):return r.has("water_gate") or str(r.fortification.part).begins_with("water_pier_") or str(r.fortification.part).begins_with("water_crown_"))
	var water_support:Array=[]
	for part:Dictionary in water_parts:
		var polygons:Array=[]
		if part.has("channel_mesh"):
			for shape:Dictionary in preload("res://scripts/world_editor/building_footprint.gd").record_shapes(part):polygons.append(shape.polygon)
		water_support.append({"inverse":T.transform(part).affine_inverse(),"half":Data.vec(part.size)*.5,"polygons":polygons})
	for r:Dictionary in next:
		if moved.has(r.uuid) or str(r.fortification.part).begins_with("water_"):continue
		var over_water:=false
		for support:Dictionary in water_support:
			var relative:Vector3=support.inverse*Data.vec(r.position)
			if absf(relative.x)>=support.half.x+.01 or absf(relative.z)>=support.half.z+.05:continue
			# Curved crowns fill the crescent outside the water arch's straight
			# chord. Battlements resting there share the fixed arch elevation;
			# lowering the bed must not lower them through their stone crown.
			var p:=Vector2(r.position[0],r.position[2])
			if support.polygons.is_empty() or support.polygons.any(func(poly):return Geometry2D.is_point_in_polygon(p,poly)):over_water=true;break
		if over_water:continue
		var center:=Data.vec(r.position);var basis:=Basis.from_euler(Data.vec(r.rotation)*PI/180);var h:=height(terrains,center)
		var dx:=maxf(.1,r.size[0]*.5);var dz:=maxf(.1,r.size[2]*.5)
		var a:=height(terrains,center+basis.x*dx);var b:=height(terrains,center-basis.x*dx);var c:=height(terrains,center+basis.z*dz);var d:=height(terrains,center-basis.z*dz)
		if not [h,a,b,c,d].all(func(v):return is_finite(v)):return Data.fail("城墙路径缺少完整地形承托")
		var anchor_a:=jamb_height(banks.jambs,center+basis.x*dx);var anchor_b:=jamb_height(banks.jambs,center-basis.x*dx)
		var anchored:=is_finite(anchor_a) or is_finite(anchor_b)
		if anchored:
			if is_finite(anchor_a):a=anchor_a
			if is_finite(anchor_b):b=anchor_b
			# The bank-side strip ends exactly at the crown rather than leaving
			# the old center-sampled plane's small step at the structural joint.
			h=(a+b)*.5
		var grade:=Vector2((a-b)/(dx*2),(c-d)/(dz*2))
		if anchored:grade.y=0.
		if grade.length()>.15:return Data.fail("墙顶通行坡度超过 15%，请分段整平地形")
		if maxf(absf((a+b)*.5-h),absf((c+d)*.5-h))>minf(foundation*.5,.15):return Data.fail("局部地形起伏过急，请平缓地形或缩短墙段")
		r.position[1]+=h-base;r.terrain_grade=[grade.x,grade.y]
	var offsets:Dictionary={}
	for i in records.size():offsets[records[i].uuid]=float(next[i].position[1])-float(records[i].position[1])
	return {"ok":true,"records":next,"height_offsets":offsets}
static func deform(source:Mesh,grade:Array)->ArrayMesh:
	var importer:=ImporterMesh.new();var gx:float=grade[0];var gz:float=grade[1]
	for slot in source.get_surface_count():
		var arrays:Array=source.surface_get_arrays(slot).duplicate(true);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			vertices[i].y+=gx*vertices[i].x+gz*vertices[i].z
			if i<normals.size():normals[i]=Vector3(normals[i].x-gx*normals[i].y,normals[i].y,normals[i].z-gz*normals[i].y).normalized()
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TANGENT]=null
		var temp:=ArrayMesh.new();temp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var st:=SurfaceTool.new();st.create_from(temp,0)
		if arrays[Mesh.ARRAY_TEX_UV]!=null:st.generate_tangents()
		var repaired:=st.commit_to_arrays();var material:=source.surface_get_material(slot)
		if material is BaseMaterial3D and material.normal_enabled:repaired=preload("res://scripts/world3d/mesh_tangent_repair.gd").repair(repaired)
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,repaired,[],{},source.surface_get_material(slot),source.surface_get_name(slot) if source is ArrayMesh else "slope_wall")
	importer.generate_lods(60,25,[])
	var result:=importer.get_mesh();preload("res://scripts/world3d/bridge_lod_preparation.gd").remember(importer,result)
	return result
