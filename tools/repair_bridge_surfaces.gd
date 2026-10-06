extends "res://tools/arrange_town_reference_styles.gd"
const Repair=preload("res://scripts/world3d/bridge_surface_repair.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const REPORT="D:/code/rmmo_runtime/review_artifacts/bridge_surfaces_rim_20261006"
var camera:Camera3D
func area(mesh:Mesh)->float:
	var faces:=mesh.get_faces();var total:=0.
	for i in range(0,faces.size(),3):total+=(faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).length()*.5
	return total
func _initialize()->void:
	OUT=REPORT;run.call_deferred()
func capture(label_:String,eye:Vector3,target:Vector3)->void:
	camera.global_position=eye;camera.look_at(target)
	for i in 20:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(REPORT+"/"+label_+".png")
func run()->void:
	DirAccess.make_dir_recursive_absolute(REPORT)
	if "--publish" in OS.get_cmdline_user_args():
		var plan:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(REPORT+"/plan.json"))
		check(plan.failures==0 and FileAccess.file_exists(REPORT+"/close_after.png"),"validated and reviewed bridge surfaces")
		var doc=Doc.open_file(FORMAL);check(doc!=null,"formal map readable")
		if failures:quit(1);return
		var original:Array=doc.records.duplicate(true)
		for patch:Dictionary in plan.patches:
			check(preload("res://scripts/world3d/city_layout.gd").token(doc._find(patch.record.uuid))==patch.source_token,"bridge source unchanged "+patch.record.uuid)
		if failures:quit(1);return
		doc.checkpoint()
		for patch:Dictionary in plan.patches:doc.records[doc.records.find(doc._find(patch.record.uuid))]=patch.record
		preload("res://scripts/world3d/structure_prefab.gd").refresh_bindings(doc.map_meta,doc.records)
		var ids:Array=plan.patches.map(func(p):return p.record.uuid)
		check(equivalent(original.filter(func(r):return not r.uuid in ids),doc.records.filter(func(r):return not r.uuid in ids)),"all non-bridge records preserved")
		check(doc.save(FORMAL)==OK,"atomic bridge surface publication")
		var reopened=Doc.open_file(FORMAL);check(reopened!=null and equivalent(reopened.records,doc.records) and equivalent(reopened.map_meta,doc.map_meta),"published map reopens exactly")
		write_report("published.json",{"failures":failures,"formal_sha256":FileAccess.get_sha256(FORMAL),"bridge_ids":ids});quit(1 if failures else 0);return
	var extras:Dictionary=Doc.authoritative_extras(FORMAL).extras;var patches:Array=[]
	for record:Dictionary in extras.rmmo_records:
		if not record.has("bridge_mesh") or not record.has("house_prefab"):continue
		var result:=Repair.repair(record);check(result.ok,"repair "+record.uuid)
		if not result.ok:continue
		var before:=Frozen.geometry(record);var after:=Frozen.geometry(result.record)
		check(var_to_bytes(before.source.get_faces())==var_to_bytes(after.source.get_faces()),"byte-exact authored collision "+record.uuid)
		check(before.mesh.get_aabb().is_equal_approx(after.mesh.get_aabb()) and absf(area(before.mesh)-area(after.mesh))<.005,"render footprint and surface area preserved "+record.uuid)
		check(after.mesh.get_surface_count()==3,"three shared material surfaces")
		check(Repair.repair(result.record).get("changed",true)==false,"surface repair idempotent")
		var generated:Mesh=Repair.Bridge.new().build(record)
		var normals:PackedVector3Array=generated.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		var upward:=true
		for n in normals:upward=upward and n.y>.7
		for p:Vector3 in generated.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:upward=upward and absf(p.z)<=record.bridge_mesh.width*.5-.4999
		check(upward,"shared generator keeps paving on top only")
		patches.append({"record":result.record,"source_token":preload("res://scripts/world3d/city_layout.gd").token(record),"moved_triangles":result.get("moved_triangles",0)})
	write_report("plan.json",{"failures":failures,"patches":patches})
	if failures or not "--review" in OS.get_cmdline_user_args():quit(1 if failures else 0);return
	root.size=Vector2i(1440,900);Engine.max_fps=60
	var doc:=Doc.new();var area:=AABB(Vector3(230,-30,85),Vector3(140,70,130))
	for record:Dictionary in extras.rmmo_records:
		if Geometry.bounds([record]).intersects(area) and not record.has("building"):doc.records.append(record)
	var scene:=doc.build();root.add_child(scene)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.46,.66,.8);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.9,.94,1);env.environment.ambient_light_energy=.7;scene.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-35,0);sun.light_energy=1.5;sun.shadow_enabled=true;scene.add_child(sun)
	camera=Camera3D.new();camera.far=500;camera.fov=60;scene.add_child(camera)
	var bridge:Dictionary=doc._find("stone_e_0be972769041dbc9");var basis:=Basis(Vector3.UP,deg_to_rad(bridge.rotation[1]));var center:=B.vec(bridge.position)
	for version_ in ["before","after"]:
		if version_=="after":
			var replacement:Dictionary=patches.filter(func(p):return p.record.uuid==bridge.uuid)[0].record
			var node:MeshInstance3D=scene.get_node(NodePath(bridge.uuid));node.mesh=Frozen.geometry(replacement).mesh.restore()
		await capture("close_"+version_,center+basis*Vector3(16,3,13),center+basis*Vector3(18,.1,0))
		await capture("wide_"+version_,center+basis*Vector3(0,6,19),center+basis*Vector3(34,0,0))
	scene.free();print("BRIDGE_SURFACE_REVIEW failures=",failures);quit(1 if failures else 0)
