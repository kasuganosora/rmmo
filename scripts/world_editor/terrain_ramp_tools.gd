extends RefCounted
## Endpoint constraints over native terrain triangles, sharing the joint-layout transaction.
const T=preload("res://scripts/world3d/terrain_surface.gd")
const Batch=preload("res://scripts/world3d/terrain_stroke_batch.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Support=preload("res://scripts/world_editor/residential_support.gd")
const Layout=preload("res://scripts/world_editor/terrain_layout_tools.gd")
const Furrows=preload("res://scripts/world3d/terrain_furrows.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const HEIGHT_TOLERANCE:=0.0002
const MAX_GRADE:=0.15

static func sample_schema()->Dictionary:
	return City.object({"id":City.text(),"point":{"type":"array","items":{"type":"number","minimum":-100000,"maximum":100000},"minItems":2,"maxItems":2}},["id","point"])
static func schema()->Dictionary:
	return City.object({"id":City.text(),"start":T.S.vector(-100000,100000),"end":T.S.vector(-100000,100000),"width":{"type":"number","minimum":1,"maximum":32},"blend_margin":{"type":"number","minimum":0.25,"maximum":16},"cross_tiles":{"type":"boolean"},"expected_token":City.text(64)},["id","start","end","width","blend_margin"])
static func fail(message:String,detail:Dictionary={})->Dictionary:
	return {"ok":false,"code":"terrain_ramp_constraint","error":message}.merged(detail,true)

static func sample(editor:Node3D,args:Dictionary)->Dictionary:
	var error:=T.S.validate(args,sample_schema())
	if not error.is_empty():return fail(error)
	var seed:Dictionary=editor._doc._find(args.id)
	if not seed.has("terrain_mesh") or not T.valid(seed):return fail("请选择有效高度场地形")
	var connected:Array=Batch.connected(editor._doc.records,seed).map(func(r):return r.uuid)
	var found:=height_at(editor._doc,args.point)
	if found.ok and not found.terrain_ids.any(func(id):return connected.has(id)):return fail("取高点不在所选地形及相邻地形上")
	return found

## Query the actual top triangle, never the brush's hole/plane fallback.
static func height_at(doc,point:Array)->Dictionary:
	var hits:Array=[];var hole:=false
	for record:Dictionary in doc.records:
		if not record.has("terrain_mesh") and not record.has("terrain_volume"):continue
		if record.has("terrain_volume") or record.rotation[0]!=0 or record.rotation[2]!=0:
			var box:AABB=Geometry.bounds([record])
			if point[0]>=box.position.x and point[0]<=box.end.x and point[1]>=box.position.z and point[1]<=box.end.z:return fail("取高暂不支持倾斜、体积或多层地形",{"terrain_id":record.uuid})
			continue
		if not T.valid(record):return fail("地形数据无效",{"terrain_id":record.uuid})
		var angle:=deg_to_rad(float(record.rotation[1]));var dx:float=point[0]-record.position[0];var dz:float=point[1]-record.position[2]
		var t:Dictionary=record.terrain_mesh
		var u:float=((cos(angle)*dx-sin(angle)*dz)/record.size[0]+.5)*t.columns
		var v:float=((sin(angle)*dx+cos(angle)*dz)/record.size[2]+.5)*t.rows
		if u<0 or v<0 or u>t.columns or v>t.rows:continue
		if record.get("editor_hidden",false) or record.get("collision","walk")=="none" or Furrows.maximum_height(record)>0:return fail("取高需要可见、有碰撞且无垄沟的高度场",{"terrain_id":record.uuid})
		var x:=mini(int(u),int(t.columns)-1);var z:=mini(int(v),int(t.rows)-1)
		if not T.solid(t,x,z):hole=true;continue
		var corners:=T.cell(record,x,z);u-=x;v-=z
		var indices:Array=[0,1,2] if u>=v else [0,2,3]
		var local_height:float=corners[0].y+(corners[1].y-corners[0].y)*u+(corners[2].y-corners[1].y)*v if u>=v else corners[0].y+(corners[2].y-corners[3].y)*u+(corners[3].y-corners[0].y)*v
		var normal:Vector3=(corners[indices[2]]-corners[0]).cross(corners[indices[1]]-corners[0]).normalized()
		normal=T.transform(record).basis*normal
		hits.append({"id":record.uuid,"height":float(record.position[1])+local_height,"normal":[normal.x,normal.y,normal.z],"cell":[x,z],"interior":u+x>0.000001 and u+x<t.columns-0.000001 and v+z>0.000001 and v+z<t.rows-0.000001})
	if hits.is_empty() or hole:return fail("取高点存在洞口或没有唯一实体地面")
	if hits.size()>1:
		for hit:Dictionary in hits:
			if hit.interior or absf(hit.height-hits[0].height)>HEIGHT_TOLERANCE:return fail("取高点存在重叠地形或接缝高差")
	return {"ok":true,"position":[point[0],hits[0].height,point[1]],"height":hits[0].height,"normal":hits[0].normal,"terrain_ids":hits.map(func(h):return h.id),"cell":hits[0].cell,"source":"native_terrain_triangle"}

static func corridor(args:Dictionary)->Array:
	var start:Array=args.start;var end:Array=args.end
	var dx:float=end[0]-start[0];var dz:float=end[2]-start[2];var length:=sqrt(dx*dx+dz*dz)
	var sx:float=-dz/length*args.width*.5;var sz:float=dx/length*args.width*.5
	return [[start[0]-sx,start[2]-sz],[end[0]-sx,end[2]-sz],[end[0]+sx,end[2]+sz],[start[0]+sx,start[2]+sz]]

static func region(doc,polygon:Array)->Dictionary:
	var origin:=Vector3(polygon[0][0],0,polygon[0][1]);var local:Array=[]
	for p:Array in polygon:local.append([p[0]-float(origin.x),p[1]-float(origin.z)])
	var component:={"record_id":"","part":"terrain_ramp","foundation_id":"","polygon":local,"bounds":Support.bounds(local),"area":Support.area(local),"floor_bottom":0.,"foundation_bottom":0.}
	var result:=Support.region(doc,component,origin,{"terrain_candidates":0,"cells_visited":0,"triangle_clips":0,"overlaps":0},true)
	result.origin=origin
	return result

static func request_token(editor:Node3D,args:Dictionary)->String:
	var inputs:=args.duplicate();inputs.erase("expected_token")
	return City.token({"request":inputs,"document":editor._doc.get_instance_id(),"revision":editor._doc.authoring_revision,"records":editor._doc.records,"meta":editor._doc.map_meta})

## Shared recipe and final-state proof also serve the residential site candidate.
static func recipe(editor:Node3D,args:Dictionary)->Dictionary:
	var error:=T.S.validate(args,schema())
	if not error.is_empty():return fail(error)
	var token:=request_token(editor,args)
	if args.has("expected_token") and args.expected_token!=token:return fail("地形或参数已变化，请重新预览坡道",{"code":"terrain_ramp_stale_preview"})
	var dx:float=args.end[0]-args.start[0];var dz:float=args.end[2]-args.start[2];var length:=sqrt(dx*dx+dz*dz)
	if length<1 or length>48:return fail("两端水平距离须为 1–48 米")
	var grade:float=(args.end[1]-args.start[1])/length
	if absf(grade)>MAX_GRADE:return fail("两端高差超过 15% 坡度，请延长坡道或调整标高",{"grade":grade,"minimum_length":absf(args.end[1]-args.start[1])/MAX_GRADE})
	if absf(args.start[1])>1000 or absf(args.end[1])>1000:return fail("两端标高须在 -1000–1000 米内")
	var polygon:=corridor(args);var original:=region(editor._doc,polygon)
	if not original.ok:original.erase("origin");return original
	var seed:Dictionary=editor._doc._find(args.id)
	if not seed.has("terrain_mesh") or not T.valid(seed):return fail("请选择有效高度场地形")
	var allowed:Array=Batch.connected(editor._doc.records,seed).map(func(r):return r.uuid) if args.get("cross_tiles",true) else [seed.uuid]
	var padding:=0.
	for id:String in original.terrain_ids:
		var record:Dictionary=editor._doc._find(id)
		if not allowed.has(id):return fail("坡道超出所选地形范围，请选择相邻地形并启用跨块同步",{"terrain_id":id})
		if record.has("surface_paint"):return fail("坡道覆盖手刷地形，请先处理手刷表面",{"terrain_id":id})
		if not editor._record_editable(record):return fail("坡道覆盖锁定、隐藏或隔层地形",{"terrain_id":id})
		padding=maxf(padding,Vector2(float(record.size[0])/record.terrain_mesh.columns,float(record.size[2])/record.terrain_mesh.rows).length())
	# A full cell diagonal beyond the requested corridor puts every intersecting
	# native triangle vertex on the target plane, including both endpoint edges.
	if length+2*padding>64 or args.width+2*padding>64:return fail("网格过粗，端点约束所需平台超出 64 米范围，请细化地形或缩短坡道")
	var stroke:={"id":args.id,"mode":"flatten","shape":"rectangle","points":[[(args.start[0]+args.end[0])*.5,(args.start[2]+args.end[2])*.5]],"plot_width":length+2*padding,"plot_depth":args.width+2*padding,"plot_yaw":-rad_to_deg(atan2(dz,dx)),"plot_grade":[grade,0.],"target_height":(args.start[1]+args.end[1])*.5,"strength":1.,"blend_margin":args.blend_margin,"cross_tiles":args.get("cross_tiles",true)}
	return {"ok":true,"stroke":stroke,"token":token,"polygon":polygon,"grade":grade,"length":length,"padding":padding}

static func prove(before,after,args:Dictionary,prepared:Dictionary,terrain_ids:Array)->Dictionary:
	var polygon:Array=prepared.polygon;var grade:float=prepared.grade;var length:float=prepared.length
	var dx:float=args.end[0]-args.start[0];var dz:float=args.end[2]-args.start[2]
	var proof:=region(after,polygon)
	if not proof.ok:proof.erase("origin");return proof
	var max_error:=0.;var max_grade:=0.
	for piece:Dictionary in proof.pieces:
		for i in piece.polygon.size():
			var p:Array=piece.polygon[i]
			var along:float=((float(proof.origin.x)+p[0]-args.start[0])*dx+(float(proof.origin.z)+p[1]-args.start[2])*dz)/length
			max_error=maxf(max_error,absf(piece.heights[i]-(args.start[1]+grade*along)))
		var a:Array=piece.corners[0];var b:Array=piece.corners[1];var c:Array=piece.corners[2]
		var det:float=(b[0]-a[0])*(c[2]-a[2])-(b[2]-a[2])*(c[0]-a[0])
		var gx:float=((b[1]-a[1])*(c[2]-a[2])-(c[1]-a[1])*(b[2]-a[2]))/det
		var gz:float=((b[0]-a[0])*(c[1]-a[1])-(c[0]-a[0])*(b[1]-a[1]))/det
		max_grade=maxf(max_grade,sqrt(gx*gx+gz*gz))
	var seams:=Support.seam_steps(proof.pieces,proof.origin)
	if not seams.ok:return seams
	if max_error>HEIGHT_TOLERANCE or max_grade>MAX_GRADE+0.00001 or seams.max_step>HEIGHT_TOLERANCE:return fail("实际地形未满足两端标高、全宽坡度或接缝约束；请调整范围或网格",{"max_height_error":max_error,"max_grade":max_grade,"max_seam_step":seams.max_step})
	return {"ok":true,"token":prepared.token,"start":args.start,"end":args.end,"length":length,"width":args.width,"grade":grade,"max_grade":max_grade,"max_height_error":max_error,"height_tolerance":HEIGHT_TOLERANCE,"max_seam_step":seams.max_step,"corridor":polygon,"grid_padding":prepared.padding,"blend_margin":args.blend_margin,"earthwork":earthwork(before,after,terrain_ids),"scope":"full_width_native_heightfield; outer_blend_not_walkability_certified"}

static func prepare(editor:Node3D,args:Dictionary)->Dictionary:
	var planned:=recipe(editor,args)
	if not planned.ok:return planned
	var result:=Layout.prepare(editor,{"strokes":[planned.stroke]})
	if not result.ok:return result
	var candidate:=Layout.Doc.new();candidate.records=result.get("records",editor._doc.records)
	var proof:=prove(editor._doc,candidate,args,planned,result.terrain_ids)
	if not proof.ok:return proof
	result.merge(proof,true);result.affected_ids=result.changed_ids
	return result

## Integrate the positive/negative linear height delta over each native triangle.
static func positive_volume(vertices:Array)->float:
	var polygon:Array=[]
	for i in vertices.size():
		var a:Vector3=vertices[i];var b:Vector3=vertices[(i+1)%vertices.size()]
		if a.y>=0:polygon.append(a)
		if (a.y>=0)!=(b.y>=0):polygon.append(a.lerp(b,a.y/(a.y-b.y)))
	var total:=0.
	for i in range(1,polygon.size()-1):
		var a:Vector3=polygon[0];var b:Vector3=polygon[i];var c:Vector3=polygon[i+1]
		var area:=absf((b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x))*.5
		total+=area*(a.y+b.y+c.y)/3.
	return total
static func earthwork(before,after,ids:Array)->Dictionary:
	var cut:=0.;var fill:=0.;var max_cut:=0.;var max_fill:=0.
	for id:String in ids:
		var a:Dictionary=before._find(id);var b:Dictionary=after._find(id);var t:Dictionary=a.terrain_mesh
		for z in int(t.rows):
			for x in int(t.columns):
				if not T.solid(t,x,z):continue
				var old:=T.cell(a,x,z);var next:=T.cell(b,x,z)
				for indices:Array in [[0,1,2],[0,2,3]]:
					var vertices:Array=[];var negative:Array=[]
					for i:int in indices:
						var delta:float=next[i].y-old[i].y;max_cut=maxf(max_cut,-delta);max_fill=maxf(max_fill,delta)
						vertices.append(Vector3(old[i].x,delta,old[i].z));negative.append(Vector3(old[i].x,-delta,old[i].z))
					fill+=positive_volume(vertices);cut+=positive_volume(negative)
	return {"cut_m3":cut,"fill_m3":fill,"max_cut_m":max_cut,"max_fill_m":max_fill,"scope":"all_changed_solid_triangles_including_padding_and_blend"}
static func preview(editor:Node3D,args:Dictionary)->Dictionary:
	return Layout.public_result(prepare(editor,args))
static func apply(editor:Node3D,args:Dictionary)->Dictionary:
	return Layout.commit_prepared(editor,prepare(editor,args))
