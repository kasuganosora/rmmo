extends SceneTree
## Read-only native array diagnosis. Does not render, regenerate, or write a map.
const Doc=preload("res://scripts/world3d/world_document.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Plan=preload("res://scripts/world3d/fortification_plan.gd")
const Fit=preload("res://scripts/world3d/fortification_terrain.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const MAP="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf"
var report:Dictionary={"read_only":true,"scope":"native frozen attribute and source recipe diagnosis","rows":[]}
func _init()->void:call_deferred("run")
static func v3(v:Vector3)->Array:return [v.x,v.y,v.z]
static func v2(v:Vector2)->Array:return [v.x,v.y]
static func inspect(a:Array,pose:Transform3D)->Dictionary:
	var verts:PackedVector3Array=a[Mesh.ARRAY_VERTEX];var ts:PackedFloat32Array=a[Mesh.ARRAY_TANGENT] if a[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
	var ns:PackedVector3Array=a[Mesh.ARRAY_NORMAL];var uv:PackedVector2Array=a[Mesh.ARRAY_TEX_UV]
	var bad:Dictionary={};var ids:PackedInt32Array=a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	if ids.is_empty():ids=PackedInt32Array(range(verts.size()))
	for i in range(0,ts.size(),4):
		var t:=Vector3(ts[i],ts[i+1],ts[i+2])
		if t.length_squared()<.1:bad[i/4]={"vertex":i/4,"local":v3(verts[i/4]),"world":v3(pose*verts[i/4]),"normal":v3(ns[i/4]),"tangent":v3(t)+[ts[i+3]],"uv":v2(uv[i/4]),"triangles":[]}
	var effective:=0;var zero:=0
	for k in range(0,ids.size(),3):
		var abc:=[ids[k],ids[k+1],ids[k+2]]
		if not abc.any(func(i):return bad.has(i)):continue
		var p:Vector3=verts[abc[0]];var q:Vector3=verts[abc[1]];var r:Vector3=verts[abc[2]]
		var area:float=(q-p).cross(r-p).length()*.5;var u:Vector2=uv[abc[1]]-uv[abc[0]];var w:Vector2=uv[abc[2]]-uv[abc[0]]
		var row:={"triangle":k/3,"indices":abc,"area_m2":area,"uv_determinant":u.cross(w),"points":[v3(p),v3(q),v3(r)]}
		if area>1e-10:effective+=1
		else:zero+=1
		for i:int in abc:
			if bad.has(i):bad[i].triangles.append(row)
	return {"vertices":verts.size(),"bad_count":bad.size(),"referenced_bad_count":bad.values().filter(func(r):return not r.triangles.is_empty()).size(),"bad_effective_triangles":effective,"bad_zero_triangles":zero,"bad":bad.values()}
func run()->void:
	report.map=MAP;report.map_sha256=FileAccess.get_sha256(MAP)
	var doc=Doc.open_file(MAP)
	if doc==null:quit(1);return
	var settings:Dictionary=City.resolve(doc.map_meta).fortifications[0].settings
	report.settings={"follow_terrain":settings.follow_terrain,"height":settings.height,"base_height":settings.base_height}
	var planned:=Plan.new().build(settings);var fitted:=Fit.fit(planned.records,doc.records.filter(func(r):return r.has("terrain_mesh")),settings.base_height,settings.foundation,settings)
	if not fitted.ok:report.error=fitted;finish();return
	report.source_count=fitted.records.size()
	var groups:Dictionary={};var source_groups:Dictionary={}
	for source:Dictionary in fitted.records:
		var p:=Frozen.vec(source.position);var tower:bool=source.fortification.role in ["tower_stair","corner_tower"];var hinge_key:Array=[]
		if source.has("fixture"):
			var closed:=Transform3D(Basis.from_euler(Frozen.vec(source.rotation)*PI/180),p)
			hinge_key=Frozen.arr((closed*Frozen.vec(source.fixture.pivot)).snapped(Vector3.ONE*.0001))
		var key:=str([floori(p.x/32),floori(p.z/32),source.get("collision","block"),source.get("fixture",{}).get("id",""),source.get("fixture",{}).get("angle",0),hinge_key,source.uuid if tower else ""])
		if not groups.has(key):groups[key]=groups.size()
		var part:="baked_"+str(groups[key])
		if not source_groups.has(part):source_groups[part]=[]
		source_groups[part].append(source)
	for record:Dictionary in doc.records:
		if not record.has("fortification") or not record.has("house_prefab"):continue
		var data:=Frozen.decode(record.house_prefab);var rendered:Dictionary={}
		for entry:Array in data.entries:rendered[entry[1][0]]=true
		for mi:int in rendered:
			var mesh:Dictionary=data.meshes[mi]
			for si in mesh.surfaces.size():
				var row:=inspect(mesh.surfaces[si],Transform3D(Basis.IDENTITY,Frozen.vec(record.position)))
				if row.bad_count==0:continue
				row.record=record.uuid;row.part=record.fortification.part;row.mesh=mi;row.surface=si;row.material=data.materials[mesh.materials[si]]
				row.sources=[]
				for source:Dictionary in source_groups.get(row.part,[]):
					var box:=AABB(-Frozen.vec(source.size)*.5,Frozen.vec(source.size)).grow(.03);var pose:=Transform3D(Basis.from_euler(Frozen.vec(source.rotation)*PI/180),Frozen.vec(source.position));var matches:Array=[]
					for vertex:Dictionary in row.bad:
						var point:Vector3=pose.affine_inverse()*Frozen.vec(vertex.world)
						if source.has("terrain_grade"):point.y-=source.terrain_grade[0]*point.x+source.terrain_grade[1]*point.z
						if box.has_point(point):matches.append(vertex.vertex)
					if not matches.is_empty():row.sources.append({"part":source.fortification.part,"role":source.fortification.role,"record":source,"bad_vertex_candidates":matches})
				report.rows.append(row)
	report.totals={"bad_surfaces":report.rows.size(),"bad_vertices":0,"bad_referenced":0,"effective_triangles":0,"zero_triangles":0}
	for row:Dictionary in report.rows:
		report.totals.bad_vertices+=row.bad_count;report.totals.bad_referenced+=row.referenced_bad_count;report.totals.effective_triangles+=row.bad_effective_triangles;report.totals.zero_triangles+=row.bad_zero_triangles
	finish()
func finish()->void:
	report.map_unchanged=FileAccess.get_sha256(MAP)==report.map_sha256
	FileAccess.open(OUT+"/fortification_tangent_probe.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify({"totals":report.get("totals",{}),"map_unchanged":report.map_unchanged,"error":report.get("error","")}));quit(0)
