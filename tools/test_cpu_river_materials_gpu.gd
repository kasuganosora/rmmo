extends SceneTree
## Run only through tools/run_godot_background.py. No map/cache files are written.
## In-memory cooked terrain fixtures exercise the actual Doc -> spec -> spawn path.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const River=preload("res://scripts/world3d/river_materials.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Regions=preload("res://scripts/world3d/terrain_regions.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Ground=preload("res://scripts/world3d/ground_batch_geometry.gd")
var failures:=0
var passed:=0
var viewport:SubViewport

func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if ok:passed+=1
	else:failures+=1

func paint(name_:String,color:Color)->Dictionary:
	return {"name":name_,"color":[color.r,color.g,color.b,color.a],"roughness":.87,"tile_size":[2,2]}

func record(case_name:String)->Dictionary:
	var base:=paint("base",Color(.28,.43,.18))
	var sand:=paint("sand",Color(.67,.52,.29))
	var rock:=paint("rock",Color(.38,.42,.45))
	var soil:=paint("soil",Color(.24,.12,.05))
	var result:={"uuid":"cpu_river_fixture","kind":"box","surface_id":"ground","collision":"walk","position":[2,0,3],"rotation":[0,17,0],"size":[8,1,8],"color":[.28,.43,.18],"terrain_material":base,"terrain_mesh":{"version":1,"columns":2,"rows":2,"floor":-2,"heights":[0,.3,1.,.1,.4,1.2,.2,.6,1.4],"holes":[false,false,false,false]}}
	match case_name:
		"saturation":result.terrain_saturation=.65
		"depth":result.terrain_depth_blend={"water_level":.25,"shore_start":.25,"shore_end":1.3,"rock_start":.6,"rock_end":2.2,"bank_profile":"depth","wet_darkening":.45,"wet_height":.3,"sand_material":sand,"rock_material":rock}
		"slope_regions":
			result.terrain_slope_blend={"steep_start":20.,"steep_end":60.,"rock_material":rock,"transition_width":1.25,"edge_noise":.3,"height_blend_strength":.5,"transition_material":soil}
			result.terrain_mesh.holes[3]=true
			result.terrain_regions={"materials":[soil,sand],"regions":[{"id":"soil_a","polygon":[[-3,-3],[3,-3],[3,3],[-3,3]],"feather":1.,"opacity":.75,"layer":0,"furrows":{"spacing":1.2,"height":.12,"angle":0.,"phase":0.,"margin":.5}},{"id":"sand_b","polygon":[[-2,-2],[0,-2],[0,2],[-2,2]],"feather":1.,"opacity":.65,"layer":1}]}
	return result

func fixture(record_:Dictionary)->Dictionary:
	var mesh:=Cpu.new();mesh.surfaces=Terrain.arrays(record_);mesh.bounds=vertex_bounds(mesh.surfaces)
	# Real Cook.pack gets bounds from the original rendered ArrayMesh. The
	# authored Terrain.bounds deliberately includes removed corner heights and
	# maximum possible furrow padding; it is not that mesh's tight vertex AABB.
	var conservative:=Terrain.bounds(record_)
	check(encloses_vertices(conservative,mesh.surfaces),"author terrain bounds enclose every actual vertex")
	if record_.has("terrain_regions"):
		var maximum:=0.
		for height in record_.terrain_mesh.heights:maximum=maxf(maximum,float(height)*record_.size[1])
		var raised:=preload("res://scripts/world3d/terrain_furrows.gd").maximum_height(record_)
		check(is_equal_approx(conservative.end.y,maximum+raised) and conservative.end.y>mesh.bounds.end.y,"hole/furrow source padding is conservative rather than added render geometry")
	var material:=Cook.Paint.make_material(record_.terrain_material,BaseMaterial3D.CULL_BACK)
	for slot in mesh.surfaces.size():mesh.materials.append(material)
	var key:Array=["terrain_mesh",record_,{}]
	var context:Dictionary={}
	if record_.has("terrain_regions"):context.region_mask=Regions.mask(record_)
	var cooked:=Cook.pack({key:{"mesh":mesh,"source":mesh}},"test_source","test_generator")
	check(Cook.valid_data(cooked),"fixture has valid plain cooked CPU geometry")
	return {"cooked":cooked,"context":context}

func vertex_bounds(surfaces:Array)->AABB:
	var result:=AABB();var initialized:=false
	for arrays:Array in surfaces:
		for vertex:Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			if not initialized:result=AABB(vertex,Vector3.ZERO);initialized=true
			else:result=result.expand(vertex)
	return result

func encloses_vertices(bounds:AABB,surfaces:Array)->bool:
	var padded:=bounds.grow(.00001)
	for arrays:Array in surfaces:
		for vertex:Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			if not padded.has_point(vertex):return false
	return true

func document(record_:Dictionary,data:Dictionary,immutable:bool):
	var doc:=Doc.new();doc.records=[record_];doc.load_immutable_records=immutable
	doc.load_paint_validation={};doc.load_texture_checks={};doc.load_material_pool={}
	doc.terrain_neighbors.data[record_.uuid]=data.context
	doc.load_box_meshes=Cook.restore(data.cooked.duplicate(),doc.load_paint_validation,doc.load_material_pool)
	return doc

func resource_value(value:Variant)->Variant:
	if value is Image:return [value.get_width(),value.get_height(),value.get_format(),value.has_mipmaps(),value.get_data()]
	if value is Texture2D:return resource_value(value.get_image())
	if value is ShaderMaterial:
		var uniforms:Dictionary={}
		for info in value.shader.get_shader_uniform_list():uniforms[str(info.name)]=resource_value(value.get_shader_parameter(info.name))
		var metadata:Dictionary={}
		for key in value.get_meta_list():metadata[str(key)]=resource_value(value.get_meta(key))
		return {"shader":value.shader.code,"name":value.resource_name,"uniforms":uniforms,"metadata":metadata}
	if value is Material:return Cook.material_data(value)
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[key]=resource_value(value[key])
		return result
	if value is Array:
		var result:Array=[]
		for item in value:result.append(resource_value(item))
		return result
	return value

func geometry(mesh:Mesh)->Array:
	var cpu:Mesh=Cpu.capture(mesh)
	return [cpu.surfaces,cpu.bounds,cpu.box_size,resource_value(cpu.materials)]

func comparable(spec:Dictionary)->Dictionary:
	var result:=spec.duplicate()
	result.mesh=geometry(spec.mesh);result.collision_mesh=geometry(spec.collision_mesh)
	result.surface_overrides=resource_value(spec.surface_overrides)
	result.material_override=resource_value(spec.material_override)
	return result

func differences(actual:Variant,expected:Variant,path:String,result:Array)->void:
	if result.size()>=32:return
	if typeof(actual)!=typeof(expected):
		result.append({"path":path,"actual_type":type_string(typeof(actual)),"expected_type":type_string(typeof(expected)),"actual":str(actual).left(200),"expected":str(expected).left(200)});return
	if actual is Dictionary:
		if actual.size()!=expected.size():result.append({"path":path,"actual_size":actual.size(),"expected_size":expected.size()})
		var actual_types:Array=[actual.get_typed_key_builtin(),actual.get_typed_key_class_name(),actual.get_typed_key_script(),actual.get_typed_value_builtin(),actual.get_typed_value_class_name(),actual.get_typed_value_script()]
		var expected_types:Array=[expected.get_typed_key_builtin(),expected.get_typed_key_class_name(),expected.get_typed_key_script(),expected.get_typed_value_builtin(),expected.get_typed_value_class_name(),expected.get_typed_value_script()]
		differences(actual_types,expected_types,path+"/@dictionary_types",result)
		for key in expected:
			if not actual.has(key):result.append({"path":path+"/"+str(key),"actual":"MISSING"})
			else:
				var same_key_type:=false
				for actual_key in actual:
					if typeof(actual_key)==typeof(key) and actual_key==key:same_key_type=true;break
				if not same_key_type:result.append({"path":path+"/"+str(key),"key_type":"MISMATCH"})
				differences(actual[key],expected[key],path+"/"+str(key),result)
		for key in actual:
			if not expected.has(key):result.append({"path":path+"/"+str(key),"expected":"MISSING"})
	elif actual is Array or typeof(actual) in [TYPE_PACKED_BYTE_ARRAY,TYPE_PACKED_INT32_ARRAY,TYPE_PACKED_INT64_ARRAY,TYPE_PACKED_FLOAT32_ARRAY,TYPE_PACKED_FLOAT64_ARRAY,TYPE_PACKED_STRING_ARRAY,TYPE_PACKED_VECTOR2_ARRAY,TYPE_PACKED_VECTOR3_ARRAY,TYPE_PACKED_COLOR_ARRAY,TYPE_PACKED_VECTOR4_ARRAY]:
		if actual is Array and (actual.get_typed_builtin()!=expected.get_typed_builtin() or actual.get_typed_class_name()!=expected.get_typed_class_name() or actual.get_typed_script()!=expected.get_typed_script()):result.append({"path":path,"array_type":"MISMATCH"})
		if actual.size()!=expected.size():result.append({"path":path,"actual_size":actual.size(),"expected_size":expected.size()})
		for i in mini(actual.size(),expected.size()):
			differences(actual[i],expected[i],path+"/"+str(i),result)
			if result.size()>=32:break
	elif actual!=expected:result.append({"path":path,"type":type_string(typeof(actual)),"actual":str(actual).left(240),"expected":str(expected).left(240)})

func compare(actual:Variant,expected:Variant,label_:String)->void:
	var leaves:Array=[];differences(actual,expected,label_,leaves)
	if not leaves.is_empty():print("CPU_RIVER_STRUCTURAL_DIFF ",JSON.stringify(leaves))
	check(leaves.is_empty(),label_)

func comparison_cases()->void:
	var empty_material:Material=null
	var plain_null:Variant=null
	var typed_empty:Array[Material]=[];typed_empty.resize(1)
	var native_null:Variant=instance_from_id(0)
	var empty_node:=MeshInstance3D.new();var getter_null:Variant=empty_node.material_override;empty_node.free()
	var leaves:Array=[];differences([plain_null],[native_null],"native_null",leaves)
	print("CPU_RIVER_NULL_TYPES ",JSON.stringify({"plain":type_string(typeof(plain_null)),"material_variable":type_string(typeof(empty_material)),"typed_array_resize":type_string(typeof(typed_empty[0])),"native_instance_from_id":type_string(typeof(native_null)),"native_material_getter":type_string(typeof(getter_null)),"scalar_equal":plain_null==native_null,"array_equal":[plain_null]==[native_null],"leaf_diff":leaves}))
	check(typeof(empty_material)==TYPE_NIL and typeof(typed_empty[0])==TYPE_NIL and typeof(native_null)==TYPE_OBJECT and typeof(getter_null)==TYPE_OBJECT and [native_null]==[getter_null],"measured native OBJECT-null differs from GDScript typed variable/array NIL")
	check(plain_null==native_null and [plain_null]!=[native_null] and not leaves.is_empty(),"native null explains scalar equality versus strict container inequality")
	var typed_array:Array[int]=[1];var plain_array:Array=[1]
	leaves=[];differences(typed_array,plain_array,"typed_array",leaves)
	check(not leaves.is_empty(),"leaf comparator rejects changed array type even with equal values")
	var typed_dictionary:Dictionary[String,int]={"value":1};var plain_dictionary:Dictionary={"value":1}
	leaves=[];differences(typed_dictionary,plain_dictionary,"typed_dictionary",leaves)
	check(not leaves.is_empty(),"leaf comparator rejects changed dictionary key/value types")
	var nested_a:Variant=1;var nested_b:Variant=1
	for i in 24:nested_a={"item":[nested_a]};nested_b={"item":[nested_b]}
	compare(nested_a,nested_b,"leaf comparator traverses independent deep containers exactly")
	leaves=[];differences({"x":[1.,2.]},{"x":[1.,2.000001]},"changed_leaf",leaves)
	check(not leaves.is_empty(),"leaf comparator rejects tiny numeric changes without approximation")
	leaves=[];differences({"x":[1]},{"y":[1,2]},"changed_shape",leaves)
	check(not leaves.is_empty(),"leaf comparator rejects key and container shape changes")

func image_delta(a:Image,b:Image)->Dictionary:
	if a.get_size()!=b.get_size() or a.get_format()!=b.get_format():return {"mean":INF,"max":INF}
	var left:=a.get_data();var right:=b.get_data()
	if left==right:return {"mean":0.,"max":0.}
	var total:=0;var maximum:=0
	for i in left.size():
		var difference:=absi(left[i]-right[i]);total+=difference;maximum=maxi(maximum,difference)
	return {"mean":float(total)/maxi(1,left.size())/255.,"max":float(maximum)/255.}

func capture(spec:Dictionary)->Image:
	var node:=Stream._spawn(viewport,spec);viewport.add_child(node)
	check(encloses_vertices(node.mesh.get_aabb(),Cpu.capture(node.mesh).surfaces),"spawned render AABB encloses all actual vertices")
	check(node.mesh.get_aabb()==spec.mesh.get_aabb(),"CPU directory and spawned GPU mesh have identical tight culling bounds")
	var world_bounds:AABB=node.transform*node.mesh.get_aabb()
	check(spec.chunk_min==Stream.chunk_key(world_bounds.position) and spec.chunk_max==Stream.chunk_key(world_bounds.end),"runtime XZ chunk coverage matches actual spawned bounds")
	check(not node.has_meta(River.CPU_SURFACE_OVERRIDES_META),"CPU directory metadata is absent from real spawned visual")
	for slot in spec.surface_overrides.size():check(node.get_surface_override_material(slot)==spec.surface_overrides[slot],"spawn installs exact slot override %d"%slot)
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image()
	node.free();RenderingServer.force_sync()
	return image

func terrain_case(name_:String)->void:
	var authored:=record(name_);var author_bytes:=var_to_bytes(authored);var data:=fixture(authored)
	River.cache.clear();River.reset_index_profile();River.cpu_index_overrides_enabled=false
	var old_doc=document(authored,data,true)
	var legacy:MeshInstance3D=old_doc._mesh(authored)
	check(not legacy.mesh is Cpu and not legacy.has_meta(River.CPU_SURFACE_OVERRIDES_META),name_+": probe false preserves temporary GPU path")
	check(River.cpu_index_legacy_restore_count==1 and River.cpu_index_override_count==0,name_+": legacy eligible CPU-to-GPU restoration counted")
	var old_spec:=Stream._spec(legacy);old_spec.map_draw_order=12345
	var expected:=comparable(old_spec);legacy.free();RenderingServer.force_sync()
	River.cache.clear();River.cpu_index_overrides_enabled=true
	var new_doc=document(authored,data,true)
	var visual:MeshInstance3D=new_doc._mesh(authored)
	check(visual.mesh is Cpu and visual.mesh.source_reference==null and not visual.mesh.get_rid().is_valid(),name_+": cooked directory mesh never uploaded")
	check(River.cpu_index_override_count==1 and River.cpu_index_legacy_restore_count==1,name_+": CPU-only path counted without another temporary restoration")
	check(visual.has_meta(River.CPU_SURFACE_OVERRIDES_META),name_+": deferred per-slot materials recorded")
	check(visual.get_meta("paint_source")==new_doc.load_box_meshes.values()[0].source,name_+": author paint/collision source retained")
	var actual:=Stream._spec(visual);actual.map_draw_order=12345
	check(actual.mesh==visual.mesh and actual.mesh.source_reference==null,name_+": spec conversion keeps original CPU mesh without upload")
	compare(comparable(actual),expected,name_+": exact geometry, collision, transform, metadata, shadow and all shader parameters")
	check(actual.collision_mesh.collision_faces()==old_spec.collision_mesh.collision_faces(),name_+": exact collision triangles")
	visual.free();RenderingServer.force_sync()
	check(actual.mesh.source_reference==null,name_+": CPU-only spec survives disposable node release")
	var before:=await capture(old_spec);var after:=await capture(actual);var delta:=image_delta(before,after)
	check(delta.mean<=1.0/255. and delta.max<=2.0/255.,name_+": rendered GPU image parity "+str(delta))
	# Opt-in is immutable runtime only; editor preview still exposes real slots.
	var editor=document(authored,data,false);var editable:MeshInstance3D=editor._mesh(authored)
	check(not editable.mesh is Cpu and not editable.has_meta(River.CPU_SURFACE_OVERRIDES_META),name_+": editable preview keeps real GPU overrides")
	compare(resource_value(Stream._spec(editable).surface_overrides),resource_value(actual.surface_overrides),name_+": editor material result is identical")
	editable.free()
	check(var_to_bytes(authored)==author_bytes,name_+": authored record unchanged")
	old_spec.clear();actual.clear();River.cache.clear();RenderingServer.force_sync()

func excluded_cases()->void:
	var plain:=record("plain");var data:=fixture(plain);var doc=document(plain,data,true)
	var visual:MeshInstance3D=doc._mesh(plain)
	check(visual.mesh is Cpu and not visual.has_meta(River.CPU_SURFACE_OVERRIDES_META),"terrain without river effects keeps ordinary CPU path")
	visual.free()
	var override_record:=record("depth");var override_fixture:=fixture(override_record)
	var override_doc=document(override_record,override_fixture,true)
	var override_node:=MeshInstance3D.new();override_node.mesh=override_doc.load_box_meshes.values()[0].mesh
	var global_material:=StandardMaterial3D.new();global_material.albedo_color=Color.RED;override_node.material_override=global_material
	River.apply(override_node,override_record,{},null,true,true)
	var override_slots:Array=override_node.get_meta(River.CPU_SURFACE_OVERRIDES_META)
	check(override_node.material_override==global_material and override_slots[1]==null and typeof(override_slots[1])==TYPE_OBJECT,"native empty slots never copy a nonempty global material override")
	override_node.free()
	var invalid:=record("depth");invalid.terrain_depth_blend.rock_end=0.
	var invalid_doc=document(invalid,fixture(invalid),false);visual=invalid_doc._mesh(invalid)
	check(visual.has_meta("paint_error") and not visual.has_meta(River.CPU_SURFACE_OVERRIDES_META),"editable invalid river parameters still fail validation")
	visual.free()
	# Wet canal banks and water are explicitly outside GroundBatch.candidate.
	var bank_doc:=Doc.new();bank_doc.load_immutable_records=true;bank_doc.load_box_meshes={}
	var bank_id:String=bank_doc.add_box("block",Vector3.ZERO,Vector3(4,2,1))
	var bank:Dictionary=bank_doc._find(bank_id);bank.color=[.4,.45,.5];bank.bank_wetness={"water_level":0.,"wet_height":.3}
	check(not Ground.candidate(bank),"wet canal bank excluded from CPU-only override path")
	var bank_seed:MeshInstance3D=bank_doc._mesh(bank);bank_seed.free()
	var bank_cook:=Cook.pack(bank_doc.load_box_meshes,"test_source","test_generator")
	bank_doc.load_box_meshes=Cook.restore(bank_cook)
	var wet:MeshInstance3D=bank_doc._mesh(bank)
	check(not wet.mesh is Cpu and not wet.has_meta(River.CPU_SURFACE_OVERRIDES_META) and wet.get_active_material(0) is ShaderMaterial,"wet bank retains existing GPU material path")
	wet.free()
	var water:Dictionary={"kind":"box","surface_id":"water","size":[4,.1,4],"channel_mesh":{},"water_depth_effect":{}}
	check(not Ground.candidate(water),"water retained on existing non-batch path")

func water_cases()->void:
	var authored:={"uuid":"water_fixture","kind":"box","surface_id":"water","collision":"none","position":[2,0,3],"rotation":[0,17,0],"size":[8,.2,8],"color":[.2,.4,.3],"channel_mesh":{"uv_origin":[0,0,0],"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]]},"water_depth_effect":{"absorption":.45,"shallow_color":[.24,.42,.34],"deep_color":[.055,.16,.14]}}
	var doc:=Doc.new();doc.load_box_meshes={}
	var seed:MeshInstance3D=doc._mesh(authored)
	check(not seed.has_meta("paint_error"),"water source passes actual document validation")
	seed.free()
	var cooked:=Cook.pack(doc.load_box_meshes,"test_source","test_generator")
	var expected:Dictionary={};var baseline:Image
	for enabled in [false,true]:
		River.water_cpu_normals_enabled=enabled;River.water_cpu_index_enabled=enabled;River.reset_index_profile();River.cache.clear()
		doc.load_immutable_records=enabled
		doc.load_box_meshes=Cook.restore(cooked.duplicate())
		var node:MeshInstance3D=doc._mesh(authored)
		check((node.mesh is Cpu)==enabled and node.has_meta(River.CPU_SURFACE_OVERRIDES_META)==enabled,"immutable water defers GPU upload until actual spawn")
		check(not node.has_meta("ground_batch_record"),"water never joins opaque ground batching")
		check(River.water_cpu_normal_hits==(node.mesh.get_surface_count() if enabled else 0),"water CPU normals switch selects measured path")
		check(node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"water still casts no slab shadow")
		var spec:=Stream._spec(node);node.free()
		check(spec.surface_overrides[0].resource_name=="River depth water" and spec.surface_overrides[1]==River.hidden_slab,"water upper face remains visible and slab edges remain hidden")
		if enabled:check(spec.mesh is Cpu and spec.mesh.source_reference==null,"off-screen water spec owns no temporary GPU mesh")
		if not enabled:
			expected=comparable(spec);baseline=await capture(spec)
		else:
			compare(comparable(spec),expected,"water CPU normals preserve exact mesh, collision, transforms and materials")
			var delta:=image_delta(baseline,await capture(spec))
			check(delta.mean<=1.0/255. and delta.max<=2.0/255.,"water GPU image parity "+str(delta))
	doc.load_immutable_records=false;doc.load_box_meshes=Cook.restore(cooked.duplicate())
	var editable:MeshInstance3D=doc._mesh(authored)
	check(not editable.mesh is Cpu and not editable.has_meta(River.CPU_SURFACE_OVERRIDES_META),"water editor preview retains native material slots")
	compare(comparable(Stream._spec(editable)),expected,"editable water matches runtime geometry and materials")
	editable.free()
	# A mesh edit invalidates its CPU cache. The fallback must inspect the new
	# surface instead of silently classifying from the old cached upper normal.
	var changed:=ArrayMesh.new();var arrays:Array=BoxMesh.new().surface_get_arrays(0)
	changed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	Cpu.remember(changed,[arrays]);changed.clear_surfaces()
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL].duplicate();normals.fill(Vector3.DOWN);arrays[Mesh.ARRAY_NORMAL]=normals
	changed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	check(not changed.has_meta("ground_cpu_cache"),"edited mesh invalidates cached water normals")
	var edited:=MeshInstance3D.new();edited.mesh=changed;River.reset_index_profile()
	River.apply(edited,authored,{},null,true)
	check(River.water_cpu_normal_hits==0 and edited.get_surface_override_material(0)==River.hidden_slab,"uncached edited surface uses current GPU normals and stays hidden")
	edited.free()

func run()->void:
	if DisplayServer.get_name()=="headless":print("GPU required; use background runner");quit(2);return
	create_timer(90).timeout.connect(func():quit(2));Engine.max_fps=60
	viewport=SubViewport.new();viewport.size=Vector2i(640,420);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.use_taa=false;root.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.12,.14,.18);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.5;viewport.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,32,0);viewport.add_child(light)
	var camera:=Camera3D.new();camera.position=Vector3(13,12,16);viewport.add_child(camera);camera.look_at(Vector3(2,0,3));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=14;camera.current=true
	var original_flag:=River.cpu_index_overrides_enabled
	var original_water:=River.water_cpu_normals_enabled
	var original_water_index:=River.water_cpu_index_enabled
	# This suite checks the original CPU-index contract with identical slot
	# layouts. Visible-only runtime projection has its own GPU/ownership suite.
	var original_visible:=River.water_visible_surfaces_enabled
	River.water_visible_surfaces_enabled=false
	comparison_cases()
	for case_name in ["saturation","depth","slope_regions"]:await terrain_case(case_name)
	await water_cases();River.water_cpu_normals_enabled=original_water;River.water_cpu_index_enabled=original_water_index
	excluded_cases();River.cpu_index_overrides_enabled=original_flag;River.water_visible_surfaces_enabled=original_visible;River.cache.clear()
	viewport.free();RenderingServer.force_sync()
	print("CPU_RIVER_MATERIALS_GPU passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
