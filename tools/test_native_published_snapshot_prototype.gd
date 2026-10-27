extends SceneTree
## Synthetic private-root-only contract. Not an integration or performance test.
## Never reads a GLB, a real map or the user's mutable compiled asset cache.
const Prototype=preload("res://tools/native_published_snapshot_prototype.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
var checks:Array=[]
var failures:Array[String]=[]
var root_path:=""

func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->void:
	checks.append({"name":label,"ok":condition})
	if not condition:failures.append(label)
	print("PASS " if condition else "FAIL ",label)

func put(path:String,data:PackedByteArray)->bool:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir())!=OK:return false
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_buffer(data);file.flush();var error:=file.get_error();file.close()
	return error==OK

func put_json(path:String,value:Variant)->bool:return put(path,JSON.stringify(value).to_utf8_buffer())

func requested_root()->String:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture-root="):
			var path:String=Prototype._root(arg.trim_prefix("--fixture-root="))
			if not path.is_empty() and not DirAccess.dir_exists_absolute(path) and not FileAccess.file_exists(path):return path
	return ""

func write_old_model(folder:String,name_:String,color:Color)->Dictionary:
	var root:=Node3D.new();root.name=name_
	var material:=StandardMaterial3D.new();material.albedo_color=color
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(0,material)
	for child_name:String in ["First","Second"]:
		var child:=MeshInstance3D.new();child.name=child_name;child.mesh=mesh;root.add_child(child);child.owner=root
	var packed:=PackedScene.new()
	if packed.pack(root)!=OK:root.free();return {}
	root.free()
	var temporary:=folder.path_join(name_+".scn")
	if ResourceSaver.save(packed,temporary,ResourceSaver.FLAG_BUNDLE_RESOURCES)!=OK:return {}
	var payload_sha:=FileAccess.get_sha256(temporary)
	var product:=Compiled.directory(folder).path_join(payload_sha+".scn")
	if DirAccess.make_dir_recursive_absolute(product.get_base_dir())!=OK or DirAccess.rename_absolute(temporary,product)!=OK:return {}
	var file:=FileAccess.open(product,FileAccess.READ)
	if file==null:return {}
	var size:=file.get_length();file.close()
	# This logical old source is deliberately not created on disk.
	var asset:=folder.path_join("assets").path_join(name_+".glb")
	var source_sha:="fixture source "+name_;source_sha=source_sha.sha256_text()
	var generator:=Compiled.generator()
	var info:={"version":Compiled.VERSION,"generator":generator,"source_sha":source_sha,"payload_sha":payload_sha,"bytes":size}
	var stats:=Footprint.empty_stats();stats.nodes=3;stats.meshes=1;stats.materials=1;stats.native_uncompressed_bytes=size
	var estimate:=Footprint.estimate_stats(stats)
	if estimate.is_empty() or not put_json(Compiled.index_path(asset,folder),info):return {}
	var descriptor:={"version":Footprint.VERSION,"footprint_generator":Footprint.generator(),"source_path":asset,"source_sha":source_sha,"payload_sha":payload_sha,"generator":generator,"bytes":size,"source_bytes":1,"stats":stats,"estimated_bytes":estimate.estimated_bytes,"resident_bytes":estimate.resident_bytes}
	var body:=JSON.stringify(descriptor)
	if not put_json(Footprint.descriptor_path(asset,folder),{"version":Footprint.VERSION,"body":body,"sha256":body.sha256_text()}):return {}
	return {"asset":asset,"sha":source_sha,"payload":payload_sha,"product":product,"estimate":estimate.estimated_bytes}

func finish()->void:
	put_json(root_path.path_join("report.json"),{"checks":checks,"failures":failures,"scope":"Synthetic headless prototype, no real map, GLB, texture, GPU timing or production integration. Private roots only."})
	print("PUBLISHED_SNAPSHOT_PROTOTYPE checks=",checks.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func run()->void:
	root_path=requested_root()
	if root_path.is_empty():push_error("--fixture-root must name a new review_artifacts directory");quit(2);return
	if DirAccess.make_dir_recursive_absolute(root_path)!=OK:quit(2);return
	var old:=root_path.path_join("old")
	if DirAccess.make_dir_recursive_absolute(old)!=OK:quit(2);return
	var first:=write_old_model(old,"A",Color.RED);var second:=write_old_model(old,"B",Color.BLUE)
	check(not first.is_empty() and not second.is_empty(),"two old native products and footprints created")
	if first.is_empty() or second.is_empty():finish();return
	check(not FileAccess.file_exists(first.asset) and not FileAccess.file_exists(second.asset),"old logical GLB files are absent")
	check(first.payload!=second.payload,"models have distinct native products")
	var rows:=[{"key":"models/a","old_asset":first.asset},{"key":"models/a_alias","old_asset":first.asset},{"key":"models/b","old_asset":second.asset}]
	var target:=root_path.path_join("published")
	var published:=Prototype.publish(old,target,rows)
	check(published.get("ok",false) and published.get("models",0)==3 and published.get("products",0)==2 and published.get("offline_payload_hashes",0)==2,"offline publication deduplicates two products and writes manifest last")
	if not published.get("ok",false):finish();return
	check(FileAccess.file_exists(target.path_join("snapshot.json")),"completion marker exists only after publication")
	var opened:=Prototype.open_snapshot(target,int(first.estimate)+int(second.estimate)-1)
	check(opened.get("ok",false),"published snapshot opens with explicit budget")
	if not opened.get("ok",false):finish();return
	var snapshot:RefCounted=opened.snapshot
	var a:Dictionary=snapshot.load_model("models/a");var alias:Dictionary=snapshot.load_model("models/a_alias")
	check(a.get("ok",false) and alias.get("ok",false) and is_same(a.get("packed"),alias.get("packed")) and alias.get("shared",false),"same payload shares one PackedScene")
	check(snapshot.physical_reads==1 and snapshot.reserved==first.estimate,"shared alias has no second read or byte charge")
	var over:Dictionary=snapshot.load_model("models/b")
	check(not over.get("ok",false) and over.get("reason")=="budget" and snapshot.physical_reads==1,"new product cannot exceed budget")
	check(snapshot.load_model("models/../a").get("reason")=="model_key","path traversal key rejected")
	check(snapshot.load_model("models/missing").get("reason")=="model_missing","unknown model has explicit error")
	if a.get("ok",false):
		var one:Node=a.packed.instantiate();var two:Node=alias.packed.instantiate()
		var mesh_one:MeshInstance3D=one.get_node("First");var mesh_two:MeshInstance3D=two.get_node("First")
		check(one!=two and mesh_one.mesh==mesh_two.mesh and mesh_one.mesh.surface_get_material(0)==mesh_two.mesh.surface_get_material(0),"independent nodes share model mesh and base material identity")
		var changed:=mesh_one.mesh.surface_get_material(0).duplicate() as Material
		mesh_one.set_surface_override_material(0,changed)
		check(mesh_one.get_active_material(0)==changed and mesh_two.get_active_material(0)!=changed,"per-instance material override leaves shared base untouched")
		one.free();two.free();changed=null
	a.clear();alias.clear();snapshot.close()
	opened=Prototype.open_snapshot(target,int(first.estimate)+int(second.estimate))
	if opened.get("ok",false):
		snapshot=opened.snapshot
		var aa:Dictionary=snapshot.load_model("models/a");var bb:Dictionary=snapshot.load_model("models/b")
		check(aa.get("ok",false) and bb.get("ok",false) and snapshot.physical_reads==2 and snapshot.reserved==int(first.estimate)+int(second.estimate),"two distinct products stay within full shared budget")
		aa.clear();bb.clear();snapshot.close()
	else:check(false,"full-budget snapshot opens")
	var path:=target.path_join("products").path_join(first.payload+".scn");var hidden:=path+".held"
	check(DirAccess.rename_absolute(path,hidden)==OK,"temporarily hide isolated published product")
	opened=Prototype.open_snapshot(target,int(first.estimate)+int(second.estimate))
	if opened.get("ok",false):
		snapshot=opened.snapshot;var missing:Dictionary=snapshot.load_model("models/a")
		check(not missing.get("ok",false) and missing.get("reason")=="product_missing_or_size" and snapshot.physical_reads==0,"missing product fails without source or GLB fallback")
		snapshot.close()
	else:check(false,"missing-product snapshot still opens")
	check(DirAccess.rename_absolute(hidden,path)==OK,"restore isolated published product")
	var bad_version:=root_path.path_join("bad_version")
	check(put_json(bad_version.path_join("snapshot.json"),{"revision":Prototype.REVISION+1,"engine_hash":Engine.get_version_info().hash}),"write isolated wrong-version marker")
	check(not Prototype.open_snapshot(bad_version,int(first.estimate)).get("ok",false),"unsupported version rejected")
	var failed_root:=root_path.path_join("failed_publish")
	var failed:=Prototype.publish(old,failed_root,[rows[0],{"key":"../escape","old_asset":second.asset}])
	check(not failed.get("ok",false) and not FileAccess.file_exists(failed_root.path_join("snapshot.json")),"failed publication leaves no completion marker")
	check(Prototype.open_snapshot(failed_root,int(first.estimate)).get("reason")=="version","uncommitted directory cannot be opened as published")
	check(FileAccess.file_exists(first.product) and FileAccess.file_exists(second.product),"old native products remain untouched")
	check(not FileAccess.file_exists(first.asset) and not FileAccess.file_exists(second.asset),"conversion and reads never create old GLB sources")
	finish()
