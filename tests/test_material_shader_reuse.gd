extends SceneTree
## GPU diagnostic: equivalent live materials must share shaders, independently
## of geometry and texture RID. Run with run_godot_background.py, not headless.
var rows:Array=[]
var held:Array=[]
var arrays:Array=[]
var texture:ImageTexture
var failures:Array[String]=[]
var checks:=0

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)

func ephemeral_resources()->Array:
	var image:=Image.create(8,8,false,Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var pixels:=ImageTexture.create_from_image(image)
	var material:=make_material();material.albedo_texture=pixels
	var mesh:=bind_material("ephemeral",material)
	return [weakref(pixels),weakref(material),weakref(mesh)]

func churn()->void:
	# 36 distinct keys exceed both the tiny stress limit and the default 32.
	for cull in 3:
		for filter in 6:
			for alpha in 2:
				var material:=StandardMaterial3D.new()
				material.cull_mode=cull;material.texture_filter=filter;material.transparency=alpha
				material.get_rid()

func concurrent_churn(seed:int)->void:
	for i in 40:
		var material:=make_material()
		material.cull_mode=(i+seed)%3
		material.get_rid()
		material.vertex_color_use_as_albedo=true
		material.get_rid()

func render_colors()->Array:
	var viewport:=SubViewport.new();viewport.size=Vector2i(64,64);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera:=Camera3D.new();camera.position=Vector3(0,0,3);viewport.add_child(camera)
	var hashes:Array=[]
	for color:Color in [Color.RED,Color.GREEN,Color.RED]:
		var node:=MeshInstance3D.new();node.mesh=QuadMesh.new()
		var image:=Image.create(8,8,false,Image.FORMAT_RGBA8);image.fill(color)
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture=ImageTexture.create_from_image(image)
		node.material_override=material;viewport.add_child(node)
		for i in 3:await process_frame
		await RenderingServer.frame_post_draw
		var actual:=viewport.get_texture().get_image()
		check(actual.get_pixel(32,32).is_equal_approx(color),"cached shader preserves per-material texture color %s"%color)
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(actual.get_data())
		hashes.append(hash.finish().hex_encode())
		node.free();material=null
		for i in 2:await process_frame
	viewport.free()
	check(hashes[0]==hashes[2] and hashes[0]!=hashes[1],"red/green/red readback is deterministic and has no stale bindings")
	return hashes

func _initialize()->void:
	call_deferred("run")

func bind_material(label:String,material:StandardMaterial3D)->ArrayMesh:
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var began:=Time.get_ticks_usec()
	mesh.surface_set_material(0,material)
	var elapsed:=Time.get_ticks_usec()-began
	var again:=Time.get_ticks_usec()
	material.get_rid()
	rows.append({"label":label,"bind_us":elapsed,"second_get_rid_us":Time.get_ticks_usec()-again})
	return mesh

func make_material()->StandardMaterial3D:
	var material:=StandardMaterial3D.new()
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.normal_enabled=true
	material.normal_texture=texture
	material.albedo_texture=texture
	material.ao_enabled=true
	material.ao_texture=texture
	return material

func run()->void:
	if DisplayServer.get_name()=="headless":push_error("Real GPU renderer required");quit(1);return
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN])
	var image:=Image.create(4,4,false,Image.FORMAT_RGBA8)
	image.fill(Color(0.5,0.5,1.0));texture=ImageTexture.create_from_image(image)
	for i in 16:
		held.append(bind_material("equivalent_live_%d"%i,make_material()))
	for i in 8:
		var source:StandardMaterial3D=held[0].surface_get_material(0)
		held.append(bind_material("duplicate_live_%d"%i,source.duplicate()))
	for i in 8:
		held.append(bind_material("same_live_%d"%i,held[0].surface_get_material(0)))
	for i in 3:await process_frame
	held.clear()
	for i in 3:await process_frame
	for i in 4:
		var mesh:=bind_material("after_release_%d"%i,make_material())
		mesh=null
		await process_frame
	var weak_owners:=ephemeral_resources()
	for i in 3:await process_frame
	for weak:WeakRef in weak_owners:check(weak.get_ref()==null,"shader cache does not retain texture, material or mesh owners")
	held.append(bind_material("live_during_eviction",make_material()))
	churn()
	held.append(bind_material("live_after_eviction",held[0].surface_get_material(0)))
	var threads:Array[Thread]=[]
	for i in 2:
		var thread:=Thread.new();check(thread.start(concurrent_churn.bind(i))==OK,"start concurrent shader churn")
		threads.append(thread)
	for thread:Thread in threads:thread.wait_to_finish()
	held.clear()
	var hashes:=await render_colors()
	print("MATERIAL_SHADER_REUSE ",JSON.stringify(rows))
	print("MATERIAL_SHADER_CHECKS ",JSON.stringify({"checks":checks,"failures":failures,"image_sha256":hashes}))
	texture=null
	quit(0 if failures.is_empty() else 1)
