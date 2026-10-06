extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Clean=preload("res://scripts/world3d/fortification_deck_cleanup.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/fortification_decks_20261006"
var failed:=0
func nearby(r:Dictionary)->bool:
	var dx:=maxf(0,absf(r.position[0]+609.4)-r.size[0]*.5)
	var dz:=maxf(0,absf(r.position[2]+38.6)-r.size[2]*.5)
	return Vector2(dx,dz).length()<35
func _initialize()->void:call_deferred("run")
func check(value:bool,label_:String)->void:
	print(("PASS " if value else "FAIL ")+label_)
	if not value:failed+=1
func collision_token(r:Dictionary)->String:
	var data:=Frozen.decode(r.house_prefab)
	return var_to_bytes(data.meshes[data.entries[0][1][1]]).hex_encode().sha256_text()
func equivalent(a:Variant,b:Variant)->bool:
	if (a is float or a is int) and (b is float or b is int):return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not equivalent(a[i],b[i]):return false
		return true
	return a==b
func run()->void:
	create_timer(900).timeout.connect(func():quit(2));Engine.max_fps=60
	DirAccess.make_dir_recursive_absolute(OUT)
	var path:="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	var publish:=false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):path=arg.trim_prefix("--map=")
		if arg=="--publish":publish=true
	var source_hash:=FileAccess.get_sha256(path)
	var doc=Doc.open_file(path);check(doc!=null,"native source document opens")
	if doc==null:quit(1);return
	var ownership_ok:=true
	for region:Dictionary in doc.map_meta.editor_layout.fortifications:
		for part:Dictionary in region.parts:
			var r:Dictionary=doc._find(part.id)
			ownership_ok=ownership_ok and not r.is_empty() and not r.get("editor_locked",false) and not r.get("editor_hidden",false) and preload("res://scripts/world3d/city_layout.gd").token(r)==part.signature
	check(ownership_ok,"saved ownership signatures match and no protected masonry is edited")
	if not ownership_ok:quit(1);return
	var records:Array=doc.records.filter(func(r):return r.has("fortification") and r.has("house_prefab") and not r.has("fixture"))
	var before:Array=records.duplicate(true);var collisions:Dictionary={}
	for r:Dictionary in records:collisions[r.uuid]=collision_token(r)
	doc.checkpoint_recovery()
	var reports:Array=[]
	for region:Dictionary in doc.map_meta.editor_layout.fortifications:
		var members:Array=records.filter(func(r):return r.fortification.id==region.settings.id)
		var floor_texture:=""
		# Resolve the authored floor identifier through the same default pack path.
		var floor_id:String=region.settings.get("floor_material_id","")
		for r:Dictionary in members:
			for p:Dictionary in r.prefab_materials:
				if not floor_id.is_empty() and p.get("texture_path","").contains("/"+floor_id.get_slice(":",2).trim_suffix("/material")+"/"):floor_texture=p.texture_path
		var report:=Clean.apply(members,region.settings.base_height+region.settings.height,floor_texture)
		print("DECK_REPAIR ",JSON.stringify(report));reports.append(report)
		check(report.ok,"coplanar deck cleanup succeeds")
		if not report.ok:quit(1);return
		var second:=Clean.apply(members,region.settings.base_height+region.settings.height,floor_texture)
		print("DECK_SECOND_PASS ",JSON.stringify(second))
		check(second.ok and second.overlap_area<.002,"no material coplanar overlap remains on repeat audit")
		for part:Dictionary in region.parts:
			var record:Dictionary=doc._find(part.id)
			part.signature=preload("res://scripts/world3d/city_layout.gd").token(record)
	check(records.all(func(r):return collision_token(r)==collisions[r.uuid]),"every collision mesh byte-identical, including stairs and wall support")
	var before_other:Array=before.map(func(r):var copy:Dictionary=r.duplicate();copy.erase("house_prefab");return copy)
	var after_other:Array=records.map(func(r):var copy:Dictionary=r.duplicate();copy.erase("house_prefab");return copy)
	check(var_to_bytes(before_other)==var_to_bytes(after_other),"identity, transforms, materials and tower semantics unchanged")
	var subset:=Doc.new()
	subset.records=doc.records.filter(func(r):return r.has("fortification") and nearby(r)).duplicate(true)
	var temporary:=OUT.path_join("test/map.gltf")
	check(subset.save(temporary)==OK,"repaired test section native atomic save")
	var reopened=Doc.open_file(temporary)
	check(reopened!=null and equivalent(reopened.records,subset.records),"repaired meshes survive native reopen")
	await capture(before,"before")
	await capture(records,"after")
	check(FileAccess.get_sha256(path)==source_hash,"source remains unchanged during verification")
	if publish and failed==0:
		check(doc.save(path)==OK,"publish authorized repair with native conflict detection and atomic save")
		var saved=Doc.open_file(path)
		check(saved!=null and equivalent(saved.records,doc.records),"published native document reopens exactly")
	var file:=FileAccess.open(OUT.path_join("published.json" if publish else "review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failed,"source":path,"source_sha256":source_hash,"published":publish and failed==0,"result_sha256":FileAccess.get_sha256(path),"reports":reports},"\t"))
	print("DECK_REPAIR_FINISHED failures=",failed);quit(1 if failed else 0)
func capture(records:Array,label_:String)->void:
	var scene:=Node3D.new();root.add_child(scene)
	var doc:=Doc.new()
	for r:Dictionary in records:
		if nearby(r):
			var node:MeshInstance3D=doc._mesh(r);scene.add_child(node)
			if label_=="after":
				var shape:=ConcavePolygonShape3D.new();shape.set_faces(node.get_meta("collision_solid").collision_faces())
				var body:=StaticBody3D.new();var collision:=CollisionShape3D.new();collision.shape=shape;body.add_child(collision);scene.add_child(body);body.transform=node.transform
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.15,.2,.24)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.5;scene.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-30,0);sun.light_energy=1.4;sun.shadow_enabled=true;scene.add_child(sun)
	var camera:=Camera3D.new();scene.add_child(camera);camera.current=true;camera.far=100
	root.size=Vector2i(1200,900)
	for i in 3:
		camera.position=Vector3(-620,18,-49) if i==0 else Vector3(-609.4,29,-38.5)
		if i==2:camera.position=Vector3(-613,11,-38.6)
		camera.look_at(Vector3(-607.9,7.5,-39.8) if i==2 else Vector3(-609,7.5,-38),Vector3.FORWARD if i==1 else Vector3.UP)
		for frame in 4:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT.path_join(label_+"_%d.png"%i))
	if label_=="after":
		var body:=CharacterBody3D.new();var collision:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=2.1;collision.shape=capsule;body.add_child(collision);scene.add_child(body)
		var center:=Vector3(-607.599975585938,7.5,-35);var outward:=Vector3(8.4,0,-56).normalized()
		body.position=center+outward*8+Vector3.UP*1.08;body.floor_snap_length=.3
		var supported:=true
		for pass_ in 2:
			for frame in 120:
				await physics_frame
				body.velocity=outward*(-2.5 if pass_==0 else 2.5);body.velocity.y=-1;body.move_and_slide()
				supported=supported and absf(body.position.y-8.55)<.06
		check(supported and body.position.distance_to(center+outward*8+Vector3.UP*1.05)<.15,"2.1m player capsule crosses repaired tower/wall seam both ways")
	scene.free();await process_frame
