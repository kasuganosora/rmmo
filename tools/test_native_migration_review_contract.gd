extends SceneTree
## Headless helper contract; no model, GPU, formal data or source writes.
const Contract=preload("res://tools/native_migration_review_contract.gd")
var failures:=0
var passed:=0
func _initialize()->void:
	var recipe:={"engine_sha":"a".repeat(64),"dimensions":[1400,1000],"exposure":1.0,"code":{"tool":"b".repeat(64)}}
	var views:Array=[]
	for name_:String in ["near","medium","far","detail"]:views.append({"name":name_,"eye":[1,2,3],"aim":[0,0,0],"fov":38.0,"projection":"perspective"})
	var packet:={"version":1,"source_sha256":"c".repeat(64),"recipe":recipe,"views":views}
	check(Contract.camera_valid(packet,recipe,"c".repeat(64)),"complete camera recipe accepted")
	check(Contract.camera_valid(JSON.parse_string(JSON.stringify(packet)),recipe,"c".repeat(64)),"JSON numeric transport preserves exact recipe")
	check(not Contract.camera_valid(packet,recipe,"d".repeat(64)),"wrong source identity rejected")
	for field:String in ["engine_sha","dimensions","exposure","code"]:
		var changed:=recipe.duplicate(true);changed[field]="different"
		check(not Contract.camera_valid(packet,changed,"c".repeat(64)),"changed "+field+" rejected")
	var altered:=packet.duplicate(true);altered.views[0].name="../escape"
	check(not Contract.camera_valid(altered,recipe,"c".repeat(64)),"camera name cannot escape image directory")
	altered=packet.duplicate(true);altered.views[0].eye=altered.views[0].aim
	check(not Contract.camera_valid(altered,recipe,"c".repeat(64)),"degenerate camera rejected")
	altered=packet.duplicate(true);altered.views[0].fov=NAN
	check(not Contract.camera_valid(altered,recipe,"c".repeat(64)),"nonfinite camera rejected")
	altered=packet.duplicate(true);altered.views.pop_back()
	check(not Contract.camera_valid(altered,recipe,"c".repeat(64)),"missing detail view rejected")
	var shadow_recipe:=recipe.duplicate(true);shadow_recipe.shadow_receiver=true
	var shadow_packet:=packet.duplicate(true);shadow_packet.recipe=shadow_recipe
	shadow_packet.receiver={"position":[0,-.025,0],"size":[8,8]}
	shadow_packet.views.append({"name":"shadow_overview","eye":[4,5,6],"aim":[0,0,0],"fov":38.0,"projection":"perspective"})
	check(Contract.camera_valid(shadow_packet,shadow_recipe,"c".repeat(64)),"source-frozen receiver and shadow camera accepted")
	altered=shadow_packet.duplicate(true);altered.receiver.size[0]=-1
	check(not Contract.camera_valid(altered,shadow_recipe,"c".repeat(64)),"invalid receiver rejected")
	altered=shadow_packet.duplicate(true);altered.views.pop_back()
	check(not Contract.camera_valid(altered,shadow_recipe,"c".repeat(64)),"missing shadow camera rejected")
	check(not Contract.camera_valid(shadow_packet,recipe,"c".repeat(64)),"receiver lighting feature recipe cannot change between arms")
	var external:=preload("res://scripts/world3d/map_paths.gd").external_root()
	var project:=ProjectSettings.globalize_path("res://")
	check(Contract.output_allowed(external.path_join("review_artifacts/fresh/report.json"),external,project),"external report output allowed")
	check(not Contract.output_allowed(external.path_join("review_artifacts/../../escape.json"),external,project),"output traversal rejected")
	check(not Contract.output_allowed(project.path_join("review_artifacts/report.json"),external,project),"project output rejected")
	check(Contract.differences({"pixel_sha":"a"},{"pixel_sha":"b"},"",[]).size()==1,"actual semantic difference retained")
	check(Contract.differences({"count":1},{"count":1.0},"",[]).is_empty(),"integer JSON representation is not a semantic change")
	print("NATIVE_MIGRATION_REVIEW_CONTRACT passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failures+=1
