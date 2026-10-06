extends RefCounted
const Data=preload("res://scripts/world3d/rock_bank_mesh.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
static func fail(message:String)->Dictionary:return {"ok":false,"error":message}
static func bridge_overlap(shapes:Array,record:Dictionary,bounds:AABB)->bool:
	# Bridge bounds include the space below arches and between cutwaters. Test
	# frozen masonry itself so a legal bank is not pushed away from the abutment.
	var mesh:Mesh
	if record.has("house_prefab"):mesh=preload("res://scripts/world3d/house_prefab.gd").geometry(record).get("mesh")
	else:mesh=preload("res://scripts/world3d/bridge_mesh.gd").new().build(record)
	if mesh==null:return true
	var faces:PackedVector3Array=preload("res://scripts/world3d/ground_cpu_mesh.gd").capture(mesh).collision_faces()
	var pose:=Transform3D(Basis.from_euler(Data.vec(record.rotation)*PI/180),Data.vec(record.position));var scale:=Data.vec(record.size)
	var nearby:Array=[];var region:=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
	for i in range(0,faces.size(),3):
		var points:Array[Vector3]=[pose*(faces[i]*scale),pose*(faces[i+1]*scale),pose*(faces[i+2]*scale)]
		var triangle:=AABB(points[0],Vector3.ZERO).expand(points[1]).expand(points[2]).grow(.015)
		if not region.intersects(Rect2(Vector2(triangle.position.x,triangle.position.z),Vector2(triangle.size.x,triangle.size.z)),true):continue
		nearby.append(points)
		if not bounds.intersects(triangle):continue
		var padded:Array[Vector3]=[]
		for p in points:
			for offset:Vector3 in [Vector3(.015,.015,.015),Vector3(-.015,-.015,-.015),Vector3(.015,-.015,-.015),Vector3(-.015,.015,.015)]:padded.append(p+offset)
		if Foot.batches_overlap(shapes,[Foot.from_points(padded)]):return true
	# Also reject a bank volume wholly contained in masonry without crossing a face.
	for shape:Dictionary in shapes:
		var sample:Vector3=shape.bounds.get_center();var hits:Array=[];var winding:=0
		for triangle:Array in nearby:
			var hit:Variant=Geometry3D.ray_intersects_triangle(sample,Vector3.UP,triangle[0],triangle[1],triangle[2])
			if hit==null:continue
			var normal:Vector3=(triangle[2]-triangle[0]).cross(triangle[1]-triangle[0]);var sign_:int=1 if normal.y>0 else -1
			if not hits.any(func(h):return absf(h[0]-hit.y)<.001 and h[1]==sign_):hits.append([hit.y,sign_]);winding+=sign_
		# Signed crossings handle overlapping closed masonry modules, for which
		# an even/odd test would incorrectly call double-covered solid "empty".
		if winding!=0:return true
	return false
static func recipe(record:Dictionary)->Dictionary:
	var p:Dictionary=record.rock_bank.duplicate(true);var pose:=Transform3D(Basis.from_euler(Data.vec(record.rotation)*PI/180),Data.vec(record.position));var scale:=Data.vec(record.size)
	for i in p.points.size():
		var at:=Data.vec(p.points[i])*scale;var inner_y:float=p.inner_heights[i]*scale.y
		p.points[i]=Data.arr(pose*at);p.inner_heights[i]=inner_y+pose.origin.y
	p.height*=scale.y;p.cap_width*=scale.x;p.roughness*=scale.x;p.water_level=p.water_level*scale.y+pose.origin.y
	if p.has("inner_widths"):
		for i in p.inner_widths.size():p.inner_widths[i]*=scale.x
	if p.has("cap_angle"):
		var direction:Vector3=pose.basis*Vector3(cos(deg_to_rad(p.cap_angle)),0,sin(deg_to_rad(p.cap_angle)));p.cap_angle=rad_to_deg(atan2(direction.z,direction.x))
	p.id=record.uuid;p.name=Geometry.label(record)
	return p
static func catalog(editor)->Dictionary:
	var rows:Array=[]
	for r:Dictionary in editor._doc.records:
		if r.has("rock_bank"):rows.append({"id":r.uuid,"name":Geometry.label(r),"editable":editor._record_editable(r),"parameters":recipe(r),"materials":r.rock_bank_materials})
	return {"ok":true,"rock_banks":rows}
static func plan(doc,args:Dictionary,library,editable:Callable,contains:Callable=Callable())->Dictionary:
	var error:=Data.S.validate(args,Data.schema())
	if not error.is_empty():return fail(error)
	var previous:Dictionary=doc._find(str(args.get("id","")))
	if not previous.is_empty():
		if not previous.has("rock_bank") or not editable.call(previous):return fail("目标岩岸需可见、未锁定且在当前楼层")
		if previous.has("surface_paint"):return fail("请先清除手刷表面覆盖，再修改岩岸形状")
		if absf(previous.rotation[0])>.001 or absf(previous.rotation[2])>.001 or not is_equal_approx(float(previous.size[0]),float(previous.size[2])):return fail("参数编辑要求水平且 X/Z 等比例；请先恢复倾斜或非均匀水平缩放")
	elif doc.records.size()>=100000:return fail("地图物件已达上限")
	var values:=Data.defaults() if previous.is_empty() else recipe(previous)
	values.merge(args.duplicate(true),true)
	if not values.has("points"):return fail("新建岩岸必须提供世界 XYZ 岸顶路径")
	if args.has("points") and not args.has("inner_heights"):values.inner_heights=args.points.map(func(p):return p[1])
	if args.has("points") and not args.has("inner_widths"):values.erase("inner_widths")
	if not values.has("inner_heights"):values.inner_heights=values.points.map(func(p):return p[1])
	error=Data.path_error(values)
	if not error.is_empty():return fail(error)
	var materials:Dictionary=previous.get("rock_bank_materials",{}).duplicate(true)
	for role in ["rock","top"]:
		var key:String=role+"_material_id"
		if args.has(key) or not materials.has(role):
			var id:String=args.get(key,"pack:default:terrain/beach_cliff/material" if role=="rock" else "pack:default:terrain/mossy_grass_vcjmej0s/material")
			var material:Dictionary=library.find(id)
			if material.is_empty() or not Paint.material_valid(material) or material.color[3]!=1:return fail("岩岸需有效的不透明 "+role+" 材质")
			materials[role]=material.duplicate(true)
	var center:=Vector3.ZERO
	for point:Array in values.points:center+=Data.vec(point)
	center/=values.points.size();center.y=0
	var name_:String=values.get("name","可编辑岩岸")
	for key in ["id","name","rock_material_id","top_material_id"]:values.erase(key)
	for i in values.points.size():values.points[i]=Data.arr(Data.vec(values.points[i])-center)
	var next:Dictionary=previous.duplicate(true)
	next.merge({"uuid":str(args.get("id",previous.get("uuid","rock_bank_"+Crypto.new().generate_random_bytes(10).hex_encode()))),"kind":"box","position":Data.arr(center),"rotation":[0,0,0],"size":[1,1,1],"surface_id":"ground","collision":"walk","editor_name":name_,"rock_bank":values,"rock_bank_materials":materials},true)
	if next.uuid.is_empty() or not Data.valid(next):return fail("岩岸记录无效")
	if not Paint.missing([next]).is_empty():return fail("岩岸材质贴图缺失")
	if contains.is_valid() and not contains.call(next):return fail("岩岸超出当前隔离楼层")
	var sections:=Data.sections(next);var shapes:Array=[]
	for i in sections.size()-1:
		var points:Array[Vector3]=[]
		for row:Dictionary in [sections[i],sections[i+1]]:
			for point:Vector3 in [row.outer,row.inner]:points.append(point+center);points.append(point+center+Vector3.DOWN*values.height)
		shapes.append(Foot.from_points(points))
	var bounds:=Geometry.bounds([next])
	# Existing terrain can be covered by the new bank, but protection and all
	# above-ground structures remain authoritative. No terrain/road is deleted.
	for r:Dictionary in doc.records:
		if r.uuid==next.uuid or not bounds.intersects(Geometry.bounds([r])):continue
		if r.has("terrain_mesh"):
			if not editable.call(r):return fail("岩岸覆盖范围内有受保护的地形："+str(r.uuid))
			continue
		if r.get("surface_id")=="water" and r.get("collision")=="none":continue
		if r.has("bridge_mesh"):
			if bridge_overlap(shapes,r,bounds):return {"ok":false,"error":"岩岸与桥梁实际石构相交","conflicts":[r.uuid]}
			continue
		if Foot.batches_overlap(shapes,Foot.record_shapes(r)):
			var rows:Array=[]
			for i in shapes.size():
				if Foot.batches_overlap([shapes[i]],Foot.record_shapes(r)):rows.append(i)
			return {"ok":false,"error":"岩岸与现有物件或通道相交","conflicts":[r.uuid],"segments":rows}
	# This is explicit manual geometry authoring. Automatic town-layout rules
	# are not global placement bans; real geometry and protection remain checked.
	return {"ok":true,"record":next,"previous":previous,"samples":sections.size(),"triangles":(sections.size()-1)*36+32,"bounds":{"position":Data.arr(bounds.position),"size":Data.arr(bounds.size)}}
static func commit(doc,result:Dictionary)->void:
	doc.checkpoint()
	if result.previous.is_empty():doc.records.append(result.record)
	else:doc.records[doc.records.find(result.previous)]=result.record
static func apply(editor,args:Dictionary,preview:bool=false)->Dictionary:
	var guard:Dictionary=editor._gameplay.guard()
	if not guard.ok:return guard
	var result:=plan(editor._doc,args,editor._material_tool.library,Callable(editor,"_record_editable"),func(r):return editor._authoring.Settings.contains(r,editor._authoring.settings))
	if not result.ok:return result
	if preview:return {"ok":true,"id":result.record.uuid,"samples":result.samples,"triangles":result.triangles,"bounds":result.bounds,"parameters":recipe(result.record)}
	commit(editor._doc,result);editor._dirty=true;editor._rebuild()
	return {"ok":true,"id":result.record.uuid,"samples":result.samples,"triangles":result.triangles}
static func remove(editor,id:String)->Dictionary:
	var guard:Dictionary=editor._gameplay.guard()
	if not guard.ok:return guard
	var r:Dictionary=editor._doc._find(id)
	if not r.has("rock_bank") or not editor._record_editable(r):return fail("请选择可见、未锁定的当前楼层岩岸")
	editor._doc.checkpoint();editor._doc.records.erase(r);editor._dirty=true;editor._rebuild();return {"ok":true}
