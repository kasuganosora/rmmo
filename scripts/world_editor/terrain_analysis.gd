extends Node
## Session-only overlays of the same native heightfield triangles used by editing.
const T=preload("res://scripts/world3d/terrain_surface.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Batch=preload("res://scripts/world3d/terrain_stroke_batch.gd")
const Furrows=preload("res://scripts/world3d/terrain_furrows.gd")
const MAX_LINES:=16384
var editor:Node3D
var request:Dictionary={}
var last:Dictionary={}
var overlay:Node3D
var observed:=""
func version()->String:return City.token([str(editor._doc.get_instance_id()),editor._doc.authoring_revision,editor._authoring.settings])
static func schema()->Dictionary:return City.object({"id":City.text(),"interval":T.S.number(.1,100),"slope_threshold":T.S.number(0,2),"contours":{"type":"boolean"},"slopes":{"type":"boolean"},"seams":{"type":"boolean"},"surface":{"type":"string","enum":["all","upward","downward","walls"]},"height_min":T.S.number(-100000,100000),"height_max":T.S.number(-100000,100000)},["id"])
static func fail(message:String)->Dictionary:return {"ok":false,"code":"terrain_analysis_unsupported","error":message}
static func supported(r:Dictionary)->bool:return r.has("terrain_mesh") and T.valid(r) and r.rotation[0]==0 and r.rotation[2]==0 and Furrows.maximum_height(r)==0

static func edge_height(r:Dictionary,p:Vector3)->float:
	var local:Vector3=T.transform(r).affine_inverse()*p
	var hx:float=r.size[0]*.5;var hz:float=r.size[2]*.5
	if absf(local.x)>hx+.001 or absf(local.z)>hz+.001 or (absf(absf(local.x)-hx)>.001 and absf(absf(local.z)-hz)>.001):return NAN
	local.x=clampf(local.x,-hx,hx);local.z=clampf(local.z,-hz,hz)
	return T.sample(r,local)+float(r.position[1])

static func build(records:Array,args:Dictionary)->Dictionary:
	var error:=T.S.validate(args,schema())
	if not error.is_empty():return {"ok":false,"code":"invalid_arguments","error":error}
	var matches:Array=records.filter(func(r):return r.uuid==args.id)
	if not matches.is_empty() and matches[0].has("terrain_volume"):return preload("res://scripts/world_editor/terrain_volume_analysis.gd").build(matches[0],args)
	if args.has("surface") or args.has("height_min") or args.has("height_max"):return fail("表面方向与标高筛选仅用于体积地形；高度场请省略这些参数")
	if matches.is_empty() or not supported(matches[0]):return fail("覆盖层需要无倾斜、无垄沟的原生高度场")
	var r:Dictionary=matches[0];var t:Dictionary=r.terrain_mesh;var pose:=T.transform(r)
	var interval:float=args.get("interval",1.);var threshold:float=args.get("slope_threshold",.15)
	var contours:Array=[];var slopes:Array=[];var seams:Array=[];var seen:Dictionary={};var max_grade:=0.;var max_step:=0.
	for z in int(t.rows):
		for x in int(t.columns):
			if not T.solid(t,x,z):continue
			var vertices:=T.cell(r,x,z)
			for indices:Array in [[0,1,2],[0,2,3]]:
				var points:Array[Vector3]=[]
				for i:int in indices:points.append(pose*vertices[i])
				var normal:Vector3=(points[1]-points[0]).cross(points[2]-points[0]).normalized()
				var grade:=Vector2(normal.x,normal.z).length()/absf(normal.y);max_grade=maxf(max_grade,grade)
				if args.get("slopes",true):slopes.append({"points":points.map(func(p):return City.xyz(p)),"grade":grade,"steep":grade>threshold,"cell":[x,z]})
				if not args.get("contours",true):continue
				var low:float=minf(points[0].y,minf(points[1].y,points[2].y));var high:float=maxf(points[0].y,maxf(points[1].y,points[2].y))
				if high-low<.000001:continue
				var first:=ceili(low/interval);var end:=floori(high/interval)
				if end-first>MAX_LINES or contours.size()+end-first>MAX_LINES:return fail("等高线超过 16384 段预算，请增大等高距")
				for level in range(first,end+1):
					var height:float=level*interval;var hits:Array[Vector3]=[]
					for i in 3:
						var a:Vector3=points[i];var b:Vector3=points[(i+1)%3]
						if absf(b.y-a.y)<.000001:continue
						var fraction:float=(height-a.y)/(b.y-a.y)
						if fraction<0 or fraction>1:continue
						var hit:=a.lerp(b,fraction)
						if not hits.any(func(p):return p.distance_squared_to(hit)<.00000001):hits.append(hit)
					if hits.size()!=2 or hits[0].distance_squared_to(hits[1])<.00000001:continue
					var keys:Array=[str(hits[0].snapped(Vector3.ONE*.0001)),str(hits[1].snapped(Vector3.ONE*.0001))];keys.sort();var key:=str(keys)
					if seen.has(key):continue
					seen[key]=true;contours.append({"height":height,"points":[City.xyz(hits[0]),City.xyz(hits[1])]})
	if args.get("seams",true):
		var neighbors:Array=records.filter(func(n):return n.uuid!=r.uuid and supported(n) and Batch.adjacent(r,n))
		if neighbors.size()>32:return fail("相邻地形超过 32 块分析预算")
		for neighbor:Dictionary in neighbors:
			var knots:Dictionary={}
			for vertex:Dictionary in Batch.edge_vertices(r)+Batch.edge_vertices(neighbor):
				var p:Vector3=vertex.p;var a:=edge_height(r,p);var b:=edge_height(neighbor,p)
				if not is_finite(a) or not is_finite(b):continue
				var key:=str(Vector2(p.x,p.z).snapped(Vector2.ONE*.0001))
				if knots.has(key):continue
				knots[key]=true;var step:=absf(a-b);max_step=maxf(max_step,step)
				seams.append({"neighbor_id":neighbor.uuid,"from":[p.x,a,p.z],"to":[p.x,b,p.z],"step":step})
	return {"ok":true,"id":r.uuid,"interval":interval,"slope_threshold":threshold,"contours":contours,"slopes":slopes,"seams":seams,"max_grade":max_grade,"max_boundary_step":max_step,"holes":t.holes.count(true),"source":"native_heightfield_triangles","scope":"surface analysis only; boundary knots of compatible neighbors, holes omitted; not a walkability certificate"}

func query(args:Dictionary)->Dictionary:
	var ready:Dictionary=editor._city.guard()
	if not ready.ok:return ready
	var records:Array=editor._doc.records.filter(func(r):return not r.get("editor_hidden",false) and editor._authoring.Settings.contains(r,editor._authoring.settings))
	var result:=build(records,args)
	if result.ok:result.base_version=version();result.geometry_token=City.token(result)
	return result

func configure(args:Dictionary)->Dictionary:
	var spec:=schema();spec.properties.enabled={"type":"boolean"};spec.required=["enabled"]
	var issue:=T.S.validate(args,spec)
	if not issue.is_empty():return {"ok":false,"code":"invalid_arguments","error":issue}
	if not args.enabled:request={};clear();last={};return state()
	var inputs:=args.duplicate(true);inputs.erase("enabled")
	var result:=query(inputs)
	if not result.ok:return result
	request=inputs;last=result;observed=version();draw(result)
	return state()

func state()->Dictionary:
	var summary:=last.duplicate();summary.erase("contours");summary.erase("slopes");summary.erase("seams")
	return {"ok":true,"enabled":not request.is_empty(),"request":request.duplicate(true),"result":summary,"line_count":last.get("contours",[]).size(),"triangle_count":last.get("slopes",[]).size(),"seam_count":last.get("seams",[]).size()}

func clear()->void:
	if is_instance_valid(overlay):overlay.free()
	overlay=null
func add_mesh(mesh:ImmediateMesh,color:Color)->void:
	if mesh.get_surface_count()==0:return
	var visual:=MeshInstance3D.new();visual.mesh=mesh;visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.vertex_color_use_as_albedo=true;material.albedo_color=color;material.cull_mode=BaseMaterial3D.CULL_DISABLED;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	visual.material_override=material;overlay.add_child(visual)
func draw(result:Dictionary)->void:
	clear();overlay=Node3D.new();overlay.name="TerrainAnalysisOverlay";editor.add_child(overlay)
	if not result.slopes.is_empty():
		var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for triangle:Dictionary in result.slopes:
			mesh.surface_set_color(Color(1.,.25,.08,.55) if triangle.steep else Color(.15,.7,.3,.28))
			for point:Array in triangle.points:mesh.surface_add_vertex(City.vec(point)+City.vec(triangle.get("normal",[0,1,0]))*.025)
		mesh.surface_end();add_mesh(mesh,Color.WHITE)
	if not result.contours.is_empty() or not result.seams.is_empty():
		var lines:=ImmediateMesh.new();lines.surface_begin(Mesh.PRIMITIVE_LINES)
		for contour:Dictionary in result.contours:
			lines.surface_set_color(Color(.8,.95,1.))
			for point:Array in contour.points:lines.surface_add_vertex(City.vec(point)+City.vec(contour.get("normal",[0,1,0]))*.045)
		for seam:Dictionary in result.seams:
			lines.surface_set_color(Color(1.,.2,1.) if seam.step>.002 else Color(.1,.8,1.))
			var a:=City.vec(seam.from)+Vector3.UP*.05;var b:=City.vec(seam.to)+Vector3.UP*.05
			if a.distance_squared_to(b)<.00001:b=a+Vector3.UP*.12
			lines.surface_add_vertex(a);lines.surface_add_vertex(b)
		lines.surface_end();add_mesh(lines,Color.WHITE)
func _process(_delta:float)->void:
	if request.is_empty() or observed==version():return
	if not editor._city.guard().ok:clear();return
	observed=version();last=query(request)
	if last.ok:draw(last)
	else:clear()
func _exit_tree()->void:clear()
