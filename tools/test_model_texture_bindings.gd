extends SceneTree
const Binding=preload("res://scripts/world3d/model_texture_bindings.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Native=preload("res://scripts/world3d/native_model_product.gd")
const Streamed=preload("res://scripts/world3d/streamed_texture_source.gd")
const A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
var checks:=0
var failures:=0

class NoReadbackTexture extends Texture2D:
	var reads:=0
	func _get_width()->int:return 4
	func _get_height()->int:return 4
	func _get_image()->Image:
		reads+=1
		return null

class StubPool extends "res://scripts/world3d/shared_prefab_images.gd":
	var reads:=0
	func _load_stream(_plan:Dictionary,_digest:String)->Texture2D:
		reads+=1
		return NoReadbackTexture.new()

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func _initialize()->void:run.call_deferred()

func run()->void:
	var root_node:=Node3D.new()
	root_node.set_meta(Binding.TABLE_META,"table")
	var main:=StandardMaterial3D.new();var overlay:=StandardMaterial3D.new();var extra:=StandardMaterial3D.new()
	main.roughness=.37;main.normal_enabled=true;main.normal_scale=.63;main.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	main.set_meta(Binding.BINDINGS_META,{"albedo_texture":{"id":A,"normal":false},"normal_texture":{"id":A,"normal":true}})
	extra.emission_enabled=true;extra.emission=Color(.25,.5,.75)
	extra.set_meta(Binding.BINDINGS_META,{"emission_texture":{"id":B,"normal":false}})
	main.next_pass=extra
	overlay.set_meta(Binding.BINDINGS_META,{"albedo_texture":{"id":A,"normal":false}})
	var mesh:=BoxMesh.new();mesh.material=main
	for i:int in 2048:
		var part:=MeshInstance3D.new();part.mesh=mesh;part.name="Part%d"%i
		if i%2==0:part.material_overlay=overlay
		if i%3==0:part.set_surface_override_material(0,main)
		root_node.add_child(part);part.owner=root_node
	var packed:=PackedScene.new()
	check(packed.pack(root_node)==OK,"pack large shared-resource fixture")
	var began:=Time.get_ticks_usec()
	var state:=Binding.begin(packed,{A:"shared-a",B:"shared-b"},"table")
	var plan_us:=Time.get_ticks_usec()-began
	check(state.ok and state.bindings.size()==3,"2048 parts visit three unique materials including next_pass and overlay")
	check(state.visited_meshes==1 and state.visited_materials==3,"resource identity eliminates repeated mesh/material walks")
	check(state["keys"].size()==2,"normal/color roles and repeated slots require only two unique products")
	check(Binding.step(state)==Binding.FAILED,"no setter can run before complete dependency adoption")
	var first:=NoReadbackTexture.new();var second:=NoReadbackTexture.new()
	check(not Binding.adopt(state,{"shared-a":first}),"incomplete texture siblings stay pending")
	check(main.albedo_texture==null and main.normal_texture==null and overlay.albedo_texture==null and extra.emission_texture==null,"pending dependency has no partial material side effect")
	check(Binding.adopt(state,{"shared-a":first,"shared-b":second}),"complete owners can be adopted without file or image reads")
	var steps:=0;var progress:=Binding.PROGRESS
	while progress==Binding.PROGRESS:
		progress=Binding.step(state);steps+=1
	check(progress==Binding.READY and steps==3 and state.sets==4,"bounded publication touches each unique material/slot once")
	check(main.albedo_texture==first and main.normal_texture==first and overlay.albedo_texture==first and extra.emission_texture==second,"all slots share the actual prepared owners")
	check(first.reads==0 and second.reads==0,"binding never reads back streaming pixels")
	check(is_equal_approx(main.roughness,.37) and is_equal_approx(main.normal_scale,.63) and main.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST and extra.emission==Color(.25,.5,.75),"non-texture material parameters and sampler semantics remain unchanged")
	check(Binding.step(state)==Binding.READY and state.sets==4,"completed publication performs no duplicate setters")
	var repeated:=Binding.begin(packed,{A:"shared-a",B:"shared-b"},"table")
	Binding.adopt(repeated,{"shared-a":first,"shared-b":second})
	while Binding.step(repeated)==Binding.PROGRESS:pass
	check(repeated.sets==0 and repeated.unchanged==4,"already-bound immutable owners avoid repeated setter work")
	check(not Binding.begin(packed,{A:"shared-a",B:"shared-b"},"different").ok,"scene/table mismatch is rejected before mutation")
	check(not Binding.begin(packed,{A:"shared-a"},"table").ok,"missing referenced product is not silently published white")
	main.set_meta(Binding.BINDINGS_META,{"roughness":{"id":A,"normal":false}})
	check(not Binding.begin(packed,{A:"shared-a",B:"shared-b"},"table").ok and is_equal_approx(main.roughness,.37),"non-texture property injection leaves material untouched")
	Binding.release(state);Binding.release(repeated)
	check(state.is_empty() and repeated.is_empty(),"plan retirement drops every extra owner")
	root_node.free()
	plan_and_pool_test()
	candidate_test()
	print("MODEL_TEXTURE_BINDINGS checks=",checks," failures=",failures," nodes=2048 plan_us=",plan_us)
	quit(1 if failures else 0)

func plan_and_pool_test()->void:
	# No product files exist: planning is strictly metadata-only. Native product
	# byte preservation and actual streaming upload are separate producer/GPU tests.
	var content_root:=ProjectSettings.globalize_path("user://absent-model-products")
	var table:Dictionary={"version":1,"textures":{}}
	for id:String in [A,B]:
		table.textures[id]={"file":"cache/world3d/model_textures_v1/"+id+".stex","width":4,"height":4,"format":Image.FORMAT_RGBA8,"bytes":64,"file_bytes":116,"mip_sizes":[64],"alpha":true}
	var planned:=Binding.texture_plan(table,content_root)
	check(planned.ok and planned.plan.rows.size()==2 and planned.sources.size()==2,"two native products plan without any product file or pixel read")
	check(planned.plan.output_bytes==128 and planned.plan.estimated_bytes==128*2+64*2+65536,"native products retain full output and streaming scratch in the common budget")
	check(Binding.Prep.valid_sources(planned.sources),"model product keys obey the existing shared texture source contract")
	var key_a:String=planned["keys"][A]
	check(key_a==Binding.Paint.texture_key(content_root.path_join(table.textures[A].file).replace("\\","/")),"color and normal roles have one native product identity")
	var bad:=table.duplicate(true);bad.textures[A].file="../outside.stex"
	check(not Binding.texture_plan(bad,content_root).ok,"product namespace rejects an escaped path without reading it")
	var ledger:=Admission.new();ledger.byte_limit=64*1024*1024
	var pool:=StubPool.new();pool.admission=ledger
	var a:=pool.offer(planned.plan)
	check(ledger.reserve_bundle("model-a",{"estimated_bytes":a.scratch_bytes,"exclusive":false},a.retained),"model producer reserves its workspace and unique pixel owners together")
	pool.commit("model-a",a)
	var b:=pool.offer(planned.plan)
	check(b.leaders.is_empty() and b.retained.is_empty() and ledger.reserve_bundle("model-b",{"estimated_bytes":b.scratch_bytes,"exclusive":false},b.retained),"another model reuses the same products without duplicate output reservations")
	pool.commit("model-b",b)
	check(not pool.ready("model-b") and pool.textures("model-b").is_empty(),"followers remain pending before any producer result")
	for key:String in planned.plan.rows:
		check(pool.load_stream("model-a",key,A,planned.plan.rows[key]),"admitted native product is published once")
		check(not pool.load_stream("model-b",key,A,planned.plan.rows[key]),"follower cannot launch a duplicate native product read")
	check(pool.reads==2 and pool.snapshot().produced==2 and pool.ready("model-b"),"both models become ready after exactly two unique native reads")
	var held:=pool.textures("model-b");var weak:WeakRef=weakref(held[key_a])
	check(held[key_a].reads==0,"shared native publication never reads back pixels")
	pool.release("model-a");ledger.release("model-a")
	check(weak.get_ref()!=null and pool.snapshot().retained_bytes==256,"retiring one model preserves the sibling's complete pixel reservation")
	held.clear();pool.release("model-b");ledger.release("model-b")
	check(weak.get_ref()==null and ledger.reserved_bytes==0 and pool.snapshot().outputs==0,"last consumer drops prepared owners and releases their unique budget")

func write_bytes(path:String,bytes:PackedByteArray)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	check(file!=null,"fixture metadata file opens")
	if file!=null:file.store_buffer(bytes);file.close()

func candidate_test()->void:
	# Synthetic metadata test: native parsing and image-free SCN persistence have
	# their own producer tests. No original GLB or STEX file is created here.
	var content_root:=ProjectSettings.globalize_path("user://native-model-candidate")
	var path:=content_root.path_join("assets/absent-import-source.glb")
	var native_bytes:PackedByteArray="metadata-fixture".to_utf8_buffer()
	var product:=Footprint.Compiled.directory(content_root).path_join(B+".scn")
	write_bytes(product,native_bytes)
	var table:Dictionary={"version":1,"image_bytes":64,"textures":{A:{"file":"cache/world3d/model_textures_v1/"+A+".stex","pixel_sha":A,"width":4,"height":4,"format":Image.FORMAT_RGBA8,"bytes":64,"file_bytes":116,"mip_sizes":[64],"alpha":false,"normal_xy":false}}}
	var table_body:=JSON.stringify(table);var table_sha:=table_body.sha256_text()
	var table_path:=Binding.Products.table_directory(content_root).path_join(table_sha+".json")
	write_bytes(table_path,table_body.to_utf8_buffer())
	var texture_descriptor:Dictionary={"version":1,"sha256":table_sha,"bytes":table_body.to_utf8_buffer().size(),"textures":1,"image_bytes":64}
	var manifest:Dictionary={"version":1,"source_path":path,"source_sha":A,"payload_sha":B,"generator":"synthetic","bytes":native_bytes.size(),"texture_table":texture_descriptor}
	var index:=Footprint.Compiled.index_path(path,content_root)
	write_bytes(index,JSON.stringify(manifest).to_utf8_buffer())
	var descriptor:=manifest.duplicate(true);descriptor.erase("texture_table")
	descriptor.merge({"source_bytes":28,"estimated_bytes":67108864,"resident_bytes":67108864,"model_metadata":{"version":1,"local_bounds":[0,0,0,1,1,1],"file_length":28,"json_bytes":4,"json_sha256":A}})
	var body:=JSON.stringify(descriptor)
	write_bytes(Footprint.descriptor_path(path,content_root),JSON.stringify({"version":1,"body":body,"sha256":body.sha256_text()}).to_utf8_buffer())
	var candidate:=Footprint.candidate(path,content_root,"",true)
	check(not candidate.is_empty() and candidate.get("texture_table")==texture_descriptor,"fixed native candidate preserves its exact texture table identity")
	var metadata:=Native.read(path,content_root)
	check(not metadata.is_empty() and metadata.native_candidate.texture_table==texture_descriptor and not FileAccess.file_exists(path),"published metadata carries split textures without opening a GLB")
	var catalog:Dictionary={}
	var alias_root:=content_root.replace("/","\\")
	var planned:=Binding.candidate_plan(candidate,alias_root,catalog)
	check(planned.ok and planned.table_sha==table_sha and planned.plan.output_bytes==64 and catalog.size()==1,"candidate reads its table once without opening native pixel products")
	var model_row:Dictionary=planned.plan.rows.values()[0]
	check(Streamed.valid_model_product(model_row,content_root),"cached model row admits the canonical root after alternate spelling")
	check(Streamed.valid_model_product(model_row,alias_root),"cached model row also admits the original alternate spelling")
	var moved:=table_path+".held"
	check(DirAccess.rename_absolute(table_path,moved)==OK,"temporarily remove table from lookup path")
	var again:=Binding.candidate_plan(candidate,content_root,catalog)
	check(again==planned and catalog.size()==1,"same operation reuses table metadata with no further filesystem read")
	check(Binding.candidate_plan(candidate,content_root.path_join("unused/.."),catalog)==planned and catalog.size()==1,"equivalent dot path reuses the same table without rereading")
	check(not Binding.candidate_plan(candidate,content_root.path_join("other_root"),catalog).ok and catalog.size()==1,"another root cannot borrow the cached texture table")
	var serialized:=candidate.duplicate(true)
	serialized.texture_table=JSON.parse_string(JSON.stringify(candidate.texture_table))
	check(Binding.candidate_plan(serialized,content_root,catalog)==planned,"JSON numeric representation preserves the same cached descriptor identity")
	var conflicting:=candidate.duplicate(true);conflicting.texture_table.image_bytes=128
	check(not Binding.candidate_plan(conflicting,content_root,catalog).ok,"same SHA with conflicting budget cannot reuse a cached table")
	check(DirAccess.rename_absolute(moved,table_path)==OK,"restore fixture table")
	manifest.texture_table.bytes="invalid"
	write_bytes(index,JSON.stringify(manifest).to_utf8_buffer())
	check(Footprint.candidate(path,content_root,"",true).is_empty(),"malformed split descriptor is rejected at fixed-product identity boundary")
	check(Binding.candidate_plan({},content_root,{}).plan.rows.is_empty(),"ordinary embedded products add no new texture work")
