extends SceneTree
const Cache=preload("res://scripts/world3d/model_texture_cache.gd")
func _initialize()->void:
	var scene:=Node3D.new()
	var image:=Image.create(32,16,false,Image.FORMAT_RGBA8)
	for y in 16:
		for x in 32:image.set_pixel(x,y,Color(float(x%2),.5,1,float((x+y)%2)))
	var texture:=ImageTexture.create_from_image(image)
	var materials:Array[StandardMaterial3D]=[]
	for i in 2:
		var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new();scene.add_child(mesh);mesh.owner=scene
		var mat:=StandardMaterial3D.new();mat.albedo_texture=texture;mat.normal_enabled=true;mat.normal_texture=texture
		mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mesh.material_override=mat;materials.append(mat)
	var result:=Cache.prepare_mipmaps(scene)
	assert(result.generated==2)
	assert(materials[0].albedo_texture==materials[1].albedo_texture)
	assert(materials[0].normal_texture==materials[1].normal_texture)
	assert(materials[0].normal_texture!=materials[0].albedo_texture)
	for mat in materials:
		for tex in [mat.albedo_texture,mat.normal_texture]:
			var prepared:Image=tex.get_image();assert(prepared.has_mipmaps());prepared.clear_mipmaps();assert(prepared.get_data()==image.get_data())
	assert(Cache.prepare_mipmaps(scene).generated==0)
	var packed:=PackedScene.new();assert(packed.pack(scene)==OK)
	var path:="user://guild_mipmap_test.scn";assert(ResourceSaver.save(packed,path)==OK)
	var reopened:PackedScene=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var copy:=reopened.instantiate();assert(copy.get_child(0).material_override.albedo_texture.get_image().has_mipmaps())
	copy.free();scene.free();DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("MODEL_MIPMAPS_PASS shared textures, normal/color separation, base pixels/alpha, idempotence, native reopen")
	quit()
