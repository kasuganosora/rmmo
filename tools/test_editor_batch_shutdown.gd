extends SceneTree
const Editor=preload("res://scripts/world_editor/world_editor.gd")
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Upload=preload("res://scripts/world3d/prepared_cpu_upload.gd")
var failed:=0
var restores:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS: " if ok else "FAIL: ",label)
	if not ok:failed+=1
func fresh()->Node3D:
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=preload("res://scripts/world3d/world_document.gd").new();session.world3d_editor_path=""
	var editor:=Editor.new();editor._mcp_autostart=false;root.add_child(editor);editor._safety.enabled=false
	if editor._ground_batches==null:editor._ground_batches=Batch.new();editor.add_child(editor._ground_batches)
	editor._ground_batches.set_process(false)
	return editor
func sources(editor:Node3D,outside:Node3D=null)->Array:
	var nodes:Array=[];var mesh:=BoxMesh.new()
	for i in 3:
		var node:=MeshInstance3D.new();node.name="shutdown_part%d"%i;node.mesh=mesh;node.position=Vector3(i*2,1,0)
		node.set_meta("ground_batch_record",{"uuid":str(node.name),"kind":"box","size":[1,1,1],"building":{"id":"shutdown_house","floor":0,"part":str(node.name),"role":"wall"}})
		(outside if outside!=null and i==2 else editor._view).add_child(node);nodes.append(node)
	return nodes
func observe(active:bool)->void:
	if active:restores+=1
func start_count()->void:
	restores=0;Upload.profile_enabled=true;Upload.profile_scope_hook=observe
func stop_count()->void:
	Upload.profile_enabled=false;Upload.profile_scope_hook=Callable()
func settle()->void:
	for i in 3:await process_frame
func run()->void:
	create_timer(90).timeout.connect(func():quit(2));Engine.max_fps=60
	for mode:String in ["queued","direct","outside","detach","worker","stale"]:
		var editor:=fresh();var outside:=Node3D.new();root.add_child(outside)
		var nodes:=sources(editor,outside if mode=="outside" else null);var batch:Node=editor._ground_batches
		batch.sync(nodes)
		if mode=="worker":
			batch._build_next(true);check(batch._workers.size()==1,"real batch worker started before editor shutdown")
		else:
			batch.flush();check(batch.groups.size()==1 and nodes.all(func(n):return n.mesh is Cpu),mode+": real merged group owns CPU-only sources")
		if mode=="stale":
			# A historical group can contain a dead entry; guard before casting.
			nodes[0].tree_exiting.disconnect(batch.groups.values()[0].exit_callback);nodes[0].free()
		start_count()
		if mode=="detach":
			root.remove_child(editor)
			check(restores==3 and nodes.all(func(n):return not n.mesh is Cpu),"detaching a live editor still restores every source")
			root.add_child(editor);batch.sync(nodes);batch.flush()
			check(batch.groups.size()==1,"detached editor can reenter and rebuild its batch")
			restores=0;editor.queue_free()
		elif mode=="direct":editor.free()
		else:editor.queue_free()
		await settle();stop_count()
		check(not is_instance_valid(editor),mode+": editor actually destroyed")
		check(restores==(1 if mode=="outside" else 0),mode+": only sources outside the dying editor may be restored")
		if mode=="outside":check(is_instance_valid(nodes[2]) and not nodes[2].mesh is Cpu,"external surviving member stays renderable")
		var deadline:=Time.get_ticks_msec()+10000
		while Time.get_ticks_msec()<deadline:
			var drainer:=root.get_node_or_null("AssetWorkerDrainer")
			if drainer==null or drainer.jobs.is_empty():break
			await process_frame
		var drainer:=root.get_node_or_null("AssetWorkerDrainer")
		check(drainer==null or drainer.jobs.is_empty(),mode+": abandoned workers drain without retaining editor owners")
		outside.free();print("EDITOR_BATCH_SHUTDOWN_WORK ",JSON.stringify({"mode":mode,"restore_calls":restores}))
	print("EDITOR_BATCH_SHUTDOWN_FAILED=",failed);quit(1 if failed else 0)
