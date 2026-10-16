extends "res://review_artifacts/town_asset_size_audit_20261011/review_lossless_candidates.gd"
## Intentional market realism changes; diagnostic A/B, never pixel-equality acceptance. Explicit isolated native root only.
## Each baseline/candidate runs separately; run through the private desktop wrapper.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Picking=preload("res://scripts/world_editor/picking_shape_cache.gd")
const Walk=preload("res://scripts/world_editor/walk_mode.gd")
const TintedGlass=preload("res://scripts/world3d/tinted_glass.gd")
const PreviewEnvironment=preload("res://scripts/world_editor/asset_preview_environment.gd")
const ROOT="D:/code/rmmo_runtime/review_artifacts/axel_market_realism_20261016"
const ART="D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016"
var plan_version:="v1"
var plan_path:=""
var asset_name:=""
var take_name:=""
var pinned:Dictionary={}

func catalog_roundtrip_same(a:Array,b:Array)->bool:
	if a.size()!=b.size():return false
	for index in a.size():
		if not a[index] is Dictionary or not b[index] is Dictionary:return false
		var left:Dictionary=a[index].duplicate(true);var right:Dictionary=b[index].duplicate(true)
		for key:String in ["bounds_position","bounds_size"]:
			if not left.get(key) is Array or not right.get(key) is Array or left[key].size()!=right[key].size():return false
			for component in left[key].size():
				var x:float=left[key][component];var y:float=right[key][component]
				if absf(x-y)>1e-12*maxf(1.,maxf(absf(x),absf(y))):return false
			left.erase(key);right.erase(key)
		# Only bounds permit JSON decimal rounding; all other fields exact.
		if left!=right:return false
	return true

func value_semantic(value:Variant,depth:int=0)->Variant:
	# Stable lightweight semantic recipe across native roundtrip; the separate
	# active_material_proof below performs actual source-channel pixel readback.
	if value is Texture2D:
		var id:int=value.get_instance_id()
		if not textures.has(id):textures[id]={"__texture":true,"class":value.get_class(),"width":value.get_width(),"height":value.get_height()}
		return textures[id]
	return super.value_semantic(value,depth)

func inspect(scene:Node)->Dictionary:
	var result:Dictionary=super.inspect(scene)
	var cache:=Picking.new();var rows:Array=[];var all:Array=[];gather(scene,all)
	for node:Node in all:
		if not node is MeshInstance3D or node.mesh==null:continue
		# PickingShapeCache attaches a scripted CPU cache to its input Mesh.
		# Audit a local mesh recipe so inspection cannot contaminate the native
		# source graph with runtime-only ground_cpu_cache metadata.
		var collision_mesh:Mesh=node.mesh.duplicate()
		var shape:ConcavePolygonShape3D=cache.shape_for(collision_mesh)
		check(shape!=null,"production picking shape "+str(node.name))
		if shape==null:continue
		var transform:=Transform3D.IDENTITY;var current:Node=node
		while current!=null:
			if current is Node3D:transform=current.transform*transform
			if current==scene:break
			current=current.get_parent()
		rows.append({"path":str(scene.get_path_to(node)),"transform":var_to_str(transform),"face_points":shape.get_faces().size(),"faces_sha256":sha(shape.get_faces().to_byte_array()),"backface_collision":shape.backface_collision,"layer":1|(Walk.WALK_MASK if Walk.physical(node.get_meta("extras",{})) else 0)})
	cache.clear();result.collision=rows
	return result

func create_views(_scene:Node,bounds:AABB)->Array:
	var c:=bounds.get_center();var radius:=maxf(1.,bounds.size.length()*.5)
	var distance:=radius/sin(deg_to_rad(22.))*1.12;var direction:=Vector3(.8,.42,1.6).normalized()
	var views:Array=[]
	for pair in [["near",1.],["medium",1.8],["far",3.]]:views.append({"name":pair[0],"eye":vec(c+direction*distance*pair[1]),"aim":vec(c),"fov":44.,"lighting":"normal"})
	views.append({"name":"back","eye":vec(c+Vector3(-.8,.38,-1.6).normalized()*distance),"aim":vec(c),"fov":44.,"lighting":"normal"})
	var front:=bounds.end.z;var top:=bounds.end.y;var height:=bounds.size.y
	views.append({"name":"cloth_detail","eye":[c.x+.9,top+.55,front+1.8],"aim":[c.x,top-.35,c.z],"fov":48.,"lighting":"normal"})
	views.append({"name":"goods_detail","eye":[c.x+.8,bounds.position.y+height*.57,front+1.4],"aim":[c.x,bounds.position.y+height*.43,c.z],"fov":54.,"lighting":"normal"})
	views.append({"name":"structure_detail","eye":[bounds.end.x+1.5,bounds.position.y+height*.42,front+1.3],"aim":[c.x+.45,bounds.position.y+height*.40,c.z],"fov":50.,"lighting":"normal"})
	for pair in [["cloth_raking",4],["goods_raking",5]]:
		var view:Dictionary=views[pair[1]].duplicate(true);view.name=pair[0];view.lighting="raking";views.append(view)
	if asset_name=="potion":
		for background:String in ["bright","dark"]:
			var view:Dictionary=views[5].duplicate(true);view.name="glass_"+background;view.lighting="normal";view.background=background;views.append(view)
		views.append({"name":"liquid_surface","eye":[c.x+.65,bounds.position.y+height*.73,front+1.],"aim":[c.x,bounds.position.y+height*.43,c.z],"fov":45.,"lighting":"normal"})
	return views

func rgba8_pixels(image:Image)->Dictionary:
	if image==null or image.is_empty():return {"invalid":true}
	var copy:Image=image.duplicate()
	if copy.is_compressed() and copy.decompress()!=OK:return {"invalid":true}
	copy.clear_mipmaps();copy.convert(Image.FORMAT_RGBA8)
	return {"width":copy.get_width(),"height":copy.get_height(),"rgba8_sha256":sha(copy.get_data())}

func source_channel_proof(mat:StandardMaterial3D,source_:Dictionary,pixels:Dictionary,optical:bool)->Dictionary:
	var channels:Dictionary={}
	check(not mat.uv1_triplanar and not mat.ao_on_uv2 and mat.uv1_scale.is_equal_approx(Vector3.ONE) and mat.uv1_offset.is_equal_approx(Vector3.ZERO),"actual material uses unchanged UV0 with no triplanar/secondary AO mapping "+mat.resource_name)
	for role:String in ["albedo","normal","roughness","metallic","ao","emission"]:
		var texture:Texture2D=mat.get(role+"_texture")
		if optical and role in ["albedo","emission"]:
			check(texture==null,"explicit optical pass intentionally clears "+role+" map "+mat.resource_name)
			channels[role]={"intentional_null":true,"reason":"Explicit rmmo_tinted_glass native two-pass contract"};continue
		var image_expected:Dictionary=source_.channels.get(role,{})
		if image_expected.is_empty():
			check(texture==null,"no unintended active "+role+" map "+mat.resource_name);continue
		if not check(texture!=null,"active "+role+" map exists "+mat.resource_name):continue
		if role=="roughness":check(mat.roughness_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_GREEN,"actual ORM roughness reads green "+mat.resource_name)
		if role=="metallic":check(mat.metallic_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_BLUE,"actual ORM metallic reads blue "+mat.resource_name)
		if role=="ao":check(mat.ao_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_RED,"actual AO reads red "+mat.resource_name)
		var id:=texture.get_instance_id()
		if not pixels.has(id):pixels[id]=rgba8_pixels(texture.get_image())
		var decoded:Dictionary=pixels[id]
		check(decoded.get("rgba8_sha256")==image_expected.rgba8_sha256 and decoded.get("width")==image_expected.width and decoded.get("height")==image_expected.height,"active GPU "+role+" pixels match actual GLB source "+mat.resource_name)
		channels[role]={"expected":image_expected,"actual":decoded}
	return channels

func runtime_uv_sampling(arrays:Array)->Dictionary:
	var positions:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var uvs:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
	if uvs.size()!=positions.size():return {"invalid":"missing active vertex UV0"}
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	if indices.is_empty():indices.resize(positions.size());for i in indices.size():indices[i]=i
	var paired:PackedStringArray=[]
	for index in indices:
		var p:=positions[index];var uv:=uvs[index];var values:=PackedFloat32Array([p.x,p.y,p.z,uv.x,uv.y])
		for k in values.size():
			if values[k]==0.:values[k]=0.
		paired.append(values.to_byte_array().hex_encode())
	paired.sort()
	var triangles:PackedStringArray=[]
	for i in range(0,indices.size(),3):
		var triangle:PackedInt32Array=PackedInt32Array([indices[i],indices[i+1],indices[i+2]]);triangle.sort()
		triangles.append("%d,%d,%d"%[triangle[0],triangle[1],triangle[2]])
	triangles.sort()
	return {"corners":indices.size(),"vertices":positions.size(),"position_uv_corner_sha256":sha("\n".join(paired).to_utf8_buffer()),"triangle_vertex_sets_sha256":sha("\n".join(triangles).to_utf8_buffer())}

func bound_uv_sampling(arrays:Array,expected:Array)->Dictionary:
	var actual:=runtime_uv_sampling(arrays);var comparisons:Array=[]
	if actual.has("invalid"):return actual
	var positions:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var uvs:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	for source_:Dictionary in expected:
		if actual.vertices!=source_.vertices or actual.corners!=source_.corners or actual.triangle_vertex_sets_sha256!=source_.triangle_vertex_sets_sha256:continue
		var reference_p:PackedFloat32Array=Marshalls.base64_to_raw(source_.position_f32_base64).to_float32_array();var reference_uv:PackedFloat32Array=Marshalls.base64_to_raw(source_.uv0_f32_base64).to_float32_array()
		var p_error:=[0.,0.,0.];var uv_error:=[0.,0.];var p_limit:=[0.,0.,0.];var uv_limit:=[0.,0.]
		for k in 3:p_limit[k]=float(source_.position_range[k])*2./65535.+.000002
		for k in 2:uv_limit[k]=maxf(1.,float(source_.uv_range[k]))*2./65535.+.0000002
		for index in positions.size():
			for k in 3:p_error[k]=maxf(p_error[k],absf(positions[index][k]-reference_p[index*3+k]))
			for k in 2:uv_error[k]=maxf(uv_error[k],absf(uvs[index][k]-reference_uv[index*2+k]))
		var passed:=true
		for k in 3:passed=passed and p_error[k]<=p_limit[k]
		for k in 2:passed=passed and uv_error[k]<=uv_limit[k]
		var matched:Dictionary={"passed":passed,"actual":actual,"source_corner_sha256":source_.position_uv_corner_sha256,"max_position_error_m":p_error,"position_limits_m":p_limit,"max_uv_error":uv_error,"uv_limits":uv_limit,"uv_error_texels_at_4096":[uv_error[0]*4096.,uv_error[1]*4096.],"rule":"Same vertex pairing and triangle vertex sets. Per-axis renderer compression allowance 2/65535 of position span, and max(1,UV span), plus float epsilon. This cannot authorize another UV channel or a topology change."}
		if passed:return matched
		comparisons.append(matched)
	return {"passed":false,"actual":actual,"matching_topology_attempts":comparisons,"reason":"Source active atlas UV/position pairing not retained within renderer compression precision"}

func active_material_proof(scene:Node)->Dictionary:
	var expected:Dictionary={}
	for item:Dictionary in pinned.expected_materials[case_name].materials:expected[item.name]=item
	var nodes:Array=[];gather(scene,nodes);var found:Dictionary={};var bindings:Array=[];var pixels:Dictionary={};var surfaces:=0;var optical_seen:Dictionary={};var uv_seen:Dictionary={}
	for node:Node in nodes:
		if not node is MeshInstance3D or node.mesh==null:continue
		for slot in node.mesh.get_surface_count():
			surfaces+=1
			var actual:Material=node.get_active_material(slot)
			if not check(actual is StandardMaterial3D,"active StandardMaterial3D adapter "+str(node.name)+"/"+str(slot)):continue
			var mat:=actual as StandardMaterial3D
			if not check(expected.has(mat.resource_name),"active source material name "+mat.resource_name):continue
			var source_:Dictionary=expected[mat.resource_name];found[mat.resource_name]=true
			var arrays:Array=node.mesh.surface_get_arrays(slot)
			var vertex_count:int=arrays[Mesh.ARRAY_VERTEX].size();var tangent_count:int=0 if arrays[Mesh.ARRAY_TANGENT]==null else arrays[Mesh.ARRAY_TANGENT].size()
			var optical_meta:Dictionary=node.get_meta("extras",{}).get(TintedGlass.KEY,{})
			var optics:Dictionary=optical_meta.get("materials",{}).get(mat.resource_name,{})
			var transmitted:=not optics.is_empty()
			var reflection_proof:Dictionary={}
			if transmitted:
				var stamp:=JSON.stringify(optics,"",true)
				if not optical_seen.has(mat.resource_name):optical_seen[mat.resource_name]=[]
				optical_seen[mat.resource_name].append(stamp)
				check(TintedGlass.valid(optical_meta) and source_.explicit_optics_surface_recipes.any(func(recipe):return JSON.stringify(recipe,"",true)==stamp),"actual optical recipe matches exact source material slot "+mat.resource_name)
				check(mat.get_meta(TintedGlass.STAMP,"")==stamp,"native optical stamp binds actual source recipe "+mat.resource_name)
				var tint:Array=optics.transmittance;var expected_tint:=Color(tint[0]*.96,tint[1]*.96,tint[2]*.96,1).linear_to_srgb()
				check(mat.albedo_color.is_equal_approx(expected_tint) and mat.blend_mode==BaseMaterial3D.BLEND_MODE_MUL and mat.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED and mat.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"thin-glass actual tinted multiply transmission "+mat.resource_name)
				check(not mat.normal_enabled and not mat.emission_enabled and not mat.refraction_enabled and not mat.clearcoat_enabled and is_zero_approx(mat.metallic),"transmission pass intentional no lighting, emission, refraction or metal "+mat.resource_name)
				if check(mat.next_pass is StandardMaterial3D,"separate native dielectric reflection pass "+mat.resource_name):
					var reflected:=mat.next_pass as StandardMaterial3D
					check(reflected.next_pass==null and reflected.blend_mode==BaseMaterial3D.BLEND_MODE_ADD and reflected.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL and reflected.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"thin-glass actual additive PBR reflection "+mat.resource_name)
					check(is_equal_approx(reflected.roughness,float(optics.get("roughness",.13))) and is_zero_approx(reflected.metallic) and is_equal_approx(reflected.metallic_specular,.5) and reflected.albedo_color.is_equal_approx(Color(0,0,0,1)) and not reflected.emission_enabled and not reflected.refraction_enabled and not reflected.clearcoat_enabled,"dielectric reflection factors with no intrinsic glow "+mat.resource_name)
					check(reflected.normal_enabled==bool(source_.normal_enabled) and (not source_.normal_enabled or is_equal_approx(reflected.normal_scale,float(source_.normal_scale))),"reflection preserves authored normal enable and scale "+mat.resource_name)
					reflection_proof={"name":reflected.resource_name,"blend_mode":reflected.blend_mode,"roughness":reflected.roughness,"normal_enabled":reflected.normal_enabled,"normal_scale":reflected.normal_scale,"channels":source_channel_proof(reflected,source_,pixels,true)}
			else:
				check(not mat.has_meta(TintedGlass.STAMP),"no unaccounted optical conversion "+mat.resource_name)
				check(mat.normal_enabled==bool(source_.normal_enabled),"intended normal enable "+mat.resource_name)
				if source_.normal_enabled:check(is_equal_approx(mat.normal_scale,float(source_.normal_scale)),"intended normal scale "+mat.resource_name)
				check(is_equal_approx(mat.roughness,float(source_.roughness_factor)) and is_equal_approx(mat.metallic,float(source_.metallic_factor)),"roughness and metallic factors "+mat.resource_name)
			if source_.normal_enabled:check(tangent_count==vertex_count*4,"complete tangents on normal mapped active surface "+str(node.name)+"/"+str(slot))
			var binding:Dictionary={"mesh":str(scene.get_path_to(node)),"surface":slot,"material":mat.resource_name,"normal_enabled":mat.normal_enabled,"normal_scale":mat.normal_scale,"roughness":mat.roughness,"metallic":mat.metallic,"alpha":mat.albedo_color.a,"transparency":mat.transparency,"roughness_channel":mat.roughness_texture_channel,"metallic_channel":mat.metallic_texture_channel,"ao_channel":mat.ao_texture_channel,"uv1_scale":vec(mat.uv1_scale),"uv1_offset":vec(mat.uv1_offset),"vertices":vertex_count,"tangent_floats":tangent_count,"optics_recipe":optics,"channels":{}}
			if not source_.channels.is_empty():
				binding.uv_sampling=bound_uv_sampling(arrays,source_.get("primitive_uv_sampling",[]))
				check(binding.uv_sampling.get("passed",false),"actual prepared UV0 retains source sampling within renderer precision "+mat.resource_name)
				if not uv_seen.has(mat.resource_name):uv_seen[mat.resource_name]=[]
				uv_seen[mat.resource_name].append(binding.uv_sampling.get("source_corner_sha256","invalid") if binding.uv_sampling.get("passed",false) else "invalid")
			binding.channels=source_channel_proof(mat,source_,pixels,transmitted);binding.reflection_pass=reflection_proof
			bindings.append(binding)
	check(found.size()==expected.size(),"every source-active material actually bound")
	for material_name:String in expected:
		var source_recipes:Array=[]
		for recipe:Dictionary in expected[material_name].explicit_optics_surface_recipes:source_recipes.append(JSON.stringify(recipe,"",true))
		var actual_recipes:Array=optical_seen.get(material_name,[]);source_recipes.sort();actual_recipes.sort()
		check(source_recipes==actual_recipes,"all source optical primitive instances retained by exact material identity "+material_name)
		var source_uv:Array=[]
		for primitive:Dictionary in expected[material_name].get("primitive_uv_sampling",[]):source_uv.append(primitive.position_uv_corner_sha256)
		var actual_uv:Array=uv_seen.get(material_name,[]);source_uv.sort();actual_uv.sort()
		check(source_uv==actual_uv,"prepared mesh UV0 triangle-corner pairing equals actual source atlas sampling "+material_name)
	return {"uv_binding_contract_version":1,"surfaces":surfaces,"unique_material_names":found.keys(),"unique_texture_objects":pixels.size(),"bindings":bindings,"optical_recipes_by_material":optical_seen,"optics_limit":"Native thin-glass multiply transmission plus additive reflection; no physical refraction simulation. Clear albedo/emission channels are deliberate. Background visibility and liquid surface still require actual human image review.","source_channel_expectations_sha256":sha(stable(pinned.expected_materials[case_name]).to_utf8_buffer()),"stage":"prepared native reopened and uploaded, before first screenshot"}

func prepared_mesh_cost(scene:Node)->Dictionary:
	# Actual prepared ArrayMesh renderer surfaces. Resource sharing is counted
	# separately from instances; pass submissions below are budgets, not draws.
	RenderingServer.force_sync()
	var nodes:Array=[];gather(scene,nodes);var meshes:Dictionary={};var rows:Array=[]
	var total:Dictionary={"mesh_instances":0,"surface_instances":0,"instance_lod0_triangles":0,"unique_lod0_triangles":0,"opaque_surface_instances":0,"transparent_surface_instances":0,"transparent_pass_instances":0,"opaque_pass_instances":0,"lod0_pass_triangle_budget":0,"unique_surfaces_with_lods":0}
	for node:Node in nodes:
		if not node is MeshInstance3D or node.mesh==null:continue
		total.mesh_instances+=1
		var unique_mesh:bool=not meshes.has(node.mesh.get_instance_id());meshes[node.mesh.get_instance_id()]=true
		for slot in node.mesh.get_surface_count():
			total.surface_instances+=1
			var surface:Dictionary=RenderingServer.mesh_get_surface(node.mesh.get_rid(),slot)
			var primitive:int=node.mesh.surface_get_primitive_type(slot)
			var index_count:int=surface.get("index_count",0);var vertex_count:int=surface.get("vertex_count",0)
			var triangles:int=(index_count if index_count>0 else vertex_count)/3 if primitive==Mesh.PRIMITIVE_TRIANGLES else 0
			var levels:Array=[]
			if not surface.get("lods",[]).is_empty():
				var stride:int=RenderingServer.mesh_surface_get_format_index_stride(surface.format,vertex_count)
				for level:Dictionary in surface.lods:
					var bytes:PackedByteArray=level.index_data
					levels.append({"edge_length":level.edge_length,"index_bytes":bytes.size(),"index_stride":stride,"indices":bytes.size()/stride,"triangles":bytes.size()/stride/3,"indices_sha256":sha(bytes)})
				if unique_mesh:total.unique_surfaces_with_lods+=1
			var passes:Array=[];var visited:Dictionary={};var material:Material=node.get_active_material(slot);var has_transparent:=false
			while material!=null and not visited.has(material.get_instance_id()):
				visited[material.get_instance_id()]=true
				var pass_:Dictionary={"class":material.get_class(),"name":material.resource_name,"render_priority":material.render_priority}
				if material is BaseMaterial3D:
					pass_.transparency=material.transparency;pass_.blend_mode=material.blend_mode;pass_.shading_mode=material.shading_mode
					pass_.transparent=material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or material.blend_mode!=BaseMaterial3D.BLEND_MODE_MIX
				else:pass_.transparent=true;pass_.classification="Conservative unknown shader pass"
				if pass_.transparent:has_transparent=true;total.transparent_pass_instances+=1
				else:total.opaque_pass_instances+=1
				passes.append(pass_);material=material.next_pass
			if has_transparent:total.transparent_surface_instances+=1
			else:total.opaque_surface_instances+=1
			total.instance_lod0_triangles+=triangles;total.lod0_pass_triangle_budget+=triangles*passes.size()
			if unique_mesh:total.unique_lod0_triangles+=triangles
			rows.append({"mesh":str(scene.get_path_to(node)),"surface":slot,"vertices":vertex_count,"indices":index_count,"primitive":primitive,"lod0_triangles":triangles,"actual_renderer_lods":levels,"visible_in_tree":node.is_visible_in_tree(),"visibility_begin":node.visibility_range_begin,"visibility_end":node.visibility_range_end,"lod_bias":node.lod_bias,"material_passes":passes})
	total.unique_mesh_resources=meshes.size()
	return {"totals":total,"surfaces":rows,"stage":"Prepared native instantiated, ten frames settled, actual RenderingServer mesh surface readback","limits":"LOD0 counts and per-pass triangle budgets are not actual per-view LOD selection or draw calls. Per-view renderer primitives/objects/draw calls are recorded separately and include test ground, background card and renderer passes. No triangle-increase or absence-of-LOD failure threshold; evaluate visible benefit and cost together."}

func draw_scene(scene:Node,views:Array)->void:
	root.size=dimensions;var vp:=SubViewport.new();vp.size=dimensions;vp.own_world_3d=true
	vp.use_taa=false;vp.msaa_3d=Viewport.MSAA_DISABLED;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(scene)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(.14,.17,.20);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.65
	env.environment.tonemap_mode=Environment.TONE_MAPPER_ACES;env.environment.tonemap_exposure=1.;PreviewEnvironment.apply_reflections(env.environment);vp.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-28,0);sun.light_energy=1.5;sun.shadow_enabled=true;sun.directional_shadow_max_distance=80.;vp.add_child(sun)
	var bounds:=scene_bounds(scene);var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(24,24);ground.mesh=plane
	ground.position=Vector3(bounds.get_center().x,bounds.position.y-.02,bounds.get_center().z)
	var ground_mat:=StandardMaterial3D.new();ground_mat.albedo_color=Color(.29,.31,.30);ground_mat.roughness=.95;ground.material_override=ground_mat;vp.add_child(ground)
	var cam:=Camera3D.new();cam.current=true;cam.near=.03;cam.far=200.;vp.add_child(cam)
	report.render_spec={"dimensions":vec(Vector3(dimensions.x,dimensions.y,0)),"taa":false,"msaa":false,"ambient_energy":.65,"sun_energy":1.5,"sun_rotation":[-38,-28,0],"exposure":1.,"tonemap":"ACES","ground_color":[.29,.31,.30],"characters":"none","wind":"no source wind metadata; one static pose only"}
	report.render_spec.reflection_environment={"recipe_version":PreviewEnvironment.RECIPE_VERSION,"helper_sha256":FileAccess.get_sha256("res://scripts/world_editor/asset_preview_environment.gd"),"source":"Shared UI asset preview/thumbnail neutral reflection helper; BG_COLOR, ambient and main light unchanged","actual_reflected_light_source":env.environment.reflected_light_source,"radiance_size":env.environment.sky.radiance_size}
	check(env.environment.reflected_light_source==Environment.REFLECTION_SOURCE_SKY and env.environment.sky!=null,"actual shared neutral reflection environment bound")
	var backdrop:=MeshInstance3D.new();var card:=QuadMesh.new();card.size=Vector2(bounds.size.x*1.2,bounds.size.y*.75);backdrop.mesh=card
	backdrop.position=Vector3(bounds.get_center().x,bounds.position.y+bounds.size.y*.40,bounds.position.z-.04)
	var backmat:=StandardMaterial3D.new();backmat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;backdrop.material_override=backmat;backdrop.visible=false;vp.add_child(backdrop)
	for frame in 10:await process_frame;await RenderingServer.frame_post_draw
	report.active_material_proof=active_material_proof(scene)
	report.prepared_mesh_cost=prepared_mesh_cost(scene)
	report.screenshots=[]
	for view:Dictionary in views:
		var raking:bool=view.get("lighting")=="raking"
		sun.rotation_degrees=Vector3(-12,65,0) if raking else Vector3(-38,-28,0)
		env.environment.ambient_light_energy=.18 if raking else .65
		backdrop.visible=view.has("background")
		backmat.albedo_color=Color(.85,.85,.85) if view.get("background")=="bright" else Color(.025,.025,.025)
		env.environment.background_color=backmat.albedo_color if backdrop.visible else Color(.14,.17,.20)
		cam.position=vector(view.eye);cam.fov=float(view.fov);cam.look_at(vector(view.aim))
		for frame in 10:await process_frame;await RenderingServer.frame_post_draw
		var im:Image=vp.get_texture().get_image();var name_:String=view.name+".png";var path:=out.path_join(case_name).path_join(name_)
		check(im.save_png(path)==OK,"exact local image "+name_)
		report.screenshots.append({"view":view,"sun_rotation":vec(sun.rotation_degrees),"ambient_energy":env.environment.ambient_light_energy,"background_card":backdrop.visible,"name":name_,"path":path,"file_sha256":FileAccess.get_sha256(path),"pixels":normalized_image(im),"draw_calls":RenderingServer.viewport_get_render_info(vp.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),"rendered_primitives":RenderingServer.viewport_get_render_info(vp.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),"rendered_objects":RenderingServer.viewport_get_render_info(vp.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),"renderer_texture_memory_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)})
	vp.queue_free();await process_frame;Drainer.synchronize_transfer()

func compare_reports()->void:
	var a:=read_json(out.path_join("baseline.json"));var b:=read_json(out.path_join("candidate.json"))
	if not check(a.get("passed",false) and b.get("passed",false),"both actual native cases pass"):finish();return
	check(a.original_sha==pinned.source_sha256 and b.original_sha==pinned.candidate_sha256,"A/B reports bind actual source SHA")
	check(a.generator==b.generator and a.generator==Compiled.generator(),"same current native generator")
	check(a.camera_views==b.camera_views and a.render_spec==b.render_spec,"same camera lighting exposure and image dimensions")
	check(vector(a.bounds.position).distance_to(vector(b.bounds.position))<.0001 and vector(a.bounds.size).distance_to(vector(b.bounds.size))<.0001,"overall authored envelope unchanged within 0.1 mm; no stale prefab bounds")
	check(a.screenshots.size()==b.screenshots.size(),"same full view coverage")
	check(not a.get("active_material_proof",{}).is_empty() and not b.get("active_material_proof",{}).is_empty(),"actual runtime channel binding evidence exists")
	report.images=[]
	for shot:Dictionary in a.screenshots:
		var d:=image_difference(out.path_join("baseline").path_join(shot.name),out.path_join("candidate").path_join(shot.name));d.name=shot.name
		report.images.append(d);check(d.get("valid",false),"readable same-sized diagnostic A/B frames "+shot.name)
	report.baseline_native=a.native;report.candidate_native=b.native
	report.source_sha256=pinned.source_sha256;report.candidate_sha256=pinned.candidate_sha256
	report.intentional_visual_change=true;report.visual_acceptance="PENDING actual root review"
	report.geometry_equality_required=false;report.pixel_equality_required=false;report.source_cost_decrease_required=false
	report.baseline_binding=a.active_material_proof;report.candidate_binding=b.active_material_proof
	report.baseline_prepared_mesh_cost=a.prepared_mesh_cost;report.candidate_prepared_mesh_cost=b.prepared_mesh_cost
	report.cost_delta={"source_bytes":b.source_bytes-a.source_bytes,"native_bytes":b.native.native_bytes-a.native.native_bytes,"instance_lod0_triangles":b.prepared_mesh_cost.totals.instance_lod0_triangles-a.prepared_mesh_cost.totals.instance_lod0_triangles,"transparent_surface_instances":b.prepared_mesh_cost.totals.transparent_surface_instances-a.prepared_mesh_cost.totals.transparent_surface_instances,"transparent_pass_instances":b.prepared_mesh_cost.totals.transparent_pass_instances-a.prepared_mesh_cost.totals.transparent_pass_instances,"note":"Diagnostic increases are intentional-change review inputs, never automatic rejection or acceptance."}
	report.note="User-directed realism changes require actual visual review; MAE/exactness and disk cost never grant acceptance. Native footprint budgets/renderer counters are not actual RSS/dedicated VRAM. Within-case native roundtrip remains exact."
	finish()

func run()->void:
	if "--syntax-only" in OS.get_cmdline_user_args():print("MARKET_REVIEW_SYNTAX_OK");quit();return
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--asset="):asset_name=arg.trim_prefix("--asset=")
		elif arg.begins_with("--case="):case_name=arg.trim_prefix("--case=")
		elif arg.begins_with("--take="):take_name=arg.trim_prefix("--take=")
		elif arg.begins_with("--plan-version="):plan_version=arg.trim_prefix("--plan-version=")
		else:push_error("Unknown argument: "+arg);quit(2);return
	if asset_name not in ["pottery","scroll","potion","ore"] or case_name not in ["baseline","candidate","compare"] or take_name.is_empty() or not take_name.is_valid_identifier():push_error("Invalid fixed review scope");quit(2);return
	if not plan_version.is_valid_identifier() or not plan_version.begins_with("v") or not plan_version.substr(1).is_valid_int():push_error("Invalid plan version");quit(2);return
	plan_path=ART.path_join(plan_version).path_join("review_plan.json")
	var plan:=read_json(plan_path)
	if plan.get("preview_recipe") is Dictionary and plan.preview_recipe.get("sha256")!=FileAccess.get_sha256("res://scripts/world_editor/asset_preview_environment.gd"):push_error("Frozen preview reflection helper SHA mismatch");quit(2);return
	for row:Dictionary in plan.get("rows",[]):
		if row.asset==asset_name:pinned=row
	if pinned.is_empty():push_error("Missing pinned plan");quit(2);return
	source=pinned.source;candidate=pinned.candidate;out=ROOT.path_join(take_name).path_join(asset_name)
	if FileAccess.get_sha256(source)!=pinned.source_sha256 or FileAccess.get_sha256(candidate)!=pinned.candidate_sha256:push_error("Frozen source SHA mismatch");quit(2);return
	if FileAccess.file_exists(out.path_join(case_name+".json")):push_error("Retain prior evidence; choose new take");quit(2);return
	DirAccess.make_dir_recursive_absolute(out);report.asset=asset_name;report.generator=Compiled.generator();report.plan_sha256=FileAccess.get_sha256(plan_path)
	report.review_tool_sha256=FileAccess.get_sha256("res://tools/review_axel_market_realism_20261016.gd")
	if case_name=="compare":compare_reports();return
	if not check(DisplayServer.get_name()!="headless","private-desktop graphics process required"):finish();return
	Engine.max_fps=60;dimensions=Vector2i(1400,1000)
	var original:String=source if case_name=="baseline" else candidate;var digest:=FileAccess.get_sha256(original)
	report.case_name=case_name;report.original=original;report.original_sha=digest;report.source_bytes=size_of(original);report.dimensions=[dimensions.x,dimensions.y]
	report.raw_admission_estimate=Estimate.estimate(original)
	var case_out:=out.path_join(case_name);var isolated:=case_out.path_join("isolated_content");var local_source:=isolated.path_join("assets").path_join(digest+".glb")
	DirAccess.make_dir_recursive_absolute(local_source.get_base_dir())
	if not check(DirAccess.copy_absolute(original,local_source)==OK and FileAccess.get_sha256(local_source)==digest,"copy exact GLB into owned isolated root"):finish();return
	var document:=GLTFDocument.new();var state:=GLTFState.new();var began:=Time.get_ticks_usec()
	if not check(document.append_from_file(local_source,state,0,local_source.get_base_dir())==OK,"real raw GLTF import"):finish();return
	report.raw_append_us=Time.get_ticks_usec()-began;report.imported_image_entries=state.images.size()
	var scene:Node=Io.generate_scene(document,state)
	if not check(scene!=null,"production scene postprocessing"):finish();return
	scene.name="MarketReview";report.semantic=inspect(scene);report.material_resource_count=materials.size();report.active_texture_bindings=textures.size()
	report.material_pixel_proof="Prepared runtime get_active_material and Texture2D RGBA8 SHA proof is recorded after upload settles, against actual source GLB images."
	var bounds:=scene_bounds(scene);report.bounds={"position":vec(bounds.position),"size":vec(bounds.size)}
	var views:Array=[];var view_path:=out.path_join("camera_views.json")
	if case_name=="baseline":views=create_views(scene,bounds);put(view_path,{"source_sha":pinned.source_sha256,"views":views})
	else:
		var saved:=read_json(view_path)
		if not check(saved.get("source_sha")==pinned.source_sha256,"frozen baseline cameras exist"):scene.free();finish();return
		views=saved.views
	report.camera_views=views
	# Private library reader/save verification; never call default-root import_file.
	var library:=Library.new(local_source.get_base_dir())
	library.entries=[{"label":pinned.label,"category":"隔离模型验收","asset_path":local_source,"bounds_position":vec(bounds.position),"bounds_size":vec(bounds.size)}]
	check(library.save()==OK,"private library atomic save")
	check(catalog_roundtrip_same(Library.new(library.directory).entries,library.entries),"private library reopen exact fields and bounds within relative 1e-12")
	own(scene,scene);var packed:=PackedScene.new()
	if not check(packed.pack(scene)==OK and Compiled._valid_packed(packed),"production native schema"):scene.free();finish();return
	var folder:String=Compiled.directory(isolated);DirAccess.make_dir_recursive_absolute(folder);var draft:=folder.path_join("review_build.scn")
	if not check(ResourceSaver.save(packed,draft,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK,"isolated compressed native save"):scene.free();finish();return
	scene.free();scene=null;packed=null;state=null;document=null;Drainer.synchronize_transfer()
	var payload_sha:=FileAccess.get_sha256(draft);var payload:=folder.path_join(payload_sha+".scn")
	check(DirAccess.rename_absolute(draft,payload)==OK,"private content-addressed native publish")
	check(ResourceLoader.get_dependencies(payload).is_empty(),"native has no external dependencies")
	check(put(Compiled.index_path(local_source,isolated),{"version":Compiled.VERSION,"generator":Compiled.generator(),"source_sha":digest,"payload_sha":payload_sha,"bytes":size_of(payload)}),"isolated native index")
	var loaded:Dictionary=Compiled.read(local_source,digest,isolated)
	if not check(loaded.get("hit",false),"production native reader accepts exact private product"):finish();return
	packed=loaded.packed;var stats:Dictionary=Footprint.measure(packed);stats.native_uncompressed_bytes=Footprint.native_uncompressed_bytes(payload)
	var estimated:Dictionary=Footprint.estimate_stats(stats);check(not estimated.is_empty(),"real native footprint measure")
	scene=packed.instantiate();check(stable(inspect(scene))==stable(report.semantic),"native save-reopen preserves materials geometry and collision shape")
	report.native={"content_root":isolated,"source":local_source,"payload":payload,"payload_sha256":payload_sha,"native_bytes":size_of(payload),"stats":stats,"estimate":estimated}
	scene.free();scene=null;loaded.clear();packed=null;Drainer.synchronize_transfer()
	var built:Dictionary=Footprint.build(local_source,isolated);check(built.get("ok",false),"production footprint build in explicit isolated root")
	var fc:Dictionary=Footprint.candidate(local_source,isolated,digest);check(not fc.is_empty(),"actual native footprint verifies");report.native.footprint_candidate=fc
	var prepared:Dictionary=Preparation.read(local_source,fc,isolated)
	if not check(prepared.get("error",FAILED)==OK and prepared.get("packed")!=null and not prepared.get("fallback_required",false),"production native preparation"):finish();return
	packed=prepared.packed;scene=packed.instantiate();check(stable(inspect(scene))==stable(report.semantic),"prepared native semantic identity")
	prepared.clear();packed=null;Drainer.synchronize_transfer();await draw_scene(scene,views)
	check(FileAccess.get_sha256(original)==digest and FileAccess.get_sha256(local_source)==digest,"formal/candidate source bytes untouched")
	report.collision_scope="Production PickingShapeCache shape faces, transforms, WalkMode physical masks before and after native save/reopen. No formal map, UI HTTP or controller traversal claim."
	finish()
