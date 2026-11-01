extends SceneTree
var checks:=0
var failures:Array[String]=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);printerr("FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	const key:="rendering/rendering_device/rmmo/secondary_draw_lists"
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	check(not output.is_empty(),"isolated output required")
	check(ProjectSettings.has_setting(key),"native project setting registered without explicit project entry")
	check(ProjectSettings.get_setting(key)==0,"native default remains zero")
	var row:Dictionary={}
	for property:Dictionary in ProjectSettings.get_property_list():
		if property.name==key:row=property;break
	check(not row.is_empty(),"setting metadata exists")
	check(int(row.get("type",-1))==TYPE_INT,"integer setting metadata")
	check((int(row.get("usage",0)) & PROPERTY_USAGE_RESTART_IF_CHANGED)!=0,"setting change requires restart")
	check(int(row.get("hint",-1))==PROPERTY_HINT_RANGE and str(row.get("hint_string",""))=="0,16,1,or_greater","range is a UI hint with explicit larger-values support")
	check(not OS.has_environment("RMMO_SECONDARY_DRAW_LISTS"),"metadata case has no environment override")
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"metadata":row,"project_value":ProjectSettings.get_setting(key)}))
	quit(0 if failures.is_empty() else 1)
