extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const F=preload("res://scripts/world3d/building_fixtures.gd")
const FORMAL="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const TARGET="D:/code/rmmo_runtime/cache/world3d/timber_door_review/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/timber_door"
const ASSET="D:/code/rmmo_runtime/assets/timber_door/timber_door_mesh.json"
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if "--publish" in OS.get_cmdline_user_args():
		var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/upgrade.json"))
		check(report.failures==0 and FileAccess.get_sha256(FORMAL)==report.baseline and FileAccess.get_sha256(TARGET)==report.candidate,"reviewed candidate and unchanged formal baseline")
		var physical:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/physical.json"))
		check(report.get("asset")==FileAccess.get_sha256(ASSET) and physical.get("candidate")==report.candidate and physical.get("failures") == 0 and physical.get("houses")==24,"current approved model and physical acceptance")
		if failures:quit(1);return
		var original=Doc.open_file(FORMAL);var reviewed=Doc.open_file(TARGET)
		original.records=reviewed.records;original.map_meta=reviewed.map_meta
		check(original.save(FORMAL)==OK,"native atomic conflict-checked publication")
		var reopened=Doc.open_file(FORMAL);check(reopened!=null and B.valid_ownership(reopened.map_meta,reopened.records),"published ownership reopens")
		print("PUBLISHED ",FileAccess.get_sha256(FORMAL));quit(1 if failures else 0);return
	var baseline:=FileAccess.get_sha256(FORMAL);var doc=Doc.open_file(FORMAL)
	if doc==null:quit(1);return
	var original:Array=doc.records.duplicate(true);var count:=0;var plans:Dictionary={};var changed:Dictionary={}
	for record:Dictionary in doc.records:
		if not record.has("building") or record.get("fixture",{}).get("kind")!="door":continue
		check(not record.get("locked",false),"leaf is not locked")
		if record.get("locked",false):continue
		var id:String=record.building.id;var instance:Dictionary=doc.map_meta.building_instances[id]
		if not plans.has(id):plans[id]=B.generate(instance.parameters)
		var plan:Dictionary=plans[id];check(plan.ok,"door source plan "+id)
		if not plan.ok:continue
		var leaves:Array=plan.records.filter(func(r):return r.get("fixture",{}).get("id")==record.fixture.id)
		check(leaves.size()==1,"one authored leaf for "+record.fixture.id)
		if leaves.size()!=1:continue
		var frozen:=Prefab.bake(leaves);check(frozen.ok and frozen.records.size()==1,"single frozen moving leaf")
		if not frozen.ok:continue
		var replacement:Dictionary=frozen.records[0];var source:Dictionary=leaves[0]
		var yaw:=Basis(Vector3.UP,deg_to_rad(instance.yaw));var origin:=B.vec(instance.position)
		replacement.position=B.arr(origin+yaw*B.vec(replacement.position));replacement.rotation=B.arr(yaw.get_euler()*180/PI)
		replacement.uuid=record.uuid;replacement.building=record.building.duplicate(true);replacement.fixture.open=record.fixture.open
		for key in ["editor_group","editor_group_name","editor_name","locked","hidden"]:
			if record.has(key):replacement[key]=record[key]
		# Preserve native identity; only this articulated leaf is replaced.
		changed[record.uuid]=true;record.clear();record.merge(replacement)
		instance.signatures[record.building.part]=B.geometry_signature(record)
		var mesh:Dictionary=Prefab.geometry(record)
		check(mesh.source.collision_faces().size()==36,"12 collision triangles per leaf")
		check(mesh.mesh.get_surface_count()==2 and mesh.mesh.collision_faces().size()==846*3,"approved 846-triangle two-material geometry")
		var tinted:=false
		for material:Material in mesh.mesh.materials:
			if material is StandardMaterial3D and material.albedo_texture!=null:tinted=material.vertex_color_use_as_albedo
		check(tinted,"wood texture and three board tones survive freezing")
		var pivots_ok:=true
		for angle in [0.0,37.0,90.0,181.0,270.0]:
			var rotation:=Basis(Vector3.UP,deg_to_rad(angle));var closed:=Transform3D(rotation,Vector3(12,3,-9))
			var pivot:=closed*B.vec(source.fixture.pivot)
			for amount in [0.0,.25,.5,.75,1.0]:pivots_ok=pivots_ok and (F.pose(closed,source.fixture,amount)*B.vec(source.fixture.pivot)).distance_to(pivot)<.0001
		check(pivots_ok,"hinge remains fixed across yaw and opening fractions")
		count+=1
	var untouched:=true
	for i in original.size():
		if not changed.has(original[i].uuid) and doc.records[i]!=original[i]:untouched=false
	check(untouched and doc.records.size()==original.size(),"non-door records and component count unchanged")
	check(B.valid_ownership(doc.map_meta,doc.records),"frozen building identity preserved")
	check(count>24,"entrances and interior leaves replaced")
	if failures==0:check(doc.save(TARGET)==OK,"isolated candidate saved natively")
	if failures==0:
		var reopened=Doc.open_file(TARGET);check(reopened!=null and B.valid_ownership(reopened.map_meta,reopened.records),"candidate reopens")
	var report:={"baseline":baseline,"candidate":FileAccess.get_sha256(TARGET),"asset":FileAccess.get_sha256(ASSET),"doors":count,"houses":plans.size(),"failures":failures}
	var file:=FileAccess.open(OUT+"/upgrade.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("DOOR_UPGRADE ",JSON.stringify(report));quit(1 if failures else 0)
