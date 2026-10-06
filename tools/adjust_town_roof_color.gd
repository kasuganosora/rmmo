extends "res://tools/arrange_town_reference_styles.gd"
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const OLD="D:/code/rmmo_runtime/packs/default/assets/materials/roofs/terracotta_plain/albedo.png"
const NEW="D:/code/rmmo_runtime/packs/default/assets/materials/roofs/terracotta_warm/albedo.png"
const REPORT="D:/code/rmmo_runtime/review_artifacts/roof_color_20261006"
var camera:Camera3D
func _initialize()->void:
	OUT=REPORT;run.call_deferred()
func capture(label_:String,at:Vector3,target:Vector3)->void:
	camera.global_position=at;camera.look_at(target)
	for i in 30:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(REPORT+"/"+label_+".png")
func run()->void:
	DirAccess.make_dir_recursive_absolute(REPORT)
	if "--publish" in OS.get_cmdline_user_args():
		var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(REPORT+"/review.json"))
		check(report.failures==0 and FileAccess.get_sha256(FORMAL)==report.baseline and FileAccess.get_sha256(NEW)==report.texture_sha256,"reviewed source and color unchanged")
		if failures:quit(1);return
		var doc=Doc.open_file(FORMAL);var original:Array=doc.records.duplicate(true);var meta:Dictionary=doc.map_meta.duplicate(true)
		doc.checkpoint()
		for patch:Dictionary in report.patches:doc.records[doc.records.find(doc._find(patch.uuid))]=patch
		var final:Array=doc.records.duplicate(true)
		check(doc.undo() and equivalent(doc.records,original),"whole roof correction undo")
		check(doc.redo() and equivalent(doc.records,final),"whole roof correction redo")
		check(equivalent(meta,doc.map_meta),"map lighting layout and ownership preserved")
		if failures:quit(1);return
		check(doc.save(FORMAL)==OK,"atomic roof color save")
		var reopened=Doc.open_file(FORMAL)
		check(reopened!=null and equivalent(reopened.records,doc.records) and equivalent(reopened.map_meta,doc.map_meta),"formal save reopen exact")
		write_report("published.json",{"failures":failures,"sha256":FileAccess.get_sha256(FORMAL),"changed_records":report.patches.size(),"houses":report.houses});quit(failures);return
	var baseline:=FileAccess.get_sha256(FORMAL);var extras:Dictionary=Doc.authoritative_extras(FORMAL).extras
	var patches:Array=[];var houses:Array=[]
	for record:Dictionary in extras.rmmo_records:
		if not record.has("building") or not record.has("house_prefab"):continue
		var changed:=false;var r:Dictionary=record.duplicate(true)
		for mat:Dictionary in r.prefab_materials:
			if mat.get("texture_path","")==OLD:mat.texture_path=NEW;changed=true
		if not changed:continue
		Frozen.retarget_materials(r)
		var before:=Frozen.decode(record.house_prefab).duplicate(true);var after:=Frozen.decode(r.house_prefab).duplicate(true)
		for i in before.materials.size():
			if before.materials[i].has("paint") and before.materials[i].paint.get("texture_path","")==OLD:before.materials[i].paint.texture_path=NEW
		check(equivalent(before,after),"only roof albedo changed "+record.uuid)
		check(Frozen.valid(r),"frozen dependency integrity")
		patches.append(r)
		if not houses.has(r.building.id):houses.append(r.building.id)
	check(patches.size()>0,"existing roof materials found")
	if failures:quit(1);return
	var doc:=Doc.new();var id:String=houses[0]
	doc.map_meta.building_instances={id:extras.building_instances[id].duplicate(true)}
	for r:Dictionary in extras.rmmo_records:
		if r.get("building",{}).get("id","")==id:doc.records.append(r.duplicate(true))
	var bounds: AABB=preload("res://scripts/world_editor/selection_geometry.gd").bounds(doc.records)
	root.size=Vector2i(1440,900);Engine.max_fps=60
	var scene:=doc.build();root.add_child(scene)
	var env:=WorldEnvironment.new();env.environment=Environment.new();scene.add_child(env)
	var sun:=DirectionalLight3D.new();scene.add_child(sun)
	camera=Camera3D.new();camera.far=500;camera.fov=50;scene.add_child(camera)
	var weather=preload("res://scripts/world3d/weather_controller.gd").new();scene.add_child(weather)
	weather.bind(camera,sun,env.environment);weather.configure(extras.environment,true)
	for i in 90:await process_frame
	weather.set_process(false)
	var center:Vector3=bounds.get_center();var span:float=maxf(bounds.size.x,bounds.size.z)
	for version_ in ["before","after"]:
		if version_=="after":
			for r:Dictionary in patches:
				if r.building.id==id:scene.get_node(NodePath(r.uuid)).mesh=Frozen.geometry(r).mesh.restore()
		await capture("house_"+version_,center+Vector3(span*1.35,span*.85,span*1.4),center)
		var top:Vector3=center+Vector3.UP*bounds.size.y*.3
		await capture("roof_"+version_,top+Vector3(span*.65,span*.55,span*.7),top)
		await capture("back_"+version_,center+Vector3(-span*1.35,span*.85,-span*1.4),center)
	for r:Dictionary in patches:
		if r.building.id==id:doc.records[doc.records.find(doc._find(r.uuid))]=r
	var path:String="D:/code/rmmo_runtime/cache/world3d/roof_color_20261006/map.gltf"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	check(doc.save(path)==OK,"temporary house native save")
	var reopen=Doc.open_file(path)
	check(reopen!=null and equivalent(reopen.records,doc.records),"temporary house material save reopen")
	write_report("review.json",{"failures":failures,"baseline":baseline,"texture_sha256":FileAccess.get_sha256(NEW),"patches":patches,"houses":houses.size(),"sample_house":id})
	scene.free();quit(failures)
