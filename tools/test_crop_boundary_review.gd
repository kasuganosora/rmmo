extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Vegetation=preload("res://scripts/world3d/vegetation_render.gd")
const Gpu=preload("res://tools/bridge_lod_assertions.gd")
var failed:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failed+=1
func record()->Dictionary:return {"uuid":"crop","kind":"asset","vegetation_batch":true,"asset_path":"crop.glb","position":[0,0,0],"size":[1,1,1],"rotation":[0,0,0]}
func holder()->Node3D:
	var result:=Node3D.new();result.name="Crop";var pivot:=Node3D.new();pivot.name="Root";result.add_child(pivot)
	var visual:=MeshInstance3D.new();visual.name="Visual";visual.mesh=BoxMesh.new();pivot.add_child(visual);return result
func mesh_with_lod()->ArrayMesh:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK,Vector3(1,0,1)])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,2,1,1,2,3])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{.25:PackedInt32Array([0,2,1])})
	mesh.surface_set_material(0,StandardMaterial3D.new());return mesh
func run()->void:
	create_timer(45).timeout.connect(func():quit(2))
	var simple:=holder();var flat:=Vegetation.flatten(simple,record())
	check(flat is MeshInstance3D and flat.has_meta("ground_batch_record"),"simple crop still flattens for batching");flat.free()
	for kind in ["light","hidden_parent","independent_parent","component","missing","visibility_range","lod_bias","cull_margin","custom_aabb","ignore_occlusion"]:
		var original:=holder();var sibling:Node=null
		var visual:MeshInstance3D=original.get_child(0).get_child(0)
		if kind=="light":sibling=OmniLight3D.new();original.get_child(0).add_child(sibling)
		if kind=="hidden_parent":original.get_child(0).hide()
		if kind=="independent_parent":original.get_child(0).top_level=true
		if kind=="component":original.set_meta("model_component_batch_sources",["sentinel"])
		if kind=="missing":original.set_meta("missing_asset",true)
		if kind=="visibility_range":visual.visibility_range_end=20
		if kind=="lod_bias":visual.lod_bias=.25
		if kind=="cull_margin":visual.extra_cull_margin=2
		if kind=="custom_aabb":visual.custom_aabb=AABB(Vector3.ZERO,Vector3.ONE*4)
		if kind=="ignore_occlusion":visual.ignore_occlusion_culling=true
		var result:=Vegetation.flatten(original,record())
		check(result==original,"preserve asset hierarchy: "+kind)
		if kind=="light":check(is_instance_valid(sibling) and sibling.get_parent()!=null,"single-mesh scatter cannot delete its light")
		result.free()
	if DisplayServer.get_name()!="headless":
		var expected:Array=[{.25:PackedInt32Array([0,2,1])}]
		var source:=mesh_with_lod();check(Gpu.matches(source,expected),"fixture has actual GPU LOD indices")
		var large_arrays:Array=[];large_arrays.resize(Mesh.ARRAY_MAX)
		var large_vertices:=PackedVector3Array();large_vertices.resize(70000);large_vertices[1]=Vector3.RIGHT;large_vertices[69999]=Vector3.BACK
		large_arrays[Mesh.ARRAY_VERTEX]=large_vertices;large_arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,69999,0,69999,1])
		var large:=ArrayMesh.new();var large_lod:Dictionary={.5:PackedInt32Array([0,1,69999])};large.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,large_arrays,[],large_lod)
		check(Cpu.capture(large).lods==[large_lod],"32-bit LOD indices retain vertices beyond 65535")
		var cpu:Mesh=Cpu.capture(source);check(cpu.lods==expected,"capture imported ArrayMesh preserves LOD table")
		var base_faces:PackedVector3Array=cpu.collision_faces();source=null
		check(Gpu.matches(cpu.restore(),expected) and cpu.collision_faces()==base_faces,"release and restore preserves LOD and base collision")
		var shared:=mesh_with_lod();var base_material:Material=shared.surface_get_material(0);var override:=StandardMaterial3D.new();override.albedo_color=Color.RED
		var batch:=Batch.new();root.add_child(batch);var members:Array=[];var snapshot:Array=[];var sources:Array=[]
		for i in 2:
			var node:=MeshInstance3D.new();node.mesh=shared;node.set_surface_override_material(0,override);root.add_child(node);members.append(node)
			var captured:Mesh=Cpu.capture(shared);captured.geometry_key();sources.append(captured)
			snapshot.append({"materials":[override],"transform":Transform3D(Basis.IDENTITY,Vector3(i*2,0,0))})
		var group:={"cpu":sources,"keys":["red"],"origin":Vector3.ZERO,"members":members}
		batch._commit_instances(group,snapshot,Time.get_ticks_usec())
		check(shared.surface_get_material(0)==base_material,"instanced material fork never changes shared source material")
		check(group.visual.multimesh.mesh.surface_get_material(0)==override and Gpu.matches(group.visual.multimesh.mesh,expected),"material fork retains its override and GPU LOD")
		for node:MeshInstance3D in members:
			Batch.restore(node);check(node.mesh.surface_get_material(0)==override and Gpu.matches(node.mesh,expected),"selection restore retains override and GPU LOD");node.free()
		batch.free()
		for mode in ["subdivided","uv2","flipped"]:
			var box:=BoxMesh.new();box.size=Vector3(2,3,4);box.material=base_material
			if mode=="subdivided":box.subdivide_width=3;box.subdivide_height=2
			if mode=="uv2":box.add_uv2=true
			if mode=="flipped":box.flip_faces=true
			var box_cpu:Mesh=Cpu.capture(box);var fork:=Cpu.new()
			fork.surfaces=box_cpu.surfaces;fork.lods=box_cpu.lods;fork.bounds=box_cpu.bounds;fork.box_size=box_cpu.box_size;fork.materials=[override]
			var restored:Mesh=fork.restore();var actual:Array=restored.surface_get_arrays(0);var original:Array=box.surface_get_arrays(0)
			check(restored is ArrayMesh and actual[Mesh.ARRAY_VERTEX]==original[Mesh.ARRAY_VERTEX] and actual[Mesh.ARRAY_INDEX]==original[Mesh.ARRAY_INDEX] and actual[Mesh.ARRAY_TEX_UV2]==original[Mesh.ARRAY_TEX_UV2],"material fork preserves complex box topology/UV2: "+mode)
			check(box.material==base_material and restored.surface_get_material(0)==override,"complex box fork preserves material ownership: "+mode)
	print("CROP_BOUNDARY_REVIEW_FINISHED failures=",failed);quit(failed)
