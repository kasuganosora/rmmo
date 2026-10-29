extends "res://tools/test_model_texture_products.gd"
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
class AfterPublication extends RefCounted:
	var target:String
	func is_cancelled()->bool:return FileAccess.file_exists(target)
class LockStaged extends RefCounted:
	var directory:String
	var prefix:String
	var release_when:String
	var released:=false
	var held:FileAccess
	func is_cancelled()->bool:
		if held!=null and FileAccess.file_exists(release_when):held.close();held=null;released=true
		if held==null and not released and DirAccess.dir_exists_absolute(directory):
			for name:String in DirAccess.get_files_at(directory):
				if name.begins_with(prefix):held=FileAccess.open(directory.path_join(name),FileAccess.READ);break
		return false

func put(path:String,data:PackedByteArray)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(data);file.close()

func rows_for(root:String,count:int,prefix:String="file")->Array:
	var rows:Array=[];DirAccess.make_dir_recursive_absolute(root)
	for index:int in count:
		var source:=root.path_join("%s_%d.staged"%[prefix,index]);var target:=root.path_join("%s_%d.product"%[prefix,index])
		put(source,PackedByteArray([1,2,3,index%256]));rows.append({"staged":source,"destination":target})
	return rows

func clean_sources(rows:Array)->void:
	for row:Dictionary in rows:
		if Paths.allowed(row.staged,folder) and FileAccess.file_exists(row.staged):DirAccess.remove_absolute(row.staged)

func no_ipc(root:String)->bool:
	return Array(DirAccess.get_directories_at(root)).filter(func(name:String)->bool:return name.begins_with(".immutable-publish-")).is_empty()

func concurrent(rows:Array,root:String,ready:Semaphore,go:Semaphore)->Dictionary:
	ready.post();go.wait();return Atomic.publish_new_batch(rows,root)

func test_atomic()->void:
	var root:=folder.path_join("atomic")
	var rows:=rows_for(root,4)
	put(rows[1].destination,PackedByteArray([9,8,7]))
	var result:=Atomic.publish_new_batch(rows,root)
	check(result.ok and result.results==[OK,ERR_ALREADY_EXISTS,OK,OK] and result.processes==1,"batch creates absent products in one process and reports existing owners")
	check(FileAccess.get_file_as_bytes(rows[1].destination)==PackedByteArray([9,8,7]) and FileAccess.file_exists(rows[1].staged),"existing target and losing caller staging are not overwritten or removed")
	check(no_ipc(root),"owned IPC manifest directory is cleaned")
	clean_sources(rows)
	var invalid:=rows_for(root,2,"invalid")
	var outside:=folder.path_join("outside.product")
	invalid[1].destination=outside
	result=Atomic.publish_new_batch(invalid,root)
	check(not result.ok and result.processes==0 and not FileAccess.file_exists(invalid[0].destination) and not FileAccess.file_exists(outside) and no_ipc(root),"out-of-root preflight fails with zero publication or IPC side effects")
	invalid[1].destination=invalid[0].destination
	check(not Atomic.publish_new_batch(invalid,root).ok and not FileAccess.file_exists(invalid[0].destination),"duplicate target preflight has no side effects")
	invalid[1].destination=invalid[0].staged
	check(not Atomic.publish_new_batch(invalid,root).ok and FileAccess.file_exists(invalid[0].staged),"source-target aliasing cannot consume another staged input")
	clean_sources(invalid)
	var missing:=rows_for(root,2,"missing");DirAccess.remove_absolute(missing[1].staged)
	check(not Atomic.publish_new_batch(missing,root).ok and not FileAccess.file_exists(missing[0].destination),"missing staged input rejects the whole batch before publication")
	clean_sources(missing)
	var directory_target:=rows_for(root,1,"directory");DirAccess.make_dir_absolute(directory_target[0].destination)
	check(not Atomic.publish_new_batch(directory_target,root).ok and FileAccess.file_exists(directory_target[0].staged),"a directory at the target is a failure, not a reusable product")
	clean_sources(directory_target)
	var quoted_root:=root.path_join("quote_'_dollar_$_unicode_源")
	var quoted:=rows_for(quoted_root,1,"literal_'_$_(data)")
	check(Atomic.publish_new_batch(quoted,quoted_root).ok and FileAccess.get_file_as_bytes(quoted[0].destination)==PackedByteArray([1,2,3,0]),"Unicode and shell punctuation remain literal path data")
	var before:=rows_for(root,2,"cancel_before");var cancelled:=Cancel.new()
	result=Atomic.publish_new_batch(before,root,cancelled)
	check(not result.ok and result.error==ERR_SKIP and result.processes==0 and not FileAccess.file_exists(before[0].destination),"cancel before batch publishes nothing")
	clean_sources(before)
	var after:=rows_for(root,2,"cancel_after");var after_token:=AfterPublication.new();after_token.target=after[0].destination
	result=Atomic.publish_new_batch(after,root,after_token)
	check(not result.ok and result.error==ERR_SKIP and result.results==[OK,OK] and FileAccess.file_exists(after[0].destination),"cancel observed after batch reports completed immutable files without granting commit")
	check(no_ipc(root),"cancel after publication also cleans IPC files")
	if OS.get_name()=="Windows":
		var partial:=rows_for(root,3,"partial")
		var held:=FileAccess.open(partial[1].staged,FileAccess.READ)
		result=Atomic.publish_new_batch(partial,root);held.close()
		check(not result.ok and result.results==[OK,ERR_FILE_CANT_WRITE,ERR_SKIP],"locked second source reproduces partial publication and stops later rows")
		check(FileAccess.file_exists(partial[0].destination) and FileAccess.file_exists(partial[1].staged) and FileAccess.file_exists(partial[2].staged) and not FileAccess.file_exists(partial[2].destination),"partial failure leaves completed immutable output and only caller-owned remaining temps")
		clean_sources(partial)
	var racers_root:=root.path_join("racers");var a:=rows_for(racers_root,1,"a");var b:=rows_for(racers_root,1,"b");b[0].destination=a[0].destination
	var ready:=Semaphore.new();var go:=Semaphore.new();var first:=Thread.new();var second:=Thread.new()
	check(first.start(concurrent.bind(a,racers_root,ready,go))==OK and second.start(concurrent.bind(b,racers_root,ready,go))==OK,"concurrent publisher threads start")
	ready.wait();ready.wait();go.post();go.post()
	var one:Dictionary=first.wait_to_finish();var two:Dictionary=second.wait_to_finish()
	check(one.ok and two.ok and [one.results[0],two.results[0]].count(OK)==1 and [one.results[0],two.results[0]].count(ERR_ALREADY_EXISTS)==1,"concurrent identical product publication has one creator and one reuse")
	check(FileAccess.get_file_as_bytes(a[0].destination)==PackedByteArray([1,2,3,0]) and no_ipc(racers_root),"racing writers preserve canonical bytes and clean both IPC directories")
	clean_sources(a);clean_sources(b)
	var many:=rows_for(root.path_join("larger_than_windows_command_line"),160)
	result=Atomic.publish_new_batch(many,root)
	check(result.ok and result.metadata_bytes>32768 and result.processes==1 and result.results.size()==160,"large path table bypasses command-line length limits without a texture count cap")
	var existing:=rows_for(root.path_join("all_existing"),3)
	for row:Dictionary in existing:put(row.destination,PackedByteArray([9]))
	result=Atomic.publish_new_batch(existing,root)
	check(result.ok and result.processes==0 and result.results==[ERR_ALREADY_EXISTS,ERR_ALREADY_EXISTS,ERR_ALREADY_EXISTS],"all-existing immutable products need no publication process")
	clean_sources(existing)

func many_model(count:int)->Node3D:
	var root:=Node3D.new();root.name="ManyTextures"
	var mesh:=ArrayMesh.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP]);mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	for index:int in count:
		var image:=Image.create(16,16,false,Image.FORMAT_RGBA8);image.fill(Color(float(index+1)/float(count+1),.5,.25,1));image.generate_mipmaps()
		var material:=StandardMaterial3D.new();material.albedo_texture=ImageTexture.create_from_image(image)
		var node:=MeshInstance3D.new();node.name="Part%d"%index;node.mesh=mesh;node.material_override=material;root.add_child(node);node.owner=root
	return root

func product_shas(table:Dictionary,root:String)->Dictionary:
	var shas:Dictionary={}
	for id:String in table.textures:shas[id]=FileAccess.get_sha256(root.path_join(table.textures[id].file))
	return shas

func test_producer_benchmark()->void:
	var scene:=many_model(60);var legacy_root:=folder.path_join("single_control");var batch_root:=folder.path_join("batch")
	var started:=Time.get_ticks_usec();var control:=Products.prepare(scene,legacy_root,null,false);measurements.single_first_us=Time.get_ticks_usec()-started
	check(control.ok and control.stats.product_publish_processes==60,"single-file control publishes each of 60 unique products")
	Products.restore(control)
	started=Time.get_ticks_usec();var batch:=Products.prepare(scene,batch_root);measurements.batch_first_us=Time.get_ticks_usec()-started
	check(batch.ok and batch.stats.product_publish_processes==1 and batch.stats.products_written==60,"batch publishes the same 60 unique products with one process")
	Products.restore(batch)
	check(control.table_sha==batch.table_sha and product_shas(control.table,legacy_root)==product_shas(batch.table,batch_root),"single and batch routes produce exactly identical table and every STEX SHA")
	check(control.stats.readbacks==batch.stats.readbacks and control.stats.pixel_hashes==batch.stats.pixel_hashes and control.stats.image_bytes==batch.stats.image_bytes,"batch does not increase readback, hashing, or decoded byte work")
	started=Time.get_ticks_usec();var control_hit:=Products.prepare(scene,legacy_root,null,false);measurements.single_existing_us=Time.get_ticks_usec()-started;Products.restore(control_hit)
	started=Time.get_ticks_usec();var batch_hit:=Products.prepare(scene,batch_root);measurements.batch_existing_us=Time.get_ticks_usec()-started;Products.restore(batch_hit)
	check(control_hit.ok and batch_hit.ok and batch_hit.stats.products_reused==60 and batch_hit.stats.product_publish_processes==0 and batch_hit.stats.table_publish_processes==0,"existing model products and table reuse without any publication process")
	measurements.single_stats=control.stats;measurements.batch_stats=batch.stats
	measurements.table_sha=batch.table_sha;measurements.products_sha_file=folder.path_join("products_sha.json")
	var hashes:=FileAccess.open(measurements.products_sha_file,FileAccess.WRITE);hashes.store_string(JSON.stringify(product_shas(batch.table,batch_root),"\t"));hashes.close()
	scene.free()

func test_producer_failure()->void:
	if OS.get_name()!="Windows":return
	var scene:=many_model(3);var root:=folder.path_join("failed_model")
	var texture_ids:Array=[]
	for texture:ImageTexture in Products._collect(scene).textures.values():texture_ids.append(Products._pixel_key(texture.get_image()))
	var token:=LockStaged.new();token.directory=Products.directory(root);token.prefix=texture_ids[1]+".stex.tmp-";token.release_when=token.directory.path_join(texture_ids[0]+".stex")
	var prior:=root.path_join("previous_index.json");put(prior,PackedByteArray([1,5,9]));var prior_sha:=FileAccess.get_sha256(prior)
	var foreign:=token.directory.path_join("other_owner.stex.tmp-foreign");put(foreign,PackedByteArray([2,4,6]))
	var result:=Products.prepare(scene,root,token)
	check(not result.ok and result.error=="texture_publish","producer reproduces failed batch publication")
	if token.held!=null:token.held.close()
	check(not scene.has_meta(Products.TABLE_META) and scene.get_child(0).material_override.albedo_texture!=null,"failed publication leaves original graph untouched")
	check(DirAccess.get_files_at(Products.table_directory(root)).is_empty() and FileAccess.get_sha256(prior)==prior_sha,"partial texture publication cannot promote table or prior index")
	check(DirAccess.get_files_at(token.directory).size()==2 and FileAccess.get_file_as_bytes(foreign)==PackedByteArray([2,4,6]) and no_ipc(root),"partial producer failure cleans only its own staging and preserves another owner's temp")
	scene.free()

func test_compiled_partial_failure()->void:
	if OS.get_name()!="Windows":return
	var scene:=many_model(3);var source:=folder.path_join("compiled_original.scn")
	var packed:=packed_scene(scene);ResourceSaver.save(packed,source,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS);packed=null
	var owner:=Compiled.PreparedSource.new();owner.path=source;owner.source_digest=FileAccess.get_sha256(source);owner.state=GLTFState.new();owner.scene=scene
	var baseline:=Compiled._build_prepared(owner,Time.get_ticks_usec(),true)
	check(baseline.get("ok",false),"compiled partial-failure test establishes a real published predecessor")
	var index:=Compiled.index_path(source);var index_before:=FileAccess.get_file_as_bytes(index)
	var marker:=folder.sha256_text().hex_decode()
	for node:MeshInstance3D in scene.get_children():
		var image:=Image.create(17,17,false,Image.FORMAT_RGBA8);image.fill(Color(float(node.get_index()+1)/5.0,.33,.67,1));image.set_pixel(0,0,Color8(marker[0],marker[1],marker[2]));image.generate_mipmaps()
		node.material_override.albedo_texture=ImageTexture.create_from_image(image)
	var ids:Array=[]
	for texture:ImageTexture in Products._collect(scene).textures.values():ids.append(Products._pixel_key(texture.get_image()))
	var token:=LockStaged.new();token.directory=Products.directory(Paths.external_root());token.prefix=ids[1]+".stex.tmp-";token.release_when=token.directory.path_join(ids[0]+".stex")
	# The producer's failure is the same error returned before the writer packs
	# or promotes an index. Keep a real prior index and reopen it afterwards.
	var failed:=Products.prepare(scene,Paths.external_root(),token)
	check(not failed.ok and failed.error=="texture_publish" and token.released,"partial producer failure closes its test lock before owned staging cleanup")
	check(FileAccess.get_file_as_bytes(index)==index_before,"partial publication preserves the exact real compiled index bytes")
	var prior:=Compiled.read(source)
	check(prior.get("hit",false) and prior.get("texture_table",{}).get("sha256")==baseline.get("texture_table",{}).get("sha256"),"previous compiled generation remains independently readable after partial failure")
	prior.clear();owner.scene=null;owner.state=null;owner=null;scene.free()

func run()->void:
	folder=Paths.external_root().path_join("batch_%d"%OS.get_process_id());DirAccess.make_dir_recursive_absolute(folder)
	test_atomic();test_producer_failure();test_compiled_partial_failure()
	if "--skip-benchmark" not in OS.get_cmdline_user_args():test_producer_benchmark()
	finish()
