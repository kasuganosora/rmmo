extends SceneTree
## Isolated review only. Run baseline and candidate in SEPARATE processes, then
## --case=compare (headless is sufficient for comparison). Never Compiled.build.
## Required: --source=... --candidate=... --out=... --case=baseline|candidate|compare
## Optional: --allow-texture-change --width=1400 --height=1000 --detail=pennant|auto
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Preparation=preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Wind=preload("res://scripts/world3d/wind_material.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Estimate=preload("res://scripts/world3d/asset_memory_estimate.gd")
var source:=""
var candidate:=""
var out:=""
var case_name:="baseline"
var allow_texture_change:=false
var detail_mode:="auto"
var dimensions:=Vector2i(1400,1000)
var report:Dictionary={"checks":[],"failures":[],"scope":"Isolated asset/native contract and fixed-view A/B; no production map/cache writes, no FPS claim."}
var textures:Dictionary={}
var materials:Dictionary={}

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->bool:
	report.checks.append({"label":label,"ok":ok})
	if not ok:report.failures.append(label);push_error(label)
	return ok
func sha(bytes:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func stable(value:Variant)->String:return JSON.stringify(value,"",true,true)
func put(path:String,value:Variant)->bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f:=FileAccess.open(path,FileAccess.WRITE)
	if f==null:return false
	f.store_string(JSON.stringify(value,"  ",true,true));f.flush();var ok:=f.get_error()==OK;f.close();return ok
func read_json(path:String)->Dictionary:
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}
func size_of(path:String)->int:
	var f:=FileAccess.open(path,FileAccess.READ)
	if f==null:return -1
	var size:=f.get_length();f.close();return size
func finish()->void:
	report.passed=report.failures.is_empty()
	put(out.path_join(case_name+".json"),report)
	print("LOSSLESS_CANDIDATE_REVIEW ",case_name," passed=",report.passed," out=",out)
	quit(0 if report.passed else 1)
func vec(v:Vector3)->Array:return [v.x,v.y,v.z]
func vector(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
func normalized_image(image:Image)->Dictionary:
	if image==null or image.is_empty():return {"invalid":true}
	var copy:Image=image.duplicate()
	if copy.is_compressed() and copy.decompress()!=OK:return {"invalid_compression":true}
	# Same pixels in RGB8/RGBA8 are aliases. HDR retains float precision.
	var normalized:int=Image.FORMAT_RGBA8 if copy.get_format()<=Image.FORMAT_RGBA8 else Image.FORMAT_RGBAF
	copy.convert(normalized)
	return {"__texture":true,"width":copy.get_width(),"height":copy.get_height(),"normalized_format":normalized,"mips":copy.has_mipmaps(),"normalized_pixels_sha256":sha(copy.get_data())}
func value_semantic(value:Variant,depth:int=0)->Variant:
	if depth>24:return {"invalid_depth":true}
	if value is Texture2D:
		var id:int=value.get_instance_id()
		if not textures.has(id):textures[id]=normalized_image(value.get_image())
		return textures[id]
	if value is Material:return material_semantic(value,depth+1)
	if value is Resource:
		check(false,"unsupported material resource: "+value.get_class());return {"unsupported":value.get_class()}
	if value is Dictionary:
		var row:Dictionary={}
		for k in value:row[str(k)]=value_semantic(value[k],depth+1)
		return row
	if value is Array:
		var row:Array=[]
		for v in value:row.append(value_semantic(v,depth+1))
		return row
	# Packed mesh data is hashed independently. Built-in math property strings
	# preserve exact imported values while avoiding object IDs/resource aliases.
	return var_to_str(value)
func material_semantic(mat:Material,depth:int=0)->Dictionary:
	if mat==null:return {"null":true}
	var id:=mat.get_instance_id()
	if materials.has(id):return materials[id]
	var row:Dictionary={"class":mat.get_class(),"properties":{}}
	for p:Dictionary in mat.get_property_list():
		var key:String=p.name
		if not (int(p.usage)&PROPERTY_USAGE_STORAGE):continue
		if key in ["resource_name","resource_path","resource_scene_unique_id","resource_local_to_scene","script"] or key.begins_with("metadata/"):continue
		row.properties[key]=value_semantic(mat.get(key),depth+1)
	materials[id]=row;return row
func gather(node:Node,rows:Array)->void:
	rows.append(node)
	for child in node.get_children():gather(child,rows)
func inspect(scene:Node)->Dictionary:
	textures.clear();materials.clear()
	var all:Array=[];gather(scene,all);var rows:Array=[];var triangle_count:=0;var mesh_count:=0
	for n:Node in all:
		var row:Dictionary={"path":"." if n==scene else str(scene.get_path_to(n)),"class":n.get_class(),"extras":n.get_meta("extras",{}),"groups":Array(n.get_groups())}
		row.groups.sort()
		if n is Node3D:row.transform=var_to_str(n.transform);row.visible=n.visible
		if n is MeshInstance3D:
			mesh_count+=1;row.surfaces=[]
			row.lod={"begin":n.visibility_range_begin,"end":n.visibility_range_end,"begin_margin":n.visibility_range_begin_margin,"end_margin":n.visibility_range_end_margin,"fade":n.visibility_range_fade_mode,"custom_aabb":var_to_str(n.custom_aabb),"lod_bias":n.lod_bias}
			row.render={"cast_shadow":n.cast_shadow,"layers":n.layers,"sorting_offset":n.sorting_offset,"transparency":n.transparency}
			if n.mesh==null:row.mesh_null=true
			else:
				row.mesh_aabb=var_to_str(n.mesh.get_aabb());row.blend_names=[]
				for blend in n.mesh.get_blend_shape_count():row.blend_names.append(str(n.mesh.get_blend_shape_name(blend)))
				for slot in n.mesh.get_surface_count():
					var arrays:Array=n.mesh.surface_get_arrays(slot)
					var count:int=n.mesh.surface_get_array_index_len(slot)
					if count==0:count=n.mesh.surface_get_array_len(slot)
					if n.mesh.surface_get_primitive_type(slot)==Mesh.PRIMITIVE_TRIANGLES:triangle_count+=count/3
					# Public Mesh.surface_get_lods is not script-bound; use the
					# serialized ArrayMesh recipe, matching the repository auditor.
					var stored_surfaces:Array=n.mesh.get("_surfaces")
					var stored_lods:Array=stored_surfaces[slot].get("lods",[])
					row.surfaces.append({"primitive":n.mesh.surface_get_primitive_type(slot),"arrays_sha256":sha(var_to_bytes(arrays)),"blend_arrays_sha256":sha(var_to_bytes(n.mesh.surface_get_blend_shape_arrays(slot))),"lods_sha256":sha(var_to_bytes(stored_lods)),"material":material_semantic(n.get_active_material(slot))})
		rows.append(row)
	return {"nodes":rows,"instance_triangles":triangle_count,"mesh_nodes":mesh_count}
func strip_textures(value:Variant)->Variant:
	if value is Dictionary:
		if value.get("__texture",false):return {"__texture":true}
		var out_value:Dictionary={}
		for k in value:out_value[k]=strip_textures(value[k])
		return out_value
	if value is Array:
		var out_value:Array=[]
		for item in value:out_value.append(strip_textures(item))
		return out_value
	return value
func own(node:Node,owner_node:Node)->void:
	for child in node.get_children():child.owner=owner_node;own(child,owner_node)
func scene_bounds(scene:Node)->AABB:
	var nodes:Array=[];gather(scene,nodes);var bounds:=AABB();var first:=true
	for n:Node in nodes:
		if not n is MeshInstance3D or n.mesh==null:continue
		var t:=Transform3D.IDENTITY;var current:Node=n
		while current!=null:
			if current is Node3D:t=current.transform*t
			if current==scene:break
			current=current.get_parent()
		var b:AABB=t*n.mesh.get_aabb();bounds=b if first else bounds.merge(b);first=false
	return bounds
func create_views(scene:Node,bounds:AABB)->Array:
	var centre:=bounds.get_center();var radius:=maxf(1,bounds.size.length()*.5)
	var near_distance:=radius/sin(deg_to_rad(19.0))*1.15
	var medium:=near_distance*1.8;var far:=near_distance*3.0
	var nodes:Array=[];gather(scene,nodes);var foliage:=false;var cloths:Array=[]
	for n:Node in nodes:
		if not n is MeshInstance3D:continue
		var extra:Dictionary=n.get_meta("extras",{});foliage=foliage or extra.has("rmmo_leaf_backlight")
		if extra.get("rmmo_wind",{}).get("profile","")=="cloth":cloths.append(n)
		var begin:float=n.visibility_range_begin
		if begin>0:far=maxf(far,begin*1.08)
	var direction:=Vector3(1,.32,1.6).normalized()
	var result:Array=[]
	for pair in [["near",near_distance],["medium",medium],["far",far]]:
		result.append({"name":pair[0],"eye":vec(centre+direction*pair[1]),"aim":vec(centre),"fov":38.0,"projection":"perspective"})
	var detail_centre:=centre+Vector3(0,bounds.size.y*.22,0)
	var detail_span:=maxf(.5,minf(bounds.size.y*.32,maxf(bounds.size.x,bounds.size.z)*.55))
	var detail_direction:=direction
	if not cloths.is_empty() or detail_mode=="pennant":
		# A complete single flag fills ~700 px vertically at 1000 px output.
		# The smallest mesh containing the full authored flag avoids the group's
		# broad bridge-span bounds. Its thinnest local axis supplies the face view.
		var chosen:MeshInstance3D=null;var chosen_score:=INF
		for n:MeshInstance3D in cloths:
			var score:float=n.get_aabb().size.length()
			if score<chosen_score:chosen=n;chosen_score=score
		if chosen!=null:
			var t:=Transform3D.IDENTITY;var current:Node=chosen
			while current!=null:
				if current is Node3D:t=current.transform*t
				if current==scene:break
				current=current.get_parent()
			var b:AABB=chosen.get_aabb();detail_centre=t*b.get_center();var thin:=0
			if b.size.y<b.size[thin]:thin=1
			if b.size.z<b.size[thin]:thin=2
			var axis:=Vector3.ZERO;axis[thin]=1;detail_direction=(t.basis*axis).normalized()
			var world_bounds:AABB=t*b;detail_span=maxf(world_bounds.size.y,maxf(world_bounds.size.x,world_bounds.size.z))*.72
			# At 38deg FOV this gives a full flag about 70% of image height.
			detail_span=maxf(.35,detail_span)
	result.append({"name":"flag_detail" if not cloths.is_empty() or detail_mode=="pennant" else "leaf_detail" if foliage else "detail","eye":vec(detail_centre+detail_direction*detail_span/tan(deg_to_rad(19))),"aim":vec(detail_centre),"fov":38.0,"projection":"perspective"})
	return result
func prepare_review_state(_state:GLTFState)->void:pass
func prepare_render_scene(_scene:Node,_viewport:SubViewport,_camera:Camera3D)->void:pass
func draw_scene(scene:Node,views:Array)->void:
	root.size=dimensions
	var viewport:=SubViewport.new();viewport.size=dimensions;viewport.own_world_3d=true;viewport.use_taa=false;viewport.msaa_3d=Viewport.MSAA_4X;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport);viewport.add_child(scene)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.14,.17,.20)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65
	environment.environment.tonemap_mode=Environment.TONE_MAPPER_ACES;environment.environment.tonemap_exposure=1.0
	viewport.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-28,0);sun.light_energy=1.5;sun.shadow_enabled=true;sun.directional_shadow_max_distance=500;viewport.add_child(sun)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.current=true;camera.near=.03;camera.far=2000
	prepare_render_scene(scene,viewport,camera)
	var winds:Array=[];var nodes:Array=[];gather(scene,nodes)
	for n:Node in nodes:
		if not n is MeshInstance3D or n.mesh==null:continue
		var config:Dictionary=n.get_meta("extras",{}).get("rmmo_wind",{})
		if config.is_empty() or config.get("profile","off")=="off":continue
		for slot in n.mesh.get_surface_count():
			var original:=n.get_active_material(slot) as StandardMaterial3D
			if not check(original!=null,"wind source StandardMaterial3D"):continue
			var material:ShaderMaterial=Wind.make(original,config,n.get_aabb());n.set_surface_override_material(slot,material);winds.append(material)
	report.wind_surface_count=winds.size();report.screenshots=[]
	for view:Dictionary in views:
		camera.position=vector(view.eye);camera.fov=view.fov;camera.look_at(vector(view.aim))
		var poses:Array=[{"name":"still","velocity":Vector3.ZERO,"time":0.0}]
		if str(view.name)=="banner_detail":poses.append_array([{"name":"wind_t1","velocity":Vector3(3,0,1),"time":1.0},{"name":"wind_t4","velocity":Vector3(3,0,1),"time":4.0}])
		for pose:Dictionary in poses:
			for mat:ShaderMaterial in winds:mat.set_shader_parameter("wind_velocity",pose.velocity);mat.set_shader_parameter("wind_time",pose.time)
			for frame in 8:await process_frame;await RenderingServer.frame_post_draw
			var im:Image=viewport.get_texture().get_image();var filename:String=str(view.name)+"_"+str(pose.name)+".png"
			check(im.save_png(out.path_join(case_name).path_join(filename))==OK,"PNG "+filename)
			var rid:=viewport.get_viewport_rid()
			report.screenshots.append({"name":filename,"pixels":normalized_image(im),"draw_calls":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),"rendered_primitives":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),"rendered_objects":RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),"global_texture_memory_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)})
	viewport.queue_free();await process_frame;Drainer.synchronize_transfer()
func image_difference(a_path:String,b_path:String)->Dictionary:
	var a:=Image.load_from_file(a_path);var b:=Image.load_from_file(b_path)
	if a==null or b==null or a.get_size()!=b.get_size():return {"valid":false}
	a.convert(Image.FORMAT_RGBA8);b.convert(Image.FORMAT_RGBA8)
	var aa:=a.get_data();var bb:=b.get_data();var total:=0;var maximum:=0;var changed_pixels:=0;var over4:=0
	for pixel in a.get_width()*a.get_height():
		var peak:=0
		for c in 3:
			var delta:=absi(int(aa[pixel*4+c])-int(bb[pixel*4+c]));total+=delta;peak=maxi(peak,delta)
		maximum=maxi(maximum,peak)
		if peak>0:changed_pixels+=1
		if peak>4:over4+=1
	var count:=a.get_width()*a.get_height()
	return {"valid":true,"width":a.get_width(),"height":a.get_height(),"rgb_mae_8bit":float(total)/(count*3),"maximum_8bit":maximum,"changed_pixel_fraction":float(changed_pixels)/count,"over_4_fraction":float(over4)/count,"exact":aa==bb}
func compare_reports()->void:
	var a:=read_json(out.path_join("baseline.json"));var b:=read_json(out.path_join("candidate.json"))
	if not check(a.get("passed",false) and b.get("passed",false),"both isolated case reports passed"):finish();return
	check(a.get("original_sha")==FileAccess.get_sha256(source),"baseline report matches current source SHA")
	check(b.get("original_sha")==FileAccess.get_sha256(candidate),"candidate report matches current candidate SHA")
	check(a.get("camera_views")==b.get("camera_views") and a.get("dimensions")==b.get("dimensions"),"same camera, image size, and framing")
	report.semantic_exact=stable(a.semantic)==stable(b.semantic)
	report.nontexture_semantic_exact=stable(strip_textures(a.semantic))==stable(strip_textures(b.semantic))
	check(report.nontexture_semantic_exact,"node/mesh/material non-texture semantics identical")
	if not allow_texture_change:check(report.semantic_exact,"all normalized texture pixels identical")
	report.texture_changes_allowed=allow_texture_change;report.images=[]
	for shot:Dictionary in a.screenshots:
		var filename:String=shot.name
		var delta:=image_difference(out.path_join("baseline").path_join(filename),out.path_join("candidate").path_join(filename))
		delta.name=filename;report.images.append(delta);check(delta.get("valid",false),"paired image "+filename)
		if not allow_texture_change:check(delta.get("exact",false),"lossless pixel equality "+filename)
	report.baseline_native=a.get("native",{});report.candidate_native=b.get("native",{})
	report.baseline_source_bytes=a.get("source_bytes");report.candidate_source_bytes=b.get("source_bytes")
	report.note="Image error is an A/B measurement, not automatic artistic approval. Footprint estimates are conservative admission budgets, not measured RSS/VRAM."
	finish()
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=").replace("\\","/").simplify_path()
		elif arg.begins_with("--candidate="):candidate=arg.trim_prefix("--candidate=").replace("\\","/").simplify_path()
		elif arg.begins_with("--out="):out=arg.trim_prefix("--out=").replace("\\","/").simplify_path().trim_suffix("/")
		elif arg.begins_with("--case="):case_name=arg.trim_prefix("--case=")
		elif arg=="--allow-texture-change":allow_texture_change=true
		elif arg.begins_with("--detail="):detail_mode=arg.trim_prefix("--detail=")
		elif arg.begins_with("--width="):dimensions.x=clampi(int(arg.trim_prefix("--width=")),640,2400)
		elif arg.begins_with("--height="):dimensions.y=clampi(int(arg.trim_prefix("--height=")),640,1800)
	var safe_out:=out.to_lower().begins_with("d:/code/rmmo_runtime/review_artifacts/axel_guild_finish_20261012/") or out.to_lower().begins_with("d:/code/rmmo_runtime/art_sources/axel_guild/finish_v1/")
	if not safe_out or case_name not in ["baseline","candidate","compare"] or not FileAccess.file_exists(source) or not FileAccess.file_exists(candidate):push_error("Invalid source/candidate/case or output outside isolated review roots");quit(2);return
	DirAccess.make_dir_recursive_absolute(out)
	if case_name=="compare":compare_reports();return
	if not check(DisplayServer.get_name()!="headless","graphics process required (private desktop wrapper)"):finish();return
	var original:String=source if case_name=="baseline" else candidate;var digest:=FileAccess.get_sha256(original)
	report.case_name=case_name;report.original=original;report.original_sha=digest;report.source_bytes=size_of(original);report.dimensions=[dimensions.x,dimensions.y]
	report.raw_admission_estimate=Estimate.estimate(original)
	var case_out:=out.path_join(case_name);var isolated:=case_out.path_join("isolated_content");var local_source:=isolated.path_join("assets/review.glb")
	DirAccess.make_dir_recursive_absolute(local_source.get_base_dir())
	if not check(DirAccess.copy_absolute(original,local_source)==OK,"copy immutable test GLB into isolated root"):finish();return
	check(FileAccess.get_sha256(local_source)==digest,"isolated source byte identity")
	var document:=GLTFDocument.new();var state:=GLTFState.new();var began:=Time.get_ticks_usec()
	if not check(document.append_from_file(local_source,state,0,local_source.get_base_dir())==OK,"raw GLTF import"):finish();return
	report.raw_append_us=Time.get_ticks_usec()-began;report.decoded_image_entries=state.images.size()
	prepare_review_state(state)
	var scene:Node=Io.generate_scene(document,state)
	if not check(scene!=null,"production scene postprocessing"):finish();return
	for figure:Node in scene.find_children("60_*", "Node3D", true, false):
		figure.get_parent().remove_child(figure);figure.free()
	report.semantic=inspect(scene);report.semantic_sha256=sha(stable(report.semantic).to_utf8_buffer())
	report.texture_resource_count=textures.size();report.material_resource_count=materials.size()
	var bounds:=scene_bounds(scene);report.bounds={"position":vec(bounds.position),"size":vec(bounds.size)}
	var views:Array=[];var views_path:=out.path_join("camera_views.json")
	if case_name=="baseline":
		views=[
			{"name":"near","eye":[43,23,31],"aim":[16,5,-6],"fov":45.0},
			{"name":"medium","eye":[54,31,47],"aim":[16,5,-6],"fov":45.0},
			{"name":"far","eye":[82,43,80],"aim":[16,5,-6],"fov":45.0},
			{"name":"roof_detail","eye":[21,15,11],"aim":[16,9,-.6],"fov":45.0},
			{"name":"roof_side","eye":[23,14,-1],"aim":[16,11.5,-2.8],"fov":50.0},
			{"name":"roof_top","eye":[16,24,-2],"aim":[16,10,-3],"fov":60.0},
			{"name":"banner_detail","eye":[19.8,7.7,8.6],"aim":[16,6.5,1.5],"fov":43.0},
			{"name":"bracket_side","eye":[21,7.2,1],"aim":[17.1,7.4,1],"fov":58.0},
			{"name":"entrance_detail","eye":[20,3.7,9],"aim":[16,1.6,0],"fov":51.0},
			{"name":"rose_detail","eye":[17.6,10.2,5],"aim":[16,9.4,.475],"fov":43.0},
			{"name":"fanlight_detail","eye":[24.5,2.5,-7.3],"aim":[24.65,2.9,-10.9],"fov":38.0},
			{"name":"hall","eye":[29,1.7,-2.3],"aim":[7,3.8,-8],"fov":76.0},
			{"name":"reception","eye":[27.5,2.1,-4.5],"aim":[23.8,2,-9.3],"fov":76.0},
			{"name":"rear","eye":[-14,22,-38],"aim":[16,5,-6],"fov":45.0}
		]
		if detail_mode=="prop":
			views=create_views(scene,bounds)
			views.append({"name":"back","eye":[-2,1.8,-3],"aim":[0,1.1,0],"fov":40.0})
		put(views_path,{"source_sha":FileAccess.get_sha256(source),"dimensions":report.dimensions,"views":views})
	else:
		var saved:=read_json(views_path)
		var saved_dimensions:Array=saved.get("dimensions",[])
		var same_dimensions:bool=saved_dimensions.size()==2 and int(saved_dimensions[0])==dimensions.x and int(saved_dimensions[1])==dimensions.y
		if not check(saved.get("source_sha")==FileAccess.get_sha256(source) and same_dimensions,"baseline camera specification exists and matches source"):scene.free();finish();return
		views=saved.get("views",[])
	report.camera_views=views
	own(scene,scene);var packed:=PackedScene.new()
	if not check(packed.pack(scene)==OK and Compiled._valid_packed(packed),"packed product passes production schema validator"):scene.free();finish();return
	var folder:String=Compiled.directory(isolated);DirAccess.make_dir_recursive_absolute(folder)
	var draft:=folder.path_join("review_build.scn")
	if not check(ResourceSaver.save(packed,draft,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK,"isolated compressed SCN save"):scene.free();finish();return
	scene.free();scene=null;packed=null;state=null;document=null;Drainer.synchronize_transfer()
	var payload_sha:=FileAccess.get_sha256(draft);var payload:=folder.path_join(payload_sha+".scn")
	if FileAccess.file_exists(payload):check(FileAccess.get_sha256(payload)==payload_sha,"existing isolated payload identity");DirAccess.remove_absolute(draft)
	else:check(DirAccess.rename_absolute(draft,payload)==OK,"publish isolated content-addressed SCN")
	check(ResourceLoader.get_dependencies(payload).is_empty(),"SCN has no external dependencies")
	var manifest:Dictionary={"version":Compiled.VERSION,"generator":Compiled.generator(),"source_sha":digest,"payload_sha":payload_sha,"bytes":size_of(payload)}
	check(put(Compiled.index_path(local_source,isolated),manifest),"write only isolated compiled manifest")
	var loaded:Dictionary=Compiled.read(local_source,digest,isolated)
	if not check(loaded.get("hit",false),"production Compiled.read accepts isolated product: "+str(loaded.get("reason",""))):finish();return
	packed=loaded.packed
	check(packed.get_meta("compiled_asset_validated",false),"validated flag set by real compiled reader")
	var stats:Dictionary=Footprint.measure(packed);stats.native_uncompressed_bytes=Footprint.native_uncompressed_bytes(payload)
	var estimated:Dictionary=Footprint.estimate_stats(stats)
	check(not estimated.is_empty(),"real Footprint.measure plus native uncompressed header produces valid estimate")
	scene=packed.instantiate();var restored:=inspect(scene)
	check(stable(restored)==stable(report.semantic),"saved/reopened SCN semantic equality")
	report.native={"content_root":isolated,"source":local_source,"payload":payload,"payload_sha256":payload_sha,"native_bytes":size_of(payload),"stats":stats,"estimate":estimated,"packed_validated":true}
	scene.free();scene=null;loaded.clear();packed=null;Drainer.synchronize_transfer()
	var build:Dictionary=Footprint.build(local_source,isolated)
	check(build.get("ok",false),"production Footprint.build with explicit isolated root: "+str(build.get("reason","")))
	var footprint_candidate:Dictionary=Footprint.candidate(local_source,isolated,digest)
	check(not footprint_candidate.is_empty(),"published isolated footprint candidate verifies")
	report.native.footprint_build=build;report.native.footprint_candidate=footprint_candidate
	var prepared:Dictionary=Preparation.read(local_source,footprint_candidate,isolated)
	if not check(prepared.get("error",FAILED)==OK and not prepared.get("fallback_required",false) and prepared.get("packed")!=null,"production footprint native preparation accepts exact candidate"):finish();return
	packed=prepared.packed;scene=packed.instantiate()
	check(stable(inspect(scene))==stable(report.semantic),"footprint preparation scene preserves semantic identity")
	prepared.clear();packed=null;Drainer.synchronize_transfer()
	await draw_scene(scene,views)
	check(FileAccess.get_sha256(original)==digest and FileAccess.get_sha256(local_source)==digest,"original and isolated source hashes unchanged")
	finish()
