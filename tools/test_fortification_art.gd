extends SceneTree
const Art=preload("res://scripts/world3d/fortification_art.gd")
const Plan=preload("res://scripts/world3d/fortification_plan.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failed:=0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label_: String) -> void:
	print(("PASS " if value else "FAIL ")+label_)
	if not value: failed+=1
func run() -> void:
	var path:=Paths.external_root().path_join("packs/default/assets/fortifications/medieval_stone/medieval_wall.glb")
	var art:=Art.new(); check(not art.kit(path).is_empty(),"owned buttress and authored Blender wall kit readable")
	var materials:={}
	for role in ["stone","trim","door","iron"]: materials[role]={"name":role,"color":[1,1,1,1],"roughness":.8}
	for shape in ["path","ellipse"]:
		var settings:={"id":"art","shape":shape,"height":7.5,"style":"medieval_stone","points":[[-20,0],[20,0]],"gates":[{"id":"gate","width":6,"height":5.0,"open":1}]}
		settings.gates[0].merge({"segment":0,"t":.5} if shape=="path" else {"angle":0})
		var plan: Dictionary=Plan.new().build(settings); check(plan.ok,"art plan "+shape)
		if not plan.ok: continue
		var rejected: Dictionary=settings.duplicate(true); rejected.gates[0].height=4.99
		check(not Plan.new().build(rejected).ok,"reject a new arch below 5m on "+shape)
		var started:=Time.get_ticks_msec()
		var axes_ok:=true
		for hinge in plan.records.filter(func(r):return r.fortification.role=="hinge"):
			var door: Dictionary=plan.records.filter(func(r):return r.fortification.role=="door" and hinge.fortification.part==r.fortification.part+"_hinge")[0]
			var fixtures=preload("res://scripts/world3d/building_fixtures.gd")
			axes_ok=axes_ok and (fixtures.transform(door)*fixtures.vec(door.fixture.pivot)).distance_to(fixtures.transform(hinge).origin)<.00001
		check(axes_ok,"visible hinge axes match door pivot on "+shape)
		var count:=0; var triangles:=0; var bounds_ok:=true; var material_ok:=true
		for r in plan.records:
			var role: String=r.fortification.role
			if role=="corner_tower" and shape=="ellipse": role="round_tower"
			r.fortification_art={"version":1,"module":role,"asset_path":path}; r.fortification_materials=materials
			var mesh: ArrayMesh=Art.new().build(r)
			if mesh==null: check(false,"mesh "+r.fortification.part); continue
			count+=1
			if role=="gate_lintel": check(r.position[1]+mesh.get_aabb().position.y>=4.999,"arch lowest point >= 5m, including curved seam")
			var size_: Vector3=preload("res://scripts/world3d/city_layout.gd").vec(r.size); var box:=mesh.get_aabb()
			if not AABB(-size_*.5-Vector3.ONE*.005,size_+Vector3.ONE*.01).encloses(box): print("BAD_BOUNDS ",r.fortification.part," ",box," ",size_)
			bounds_ok=bounds_ok and AABB(-size_*.5-Vector3.ONE*.005,size_+Vector3.ONE*.01).encloses(box)
			material_ok=material_ok and mesh.get_surface_count()<=2
			for i in mesh.get_surface_count(): triangles+=mesh.surface_get_array_index_len(i)/3
		check(count==plan.records.size() and bounds_ok,"all "+shape+" modules stay within validated collision footprint")
		check(material_ok,"at most two shared PBR surfaces per "+shape+" component")
		var first_ms:=Time.get_ticks_msec()-started; started=Time.get_ticks_msec()
		for r in plan.records: Art.new().build(r)
		var warm_ms:=Time.get_ticks_msec()-started
		check(Art.cache_bytes<=Art.CACHE_BYTES and Art.cache.size()<=1024,"bounded mesh cache")
		print("ART_STATS ",shape," records=",count," triangles=",triangles," first_ms=",first_ms," warm_ms=",warm_ms," estimated_cache_bytes=",Art.cache_bytes)
	print("FORTIFICATION_ART_FINISHED failures=",failed); quit(0 if failed==0 else 1)
