extends SceneTree
## Export trusted server collision policy from the exact client rest-point rule.
## Reads authoring JSON only; no mesh, texture, renderer or asset file is changed.
const Clearance=preload("res://scripts/world3d/player_clearance.gd")
const Shapes=preload("res://scripts/char/character_body_shapes.gd")
class BodyData extends RefCounted:
	var rest_points:=PackedVector3Array()
class AxisData extends RefCounted:
	var body:=BodyData.new()
class Model extends Node3D:
	var axis_rig:RefCounted

func _initialize()->void:run.call_deferred()
func fail(message:String)->void:
	push_error(message);quit(1)
func run()->void:
	var manifest_path:="";var output_path:="";var content_root:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="):manifest_path=arg.trim_prefix("--manifest=")
		if arg.begins_with("--output="):output_path=arg.trim_prefix("--output=")
		if arg.begins_with("--content-root="):content_root=arg.trim_prefix("--content-root=")
	if manifest_path.is_empty() or output_path.is_empty() or content_root.is_empty():fail("Require --manifest, --output and --content-root");return
	ProjectSettings.set_setting("rmmo/content_root",content_root)
	var manager:=root.get_node_or_null("AssetManager")
	if manager!=null:manager.content_root_override=content_root
	var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Array or manifest.size()>512:fail("Invalid body manifest");return
	var profiles:Dictionary={};var sources:Dictionary={}
	for row:Dictionary in manifest:
		var key:=str(row.get("gender",""))+"/"+str(row.get("look_id",""))
		if row.get("gender","") not in ["female","male"] or str(row.get("look_id","")).is_empty() or profiles.has(key):fail("Invalid or duplicate avatar identity");return
		var model:=Model.new()
		if row.get("gender")=="female":
			var path:=content_root.path_join("assets/characters/base/female_base_v2/female_display_topology.json")
			if not FileAccess.file_exists(path):model.free();fail("Missing trusted rest topology: "+path);return
			var topology:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
			if not topology is Dictionary or not topology.get("points") is Array or topology.points.size()!=21556:model.free();fail("Invalid control topology");return
			var points:=PackedVector3Array()
			for point:Array in topology.points:
				if point.size()!=3:model.free();fail("Invalid rest point");return
				var vector:=Vector3(point[0],point[1],point[2])
				if not vector.is_finite():model.free();fail("Non-finite rest point");return
				points.append(vector)
			model.axis_rig=AxisData.new()
			model.axis_rig.body.rest_points=Shapes.evaluate(points,Shapes.normalize(row.get("body_shapes",{})))
			if model.axis_rig.body.rest_points.is_empty():model.free();fail("Cannot evaluate body recipe");return
			sources[key]={"topology_sha256":FileAccess.get_sha256(path),"body_shapes":row.get("body_shapes",{})}
		profiles[key]={"radius":Clearance.RADIUS,"height":Clearance.standing_height(model)}
		model.free()
	var output:=FileAccess.open(output_path,FileAccess.WRITE)
	if output==null:fail("Cannot write body profiles");return
	output.store_string(JSON.stringify({"$schema":"rmmo.body-profiles/v1","profiles":profiles},"\t"));output.close()
	var provenance:=FileAccess.open(output_path+".sources.json",FileAccess.WRITE)
	if provenance==null:fail("Cannot write provenance");return
	provenance.store_string(JSON.stringify({"profiles_sha256":FileAccess.get_sha256(output_path),"client_rule_sha256":FileAccess.get_sha256("res://scripts/world3d/player_clearance.gd"),"sources":sources},"\t"));provenance.close()
	print("BODY_PROFILES_EXPORTED count=",profiles.size());quit()
