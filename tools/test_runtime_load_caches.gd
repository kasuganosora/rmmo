extends SceneTree
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const NavCache=preload("res://scripts/world3d/navigation_cache.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var failed:=0
func check(ok:bool,label_:String)->void:
	print(("PASS: " if ok else "FAIL: ")+label_)
	if not ok:failed+=1
func _initialize()->void:call_deferred("run")
func run()->void:
	fixture_validation()
	var directory:=preload("res://scripts/world3d/map_paths.gd").cache_directory("load_cache_test_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var doc=preload("res://scripts/world3d/world_document.gd").new()
	doc.load_box_meshes={};doc.load_paint_validation={};doc.load_texture_checks={}
	var B=preload("res://scripts/world3d/building_blueprint.gd")
	var plan:Dictionary=B.generate(B.medieval_presets()[0].parameters)
	var records:Array=[];var wanted:=["wall_grid","draped_cloth","joined_box","roof_prism","candle_sconce","cylinder"]
	for shape:String in wanted:
		for record:Dictionary in plan.records:
			if record.get("building_shape")==shape:records.append(record);break
	for record:Dictionary in plan.records:
		if record.has("fixture") and record.fixture.kind=="door":records.append(record);break
	var specs:Array=[]
	for record:Dictionary in records:
		var visual:MeshInstance3D=doc._mesh(record);specs.append(Stream._spec(visual));visual.free()
	var data:=Cook.pack(doc.load_box_meshes,"source","generator",specs)
	check(data.specs.size()==records.size() and Cook.valid_data(data),"all house shapes and moving door have valid cooked specs")
	Cook.write(path,data)
	var restored:=Cook.read(path,"source","generator")
	check(not restored.is_empty(),"cooked geometry binary round trip")
	check(Cook.read(path,"changed","generator").is_empty() and Cook.read(path,"source","changed").is_empty(),"source and generator changes invalidate cooked geometry")
	Cook.restore(restored)
	var loaded:=Cook.restore_specs(restored,records)
	var equal_:bool=loaded.size()==specs.size()
	for i in mini(loaded.size(),specs.size()):
		equal_=equal_ and loaded[i].transform==specs[i].transform and loaded[i].extras==specs[i].extras and loaded[i].uuid==specs[i].uuid
		equal_=equal_ and var_to_bytes(Cpu.capture(specs[i].mesh).surfaces)==var_to_bytes(loaded[i].mesh.surfaces)
		for slot in specs[i].mesh.get_surface_count():
			equal_=equal_ and Cook.material_data(specs[i].mesh.surface_get_material(slot))==Cook.material_data(loaded[i].mesh.surface_get_material(slot))
		if specs[i].get("collision_mesh") is BoxMesh:equal_=equal_ and loaded[i].collision_mesh is BoxMesh and loaded[i].collision_mesh.size==specs[i].collision_mesh.size
		if specs[i].has("closed_transform"):equal_=equal_ and loaded[i].closed_transform==specs[i].closed_transform
	check(equal_,"positions, UVs, tangents, materials, solid hulls and hinge pivots stay exact")
	var bad:=data.duplicate(true);bad.entries[0][1][0]=999999
	check(not Cook.valid_data(bad),"reject out of range geometry reference")
	bad=data.duplicate(true);bad.specs[0].spec.transform="invalid"
	check(not Cook.valid_data(bad),"reject invalid cached transform")
	bad=data.duplicate(true);bad.meshes[0].surfaces[0][Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,999999])
	check(not Cook.valid_data(bad),"reject invalid triangle index")
	var file:=FileAccess.open(Cook.cache_path(path),FileAccess.WRITE);file.store_string("damaged");file.close()
	check(Cook.read(path,"source","generator").is_empty(),"damaged cache falls back without loading an Object")
	var image_path:=directory.path_join("pixels.png")
	var original:=Image.create(8,4,false,Image.FORMAT_RGBA8);original.fill(Color(.2,.7,.4,.5));original.save_png(image_path)
	var first:=Pixels.image(image_path,false);var second:=Pixels.image(image_path,false)
	var definition:={"name":"cache test","texture_path":image_path,"color":[1,1,1,1],"roughness":.8}
	Paint.prepare_images({image_path:first})
	var previous_material:=Paint.make_material(definition)
	original.generate_mipmaps()
	check(first.get_data()==original.get_data() and first.get_data()==second.get_data(),"pixel cache preserves every pixel and mip level losslessly")
	var flipped:=Pixels.image(image_path,true)
	check(absf(flipped.get_pixel(0,0).g-(1.0-original.get_pixel(0,0).g))<.005,"DirectX normal orientation has a separate cache")
	file=FileAccess.open(Pixels.cache_path(image_path,false),FileAccess.WRITE);file.store_string("damaged");file.close()
	check(Pixels.image(image_path,false).get_data()==original.get_data(),"damaged pixel cache decodes original image")
	original.fill(Color(.9,.1,.3));original.save_png(image_path)
	check(Pixels.image(image_path,false).get_pixel(0,0).r>.85,"changed source image invalidates decoded pixels")
	Paint.prepare_images({image_path:Pixels.image(image_path,false)})
	var updated_material:=Paint.make_material(definition)
	check(updated_material!=previous_material and updated_material.albedo_texture.get_image().get_pixel(0,0).r>.85,"same-process map reload replaces changed resident texture and material")
	check(not Pixels.valid_pixels({"width":999999,"height":4,"format":Image.FORMAT_RGBA8,"size":20}),"reject invalid dimensions before allocating image")
	var nav:=NavigationMesh.new();nav.set_vertices(PackedVector3Array([Vector3.ZERO,Vector3(0,0,3),Vector3(3,0,0)]));nav.add_polygon(PackedInt32Array([0,1,2]))
	var key:="cache-regression-"+directory
	NavCache.store_mesh(key,nav);var copy:=NavigationMesh.new()
	check(NavCache.restore(key,copy) and copy.get_vertices()==nav.get_vertices() and copy.get_polygon(0)==nav.get_polygon(0),"navigation vertices and polygons remain exact")
	check(not NavCache.restore(key+"new-agent-height",NavigationMesh.new()),"different geometry/agent key cannot reuse navigation")
	file=FileAccess.open(NavCache.path(key),FileAccess.WRITE);file.store_string("damaged");file.close()
	check(not NavCache.restore(key,NavigationMesh.new()),"damaged navigation requests a fresh bake")
	# The deferred initial upload must still restore singleton/transparent draws.
	var host:=Node3D.new();root.add_child(host)
	var source:MeshInstance3D=Stream._spawn(specs[0],true);host.add_child(source)
	check(source.mesh is Cpu and source.has_meta("deferred_gpu"),"initial source can remain CPU-only under loading cover")
	preload("res://scripts/world3d/ground_batcher.gd").restore(source)
	check(not source.mesh is Cpu,"unbatched source restores a real render mesh")
	host.free()
	for target in [Cook.cache_path(path),Pixels.cache_path(image_path,false),Pixels.cache_path(image_path,true),NavCache.path(key),image_path]:DirAccess.remove_absolute(target)
	DirAccess.remove_absolute(directory)
	print("RUNTIME_LOAD_CACHES_FINISHED failures=",failed);quit(1 if failed else 0)

func fixture_validation()->void:
	var Schema=preload("res://scripts/world3d/document_schema.gd")
	var schema:={"type":"object","properties":{
		"id":{"type":"string","minLength":1,"maxLength":180},"kind":{"type":"string","enum":["door","window","shutter"]},
		"pivot":Schema.vector(-100,100),"angle":Schema.number(-180,180),"open":Schema.number(0,1)},
		"required":["id","kind","pivot","angle","open"],"additionalProperties":false}
	var seed:={"id":"door","kind":"door","pivot":[0,0,0],"angle":90.0,"open":0.0}
	var cases:Array=[seed,{},null,[]]
	for key in seed:
		for value in [null,true,{},[],"",&"door",0,1,-1,INF,NAN,180,181,"door","window","shutter","bad","x".repeat(181),[0,0,0],[100,-100,0],[101,0,0],[NAN,0,0],[0,0],[0,0,0,0]]:
			var candidate:Dictionary=seed.duplicate(true);candidate[key]=value;cases.append(candidate)
		var missing:Dictionary=seed.duplicate(true);missing.erase(key);cases.append(missing)
	var extra:Dictionary=seed.duplicate(true);extra.unsupported=true;cases.append(extra)
	var same:=true
	for value in cases:
		var expected:bool=Schema.validate(value,schema).is_empty() and not str(value.id).is_empty()
		same=same and preload("res://scripts/world3d/building_fixtures.gd").valid({"kind":"box","fixture":value})==expected
	check(same,"direct fixture validator matches schema for "+str(cases.size())+" valid/invalid boundaries")
