extends "res://tools/review_guild_full_batch.gd"
## Candidate-only production native compilation and rendering in an isolated content root.
const Components=preload("res://scripts/world3d/model_components.gd")
const Imported=preload("res://scripts/world3d/imported_building.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const Lamps=preload("res://scripts/world3d/streetlamp_lights.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var asset_kind:="church"
var expected_sha:=""
var fixture_root:=""
var physics_only:=false
var requested_views:PackedStringArray=[]
var vp:SubViewport
var camera_:Camera3D
var lights_:Node3D
var body_map:Dictionary={}
class ReviewWeather extends Node:
	var values:Dictionary={"time_hours":12.0}
	var night_sky:Dictionary={"ready":false}

func close_report()->void:
	report.passed=report.failures.is_empty()
	put(out.path_join("report.json"),report)
	print("AXEL_LANDMARK_REVIEW ",asset_kind," passed=",report.passed)
	quit(0 if report.passed else 1)

func runtime_nodes(scene:Node3D,descriptor:Dictionary)->void:
	var record:={"kind":"asset","uuid":"review_"+asset_kind,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"model_building":descriptor.duplicate(true)}
	record.model_building.source_sha=expected_sha
	Components.apply(scene,record)
	check(not scene.has_meta("model_components_error"),"authored building accepted by production consumer")
	var specs:Array=[];var visuals:Dictionary={};body_map={}
	for n:MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
		var e:Dictionary=n.get_meta("extras",{})
		Lamps.register(n)
		if e.get("rmmo_collision","none") in ["block","walk"]:
			var body:=StaticBody3D.new();var shape:=CollisionShape3D.new()
			shape.shape=n.mesh.create_trimesh_shape();body.add_child(shape);vp.add_child(body);body.global_transform=n.global_transform
			body.set_meta("source_part",e.get("rmmo_part",{}));body_map[e.uuid]=body
		if e.has("fixture"):
			var spec:={"uuid":e.uuid,"extras":e,"transform":n.global_transform,"mesh":n.mesh}
			Fixtures.prepare_spec(spec);specs.append(spec);visuals[e.uuid]=n
	scene.set_meta("stream_library",specs);scene.set_meta("stream_meshes",visuals);scene.set_meta("stream_bodies",body_map)
	report.fixtures=Fixtures.list_runtime(scene,record.uuid)
	report.collider_meshes=body_map.size()
	for row:Dictionary in report.fixtures:
		var closed:Dictionary={}
		for id:String in row.members:closed[id]=visuals[id].global_transform
		for amount:float in [0.5,1.0,0.0]:
			check(Fixtures.set_runtime(scene,record.uuid,row.id,amount,0).ok,"hinge state "+row.id+" "+str(amount))
			for id:String in row.members:
				check(visuals[id].global_transform.is_equal_approx(body_map[id].global_transform),"hinge moving collision "+id)
				check(visuals[id].global_transform.is_equal_approx(closed[id]) if amount==0 else not visuals[id].global_transform.is_equal_approx(closed[id]),"hinge pose "+id+" "+str(amount))

func doors(scene:Node3D,amount:float)->void:
	for row:Dictionary in report.fixtures:Fixtures.set_runtime(scene,"review_"+asset_kind,row.id,amount,0)

func physics_checks(scene:Node3D)->void:
	report.physics_completed=false
	doors(scene,1.0)
	for f in 4:await physics_frame
	var approaches:Array=[]
	if asset_kind=="church":approaches=[["main",Vector3(0,.3,11.24),Vector3(0,0,1),.48],["tower_side",Vector3(-10.84,.3,-4.85),Vector3(-1,0,0),.25]]
	elif asset_kind=="guardhouse":approaches=[["main",Vector3(0,.3,5),Vector3(0,0,1),.42],["rear",Vector3(3.7,.3,-5),Vector3(0,0,-1),.2]]
	else:approaches=[["main",Vector3(-1.5,0,5.4),Vector3(0,0,1),.45],["rear",Vector3(-2.2,0,-5.4),Vector3(0,0,-1),.25]]
	report.portal_checks=[]
	for entry in approaches:
		var side:Vector3=entry[2].cross(Vector3.UP)
		for dx:float in [-float(entry[3]),0.0,float(entry[3])]:
			for h:float in [.45,1.25,2.1]:
				var center:Vector3=entry[1]+side*dx+Vector3.UP*h
				var q:=PhysicsRayQueryParameters3D.create(center+entry[2]*.85,center-entry[2]*.85)
				q.hit_back_faces=true
				var hit:=scene.get_world_3d().direct_space_state.intersect_ray(q)
				var row:={"portal":entry[0],"height":h,"offset":dx,"blocked":not hit.is_empty()}
				if not hit.is_empty():row.part=hit.collider.get_meta("source_part",{})
				report.portal_checks.append(row);check(hit.is_empty(),"open portal clearance "+str(entry[0])+" "+str(dx)+" "+str(h))
	# This uses the actual native mesh colliders and production hinge operation.
	# It is a sampled aperture check, not a complete character navigation run.
	report.physics_scope="Native mesh trimesh colliders, production Fixtures.set_runtime pose/collider agreement, nine aperture rays per entry. Full controller/map traversal remains separate."
	doors(scene,0.0)
	report.physics_completed=true

func view_specs(bounds:AABB)->Array:
	var c:=bounds.get_center();var distance:=bounds.size.length()*.5/sin(deg_to_rad(24))*1.04
	var views:Array=[]
	var direction:=Vector3(-.70,.38,1.5).normalized()
	for pair in [["near",1.0],["medium",1.7],["far",2.7]]:views.append({"name":pair[0],"eye":vec(c+direction*distance*pair[1]),"aim":vec(c),"fov":48})
	views.append({"name":"back","eye":vec(c+Vector3(.7,.35,-1.5).normalized()*distance),"aim":vec(c),"fov":48})
	if asset_kind=="church":
		views.append_array([
			{"name":"front","eye":[0,8,38],"aim":[-1,8,6],"fov":55},
			{"name":"portal_closed","eye":[4.1,3.3,18.5],"aim":[0,2.1,11.3],"fov":48},
			{"name":"portal_open","eye":[1.8,2.5,17],"aim":[0,1.8,10.5],"fov":58,"open":true},
			{"name":"glass_front","eye":[2.7,13.0,19],"aim":[0,12.9,11.28],"fov":48},
			{"name":"glass_inside","eye":[1.4,12.3,6.8],"aim":[0,13.2,11.26],"fov":64},
			{"name":"lantern_day","eye":[3.15,3.05,13.65],"aim":[1.91,2.7,11.65],"fov":38},
			{"name":"lantern_night","eye":[3.15,3.05,13.65],"aim":[1.91,2.7,11.65],"fov":38,"night":true},
			{"name":"stone_grazing","eye":[3.7,3.4,14.8],"aim":[3.45,2.5,11.24],"fov":39,"grazing":true},
			{"name":"roof_detail","eye":[10.4,19,6],"aim":[3.3,13.8,2.5],"fov":48},
			{"name":"tower_roof","eye":[-20,25,4],"aim":[-7.8,20.4,-6.7],"fov":43},
			{"name":"hall_day","eye":[0,2.1,9.6],"aim":[0,3,-8],"fov":76,"open":true},
			{"name":"hall_night","eye":[0,2.1,9.6],"aim":[0,3,-8],"fov":76,"open":true,"night":true},
			{"name":"cutaway","eye":[-21,31,22],"aim":[-3.6,2.7,0],"fov":55,"cut":true,"open":true},
			{"name":"side_rooms","eye":[-18,16,10],"aim":[-7.5,1.4,2],"fov":55,"cut":true,"open":true},
			{"name":"reception_room","eye":[-8.7,1.9,4.35],"aim":[-8.7,1.1,6.4],"fov":79,"open":true},
			{"name":"staff_room","eye":[-7.2,1.9,-2.3],"aim":[-9.1,1.0,-1.25],"fov":79,"open":true},
			{"name":"office_room","eye":[-7.2,1.9,2.0],"aim":[-9.4,1.0,2.7],"fov":79,"open":true},
			{"name":"tower_stairs","eye":[-9.65,2,-4.75],"aim":[-7,4.1,-7.4],"fov":79,"open":true}
		])
	elif asset_kind=="guardhouse":
		views.append_array([
			{"name":"portal_closed","eye":[4,2.8,13],"aim":[0,2.0,5.1],"fov":48},
			{"name":"portal_open","eye":[1.8,2.3,10],"aim":[0,1.9,4.4],"fov":62,"open":true},
			{"name":"stone_grazing","eye":[4,2.7,8.1],"aim":[4,1.7,5.1],"fov":42,"grazing":true},
			{"name":"roof_detail","eye":[9,11,11],"aim":[2,8.4,2],"fov":48},
			{"name":"eave_joint","eye":[8,7.1,7.4],"aim":[6.3,7.2,4.8],"fov":38},
			{"name":"porch_base","eye":[-4,1.8,8.4],"aim":[0,.45,5.85],"fov":48},
			{"name":"window_detail","eye":[-5.5,6.4,9],"aim":[-3.8,5.5,5.1],"fov":50},
			{"name":"cutaway","eye":[-14,23,20],"aim":[0,2.4,0],"fov":55,"cut":true,"open":true},
			{"name":"ground_interior","eye":[0,2.0,4.1],"aim":[2,1.8,-2.8],"fov":80,"open":true},
			{"name":"upper_interior","eye":[2,5.8,3.5],"aim":[-3,4.8,-1],"fov":80,"open":true},
			{"name":"stairs","eye":[-5.2,2.0,3],"aim":[-4.8,3.7,-2.7],"fov":76,"open":true}
		])
	else:
		views.append_array([
			{"name":"wheel_side","eye":[18,12,21],"aim":[1,3.8,0],"fov":48},
			{"name":"waterwheel","eye":[13,3,7],"aim":[6.85,1.1,0],"fov":54},
			{"name":"bearing_foundation","eye":[12,1.6,3.7],"aim":[8.3,-.3,0],"fov":48},
			{"name":"foundation_rear","eye":[14,2.1,-12],"aim":[3,-.6,-3.1],"fov":50},
			{"name":"portal_closed","eye":[1.7,2.5,12],"aim":[-1.5,1.5,5.4],"fov":48},
			{"name":"portal_open","eye":[-1.0,2.0,10],"aim":[-1.5,1.5,4.5],"fov":62,"open":true},
			{"name":"stone_grazing","eye":[2.5,2.7,8.5],"aim":[2,1.5,5.4],"fov":42,"grazing":true},
			{"name":"roof_detail","eye":[10,11,12],"aim":[2.1,7.9,2.0],"fov":48},
			{"name":"window_detail","eye":[9,5.5,6.5],"aim":[5.4,5.1,3.4],"fov":45},
			{"name":"cutaway","eye":[-13,21,18],"aim":[0,1.5,0],"fov":55,"cut":true,"open":true},
			{"name":"lower_mechanism","eye":[-1.3,2.1,3],"aim":[3.3,1.7,0],"fov":75,"open":true},
			{"name":"upper_millstone","eye":[-1,5.7,3.1],"aim":[1.75,4.8,0],"fov":70,"open":true},
			{"name":"stairs","eye":[-3.94,1.9,4.4],"aim":[-3.94,3.9,-3.3],"fov":72,"open":true},
			{"name":"entry_support","eye":[-1.5,1.6,4.1],"aim":[-2.82,2.0,2.6],"fov":78,"open":true},
			{"name":"entry_to_stairs","eye":[-1.5,2.0,6.6],"aim":[-3.25,1.4,3.35],"fov":78,"open":true},
			{"name":"inner_pier_underside","eye":[-3.7,-2.5,4.7],"aim":[-2.82,-1.1,2.6],"fov":70,"hide_ground":true,"open":true}
		])
	return views

func gallery(scene:Node,folder:String)->void:
	var bounds:=scene_bounds(scene)
	vp=SubViewport.new();vp.size=Vector2i(1440,1080);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=false;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp);vp.add_child(scene)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.16,.20,.23);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.4;env.tonemap_mode=Environment.TONE_MAPPER_ACES;env.tonemap_exposure=1
	var sky_material:=ProceduralSkyMaterial.new();sky_material.sky_top_color=Color(.20,.36,.60);sky_material.sky_horizon_color=Color(.68,.76,.84);sky_material.ground_bottom_color=Color(.12,.15,.13);sky_material.ground_horizon_color=Color(.50,.55,.54)
	var sky:=Sky.new();sky.sky_material=sky_material;env.sky=sky;env.background_mode=Environment.BG_SKY
	env.ssao_enabled=true;env.ssao_radius=1.6;env.ssao_intensity=1.2
	var world:=WorldEnvironment.new();world.environment=env;vp.add_child(world)
	var sun:=DirectionalLight3D.new();sun.light_energy=1.5;sun.shadow_enabled=true;sun.directional_shadow_max_distance=160;vp.add_child(sun)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(180,180);ground.mesh=plane;ground.position.y=bounds.position.y-.02
	var gm:=StandardMaterial3D.new();gm.albedo_color=Color(.21,.24,.21);gm.roughness=1;ground.material_override=gm;vp.add_child(ground)
	camera_=Camera3D.new();camera_.current=true;camera_.near=.03;camera_.far=500;vp.add_child(camera_)
	var weather:=ReviewWeather.new();vp.add_child(weather)
	lights_=Lamps.new();vp.add_child(lights_);lights_.weather=weather;lights_.camera=camera_
	var described:=Imported.describe(scene);check(not described.is_empty(),"production Imported.describe returns full building")
	if described.is_empty():
		var bad:Array=[];var all:Array[Node]=[scene];all.append_array(scene.find_children("*","",true,false))
		for n:Node in all:
			var e:Dictionary=n.get_meta("extras",{})
			if e.has("rmmo_model_components") or (n is MeshInstance3D and not Imported.valid_part(e.get("rmmo_part"))) or e.has("rmmo_hinge"):bad.append({"path":str(scene.get_path_to(n)),"extras":e})
		report.semantic_rejection_diagnostics=bad;vp.remove_child(scene);vp.queue_free();return
	report.building_descriptor=described
	runtime_nodes(scene,described)
	await physics_checks(scene)
	check(report.get("physics_completed",false),"native physics aperture checks completed")
	if physics_only:
		report.gallery_scope="Physics-only follow-up; prior unchanged-source gallery remains separately bound by SHA."
		vp.remove_child(scene);vp.queue_free();await process_frame;return
	report.runtime_materials=[];var seen:Dictionary={}
	for n:MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
		for slot in n.mesh.get_surface_count():
			var mat:Material=n.get_active_material(slot)
			if mat==null or seen.has(mat.get_instance_id()):continue
			seen[mat.get_instance_id()]=true
			var data:={"name":mat.resource_name,"class":mat.get_class()}
			if mat is BaseMaterial3D:
				data.merge({"albedo":var_to_str(mat.albedo_color),"roughness":mat.roughness,"metallic":mat.metallic,"normal_enabled":mat.normal_enabled,"normal_scale":mat.normal_scale,"transparency":mat.transparency,"emission_enabled":mat.emission_enabled,"emission_energy":mat.emission_energy_multiplier})
			elif mat is ShaderMaterial:data.shader_code_sha=sha(mat.shader.code.to_utf8_buffer())
			report.runtime_materials.append(data)
	var views:=view_specs(bounds);report.screenshots=[]
	if not requested_views.is_empty():
		for selected in requested_views:
			check(views.any(func(v):return v.name==selected),"requested gallery view exists: "+selected)
		views=views.filter(func(v):return v.name in requested_views)
		report.gallery_scope="Targeted material recheck; unchanged geometry and other views require explicit previous-version identity evidence."
	report.render_environment={"dimensions":[1440,1080],"renderer":RenderingServer.get_current_rendering_method(),"msaa":4,"taa":false,"exposure":1,"day_sun":1.5,"day_ambient":.4,"sky_reflections":true,"source_identity":expected_sha,"scope":"No characters, isolated neutral studio ground and fixed procedural daylight sky for dielectric/metal reflections. Back view reverses sunlight for material inspection; all values per shot recorded."}
	for v:Dictionary in views:
		var night:bool=v.get("night",false);var cut:bool=v.get("cut",false)
		ground.visible=not v.get("hide_ground",false)
		doors(scene,1.0 if v.get("open",false) else 0.0)
		for n:MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
			var part:Dictionary=n.get_meta("extras",{}).get("rmmo_part",{})
			n.visible=not cut or (part.get("role","") not in ["roof","ceiling"] and int(part.get("floor",0))==0)
		var direction:=Vector3(.65,.8,1).normalized()
		if v.name=="back":direction=Vector3(-.65,.8,-1).normalized()
		if v.get("grazing",false):direction=Vector3(1,.3,.17).normalized()
		sun.position=bounds.get_center()+direction*50;sun.look_at(bounds.get_center());sun.light_energy=.025 if night else 1.5
		env.ambient_light_energy=.04 if night else .4;env.background_color=Color(.008,.012,.025) if night else Color(.16,.20,.23)
		sky_material.sky_energy_multiplier=.035 if night else 1.0;sky_material.ground_energy_multiplier=.035 if night else 1.0
		weather.values.time_hours=22.0 if night else 12.0
		camera_.fov=float(v.fov);camera_.position=vector(v.eye);camera_.look_at(vector(v.aim));lights_.refresh()
		for frame in 10:await process_frame;await RenderingServer.frame_post_draw
		var path:=folder.path_join(str(v.name)+".png")
		check(vp.get_texture().get_image().save_png(path)==OK,"screenshot "+str(v.name))
		var row:Dictionary=v.duplicate(true);row.merge({"path":path,"sha256":FileAccess.get_sha256(path),"sun":sun.light_energy,"ambient":env.ambient_light_energy,"light_direction":vec(direction),"draw_calls_with_ground":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"triangles_with_ground":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"light_sockets":lights_.fixtures.size(),"active_lights":lights_.lights.filter(func(l):return l.visible).size()});report.screenshots.append(row)
		report.gallery_completed=false;put(folder.path_join("report.json"),report)
	report.gallery_completed=true
	vp.remove_child(scene);vp.queue_free();await process_frame

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
		if arg.begins_with("--out="):out=arg.trim_prefix("--out=")
		if arg.begins_with("--kind="):asset_kind=arg.trim_prefix("--kind=")
		if arg.begins_with("--sha="):expected_sha=arg.trim_prefix("--sha=")
		if arg.begins_with("--fixture-root="):fixture_root=arg.trim_prefix("--fixture-root=")
		if arg=="--physics-only":physics_only=true
		if arg.begins_with("--views="):requested_views=arg.trim_prefix("--views=").split(",",false)
	if DisplayServer.get_name()=="headless":print("AXEL_REVIEW_SYNTAX_OK");quit();return
	if not source.begins_with("D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/") or not out.begins_with("D:/code/rmmo_runtime/review_artifacts/axel_landmarks_20261016/") or not fixture_root.begins_with("D:/code/rmmo_runtime/review_fixtures/axel_landmarks_20261016/") or asset_kind not in ["church","guardhouse","watermill"]:push_error("Review scope rejected");quit(2);return
	report={"checks":[],"failures":[],"asset":asset_kind,"identity":{"path":source,"sha256":expected_sha,"bytes":size_of(source)},"engine":Engine.get_version_info(),"scope":"Candidate-only isolated native import/reopen and material/structure gallery. No production catalog/map mutation. Memory figures are measured resource bytes and conservative accounting, never actual process RSS/VRAM."}
	if not check(FileAccess.get_sha256(source)==expected_sha,"exact requested source SHA"):close_report();return
	DirAccess.make_dir_recursive_absolute(out);DirAccess.make_dir_recursive_absolute(fixture_root.path_join("assets"))
	var local_source:=fixture_root.path_join("assets/review.glb")
	if FileAccess.file_exists(local_source):
		if not check(FileAccess.get_sha256(local_source)==expected_sha,"existing isolated source identity"):close_report();return
	else:check(DirAccess.copy_absolute(source,local_source)==OK,"copy immutable candidate into temporary library")
	var manager:=root.get_node("AssetManager");var old_override:String=manager.content_root_override;manager.content_root_override=fixture_root
	if not check(Paths.external_root()==fixture_root,"process-only isolated content root"):close_report();return
	report.runtime_code_sha={}
	for file in ["imported_building.gd","model_components.gd","building_fixtures.gd","streetlamp_lights.gd","tinted_glass.gd","compiled_asset_cache.gd","model_lod_preparation.gd"]:report.runtime_code_sha[file]=FileAccess.get_sha256("res://scripts/world3d/"+file)
	var prepared:=Compiled.prepare_source(local_source)
	if not check(prepared.error==OK,"production parse preparation"):prepared.dispose();close_report();return
	var authored:Node=prepared.get_scene()
	if not check(authored!=null,"production GLTF processing"):prepared.dispose();close_report();return
	var semantic:=inspect(authored);report.semantic_sha256=sha(stable(semantic).to_utf8_buffer());report.triangles=semantic.instance_triangles;report.meshes=semantic.mesh_nodes;report.materials=materials.size();report.textures=textures.size();report.texture_diagnostics=textures.values()
	report.bounds={"position":vec(scene_bounds(authored).position),"size":vec(scene_bounds(authored).size)}
	var build:=Compiled.build_from_prepared(prepared);report.native_build=build;prepared.dispose();authored=null;prepared=null;Drainer.synchronize_transfer()
	if not check(build.get("ok",false),"production native compilation "+str(build.get("reason",""))):close_report();return
	var hit:=Compiled.read(local_source,expected_sha,fixture_root)
	if not check(hit.get("hit",false),"production native reopen "+str(hit.get("reason",""))):Drainer.dispose_result(hit);close_report();return
	var packed:PackedScene=hit.packed;var scene:Node3D=packed.instantiate()
	check(stable(inspect(scene))==stable(semantic),"native geometry/material/extras roundtrip exact")
	scene.free();scene=null;hit.clear();packed=null;Drainer.synchronize_transfer()
	var footprint:=Footprint.build(local_source,fixture_root);report.footprint=footprint
	if not check(footprint.get("ok",false),"production footprint "+str(footprint.get("reason",""))):close_report();return
	var candidate_:Dictionary=Footprint.candidate(local_source,fixture_root,expected_sha)
	var native:Dictionary=Preparation.read(local_source,candidate_,fixture_root)
	if not check(native.get("error",FAILED)==OK and not native.get("fallback_required",false) and native.get("packed")!=null,"actual native prepared resource read"):Drainer.dispose_result(native);close_report();return
	report.compiled_manifest=read_json(Compiled.index_path(local_source,fixture_root));report.isolated_content_root=fixture_root
	packed=native.packed;scene=packed.instantiate();native.clear();packed=null
	check(stable(inspect(scene))==stable(semantic),"production prepared read preserves semantic identity")
	await gallery(scene,out)
	scene.free();scene=null;Drainer.synchronize_transfer()
	check(FileAccess.get_sha256(source)==expected_sha and FileAccess.get_sha256(local_source)==expected_sha,"sources unchanged")
	manager.content_root_override=old_override
	close_report()
