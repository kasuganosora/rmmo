extends SceneTree
## Private-desktop GPU only. Replays saved old/new frozen payloads, never the
## current procedural generator, and never writes either source map.
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Tangents=preload("res://scripts/world3d/mesh_tangent_repair.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const PREP="C:/Users/luna/.codex/skills/rmmo-model-review/scripts/prepare_review_image.py"
const PY="C:/Users/luna/AppData/Local/Programs/Python/Python312/python.exe"
var expected_sha:=""
var after_snapshot:=OUT+"/wall_regenerated_records.json"
var expected_snapshot_sha:=""
var output:=OUT+"/fortification_tangent_ab"
var receipt_path:=OUT+"/fortification_regeneration.json"
var expected_receipt_sha:=""
var plan:Dictionary
var report:Dictionary={"checks":[],"screenshots":[],"subjects":[],"failures":0,"visual_accepted":false,"phase":"starting"}
var stage:Node3D
var camera:Camera3D
var sun:DirectionalLight3D
var ground:MeshInstance3D
func _init()->void:call_deferred("run")
func check(ok:bool,label_:String)->bool:
	report.checks.append({"check":label_,"passed":ok})
	if not ok:report.failures+=1
	print("PASS " if ok else "FAIL ",label_);return ok
func setup()->void:
	Engine.max_fps=60;root.size=Vector2i(1400,1000);root.content_scale_size=root.size;root.msaa_3d=Viewport.MSAA_DISABLED;root.use_taa=false
	stage=Node3D.new();root.add_child(stage)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.16,.19,.23)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.78,.82,.88);env.environment.ambient_light_energy=.65
	env.environment.tonemap_mode=Environment.TONE_MAPPER_ACES;env.environment.tonemap_exposure=1.;stage.add_child(env)
	sun=DirectionalLight3D.new();sun.light_energy=1.5;sun.shadow_enabled=true;stage.add_child(sun)
	camera=Camera3D.new();camera.near=.03;camera.far=500.;stage.add_child(camera);camera.make_current()
	ground=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(150,.2,150);var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.28,.30,.27);mat.roughness=1.;box.material=mat;ground.mesh=box;stage.add_child(ground)
func digest(bytes:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func capture(subject:Dictionary,variant:String,view:Dictionary,origin:Vector3)->Dictionary:
	camera.position=City.vec(view.eye)-origin;camera.look_at(City.vec(view.target)-origin);camera.fov=view.fov
	for i in 10:await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();var raw:=output.path_join(subject.label+"_"+variant+"_"+view.id+".png")
	if not check(image.save_png(raw)==OK,"local lossless capture "+raw.get_file()):return {}
	var stdout:Array=[];var code:=OS.execute(PY,PackedStringArray([PREP,raw,"--keep-source"]),stdout,true,false);var encoded:Dictionary={}
	if code==0:
		for line:String in "\n".join(stdout).split("\n"):
			if line.strip_edges().is_empty():continue
			var parsed:Variant=JSON.parse_string(line)
			if parsed is Dictionary and parsed.has("path"):encoded=parsed
	if not check(code==0 and encoded.get("quality")==90 and encoded.get("lossless")==false and FileAccess.get_sha256(encoded.get("path",""))==encoded.get("sha256",""),"actual Q90 upload receipt "+raw.get_file()):return {}
	var row:={"id":subject.label+"_"+variant+"_"+view.id,"subject":subject.id,"variant":variant,"view":view,"path":encoded.path,"sha256":encoded.sha256,"quality":90,"lossless":false,"receipt":encoded,"local_lossless":raw,"local_lossless_sha256":FileAccess.get_sha256(raw),"pixels_sha256":digest(image.get_data()),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	report.screenshots.append(row);return row
func render_identity(record:Dictionary,node:MeshInstance3D)->Dictionary:
	var cpu=Frozen.geometry(record).mesh
	var surfaces:Array=[]
	for slot in node.mesh.get_surface_count():
		var material:Material=node.mesh.surface_get_material(slot)
		var arrays:Array=cpu.surfaces[slot];var gpu:Array=node.mesh.surface_get_arrays(slot)
		var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var bad:=0
		for i in normals.size():
			if Tangents.invalid(Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2]),tangents[i*4+3],normals[i]):bad+=1
		var row:={"slot":slot,"cpu_tangents_sha256":digest(tangents.to_byte_array()),"gpu_tangents_sha256":digest(gpu[Mesh.ARRAY_TANGENT].to_byte_array()),"cpu_invalid_basis":bad}
		if material is BaseMaterial3D:
			row.normal_enabled=material.normal_enabled;row.normal_scale=material.normal_scale;row.normal_texture_sha256=material.normal_texture.get_meta("runtime_source_sha256","") if material.normal_texture!=null else "";row.material_rid=material.get_rid().get_id()
		surfaces.append(row)
	return {"geometry_key":cpu.geometry_key(),"gpu_mesh_rid":node.mesh.get_rid().get_id(),"surfaces":surfaces}
func finish()->void:
	report.phase="complete";report.status="passed_capture_pending_visual_review" if report.failures==0 else "failed"
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));quit(report.failures)
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--after-snapshot="):after_snapshot=arg.trim_prefix("--after-snapshot=")
		elif arg.begins_with("--expected-snapshot-sha="):expected_snapshot_sha=arg.trim_prefix("--expected-snapshot-sha=")
		elif arg.begins_with("--expected-map-sha="):expected_sha=arg.trim_prefix("--expected-map-sha=")
		elif arg.begins_with("--expected-receipt-sha="):expected_receipt_sha=arg.trim_prefix("--expected-receipt-sha=")
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	if not check(DisplayServer.get_name()!="headless","real renderer required") or not check(not expected_sha.is_empty() and not expected_snapshot_sha.is_empty() and FileAccess.get_sha256(after_snapshot)==expected_snapshot_sha,"exact regenerated native snapshot SHA") or not check(not expected_receipt_sha.is_empty() and FileAccess.get_sha256(receipt_path)==expected_receipt_sha,"exact native regeneration receipt"):finish();return
	var receipt:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	if not check(receipt.get("saved",false) and receipt.get("native_reopen_passed",false) and receipt.get("failures",-1)==0 and receipt.get("output_sha256")==expected_sha,"actual atomic save/reopen passed"):finish();return
	plan=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/fortification_tangent_ab_plan.json"));report.plan_sha256=FileAccess.get_sha256(OUT+"/fortification_tangent_ab_plan.json")
	if not check(FileAccess.get_sha256(plan.baseline_snapshot)==plan.baseline_snapshot_sha256,"unchanged native baseline snapshot"):finish();return
	var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(plan.baseline_snapshot));var candidate:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(after_snapshot))
	if not check(candidate.get("map_sha256")==expected_sha and candidate.get("records") is Array and baseline.map_sha256==plan.baseline_map_sha256,"read-only native before/after document snapshots"):finish();return
	report.baseline={"map_sha256":plan.baseline_map_sha256,"snapshot":plan.baseline_snapshot,"sha256":plan.baseline_snapshot_sha256};report.after_snapshot={"path":after_snapshot,"sha256":expected_snapshot_sha};report.map_sha256=expected_sha;report.regeneration_receipt={"path":receipt_path,"sha256":expected_receipt_sha};report.render_spec=plan.camera_spec
	setup()
	for subject:Dictionary in plan.subjects:
		var left:Array=baseline.records.filter(func(r):return r.uuid==subject.id);var right:Array=candidate.records.filter(func(r):return r.uuid==subject.id)
		if not check(left.size()==1 and right.size()==1,"same frozen native subject "+subject.id):continue
		if not check(left[0].house_prefab.sha256==subject.baseline_payload_sha256 and left[0].house_prefab.sha256!=right[0].house_prefab.sha256,"real old and repaired payload identities "+subject.id):continue
		var row:={"id":subject.id,"label":subject.label,"before_payload_sha256":left[0].house_prefab.sha256,"after_payload_sha256":right[0].house_prefab.sha256,"comparison":[],"render_identity":{}};var captures:Dictionary={}
		var origin:=City.vec(subject.baseline_position);var n:=City.vec(subject.normal);ground.position=Vector3(0,-subject.baseline_size[1]*.5-.15,0)
		sun.position=n*8+Vector3(3,7,2);sun.look_at(Vector3.ZERO)
		for variant:String in ["baseline","candidate"]:
			var record:Dictionary=left[0] if variant=="baseline" else right[0]
			var node:=Frozen.visual(record,true)
			if not check(node.mesh!=null and not node.has_meta("paint_error"),"production frozen geometry/material restore "+variant+" "+subject.id):node.free();continue
			row.render_identity[variant]=render_identity(record,node)
			node.position-=origin;stage.add_child(node)
			for view:Dictionary in subject.cameras:captures[variant+"/"+view.id]=await capture(subject,variant,view,origin)
			node.queue_free();await process_frame
		if row.render_identity.size()==2:
			check(row.render_identity.baseline.geometry_key!=row.render_identity.candidate.geometry_key and row.render_identity.baseline.gpu_mesh_rid!=row.render_identity.candidate.gpu_mesh_rid,"distinct old/new production geometry and GPU allocations "+subject.id)
			for slot in row.render_identity.candidate.surfaces.size():
				var a:Dictionary=row.render_identity.baseline.surfaces[slot];var b:Dictionary=row.render_identity.candidate.surfaces[slot]
				if a.get("normal_enabled",false):check(not a.normal_texture_sha256.is_empty() and a.normal_texture_sha256==b.normal_texture_sha256 and b.get("normal_enabled",false) and b.normal_scale==a.normal_scale and b.cpu_invalid_basis==0,"same active normal map and repaired CPU tangent basis "+subject.id+"/"+str(slot))
		for view:Dictionary in subject.cameras:
			var a:Dictionary=captures.get("baseline/"+view.id,{});var b:Dictionary=captures.get("candidate/"+view.id,{})
			row.comparison.append({"view":view.id,"exact_pixels":not a.is_empty() and not b.is_empty() and a.pixels_sha256==b.pixels_sha256,"baseline":a.get("local_lossless",""),"candidate":b.get("local_lossless","")})
		report.subjects.append(row)
	check(FileAccess.get_sha256(after_snapshot)==expected_snapshot_sha and FileAccess.get_sha256(plan.baseline_snapshot)==plan.baseline_snapshot_sha256,"both immutable native snapshots unchanged")
	finish()
