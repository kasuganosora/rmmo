extends RefCounted
const T=preload("res://scripts/world3d/terrain_surface.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
static func height(terrains:Array,p:Vector3)->float:
	var result:=-INF
	for r:Dictionary in terrains:
		var pose:=T.transform(r);var local:Vector3=pose.affine_inverse()*p;var value:=T.sample(r,local)
		if is_finite(value):result=maxf(result,(pose*Vector3(local.x,value,local.z)).y)
	return result
static func fit(records:Array,terrains:Array,base:float,foundation:float)->Dictionary:
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
		var grade:=Vector2((a-b)/(dx*2),(c-d)/(dz*2))
		if grade.length()>.15:return Data.fail("墙顶通行坡度超过 15%，请分段整平地形")
		if maxf(absf((a+b)*.5-h),absf((c+d)*.5-h))>minf(foundation*.5,.15):return Data.fail("局部地形起伏过急，请平缓地形或缩短墙段")
		r.position[1]+=h-base;r.terrain_grade=[grade.x,grade.y]
	return {"ok":true,"records":next}
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
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,st.commit_to_arrays(),[],{},source.surface_get_material(slot),source.surface_get_name(slot) if source is ArrayMesh else "slope_wall")
	importer.generate_lods(60,25,[])
	var result:=importer.get_mesh();preload("res://scripts/world3d/bridge_lod_preparation.gd").remember(importer,result)
	return result
