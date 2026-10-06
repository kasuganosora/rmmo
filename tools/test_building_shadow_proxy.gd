extends SceneTree
const Shadow=preload("res://scripts/world3d/building_shadow_proxy.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func piece(mesh:Mesh)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.mesh=mesh
	node.set_meta("ground_batch_record",{"house_prefab":{},"building":{"id":"test","floor":0}})
	root.add_child(node);return node
func run()->void:
	Shadow.enabled=true
	var cpu:=Cpu.new();var wood:=StandardMaterial3D.new();var iron:=StandardMaterial3D.new()
	wood.albedo_color=Color.SADDLE_BROWN;iron.albedo_color=Color.DIM_GRAY
	for i in 2:
		var box:=BoxMesh.new();box.size=Vector3(1+i*.5,.2,2)
		var arrays:=box.surface_get_arrays(0)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for v in vertices.size():vertices[v]+=Vector3(i*.7,i*.4,0)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		cpu.surfaces.append(arrays);cpu.materials.append(wood if i==0 else iron)
	var mesh:=cpu.restore();var original:=var_to_bytes(cpu.surfaces)
	var a:=piece(mesh);var b:=piece(mesh)
	a.position=Vector3(2,3,4);a.rotation.y=.67;b.position=Vector3(-4,0,2)
	check(Shadow.attach(a) and Shadow.attach(b),"eligible frozen pieces receive independent shadow nodes")
	var proxy_a:MeshInstance3D=a.get_meta("building_shadow_proxy");var proxy_b:MeshInstance3D=b.get_meta("building_shadow_proxy")
	check(proxy_a.mesh==proxy_b.mesh and proxy_a.mesh.get_surface_count()==1,"shared geometry uses one shadow surface across materials")
	check(a.mesh==mesh and var_to_bytes(cpu.surfaces)==original,"visual geometry and materials remain untouched")
	var expected:PackedVector3Array=a.global_transform*cpu.collision_faces()
	var actual:PackedVector3Array=proxy_a.global_transform*proxy_a.mesh.get_faces()
	var error:=0.0
	for i in mini(expected.size(),actual.size()):error=maxf(error,expected[i].distance_to(actual[i]))
	check(expected.size()==actual.size() and error<.000001,"all indexed triangles and winding retained (float error="+str(error)+")")
	a.rotation.y+=.8;a.position+=Vector3(1,2,3)
	check(proxy_a.global_transform==a.global_transform and proxy_b.global_transform==b.global_transform,"door rotation and individual transforms propagate without a frame poll")
	a.hide();check(not proxy_a.is_visible_in_tree() and proxy_b.is_visible_in_tree(),"cutaway hides only its own floor shadow")
	check(not Shadow.attach(b) and b.get_child_count()==1,"repeated registration creates no duplicate shadow")
	var shared_shadow:=proxy_b.mesh
	a.free();check(is_instance_valid(proxy_b) and proxy_b.mesh==shared_shadow,"unloading one instance preserves other shared shadows")
	b.free()
	for property:String in ["transparency","grow","billboard_mode","distance_fade_mode","proximity_fade_enabled","heightmap_enabled"]:
		var previous:Variant=wood.get(property)
		wood.set(property,true if previous is bool else 1)
		var node:=piece(mesh)
		check(not Shadow.attach(node) and node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON and node.get_child_count()==0,"unsupported material falls back without side effects: "+property)
		node.free();wood.set(property,previous)
	var shader_material:=ShaderMaterial.new();var shader:=Shader.new();shader.code="shader_type spatial; void vertex(){VERTEX.x += TIME;}";shader_material.shader=shader
	var dynamic:=piece(mesh);dynamic.material_override=shader_material
	check(not Shadow.attach(dynamic),"deforming shaders remain on their original shadow path");dynamic.free()
	var mixed:=piece(mesh);iron.cull_mode=BaseMaterial3D.CULL_DISABLED
	check(not Shadow.attach(mixed),"mixed culling is not flattened");mixed.free();iron.cull_mode=BaseMaterial3D.CULL_BACK
	var mixed_cpu:=Cpu.new();mixed_cpu.surfaces=cpu.surfaces.duplicate();mixed_cpu.surfaces.append(cpu.surfaces[0])
	var two_sided:=StandardMaterial3D.new();two_sided.cull_mode=BaseMaterial3D.CULL_DISABLED
	mixed_cpu.materials=[wood,two_sided,iron]
	var multi:=piece(mixed_cpu.restore())
	check(Shadow.attach(multi),"mixed culling can merge within separate partitions")
	var multi_shadow:Mesh=multi.get_meta("building_shadow_proxy").mesh
	check(multi_shadow.get_surface_count()==2 and multi_shadow.surface_get_material(0).cull_mode==BaseMaterial3D.CULL_BACK and multi_shadow.surface_get_material(1).cull_mode==BaseMaterial3D.CULL_DISABLED,"each partition retains its original culling rule")
	check(multi_shadow.get_faces().size()==mixed_cpu.collision_faces().size(),"partitioning retains every triangle");multi.free()
	var authored:=piece(mesh);authored.remove_meta("ground_batch_record")
	check(not Shadow.attach(authored),"ordinary editable meshes are left intact");authored.free()
	print("BUILDING_SHADOW_PROXY_FINISHED failures=",failures," stats=",Shadow.stats());quit(1 if failures else 0)
