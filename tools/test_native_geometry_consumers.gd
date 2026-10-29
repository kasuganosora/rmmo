extends "res://tools/test_native_texture_preview.gd"
## Geometry consumers must not wait for a texture table or publish an unbound
## scene as a render template. The inherited fixture never creates a GLB.
const TreeModel=preload("res://scripts/world3d/parametric_tree.gd")

func geometry(path_:String,candidate:Dictionary={}) -> Node3D:
	# The old entry used by these consumers gives a meaningful baseline failure.
	var library:RefCounted=Assets.new()
	if library.has_method("instantiate_geometry"):
		return library.call("instantiate_geometry",path_,candidate)
	return Assets.instantiate_preview(path_,true)

func read_count(trace:Dictionary)->int:
	var count:=0
	for stat:Dictionary in trace.stats:
		if stat.label=="compiled.native_read":count+=int(stat.count)
	return count

func tree_fixture()->Dictionary:
	var model:=fixture("tree_geometry",true)
	var index_path:=Compiled.index_path(model.path,content_root)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(index_path))
	var folder:=Compiled.directory(content_root)
	var packed:PackedScene=ResourceLoader.load(folder.path_join(manifest.payload_sha+".scn"),"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var source:=packed.instantiate()
	var material:StandardMaterial3D=source.get_child(0).mesh.surface_get_material(0)
	material.resource_name="pine_foliage"
	for child in source.get_children():child.free()
	for level:int in 2:
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-1,1,.2),Vector3(1,2,-.2),Vector3(0,3,0)])
		arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD])
		arrays[Mesh.ARRAY_TEX_UV2]=PackedVector2Array([Vector2(1,0),Vector2(1,0),Vector2(1,0)])
		arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(0,material)
		var part:=MeshInstance3D.new();part.name="FoliageLOD%d"%level;part.mesh=mesh
		part.set_meta("extras",{"rmmo_tree_recipe":{"version":1,"role":"foliage","height":4.,"bare_trunk":1.,"anchors":[[0,2,0]]},
			"rmmo_visibility_range":{"begin":0. if level==0 else 20.,"end":20. if level==0 else 80.,"bounds":[-1,1,-.2,2,2,.4]}})
		source.add_child(part);part.owner=source
	packed=PackedScene.new();check(packed.pack(source)==OK,"pack recipe, UV2 and two LOD fixture");source.free()
	var staging:=folder.path_join("tree_geometry_%d.scn"%OS.get_process_id())
	check(ResourceSaver.save(packed,staging,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"serialize recipe fixture")
	packed=null
	manifest.payload_sha=FileAccess.get_sha256(staging)
	var product:=folder.path_join(manifest.payload_sha+".scn")
	check(DirAccess.rename_absolute(staging,product)==OK,"publish recipe fixture native product")
	var file:=FileAccess.open(product,FileAccess.READ);manifest.bytes=file.get_length();file.close()
	write(index_path,JSON.stringify(manifest))
	var descriptor_path:=Footprint.descriptor_path(model.path,content_root)
	var envelope:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(descriptor_path))
	var descriptor:Dictionary=JSON.parse_string(envelope.body)
	descriptor.payload_sha=manifest.payload_sha;descriptor.bytes=manifest.bytes
	descriptor.model_metadata.local_bounds=[-1,1,-.2,2,2,.4]
	var body:=JSON.stringify(descriptor)
	write(descriptor_path,JSON.stringify({"version":1,"body":body,"sha256":body.sha256_text()}))
	check(DirAccess.remove_absolute(Binding.Products.table_directory(content_root).path_join(model.table_sha+".json"))==OK,"recipe geometry needs no texture table")
	return model

func compare_tree_recipe()->void:
	var model:=tree_fixture();var candidate:=Assets.native_candidate(model.path)
	var query:=geometry(model.path,candidate)
	var packet:=Assets._read_published_native(model.path,candidate)
	check(query!=null and packet.get("hit",false),"read independent geometry and rendering allocations")
	if query==null or not packet.get("hit",false):
		if query!=null:Drainer.dispose_scene(query)
		Drainer.dispose_result(packet);return
	var binding:=Binding.begin(packet.packed,{SHA:"tree"},model.table_sha)
	var texture:=GradientTexture2D.new()
	check(Binding.adopt(binding,{"tree":texture}) and Binding.step(binding)==Binding.READY,"bind comparison render template")
	Binding.release(binding)
	var rendered:=Assets._instantiate(packet.packed)
	check(rendered!=null and query.get_child_count()==2 and rendered.get_child_count()==2,"both paths retain two authored LOD nodes")
	check(TreeModel.resolved(query,{})==TreeModel.resolved(rendered,{}) and not TreeModel.resolved(query,{}).is_empty(),"recipe defaults are identical without texture rebinding")
	var record:={"kind":"asset","tree_settings":{"height":6.,"crown_scale":1.4,"trunk_scale":1.1,"bare_trunk":.8,"lean":.3,"density":1.2,"seed":17}}
	check(TreeModel.apply(query,record).is_empty() and TreeModel.apply(rendered,record).is_empty(),"non-default tree deformation succeeds for both paths")
	for level:int in 2:
		var a:MeshInstance3D=query.get_child(level);var b:MeshInstance3D=rendered.get_child(level)
		var aa:=a.mesh.surface_get_arrays(0);var ba:=b.mesh.surface_get_arrays(0)
		check(aa[Mesh.ARRAY_VERTEX]==ba[Mesh.ARRAY_VERTEX] and aa[Mesh.ARRAY_NORMAL]==ba[Mesh.ARRAY_NORMAL] and aa[Mesh.ARRAY_TEX_UV2]==ba[Mesh.ARRAY_TEX_UV2] and aa[Mesh.ARRAY_INDEX]==ba[Mesh.ARRAY_INDEX],"LOD %d vertices, normals, branch UV2 and topology match"%level)
		check(a.custom_aabb==b.custom_aabb and a.visibility_range_begin==b.visibility_range_begin and a.visibility_range_end==b.visibility_range_end,"LOD %d adjusted bounds and visibility ranges match"%level)
		check(a.mesh!=b.mesh and a.mesh.surface_get_material(0).albedo_texture==null and b.mesh.surface_get_material(0).albedo_texture==texture,"LOD %d cold geometry cache never replaces rendered material ownership"%level)
	check(Assets.bounds_of(query)==Assets.bounds_of(rendered),"tree editing computes identical placement bounds")
	check(not Assets._scenes.has(model.path),"tree queries and private render comparison never publish a global cache entry")
	TreeModel.cache.clear();Drainer.dispose_scene(query);Drainer.dispose_scene(rendered)
	Drainer.dispose_result(packet);texture=null

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):
		printerr("Requires isolated review_artifacts content root");quit(2);return
	var model:=fixture("geometry",true)
	var candidate:=Assets.native_candidate(model.path)
	check(not candidate.is_empty() and not FileAccess.file_exists(model.path),"geometry candidate needs no authoring GLB")
	var table_path:=Binding.Products.table_directory(content_root).path_join(model.table_sha+".json")
	check(DirAccess.remove_absolute(table_path)==OK,"remove the private table to prove geometry has no texture dependency")
	Trace.start()
	var node:=geometry(model.path,candidate)
	var counted:=read_count(Trace.stop())
	check(node!=null,"cold split geometry stays available with no table or STEX")
	check(counted==1,"cold geometry reads its native product exactly once")
	if node!=null:
		var mesh:Mesh=node.get_child(0).mesh
		check(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP]),"native geometry vertices remain exact")
		# Godot gives a planar native mesh a 0.00001 depth. Compare the serialized
		# mesh's actual AABB, not an invented zero-depth renderer bound.
		check(Assets.bounds_of(node)==mesh.get_aabb(),"geometry query preserves actual native bounds")
		var material:StandardMaterial3D=node.get_child(0).mesh.surface_get_material(0)
		check(material.albedo_texture==null and material.has_meta(Binding.BINDINGS_META),"material role metadata survives without binding pixels")
		check(not Ready.scene_ready(node),"geometry-only instance is not a completed render scene")
		check(not Assets.cache_scene(model.path,node,SHA),"geometry-only instance cannot enter render cache")
		Drainer.dispose_scene(node);node=null
	check(not Assets._scenes.has(model.path),"geometry query leaves global scene cache unchanged")
	var packet:=Assets._read_published_native(model.path,candidate)
	check(packet.get("hit",false),"private geometry product remains independently readable")
	var binding:=Binding.begin(packet.packed,{SHA:"warm"},model.table_sha)
	var texture:=GradientTexture2D.new()
	check(Binding.adopt(binding,{"warm":texture}) and Binding.step(binding)==Binding.READY,"prepare a complete warm render template")
	Binding.release(binding)
	check(Assets.cache_packed(model.path,packet.packed,SHA,candidate),"publish prepared render template")
	Trace.start();node=geometry(model.path,candidate)
	counted=read_count(Trace.stop())
	check(node!=null and counted==0,"geometry query reuses an existing template without another product read")
	if node!=null:
		check(node.get_child(0).mesh.surface_get_material(0).albedo_texture==texture,"borrowed geometry preserves shared material owner")
		check(not Ready.scene_ready(node) and not Assets.cache_scene(model.path,node,SHA),"even warm geometry-only instances cannot be republished as render scenes")
		Drainer.dispose_scene(node);node=null
	check(Ready.packed_ready(packet.packed),"geometry query never changes the original render readiness")
	var preview:=Assets.instantiate_preview(model.path,true)
	check(preview!=null and Ready.scene_ready(preview),"ordinary warm preview remains render-ready")
	if preview!=null:Drainer.dispose_scene(preview);preview=null
	Assets._scenes.erase(model.path);Drainer.dispose_result(packet);texture=null
	var embedded:=fixture("embedded_geometry",false)
	node=geometry(embedded.path)
	check(node!=null,"ordinary native geometry remains available")
	if node!=null:
		check(not Ready.scene_ready(node) and not Assets.cache_scene(embedded.path,node,SHA),"geometry intent is explicit for ordinary native products too")
		Drainer.dispose_scene(node);node=null
	check(not Assets._scenes.has(embedded.path),"ordinary geometry query does not grow render cache")
	compare_tree_recipe()
	Drainer.synchronize_transfer()
	print("NATIVE_GEOMETRY_CONSUMERS checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
