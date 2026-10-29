extends SceneTree
## CPU/headless producer contract. Outputs are external; no GLB or formal pack.
const Products=preload("res://scripts/world3d/model_texture_products.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failures:Array[String]=[]
var checks:=0
var folder:String
var measurements:Dictionary={}
class Cancel extends RefCounted:
	var calls:=0
	var at:=1
	func is_cancelled()->bool:
		calls+=1
		return calls>=at

func _initialize()->void:call_deferred("run")
func check(condition:bool,message:String)->void:
	checks+=1
	if not condition:failures.append(message);push_error(message)
	else:print("PASS "+message)

func fixture()->Dictionary:
	var image:=Image.create(4,4,false,Image.FORMAT_RGBA8);image.fill(Color(.25,.5,.75,1));image.set_pixel(0,0,Color(.9,.2,.1,.4));image.generate_mipmaps()
	var other:=Image.create(3,5,false,Image.FORMAT_RGB8);other.fill(Color(.1,.4,.7))
	var texture:=ImageTexture.create_from_image(image)
	var duplicate:=ImageTexture.create_from_image(image)
	var second:=ImageTexture.create_from_image(other)
	var material:=StandardMaterial3D.new();material.resource_name="CompleteMaterial"
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.texture_repeat=false;material.uv1_scale=Vector3(2,3,1);material.uv1_offset=Vector3(.25,.5,0)
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;material.alpha_scissor_threshold=.37
	material.cull_mode=BaseMaterial3D.CULL_DISABLED;material.roughness=.63;material.metallic=.12
	material.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	for feature:int in BaseMaterial3D.FEATURE_MAX:material.set_feature(feature,true)
	var texture_slots:Array[String]=[]
	for info:Dictionary in material.get_property_list():
		if int(info.usage)&PROPERTY_USAGE_STORAGE and info.get("hint_string","")=="Texture2D":
			material.set(info.name,texture);texture_slots.append(str(info.name))
	material.set_meta("author_marker",{"kind":"original","color":Color(.2,.3,.4,1)})
	var next:=StandardMaterial3D.new();next.resource_name="NextPass";next.emission_enabled=true;next.emission_texture=duplicate;next.emission=Color(.4,.3,.2,1);material.next_pass=next
	var override:=StandardMaterial3D.new();override.resource_name="Override";override.albedo_texture=second
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.UP])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(0,material)
	var scene:=Node3D.new();scene.name="OriginalNative"
	var node:=MeshInstance3D.new();node.name="Mesh";node.mesh=mesh;node.material_overlay=next
	scene.add_child(node);node.owner=scene;node.set_surface_override_material(0,override)
	return {"scene":scene,"node":node,"materials":[material,next,override],"images":[image,other],"textures":[texture,duplicate,second],"slots":texture_slots}

func scalars(material:Material)->Dictionary:
	var result:Dictionary={}
	for info:Dictionary in material.get_property_list():
		if not (int(info.usage)&PROPERTY_USAGE_STORAGE) or int(info.type)==TYPE_OBJECT or str(info.name) in ["resource_path","resource_scene_unique_id","metadata/"+str(Products.BINDINGS_META)]:continue
		result[str(info.name)]=material.get(info.name)
	return result

func packed_scene(scene:Node)->PackedScene:
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"scene packs")
	return packed

func exact_product(row:Dictionary,image:Image)->void:
	var bytes:=FileAccess.get_file_as_bytes(folder.path_join(row.file))
	check(bytes.size()==row.file_bytes and bytes.slice(0,4).get_string_from_ascii()=="GSTF","standalone GSTF size and signature")
	check(bytes.decode_u32(4)==1 and bytes.decode_u32(8)==image.get_width() and bytes.decode_u32(12)==image.get_height() and bytes.decode_u32(20)==image.get_format(),"product preserves size and original image format")
	check(bytes.decode_u32(24)==image.get_mipmap_count(),"product preserves authored mip count")
	var offset:=44+8*(image.get_mipmap_count()+1)
	check(bytes.slice(offset)==image.get_data(),"product preserves every original pixel / mip byte")

func write_test_table(table:Dictionary)->Dictionary:
	var text:=JSON.stringify(table,"",true,true)
	var digest:=text.sha256_text();var path:=Products.table_directory(folder).path_join(digest+".json")
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(text);file.close()
	return {"version":1,"sha256":digest,"bytes":text.to_utf8_buffer().size(),"textures":table.textures.size(),"image_bytes":table.image_bytes}

func run()->void:
	folder=Paths.external_root().path_join("producer_%d"%OS.get_process_id());DirAccess.make_dir_recursive_absolute(folder)
	var sample:=fixture();var original:Node=sample.scene
	var snapshots:Array=[]
	for material:Material in sample.materials:snapshots.append(scalars(material))
	var old:=packed_scene(original)
	check(Compiled._valid_packed(old) and not Compiled._valid_packed(old,false),"strict native graph rejects embedded images")
	var legacy_path:=folder.path_join("original.scn")
	check(ResourceSaver.save(old,legacy_path,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK,"legacy native fixture saved without any GLB")
	old=null
	var prepare_started:=Time.get_ticks_usec()
	var prepared:=Products.prepare(original,folder)
	measurements.prepare_us=Time.get_ticks_usec()-prepare_started
	check(prepared.ok,"producer prepares native image split")
	if not prepared.ok:finish();return
	check(prepared.stats.readbacks==3 and prepared.stats.pixel_hashes==3 and prepared.stats.textures==2,"one readback per image resource and content dedup across separate texture objects")
	check(prepared.stats.products_written==2 and prepared.stats.products_reused==0,"one immutable product per distinct pixel layout")
	measurements.prepare_stats=prepared.stats
	var table:Dictionary=prepared.table
	for image:Image in sample.images:exact_product(table.textures[Products._pixel_key(image)],image)
	for index:int in sample.materials.size():check(scalars(sample.materials[index])==snapshots[index],"all authored nontexture material parameters retained %d"%index)
	var base:StandardMaterial3D=sample.materials[0]
	var bindings:Dictionary=base.get_meta(Products.BINDINGS_META)
	check(bindings.size()==sample.slots.size() and bindings.size()>=15,"all stored texture slots captured including disabled shader variants")
	for slot:String in sample.slots:
		check(base.get(slot)==null and bindings[slot].normal==(slot in Products.NORMAL_SLOTS),"texture reference cleared and semantic role retained: "+slot)
	check(base.next_pass==sample.materials[1] and sample.node.material_overlay==sample.materials[1],"next_pass and shared graph identity retained")
	var bare:=packed_scene(original)
	check(Compiled._valid_packed(bare,false),"split graph has no Image or ImageTexture resource")
	var path:=folder.path_join("split.scn")
	check(ResourceSaver.save(bare,path,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK and ResourceLoader.get_dependencies(path).is_empty(),"SCN saves with no mandatory external texture dependencies")
	measurements.split_scn_bytes=FileAccess.get_file_as_bytes(path).size();measurements.original_scn_bytes=FileAccess.get_file_as_bytes(legacy_path).size()
	bare=null
	Products.restore(prepared);Products.restore(prepared)
	check(not prepared.has("restore") and not original.has_meta(Products.TABLE_META),"restore releases owner packet and is idempotent")
	for slot:String in sample.slots:check(base.get(slot)==sample.textures[0],"source texture restored: "+slot)
	var loaded:PackedScene=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(loaded!=null and Compiled._valid_packed(loaded,false),"saved split SCN remains image free after independent reopen")
	var reopened:Node=loaded.instantiate();var reopened_mesh:MeshInstance3D=reopened.get_node("Mesh")
	var reopened_material:StandardMaterial3D=reopened_mesh.mesh.surface_get_material(0)
	check(reopened.get_meta(Products.TABLE_META)==prepared.table_sha and reopened_material.get_meta(Products.BINDINGS_META)==bindings,"scalar table identity and bindings survive native serialization")
	check(scalars(reopened_material)==snapshots[0] and scalars(reopened_material.next_pass)==snapshots[1],"full material and next_pass parameter snapshots survive native reopen")
	check(reopened_mesh.mesh.surface_get_arrays(0)==sample.node.mesh.surface_get_arrays(0),"native split preserves exact geometry")
	check(not Products.prepare(reopened,folder).ok,"already split graph rejects destructive re-extraction")
	check(Products.read_table(prepared.texture_table,folder,false).get("ok",false),"table alone reads before SCN with strict table checksum")
	var first_id:String=table.textures.keys()[0];var product_path:=folder.path_join(table.textures[first_id].file)
	DirAccess.rename_absolute(product_path,product_path+".hidden")
	check(Products.read_table(prepared.texture_table,folder).ok,"table reader does not reopen or rehash individual texture files")
	DirAccess.rename_absolute(product_path+".hidden",product_path)
	var relocated:=folder.path_join("relocated")
	DirAccess.make_dir_recursive_absolute(Products.directory(relocated));DirAccess.make_dir_recursive_absolute(Products.table_directory(relocated))
	DirAccess.copy_absolute(prepared.table_path,Products.table_directory(relocated).path_join(prepared.table_sha+".json"))
	for id:String in table.textures:DirAccess.copy_absolute(folder.path_join(table.textures[id].file),relocated.path_join(table.textures[id].file))
	DirAccess.copy_absolute(path,relocated.path_join("model.scn"))
	check(Products.read_table(prepared.texture_table,relocated,false).ok,"table and immutable products relocate without source or absolute texture paths")
	var relocated_packed:PackedScene=ResourceLoader.load(relocated.path_join("model.scn"),"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(Compiled.strict_image_free(relocated_packed),"relocated geometry reloads independently without eager texture dependencies")
	relocated_packed=null
	var malformed:Dictionary=table.duplicate(true);malformed.textures[first_id].file="../outside.stex"
	var rejected:=Products.read_table(write_test_table(malformed),folder)
	check(not rejected.ok and rejected.table.is_empty(),"malformed texture path returns no partial consumable table")
	malformed=table.duplicate(true);malformed.textures[first_id].mip_sizes=[-1]
	check(not Products.read_table(write_test_table(malformed),folder).ok,"invalid mip byte layout is rejected without pixel IO")
	var another:=Products.prepare(original,folder)
	check(another.ok and another.stats.products_written==0 and another.stats.products_reused==2 and another.table_sha==prepared.table_sha,"second model reuses the same immutable products and stable table")
	Products.restore(another)
	var cancel:=Cancel.new();cancel.at=5
	var cancelled:=Products.prepare(original,folder.path_join("cancelled"),cancel)
	check(not cancelled.ok and cancelled.error=="cancelled" and base.albedo_texture==sample.textures[0] and not base.has_meta(Products.BINDINGS_META),"mid-product cancellation leaves original graph untouched")
	var cancel_folder:=Products.directory(folder.path_join("cancelled"))
	check(Array(DirAccess.get_files_at(cancel_folder)).filter(func(name:String)->bool:return name.contains(".tmp-")).is_empty(),"cancelled transaction leaves no staging file")
	var streamed:Texture2D=ClassDB.instantiate("StreamedTexture2D")
	base.albedo_texture=streamed
	var unsafe:=Products.prepare(original,folder)
	check(not unsafe.ok and unsafe.error.begins_with("unsupported_texture:") and base.albedo_texture==streamed,"streamed resident readback cannot replace a complete pixel product")
	base.albedo_texture=sample.textures[0];streamed=null
	var legacy:PackedScene=ResourceLoader.load(legacy_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var native:Node=legacy.instantiate();var conversion:=Products.prepare(native,folder)
	check(conversion.ok and conversion.stats.products_written==0,"legacy native-to-native conversion needs no GLB and reuses pixels")
	var native_bare:=packed_scene(native);check(Compiled._valid_packed(native_bare,false),"converted legacy native has no embedded images")
	native_bare=null;Products.restore(conversion);native.free();legacy=null
	# Exercise the private writer transaction with a native-owned scene. This is
	# not a GLTF import or renderer acceptance; it verifies descriptor promotion
	# and restoration around the exact pack/save implementation headlessly.
	var owner:=Compiled.PreparedSource.new();owner.path=legacy_path;owner.source_digest=FileAccess.get_sha256(legacy_path);owner.state=GLTFState.new();owner.scene=original
	var compiled:=Compiled._build_prepared(owner,Time.get_ticks_usec(),true)
	check(compiled.get("ok",false) and compiled.has("texture_table"),"explicit compiled transaction publishes split descriptor")
	check(base.albedo_texture==sample.textures[0] and not original.has_meta(Products.TABLE_META),"compiled transaction restores borrowed scene before returning")
	var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string(Compiled.index_path(legacy_path)))
	check(manifest is Dictionary and manifest.get("texture_table",{}).get("sha256")==compiled.get("texture_table",{}).get("sha256") and Products.read_table(manifest.texture_table,Paths.external_root(),false).ok,"compiled manifest carries table identity beside geometry payload")
	var compiled_hit:=Compiled.read(legacy_path)
	check(compiled_hit.get("hit",false) and compiled_hit.has("texture_table") and Compiled.strict_image_free(compiled_hit.packed),"strict compiled reader accepts split geometry and its table")
	compiled_hit.clear()
	var hidden:=Image.create(1,1,false,Image.FORMAT_RGBA8);original.set_meta("unsupported_hidden_image",hidden)
	var hidden_prepared:=Products.prepare(original,folder);var invalid:=packed_scene(original)
	check(not Compiled._valid_packed(invalid,false),"strict graph rejects images hidden outside supported material slots")
	invalid=null;Products.restore(hidden_prepared);original.remove_meta("unsupported_hidden_image")
	check(base.albedo_texture==sample.textures[0],"failed final graph validation can restore source slots")
	original.set_meta("unsupported_hidden_image",hidden)
	var prior_index:=FileAccess.get_file_as_bytes(Compiled.index_path(legacy_path))
	var failed_compiled:=Compiled._build_prepared(owner,Time.get_ticks_usec(),true)
	check(not failed_compiled.get("ok",true) and base.albedo_texture==sample.textures[0] and not original.has_meta(Products.TABLE_META),"failed compiled validation restores all borrowed slots")
	check(FileAccess.get_file_as_bytes(Compiled.index_path(legacy_path))==prior_index,"failed compiled transaction leaves previous publication intact")
	original.remove_meta("unsupported_hidden_image")
	var ordinary:=Compiled._build_prepared(owner,Time.get_ticks_usec())
	var ordinary_hit:=Compiled.read(legacy_path)
	check(ordinary.get("ok",false) and ordinary_hit.get("hit",false) and not ordinary.has("texture_table") and not ordinary_hit.has("texture_table") and not Compiled.strict_image_free(ordinary_hit.packed),"ordinary build remains on legacy embedded-image contract until explicit cutover")
	ordinary_hit.clear();owner.scene=null;owner.state=null;owner=null
	reopened.free();loaded=null;reopened_mesh=null;reopened_material=null
	original.free();sample.clear();base=null
	finish()

func finish()->void:
	var report:Dictionary={"checks":checks,"failures":failures,"engine":Engine.get_version_info(),"folder":folder,"measurements":measurements,"visual_validation":"pending; headless producer contract only"}
	var file:=FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MODEL_TEXTURE_PRODUCTS_RESULT "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
