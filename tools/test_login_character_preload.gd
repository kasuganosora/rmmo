extends SceneTree
const Assets=preload("res://scripts/char/character_axis_assets.gd")
const Net=preload("res://scripts/net/net.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(60).timeout.connect(func():push_error("Login/preload flow timeout");quit(2))
	# Close a login page while its shared resource request is in flight.
	var abandoned=load("res://scenes/login.tscn").instantiate();root.add_child(abandoned)
	abandoned.free()
	var login=load("res://scenes/login.tscn").instantiate();root.add_child(login);current_scene=login
	login.pass_edit.text="";login._on_login_pressed()
	assert(login.login_btn.disabled)
	await create_timer(.6).timeout
	assert(is_instance_valid(login) and not login.login_btn.disabled and not login._accepted_login)
	login.pass_edit.text="demo";login._on_login_pressed()
	login.user_edit.text="edited-after-request";login.server_edit.text="wrong-after-request"
	while current_scene==login:
		await process_frame
	assert(current_scene.scene_file_path=="res://scenes/character_select.tscn")
	assert(Net.session().username=="demo" and Net.session().server_address!="wrong-after-request")
	assert(Assets.preload_pending.is_empty() and Assets.preloaded.size()==2)
	for frame in 5:await process_frame
	print("PASS login preload: close/reopen, failed authentication/retry, request identity and normal scene transition");quit()
