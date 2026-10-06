extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const P=preload("res://scripts/world3d/house_prefab.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Contacts=preload("res://scripts/world3d/house_wall_contacts.gd")
const FORMAL="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const TARGET="D:/code/rmmo_runtime/cache/world3d/house_flicker/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/house_flicker"
var changed_faces:=0
var cap_faces:=0
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label_:String)->void:
	if not value:failures+=1;push_error(label_)

func vertex(a:Array,i:int,offset:Vector3)->Dictionary:
	var t:Variant=a[Mesh.ARRAY_TANGENT]
	return {"p":a[Mesh.ARRAY_VERTEX][i]+offset,"n":a[Mesh.ARRAY_NORMAL][i],"uv":a[Mesh.ARRAY_TEX_UV][i],"t":Vector4(t[i*4],t[i*4+1],t[i*4+2],t[i*4+3]) if t!=null and not t.is_empty() else Vector4(1,0,0,1)}

func split(poly:Array,axis:int,bound:float,lower:bool)->Array:
	var yes:Array=[];var no:Array=[]
	for i in poly.size():
		var a:Dictionary=poly[i];var b:Dictionary=poly[(i+1)%poly.size()]
		var inside:bool=a.p[axis]>=bound if lower else a.p[axis]<=bound
		var other:bool=b.p[axis]>=bound if lower else b.p[axis]<=bound
		(yes if inside else no).append(a)
		if inside!=other:
			var t:float=(bound-a.p[axis])/(b.p[axis]-a.p[axis]);var at:Dictionary={}
			for key in ["p","n","uv","t"]:at[key]=a[key].lerp(b[key],t)
			yes.append(at);no.append(at)
	return [yes,no]

func subtract(poly:Array,cut:Rect2,axis:int)->Array:
	var inside:Array=poly;var outside:Array=[];var u:=(axis+1)%3;var v:=(axis+2)%3
	var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
	for point:Dictionary in poly:low=low.min(Vector2(point.p[u],point.p[v]));high=high.max(Vector2(point.p[u],point.p[v]))
	var overlap:=cut.intersection(Rect2(low,high-low))
	if overlap.size.x<.00001 or overlap.size.y<.00001:return [poly]
	for edge in [[u,cut.position.x,true],[u,cut.end.x,false],[v,cut.position.y,true],[v,cut.end.y,false]]:
		if inside.size()<3:break
		var parts:=split(inside,edge[0],edge[1],edge[2]);inside=parts[0]
		if parts[1].size()>=3 and area(parts[1])>.00000001:outside.append(parts[1])
	return outside

func append_poly(st:SurfaceTool,poly:Array,offset:Vector3)->void:
	for i in range(1,poly.size()-1):
		if (poly[i].p-poly[0].p).cross(poly[i+1].p-poly[0].p).length_squared()<1e-14:continue
		for point:Dictionary in [poly[0],poly[i],poly[i+1]]:
			st.set_normal(point.n);st.set_uv(point.uv);st.set_tangent(Plane(Vector3(point.t.x,point.t.y,point.t.z),point.t.w));st.add_vertex(point.p-offset)

func area(poly:Array)->float:
	var result:=0.0
	for i in range(1,poly.size()-1):result+=(poly[i].p-poly[0].p).cross(poly[i+1].p-poly[0].p).length()/2
	return result

func repair(record:Dictionary,instance:Dictionary,plan:Dictionary,walls:Array)->bool:
	var old:=P.geometry(record);var source:Mesh=old.mesh
	var stone:=-1;var plaster:=-1;var interior:=-1
	for slot in source.get_surface_count():
		var mat:Material=source.surface_get_material(slot)
		var paint:Dictionary=mat.get_meta("runtime_paint_definition",{}) if mat!=null else {}
		if str(paint.get("texture_path","")).contains("/sandstone_floor/"):stone=slot
		if str(paint.get("texture_path","")).contains("/earthen_plaster/"):plaster=slot
		if str(paint.get("normal_path","")).contains("/fine_plaster/"):interior=slot
	if stone<0:return false
	var yaw:=Basis(Vector3.UP,deg_to_rad(instance.yaw));var offset:=yaw.inverse()*(B.vec(record.position)-B.vec(instance.position))
	var caps:Array=[]
	for r:Dictionary in plan.records:
		if r.get("building_shape")!="wall_grid" or r.wall_grid.axis!="z" or r.building.floor!=record.building.floor:continue
		var part:String=r.building.part
		if not (part.ends_with("/west/solid") or part.ends_with("/east/solid")):continue
		caps.append(AABB(B.vec(r.position)-B.vec(r.size)/2,B.vec(r.size)))
	var builders:Dictionary={};var did_change:=false
	for slot in [stone,interior,plaster]:
		if slot<0 or builders.has(slot):continue
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);builders[slot]=st
	for slot in builders:
		var a:Array=source.surfaces[slot];var indices:PackedInt32Array=a[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size(),3):
			var poly:Array=[vertex(a,indices[i],offset),vertex(a,indices[i+1],offset),vertex(a,indices[i+2],offset)]
			var normal:Vector3=poly[0].n;var axis:=normal.abs().max_axis_index();var plane:float=poly[0].p[axis]
			if slot==interior and plaster>=0 and absf(normal.z)>.999:
				var cap:=false
				for box:AABB in caps:
					var z:float=box.end.z if normal.z>0 else box.position.z
					if absf(plane-z)<.0001 and poly.all(func(v):return v.p.x>=box.position.x-.0001 and v.p.x<=box.end.x+.0001 and v.p.y>=box.position.y-.0001 and v.p.y<=box.end.y+.0001):cap=true;break
				if cap:append_poly(builders[plaster],poly,offset);cap_faces+=1;did_change=true;continue
			var polygons:Array=[poly]
			if slot==stone and absf(normal[axis])>.999:
				var u:=(axis+1)%3;var v:=(axis+2)%3;var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
				for point:Dictionary in poly:low=low.min(Vector2(point.p[u],point.p[v]));high=high.max(Vector2(point.p[u],point.p[v]))
				var cuts:=Contacts.cuts(walls,axis,plane,int(record.building.floor),Rect2(low,high-low))
				for cut:Rect2 in cuts:
					var next:Array=[]
					for polygon:Array in polygons:next.append_array(subtract(polygon,cut,axis))
					polygons=next
				var remaining:=0.0
				for polygon:Array in polygons:remaining+=area(polygon)
				if area(poly)-remaining>.0000001:did_change=true;changed_faces+=1
				else:polygons=[poly]
			for polygon:Array in polygons:append_poly(builders[slot],polygon,offset)
	if not did_change:return false
	var mesh:=Cpu.new();mesh.bounds=source.bounds;mesh.materials=source.materials.duplicate();mesh.surfaces=source.surfaces.duplicate()
	for slot in builders:
		builders[slot].index();mesh.surfaces[slot]=builders[slot].commit_to_arrays()
	var cache:Dictionary={};cache[[0]]={"mesh":mesh,"source":old.source}
	var data:=Cook.pack(cache,"","house_prefab_v1")
	check(Cook.valid_data(data),"repaired static mesh validates")
	var bytes:=var_to_bytes(data)
	record.house_prefab={"version":1,"sha256":Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	check(P.geometry(record).source.collision_faces()==old.source.collision_faces(),"collision unchanged")
	return true

func run()->void:
	if "--publish" in OS.get_cmdline_user_args():
		var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/repair.json"))
		check(report.failures==0 and FileAccess.get_sha256(FORMAL)==report.baseline and FileAccess.get_sha256(TARGET)==report.candidate,"unchanged source and verified candidate")
		if failures:quit(1);return
		var doc=Doc.open_file(FORMAL);var candidate=Doc.open_file(TARGET);doc.records=candidate.records;doc.map_meta=candidate.map_meta
		check(doc.save(FORMAL)==OK,"native publication");var reopened=Doc.open_file(FORMAL);check(reopened!=null and B.valid_ownership(reopened.map_meta,reopened.records),"published map reopens")
		print("CONTACTS_PUBLISHED failures=",failures);quit(1 if failures else 0);return
	var baseline:=FileAccess.get_sha256(FORMAL);var doc=Doc.open_file(FORMAL);var plans:Dictionary={};var changed:=0;var houses:Dictionary={}
	var originals:Array=doc.records.duplicate(true)
	for record:Dictionary in doc.records:
		if not record.has("house_prefab") or not record.has("building") or record.has("fixture"):continue
		var id:String=record.building.id;var instance:Dictionary=doc.map_meta.building_instances[id]
		if not plans.has(id):
			print("REPAIR_HOUSE ",plans.size()+1," ",id)
			var plan:=B.generate(instance.parameters);check(plan.ok,"valid source plan")
			plans[id]={"plan":plan,"walls":Contacts.solids(plan.records)}
		if repair(record,instance,plans[id].plan,plans[id].walls):
			changed+=1;houses[id]=true
			check(not repair(record.duplicate(true),instance,plans[id].plan,plans[id].walls),"no remaining wall/stone overlap or wrong exterior cap")
	check(B.valid_ownership(doc.map_meta,doc.records),"ownership unchanged")
	for i in originals.size():
		var old:Dictionary=originals[i];var now:Dictionary=doc.records[i]
		if old.has("fixture") or not old.has("building"):check(old==now,"doors, windows and non-house objects untouched")
	check(failures==0 and doc.save(TARGET)==OK,"save repaired candidate")
	var reopened=Doc.open_file(TARGET);check(reopened!=null and B.valid_ownership(reopened.map_meta,reopened.records),"candidate reopens")
	var report:={"baseline":baseline,"candidate":FileAccess.get_sha256(TARGET),"houses":houses.size(),"records":changed,"clipped_faces":changed_faces,"exterior_caps":cap_faces,"failures":failures}
	var file:=FileAccess.open(OUT+"/repair.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close();print("CONTACTS_REPAIRED ",JSON.stringify(report));quit(1 if failures else 0)
