extends Node
## Attach to root before entering Loading. Diagnostic only; never shipped in a scene.
var output_dir: String="user://loading_probe"
var started: int
var seen_loading:=false
var saved: Dictionary={}
var observations: Array=[]
func _ready():
	started=Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
func capture(label: String):
	if saved.has(label) or DisplayServer.get_name()=="headless":return
	saved[label]=true
	get_viewport().get_texture().get_image().save_png(output_dir.path_join(label+".png"))
func _process(_delta):
	var scene=get_tree().current_scene
	if scene==null:return
	var session=get_node("/root/GameSession")
	if scene.name=="Loading":
		seen_loading=true
		var text: String=scene.status_label.text
		if observations.is_empty() or observations[-1].text!=text:
			observations.append({"text":text,"elapsed_ms":Time.get_ticks_msec()-started,"bar":scene.bar.value,"total":scene.bar.max_value,"visible":scene.bar.modulate.a>0})
		if "0 /" in text:capture("loading_start")
		if scene.bar.value>0 and scene.bar.value<scene.bar.max_value:capture("loading_progress")
	var cover=session.get_node_or_null("WorldTransition")
	if cover!=null and cover.get_child_count()>0:
		var alpha: float=cover.get_child(0).modulate.a
		if alpha>.15 and alpha<.8:capture("loading_fade")
	if seen_loading and scene.name=="World" and cover==null:
		capture("loading_world")
		var file=FileAccess.open(output_dir.path_join("loading_visual.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"observations":observations,"images":saved,"elapsed_ms":Time.get_ticks_msec()-started,"load":scene.map_field.load_profile,"history":session.last_loading_progress},"\t"))
		queue_free()
	elif Time.get_ticks_msec()-started>15000:
		push_error("Loading visual probe timed out")
		queue_free()
