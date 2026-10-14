extends "res://tools/review_axel_guild_finish.gd"
var destination:="D:/code/rmmo/review_artifacts/axel_guild_finish_20261012/repair_review"
var evidence_path:=""
var source_path:=""
var isolated_content_root:=""
const Components=preload("res://scripts/world3d/model_components.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
class TestWeather extends Node:
	var values:Dictionary={"time_hours":22.0}
	var night_sky:Dictionary={"ready":false}
func runtime_identity()->Dictionary:
	var result:Dictionary={}
	for file:String in ["model_components.gd","building_fixtures.gd","streetlamp_lights.gd","world_stream.gd","runtime_mesh_cache.gd"]:
		result[file]=FileAccess.get_sha256("res://scripts/world3d/"+file)
	return result
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--syntax-only":print("GUILD_RUNTIME syntax only");quit();return
		if arg.begins_with("--out="):destination=arg.trim_prefix("--out=")
		if arg.begins_with("--evidence="):evidence_path=arg.trim_prefix("--evidence=")
		if arg.begins_with("--source="):source_path=arg.trim_prefix("--source=")
		if arg.begins_with("--content-root="):isolated_content_root=arg.trim_prefix("--content-root=")
	out=destination;case_name="runtime";DirAccess.make_dir_recursive_absolute(out)
	if not isolated_content_root.is_empty():
		var paths=preload("res://scripts/world3d/map_paths.gd")
		if not check(paths.allowed(isolated_content_root) and isolated_content_root.get_file().begins_with("guild_reference_native_scope_") and DirAccess.dir_exists_absolute(isolated_content_root),"confined isolated import content root"):finish();return
		root.get_node("AssetManager").content_root_override=isolated_content_root
		check(paths.external_root()==isolated_content_root,"runtime reuses exact imported content scope")
		report.content_root=isolated_content_root
	var packed:PackedScene
	var evidence:Dictionary={}
	if not source_path.is_empty():
		var compiled:=Compiled.read(source_path)
		check(compiled.get("hit",false),"current production native identity hit")
		if not compiled.get("hit",false):Drainer.dispose_result(compiled);finish();return
		packed=compiled.packed
		evidence={"original_sha":FileAccess.get_sha256(source_path),"path":source_path,"generator":Compiled.generator(),"identity":JSON.parse_string(FileAccess.get_file_as_string(Compiled.index_path(source_path)))}
	else:
		if evidence_path.is_empty():evidence_path=destination+"/final_building/baseline.json"
		evidence=read_json(evidence_path)
		if not evidence.get("native") is Dictionary or not evidence.native.get("payload") is String:check(false,"valid native evidence");finish();return
		packed=ResourceLoader.load(evidence.native.payload,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
	check(packed!=null,"review native reopen")
	if packed==null:finish();return
	report.input_evidence=evidence
	report.runtime_implementation={}
	for path in ['model_components.gd','runtime_mesh_cache.gd','streetlamp_lights.gd','building_fixtures.gd']:
		report.runtime_implementation[path]=FileAccess.get_sha256('res://scripts/world3d/'+path)
	report.runtime_implementation=runtime_identity()
	var doc:=preload("res://scripts/world3d/world_document.gd").new()
	var holder:Node3D=doc._asset({"kind":"asset","uuid":"guild_runtime","position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}, {"scene":packed.instantiate()})
	root.add_child(holder)
	var visual_map:Dictionary={};var bodies:Dictionary={};var specs:Array=[]
	for mesh:MeshInstance3D in holder.find_children("*","MeshInstance3D",true,false):
		var extra:Dictionary=mesh.get_meta("extras",{})
		if extra.get("semantic_group","") in ["11_Exterior_Upper","30_Rooms_L1"] and not str(mesh.name).contains("glazing"):
			var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=mesh.mesh.create_trimesh_shape();body.add_child(shape);mesh.add_child(body)
			body.set_meta("mesh_path",str(holder.get_path_to(mesh)))
		if not extra.has("fixture"):continue
		var id:String=extra.uuid
		var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=mesh.mesh.create_trimesh_shape();body.add_child(shape);root.add_child(body);body.global_transform=mesh.global_transform
		visual_map[id]=mesh;bodies[id]=body
		var spec:={"uuid":id,"extras":extra,"transform":mesh.global_transform,"mesh":mesh.mesh}
		Fixtures.prepare_spec(spec);specs.append(spec)
	holder.set_meta("stream_library",specs);holder.set_meta("stream_meshes",visual_map);holder.set_meta("stream_bodies",bodies)
	var rows:=Fixtures.list_runtime(holder,"guild_runtime")
	report.component_count=rows.size();report.moving_meshes=specs.size()
	var cabinet_rows:Array=rows.filter(func(r):return not str(r.id).contains("architecture:"))
	check(cabinet_rows.size()==24,"fourteen cabinets have 24 independently operated leaves")
	var original:Dictionary={}
	for spec:Dictionary in specs:original[spec.uuid]=spec.transform
	for row:Dictionary in rows:
		var original_amount:float=row.open
		var untouched:Dictionary={};var closed:Dictionary={}
		for id in visual_map:
			if not id in row.members:untouched[id]=visual_map[id].global_transform
		for amount in [0.0,.5,1.0,original_amount]:
			check(Fixtures.set_runtime(holder,"guild_runtime",row.id,amount,0).ok,"runtime hinge "+row.id+" "+str(amount))
			var changed:=false
			for id:String in row.members:
				check(visual_map[id].global_transform.is_equal_approx(bodies[id].global_transform),"active collision matches moving part")
				if amount==0:closed[id]=visual_map[id].global_transform
				elif not visual_map[id].global_transform.is_equal_approx(closed[id]):changed=true
			if amount==.5 or amount==1:check(changed,"hinge truly moves from closed "+str(row.id))
			for id in untouched:check(visual_map[id].global_transform.is_equal_approx(untouched[id]),"unrelated hinge remains fixed")
	for spec:Dictionary in specs:check(spec.transform.is_equal_approx(original[spec.uuid]),"roundtrip restores authored pose")
	for frame in 3:await physics_frame
	report.apertures=[]
	for probe in [["203 east",Vector3(31.2,6.2,-3.7),Vector3(32.5,6.2,-3.7)],["204 east",Vector3(31.2,6.2,-6.7),Vector3(32.5,6.2,-6.7)],["wash east",Vector3(31.2,6.2,-10.8),Vector3(32.5,6.2,-10.8)],["wash rear",Vector3(29.7,6.2,-13.2),Vector3(29.7,6.2,-14.5)]]:
		var hit:=root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(probe[1],probe[2]))
		report.apertures.append({"name":probe[0],"blocked":not hit.is_empty()});check(hit.is_empty(),"through window aperture "+probe[0])
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.025,.035,.06)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.045;env.environment.tonemap_mode=Environment.TONE_MAPPER_ACES;root.add_child(env)
	var cam:=Camera3D.new();root.add_child(cam);cam.current=true;cam.position=Vector3(26,1.8,-2.3);cam.look_at(Vector3(8,2.5,-8));cam.fov=72
	var weather:=TestWeather.new();root.add_child(weather)
	var lights:=preload("res://scripts/world3d/streetlamp_lights.gd").new();root.add_child(lights);lights.weather=weather;lights.camera=cam;lights.refresh()
	report.light_sockets=lights.fixtures.size()
	var magic_stones:=0
	for mesh:MeshInstance3D in holder.find_children('*','MeshInstance3D',true,false):
		if mesh.mesh==null:continue
		for slot in mesh.mesh.get_surface_count():
			var mat:=mesh.get_active_material(slot)
			if mat!=null and mat.resource_name=='Guild warm white floating magic stone':
				magic_stones+=1
				check(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,'magic stone does not shadow its own socket')
	check(magic_stones==8,'six hall plus two exterior magic stones retain authored material')
	report.magic_stone_self_shadow_exclusions=magic_stones
	check(lights.fixtures.size()==16,"six hall, eight candle and two facade lights registered")
	check(lights.fixtures.values().filter(func(r):return r.glow.mesh!=null).size()==8,"eight candle flames reuse existing effect")
	for frame in 12:await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination+"/hall_night.png")
	report.lit_lights=lights.lights.filter(func(l):return l.visible).size()
	check(report.lit_lights>0 and report.lit_lights<=6,"real nearby lights obey six-light budget")
	check(lights.lights.filter(func(l):return l.visible and l.shadow_enabled).size()<=2,"shadow budget bounded")
	weather.values.time_hours=12.0;lights.refresh()
	check(lights.fixtures.values().filter(func(r):return not r.node.get_ref().get_meta("extras").rmmo_model_light.indoor and r.light.visible).is_empty(),"facade lights switch off by day")
	cam.position=Vector3(28.0,6.15,-1.0);cam.look_at(Vector3(30.3,5.5,-3.5));lights.refresh()
	for frame in 12:await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination+"/guest_lighting.png")
	report.source_sha=evidence.original_sha
	check(stable(report.runtime_implementation)==stable(runtime_identity()),"runtime implementation unchanged during verification")
	finish()
