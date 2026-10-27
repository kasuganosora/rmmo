extends SceneTree
## Synthetic source and generated products only. No production files or GPU.
const Prototype=preload("res://tools/native_material_descriptor_prototype.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func image_texture(color:Color)->ImageTexture:
	var image:=Image.create_empty(4,4,false,Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

func make_source()->PackedScene:
	var root:=Node3D.new();root.name="Prototype"
	var albedo:=image_texture(Color(.7,.2,.3,.6))
	var normal:=image_texture(Color(.2,.7,1.0,1.0))
	var mat:=StandardMaterial3D.new();mat.resource_name="shared_pbr"
	mat.albedo_texture=albedo;mat.normal_texture=normal;mat.normal_enabled=true
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.uv1_scale=Vector3(1.7,2.1,1.0);mat.uv1_offset=Vector3(.1,.2,0);mat.normal_scale=.7
	var second:=mat.duplicate() as StandardMaterial3D;second.resource_name="node_override";second.roughness=.37
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(0,0,0),Vector3(1,0,0),Vector3(0,1,0)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD])
	arrays[Mesh.ARRAY_TANGENT]=PackedFloat32Array([1,0,0,1,1,0,0,1,1,0,0,1])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN])
	arrays[Mesh.ARRAY_TEX_UV2]=PackedVector2Array([Vector2(.1,.2),Vector2(.3,.4),Vector2(.5,.6)])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,mat);mesh.surface_set_material(1,mat)
	for name_:String in ["First","Second","Third"]:
		var node:=MeshInstance3D.new();node.name=name_;node.mesh=mesh
		root.add_child(node);node.owner=root
		if name_=="Second":node.set_surface_override_material(1,second)
		if name_=="Third":node.material_override=second;node.material_overlay=mat
	var free_mesh:=ArrayMesh.new()
	free_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var free_node:=MeshInstance3D.new();free_node.name="FreeMesh";free_node.mesh=free_mesh
	root.add_child(free_node);free_node.owner=root
	var packed:=PackedScene.new();check(packed.pack(root)==OK,"source scene packs")
	root.free();return packed

func rejected_case(case_name:String)->void:
	var source:=make_source()
	var root:=source.instantiate()
	var node:=root.get_node("First") as MeshInstance3D
	var mesh:=node.mesh as ArrayMesh
	var material:=mesh.surface_get_material(0) as StandardMaterial3D
	var texture:=material.albedo_texture as ImageTexture
	match case_name:
		"texture_local": texture.resource_local_to_scene=true
		"texture_size": texture.set_size_override(Vector2i(16,16))
		"material_local": material.resource_local_to_scene=true
		"mesh_local": mesh.resource_local_to_scene=true
		"material_script":
			var script:=GDScript.new();script.source_code="extends StandardMaterial3D\n";script.reload();material.set_script(script)
		"node_script":
			var script:=GDScript.new();script.source_code="extends MeshInstance3D\n";script.reload();node.set_script(script)
		"nonmesh_material":
			var csg:=CSGBox3D.new();csg.material=material;root.add_child(csg);csg.owner=root
		"node_metadata": node.set_meta("nested",{"items":[material]})
		"mesh_metadata": mesh.set_meta("nested",{"items":[texture]})
		"material_metadata": material.set_meta("nested",{"items":[texture]})
		"skin": node.skin=Skin.new()
		"blendshape":
			var blended:=ArrayMesh.new();blended.add_blend_shape("shape");node.mesh=blended
		"shadow_mesh": mesh.shadow_mesh=ArrayMesh.new()
		"persistent_signal_material": node.visibility_changed.connect(Callable(node,"hide").bind(material),CONNECT_PERSIST)
		"persistent_signal_texture": node.visibility_changed.connect(Callable(node,"hide").bind(texture),CONNECT_PERSIST)
		"animation":
			var animator:=AnimationPlayer.new();root.add_child(animator);animator.owner=root
	var packed:=PackedScene.new();var err:=packed.pack(root);root.free()
	check(err==OK,"pack rejection fixture "+case_name)
	if err==OK:
		if case_name.begins_with("persistent_signal_"):
			var reopened:=packed.instantiate()
			var connections: Array = reopened.get_node("First").get_signal_connection_list("visibility_changed")
			var bound: Array = connections[0].callable.get_bound_arguments() if not connections.is_empty() else []
			check(bound.size()==1 and (bound[0] is Material if case_name.ends_with("material") else bound[0] is Texture2D),"persistent signal retained actual bound resource "+case_name)
			reopened.free()
			var directory:="D:/code/rmmo_runtime/review_artifacts/native_material_signal_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
			DirAccess.make_dir_recursive_absolute(directory)
			var file_path:=directory.path_join("source.scn")
			var save_err:=ResourceSaver.save(packed,file_path,ResourceSaver.FLAG_BUNDLE_RESOURCES)
			var disk_scene:=ResourceLoader.load(file_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene if save_err==OK else null
			if disk_scene!=null:
				var disk_root:=disk_scene.instantiate()
				var disk_connections:Array=disk_root.get_node("First").get_signal_connection_list("visibility_changed")
				var disk_bound:Array=disk_connections[0].callable.get_bound_arguments() if not disk_connections.is_empty() else []
				check(disk_bound.size()==1 and (disk_bound[0] is Material if case_name.ends_with("material") else disk_bound[0] is Texture2D),"disk scene retains persistent bound resource "+case_name)
				disk_root.free()
			else:check(false,"disk scene retains persistent bound resource "+case_name)
		var result:=Prototype.extract(packed)
		check(not str(result.get("error","")).is_empty(),"reject unsafe "+case_name)

func run()->void:
	var source:=make_source()
	var initial:=source.instantiate()
	var first:=initial.get_node("First") as MeshInstance3D
	var second:=initial.get_node("Second") as MeshInstance3D
	check(first.mesh.get_surface_count()==2,"fixture preserves two surfaces")
	check(first.mesh==second.mesh,"fixture shares a mesh across nodes")
	check(first.mesh.surface_get_material(0)==first.mesh.surface_get_material(1),"fixture shares base material across slots")
	check(second.get_surface_override_material(1)!=null,"fixture has per-node surface override")
	var third:=initial.get_node("Third") as MeshInstance3D
	check(third.material_override==second.get_surface_override_material(1) and third.material_overlay==first.mesh.surface_get_material(0),"fixture has shared node override and overlay")
	var result:=Prototype.extract(source)
	if not result.get("error","").is_empty():print("EXTRACTION_ERROR ",result.error)
	check(result.get("error","").is_empty(),"offline extraction succeeds")
	if result.get("error","").is_empty():
		var geometry:PackedScene=result.geometry
		var descriptor:Dictionary=result.descriptor
		var directory:="D:/code/rmmo_runtime/review_artifacts/native_material_proto_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
		check(DirAccess.make_dir_recursive_absolute(directory)==OK,"external fixture directory created")
		var geometry_path:=directory.path_join("geometry.scn")
		check(ResourceSaver.save(geometry,geometry_path,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"native geometry saved externally")
		var payload:=var_to_bytes(descriptor)
		var file:=FileAccess.open(directory.path_join("materials.bin"),FileAccess.WRITE)
		check(file!=null and not payload.is_empty(),"material descriptor encodes as pure variant data")
		if file!=null:file.store_buffer(payload);file.close()
		geometry=ResourceLoader.load(geometry_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		file=FileAccess.open(directory.path_join("materials.bin"),FileAccess.READ)
		if file!=null:descriptor=bytes_to_var(file.get_buffer(file.get_length()));file.close()
		check(geometry!=null and descriptor.get("version")==1,"separate products reopen from disk")
		var white:=geometry.instantiate()
		var white_first:=white.get_node("First") as MeshInstance3D
		var white_second:=white.get_node("Second") as MeshInstance3D
		check(white_first.mesh.surface_get_material(0)==null and white_first.mesh.surface_get_material(1)==null,"geometry product carries no source materials")
		check(white_second.get_surface_override_material(1)==null,"geometry product carries no surface override")
		var white_third:=white.get_node("Third") as MeshInstance3D
		check(white_third.material_override==null and white_third.material_overlay==null,"geometry product carries no node override or overlay")
		check(white_first.mesh.has_meta("_rmmo_native_cpu_geometry_v1"),"geometry uses production native CPU metadata")
		var source_arrays:=first.mesh.surface_get_arrays(0)
		var white_arrays:=white_first.mesh.surface_get_arrays(0)
		check(source_arrays[Mesh.ARRAY_NORMAL]==white_arrays[Mesh.ARRAY_NORMAL] and source_arrays[Mesh.ARRAY_TANGENT]==white_arrays[Mesh.ARRAY_TANGENT] and source_arrays[Mesh.ARRAY_TEX_UV]==white_arrays[Mesh.ARRAY_TEX_UV] and source_arrays[Mesh.ARRAY_TEX_UV2]==white_arrays[Mesh.ARRAY_TEX_UV2],"geometry retains normals tangents UV and UV2")
		check(first.mesh.surface_get_material(0)!=null and third.material_override!=null,"extraction does not modify original source")
		var restored:=Prototype.restore(geometry,descriptor)
		if not restored.get("error","").is_empty():print("RESTORE_ERROR ",restored.error)
		check(restored.get("error","").is_empty(),"offline descriptor reconstructs material bindings")
		if restored.get("error","").is_empty():
			var node:Node=restored.packed.instantiate()
			var a:=node.get_node("First") as MeshInstance3D;var b:=node.get_node("Second") as MeshInstance3D
			var c:=node.get_node("Third") as MeshInstance3D
			var free_node:=node.get_node("FreeMesh") as MeshInstance3D
			var base:=a.mesh.surface_get_material(0) as StandardMaterial3D
			var changed:=b.get_surface_override_material(1) as StandardMaterial3D
			check(a.mesh==b.mesh and a.mesh.get_surface_count()==2,"restored nodes retain shared multisurface geometry")
			check(free_node.mesh!=a.mesh and free_node.mesh.get_surface_count()==1 and free_node.mesh.surface_get_material(0)==null,"independent mesh and empty material slot survive")
			check(base!=null and base==a.mesh.surface_get_material(1),"base slots share source material identity")
			check(changed!=null and changed!=base and is_equal_approx(changed.roughness,.37),"per-node override remains separate")
			check(c.mesh==a.mesh and c.material_override==changed and c.material_overlay==base,"node override and overlay retain shared identities")
			check(base!=null and base.normal_enabled and is_equal_approx(base.normal_scale,.7) and base.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA and base.cull_mode==BaseMaterial3D.CULL_DISABLED,"normal alpha and culling survive")
			check(base!=null and base.uv1_scale.is_equal_approx(Vector3(1.7,2.1,1)) and base.uv1_offset.is_equal_approx(Vector3(.1,.2,0)),"material UV transform survives")
			check(base!=null and changed!=null and base.albedo_texture==changed.albedo_texture and base.normal_texture==changed.normal_texture,"independent materials retain shared image bindings")
			check(base!=null and base.albedo_texture.get_image().get_data()==(first.mesh.surface_get_material(0) as StandardMaterial3D).albedo_texture.get_image().get_data() and base.normal_texture.get_image().get_data()==(first.mesh.surface_get_material(0) as StandardMaterial3D).normal_texture.get_image().get_data(),"texture bytes survive separate product roundtrip")
			check(white_first.mesh.surface_get_material(0)==null,"restore leaves native geometry product untouched")
			node.free()
		white.free()
	var unsupported_source:=make_source()
	var unsupported:=unsupported_source.instantiate()
	(unsupported.get_node("First") as MeshInstance3D).material_override=ShaderMaterial.new()
	var unsupported_packed:=PackedScene.new();unsupported_packed.pack(unsupported);unsupported.free()
	var unsupported_result:=Prototype.extract(unsupported_packed)
	check(str(unsupported_result.get("error","")).contains("unsupported material"),"unsupported shader material is rejected explicitly")
	for case_name:String in ["texture_local","texture_size","material_local","mesh_local","material_script","node_script","nonmesh_material","node_metadata","mesh_metadata","material_metadata","skin","blendshape","shadow_mesh","animation","persistent_signal_material","persistent_signal_texture"]:
		rejected_case(case_name)
	check(not Prototype._plain(RID()),"reject RID from descriptor data")
	check(not Prototype._plain(Callable(self,"quit")),"reject Callable from descriptor data")
	check(not Prototype._plain(Signal(initial,"ready")),"reject Signal from descriptor data")
	check(not Prototype._plain({"nested":[Callable(self,"quit")]}),"reject nested Callable from descriptor data")
	initial.free()
	print("NATIVE_MATERIAL_DESCRIPTOR_PROTOTYPE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
