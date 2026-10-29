extends SceneTree
## Isolated native-owner and material-work contract. Artifacts use content_root.
const Grass=preload("res://scripts/world3d/grass_texture_cache.gd")
const Product=preload("res://scripts/world3d/streamed_texture_product.gd")
var checks:=0
var failures:Array[String]=[]
var observed:Dictionary={}
var folder:String

class PixelTexture extends Texture2D:
	var pixels:Image
	var reads:=0
	func _get_width()->int:return pixels.get_width()
	func _get_height()->int:return pixels.get_height()
	func _get_rid()->RID:return RID()
	func _get_image()->Image:
		reads+=1
		return pixels

func check(value:bool,label:String)->void:
	checks+=1
	print("PASS " if value else "FAIL ",label)
	if not value:failures.append(label)

func _initialize()->void:run.call_deferred()

func image(color:Color)->Image:
	var result:=Image.create(4,4,false,Image.FORMAT_RGBA8)
	result.fill(color);result.generate_mipmaps()
	return result

func write_product(path:String,pixels:Image)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	var error:=Product.write(file,pixels);file.close()
	return error==OK

func legacy_key(pixels:Image)->String:
	var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256)
	hash_.update(var_to_bytes([pixels.get_width(),pixels.get_height(),pixels.get_format(),pixels.has_mipmaps()]))
	hash_.update(pixels.get_data())
	return hash_.finish().hex_encode()

func surface(colored:bool)->Array:
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3.ZERO,Vector3.RIGHT,Vector3.UP]:
		if colored:tool.set_color(Color(.2,.4,.3,1))
		tool.add_vertex(point)
	return tool.commit_to_arrays()

func run()->void:
	folder=str(ProjectSettings.get_setting("rmmo/content_root","")).path_join("grass_native_%d"%OS.get_process_id())
	if not folder.is_absolute_path() or DirAccess.make_dir_recursive_absolute(folder)!=OK:quit(2);return
	Grass._textures.clear()
	var path:=folder.path_join("source.stex")
	var red:=image(Color(.8,.1,.2,.6));var blue:=image(Color(.1,.3,.8,.6))
	check(write_product(path,red),"write isolated native texture product")
	var native:Texture2D=ClassDB.instantiate("StreamedTexture2D")
	check(native!=null and native.call("load",path)==OK,"load real StreamedTexture2D")
	if native==null:finish();return
	check(native.get_width()==4 and native.get_height()==4,"native owner retains authored dimensions")
	# Controlled source replacement detects the OLD getter path, which reads
	# the file again at mip zero instead of using the already prepared owner.
	# This is only a disposable fixture, never mutation of a published package.
	check(write_product(path,blue),"replace fixture bytes after native preparation")
	var before_meta:=native.get_meta_list()
	check(Grass.shared(native,true)==native,"compiled grass retains the prepared native owner")
	observed.native_legacy_key=str(native.get_meta("compiled_grass_pixel_key",""))
	observed.reopened_fixture_pixels=observed.native_legacy_key==legacy_key(blue)
	check(native.get_meta_list()==before_meta and Grass._textures.is_empty(),"native grass does not reopen pixels or add legacy hash/cache state")
	check(Grass.shared(native,false)==native and Grass._textures.is_empty(),"ordinary grass also preserves native owner without old image interning")
	Grass._textures.clear()
	var old:=PixelTexture.new();old.pixels=red
	Grass._textures["old-grass-key"]=weakref(old)
	native.set_meta("compiled_grass_pixel_key","old-grass-key")
	check(Grass.shared(native,true)==native,"stale grass tag cannot replace native owner with a legacy texture")
	check(Grass._textures.size()==1 and Grass._textures["old-grass-key"].get_ref()==old,"native owner bypass leaves another legacy cache entry unchanged")
	native.remove_meta("compiled_grass_pixel_key");Grass._textures.clear()
	material_work(native)
	vertex_colors(native)
	legacy_behavior(red)
	native=null;red=null;blue=null;old=null;Grass._textures.clear()
	await process_frame
	finish()

func material_work(native:Texture2D)->void:
	var root:=Node3D.new();var material:=StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true;material.roughness=.37;material.metallic=.12
	var authored:=[material.roughness,material.metallic]
	for field:String in ["albedo_texture","normal_texture","roughness_texture","metallic_texture","ao_texture"]:material.set(field,native)
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface(false));mesh.surface_set_material(0,material)
	for unused:int in 24:
		var node:=MeshInstance3D.new();node.mesh=mesh;node.set_meta("extras",{"rmmo_grass":true});root.add_child(node)
	var events:Dictionary={"count":0}
	material.property_list_changed.connect(func():events.count+=1)
	Grass.apply(root,true);Grass.apply(root,true)
	observed.unchanged_material_setter_notifications=events.count
	check(events.count==0,"24 grass instances and repeat apply produce zero same-owner setters")
	check([material.roughness,material.metallic]==authored,"grass keeps authored material parameters")
	var same:=true
	for field:String in ["albedo_texture","normal_texture","roughness_texture","metallic_texture","ao_texture"]:same=same and material.get(field)==native
	check(same and Grass._textures.is_empty(),"all five grass slots retain the native owner with no legacy cache")
	root.free()

func vertex_colors(native:Texture2D)->void:
	var root:=Node3D.new();var source:=StandardMaterial3D.new();source.albedo_texture=native
	var mixed:=MeshInstance3D.new();mixed.mesh=ArrayMesh.new()
	for colored:bool in [true,false]:
		mixed.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface(colored));mixed.mesh.surface_set_material(mixed.mesh.get_surface_count()-1,source)
	mixed.material_override=source;mixed.set_meta("extras",{"rmmo_grass":true});root.add_child(mixed)
	var other:=MeshInstance3D.new();other.mesh=mixed.mesh;root.add_child(other)
	var peer:=MeshInstance3D.new();peer.mesh=mixed.mesh;peer.set_meta("extras",{"rmmo_grass":true});root.add_child(peer)
	Grass.apply(root,true)
	check(mixed.get_active_material(0).vertex_color_use_as_albedo,"colored native grass still enables vertex shading")
	check(not mixed.get_active_material(1).vertex_color_use_as_albedo,"uncolored native grass keeps source shading")
	check(not other.get_active_material(0).vertex_color_use_as_albedo and not source.vertex_color_use_as_albedo,"non-grass shared material remains unchanged")
	check(peer.get_active_material(0)==mixed.get_active_material(0),"colored native grass peers share their derived material")
	check(mixed.get_active_material(0).albedo_texture==native and source.albedo_texture==native,"derived vertex-color material keeps exact native texture")
	var first:Material=mixed.get_active_material(0);Grass.apply(root,true)
	check(mixed.get_active_material(0)==first,"repeat native processing does not duplicate vertex-color material")
	root.free()

func legacy_behavior(pixels:Image)->void:
	Grass._textures.clear()
	var first:=PixelTexture.new();first.pixels=pixels
	var second:=PixelTexture.new();second.pixels=pixels.duplicate()
	check(Grass.shared(first)==first and first.reads==1,"ordinary legacy texture still reads its pixels once")
	check(Grass.shared(second)==first and second.reads==1,"identical legacy pixels still share the original owner")
	var third:=PixelTexture.new();third.pixels=pixels
	third.set_meta("compiled_grass_pixel_key",first.get_meta("compiled_grass_pixel_key"))
	check(Grass.shared(third,true)==first and third.reads==0,"compiled legacy key still avoids pixel readback")
	Grass._textures.clear()

func finish()->void:
	var result:={"checks":checks,"failures":failures,"observed":observed,"renderer":DisplayServer.get_name()}
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("GRASS_NATIVE_RESULT ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
