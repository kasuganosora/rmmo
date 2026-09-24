extends SceneTree
var failed:=0
func check(ok: bool,label: String):
	if ok:print("PASS ",label)
	else:failed+=1;push_error(label)
func _init():call_deferred("run")
func run():
	var screen=load("res://scenes/loading.tscn").instantiate()
	screen.status_label=screen.get_node("Center/VBox/Status")
	screen.bar=screen.get_node("Center/VBox/Bar")
	screen._stage("Visible",2,4)
	check(screen.bar.value==2 and screen.bar.max_value==4,"bar reports completed work, not estimated time")
	screen._stage("Reading")
	check(screen.bar.modulate.a==0 and screen.bar.visible,"unknown stages reserve layout without fake progress")
	var visual=screen.transition_visual()
	check(visual.get_child_count()==2,"transition cover retains loading visuals without loading script")
	screen._on_enter_ready(false,"Fixture load failure",{})
	check(screen.has_node("FailActions") and screen.status_label.text=="Fixture load failure" and not screen.bar.visible,"failure stays readable with return action and no completed bar")
	visual.free();screen.free()
	var field=load("res://scripts/map/map_field.gd").new()
	field.skip_ready_rebuild=true
	field.pack_path="user://content/packs/default"
	field.prepared_pack=load("res://scripts/map/tilemap_pack.gd").load_pack(field.pack_path,"Axel256").render_snapshot()
	root.get_node("GameSession").spawn_data={"cell":{"x":112,"y":119},"map_id":"Axel256"}
	root.add_child(field)
	var fractions: Array=[]
	var states: Array=[]
	await field.rebuild_async(func(value):
		fractions.append(value)
		states.append(field.loading_state.duplicate()))
	var monotonic:=true
	for i in range(1,fractions.size()):
		if fractions[i]<fractions[i-1]:monotonic=false
	check(monotonic and fractions[-1]==1.0,"legacy progress callback stays monotonic")
	var visible_states:=0
	for state in states:
		if state.phase=="visible":
			visible_states+=1
			if state.done>state.total:failed+=1
	check(visible_states>1 and field._chunk_stream_module_logic.visible_ready(),"completion waits for actual visible chunks")
	field.free()
	print("LOADING TEST failures=",failed)
	quit(1 if failed else 0)
