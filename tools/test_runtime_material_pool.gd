extends SceneTree
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Merge=preload("res://scripts/world3d/ground_batch_geometry.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if not ok:failures+=1
func data(value:Dictionary)->Dictionary:
	return {"materials":[value],"meshes":[{"surfaces":[],"materials":[0],"bounds":AABB(),"box_size":Vector3.ZERO}],"entries":[[[0],[0,0]]]}
func restore(value:Dictionary,pool:Variant=null)->Material:
	var result:=Cook.restore(data(value),null,pool)
	return result.values()[0].mesh.materials[0] if not result.is_empty() else null
func run()->void:
	var source:=StandardMaterial3D.new();source.albedo_color=Color(.3,.4,.6);source.roughness=.71;source.emission_enabled=true
	var definition:=Cook.material_data(source);var before:=var_to_bytes(definition);var pool:={}
	var first:=restore(definition,pool);var second:=restore(definition.duplicate(true),pool)
	check(first!=null and first==second,"one immutable load shares exactly equal material definitions")
	check(Cook.material_data(first)==definition and var_to_bytes(definition)==before,"pool preserves every stored value without mutating definitions")
	var changed:=definition.duplicate(true);changed["values"].roughness=.22
	var third:=restore(changed,pool)
	check(third!=first and is_equal_approx(third.roughness,.22) and is_equal_approx(first.roughness,.71),"different material values remain separate")
	check(restore(definition)!=restore(definition),"independent editor restores never share the runtime pool")
	var invalid:=definition.duplicate(true);invalid["values"].roughness="invalid"
	check(restore(invalid,pool)==null,"populated pool cannot bypass invalid property types")
	invalid=definition.duplicate(true);invalid["values"]["script"]=null
	check(restore(invalid,pool)==null,"populated pool cannot attach a script")
	var key:=Merge.material_key(first)
	check(key==Merge.material_key(first.duplicate()) and key!=Merge.material_key(third),"binary material identity shares equal copies and separates different roughness")
	for edit in [{"albedo_color":Color.RED},{"uv1_scale":Vector3(2,1,1)},{"emission":Color.GREEN},{"normal_enabled":true}]:
		var copy:StandardMaterial3D=first.duplicate()
		for property in edit:copy.set(property,edit[property])
		check(Merge.material_key(copy)!=key,"changed rendering property changes identity: "+str(edit.keys()[0]))
	var texture:=ImageTexture.create_from_image(Image.create(2,2,false,Image.FORMAT_RGB8))
	var painted:StandardMaterial3D=first.duplicate();painted.albedo_texture=texture
	check(Merge.material_key(painted)==Merge.material_key(painted.duplicate()) and Merge.material_key(painted)!=key,"shared texture identity is retained and differs from an untextured material")
	for edit in [{"transparency":BaseMaterial3D.TRANSPARENCY_ALPHA},{"uv1_triplanar":true},{"grow":true},{"next_pass":StandardMaterial3D.new()}]:
		var copy:StandardMaterial3D=first.duplicate()
		for property in edit:copy.set(property,edit[property])
		check(Merge.material_key(copy).is_empty(),"unsupported batching remains excluded: "+str(edit.keys()[0]))
	var terrain:=ShaderMaterial.new();terrain.shader=Merge.TERRAIN_SHADER;terrain.set_shader_parameter("ground_enabled",false)
	var terrain_key:=Merge.material_key(terrain);terrain.set_shader_parameter("terrain_span",Vector2(5,8))
	check(Merge.material_key(terrain)==terrain_key,"per-patch terrain span remains outside the shared material identity")
	print("RUNTIME_MATERIAL_POOL_FINISHED failures=",failures);quit(1 if failures else 0)
