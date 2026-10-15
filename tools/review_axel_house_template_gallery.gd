extends SceneTree
## Isolated exterior review of the exact prepared native templates.
const Doc=preload("res://scripts/world3d/world_document.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
const GALLERY=OUT+"/template_gallery_20261015"
const CACHE="D:/code/rmmo_runtime/cache/world3d/axel_template_gallery_20261015"
var gallery:=GALLERY
var report:Dictionary={"items":[],"failures":0,"visual_acceptance":"pending actual image review","render":{"size":[1400,1000],"exposure":1.0,"sun_rotation":[-38,-35,0],"sun_energy":1.1,"ambient_energy":.45,"msaa":"4x","tonemap":"ACES"}}
var camera:Camera3D
func _init()->void:call_deferred("run")
func put()->void:
	FileAccess.open(gallery+"/capture.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
func capture(folder:String,label:String,at:Vector3,target:Vector3,extent:float)->Dictionary:
	camera.position=at;camera.look_at(target);camera.size=extent
	for i in 24:await process_frame
	await RenderingServer.frame_post_draw
	var path:=folder+"/"+label+".png"
	var err:=root.get_texture().get_image().save_png(path)
	return {"path":path,"capture_ok":err==OK,"position":[at.x,at.y,at.z],"target":[target.x,target.y,target.z],"orthographic_size":extent,"visual":"pending"}
func run()->void:
	DirAccess.make_dir_recursive_absolute(GALLERY)
	var only:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):only=arg.trim_prefix("--only=")
		if arg.begins_with("--label="):gallery=GALLERY+"_"+arg.trim_prefix("--label=")
	DirAccess.make_dir_recursive_absolute(gallery)
	if not only.is_empty() and FileAccess.file_exists(gallery+"/capture.json"):
		report=JSON.parse_string(FileAccess.get_file_as_string(gallery+"/capture.json"));report.items=report.items.filter(func(i):return not str(i.template_id) in only.split(","));report.failures=0;report.complete=false
	root.size=Vector2i(1400,1000);root.msaa_3d=Viewport.MSAA_4X;root.use_taa=true
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.19,.23,.28)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.85,.88,.92);env.ambient_light_energy=.45
	env.tonemap_mode=Environment.TONE_MAPPER_ACES;env.tonemap_exposure=1.;env.ssao_enabled=true
	var environment:=WorldEnvironment.new();environment.environment=env;root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-35,0);sun.light_energy=1.1;sun.shadow_enabled=true;root.add_child(sun)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true;root.add_child(camera)
	var index:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/house_templates.json"));var used:Dictionary={}
	for filename:String in ["house_plan_s1_s2.json","house_plan_s10_s12.json"]:
		var plan:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/"+filename))
		for h:Dictionary in plan.houses:used[h.template_id]=true
	for template:Dictionary in index.templates:
		if not used.has(template.id):continue
		if not only.is_empty() and not str(template.id) in only.split(","):continue
		var folder:String=gallery+"/"+str(template.id);DirAccess.make_dir_recursive_absolute(folder)
		var loaded:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(template.loaded_path))
		var doc=Doc.new();doc.records=loaded.records;doc.map_meta.building_instances=loaded.building_instances;doc._next=990000
		var ground_id:String=doc.add_box("ground",Vector3(0,-.2,0),Vector3(180,.4,180))
		for r:Dictionary in doc.records:
			if r.uuid==ground_id:r.color=[.31,.35,.27]
		var path:String=CACHE+"/"+str(template.id)+"/map.gltf";DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var saved:Error=doc.save(path)
		var reopened=Doc.open_file(path) if saved==OK else null
		var item:Dictionary={"template_id":template.id,"template_sha256":FileAccess.get_sha256(template.loaded_path),"native_path":path,"native_sha256":FileAccess.get_sha256(path) if saved==OK else "","save_ok":saved==OK,"reopen_ok":reopened!=null,"images":[]}
		if reopened==null:report.failures+=1;report.items.append(item);put();continue
		item.records_before=doc.records.size();item.records_after=reopened.records.size();item.ownership_preserved=reopened.map_meta.get("building_instances",{}).keys()==loaded.building_instances.keys()
		if item.records_before!=item.records_after or not item.ownership_preserved:report.failures+=1
		var view:Node3D=reopened.build();root.add_child(view)
		var p:Dictionary=template.parameters;var height:float=float(p.floors)*float(p.floor_height)+float(p.width)*.35
		var extent:float=maxf(float(p.width),maxf(float(p.depth),height))*1.5
		item.images.append(await capture(folder,"near",Vector3(20,12,-25),Vector3(0,height*.42,0),extent))
		item.images.append(await capture(folder,"middle",Vector3(20,12,-25),Vector3(0,height*.42,0),extent*1.6))
		item.images.append(await capture(folder,"far",Vector3(20,12,-25),Vector3(0,height*.42,0),extent*2.7))
		item.images.append(await capture(folder,"roof_detail",Vector3(13,height+7,-13),Vector3(0,float(p.floors)*float(p.floor_height)+1,0),float(p.width)*1.15))
		var detail_target:=Vector3(-float(p.width)/2+1.2,2,-float(p.depth)/2)
		var detail_extent:=6.0
		if template.id=="s2_oculus_home":detail_target=Vector3(0,float(p.floor_height)+2,-float(p.depth)/2);detail_extent=6
		if template.id=="s12_arch_hall":detail_target=Vector3(-3.88,2.6,-float(p.depth)/2);detail_extent=7
		item.images.append(await capture(folder,"front_detail",detail_target+Vector3(3,1,-12),detail_target,detail_extent))
		report.items.append(item);put();print("TEMPLATE_CAPTURED ",template.id)
		view.free();await process_frame
	report.complete=true;put();quit(int(report.failures))
