extends SceneTree
## Isolated CPU regression for inputs beyond the retired texture thresholds.
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var checks:=0
var failures:Array[String]=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var root:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):root=arg.trim_prefix("--root=").replace("\\","/")
	if root.is_empty() or not root.is_absolute_path():push_error("--root=<fresh external directory> required");quit(1);return
	var folder:=root.path_join("large_texture_%d"%OS.get_process_id())
	if DirAccess.dir_exists_absolute(folder):push_error("fixture exists");quit(1);return
	check(DirAccess.make_dir_recursive_absolute(folder)==OK,"create isolated fixture")
	var path:=folder.path_join("wide.png")
	var image:=Image.create(4097,2,false,Image.FORMAT_RGBA8);image.fill(Color(.2,.4,.8))
	check(image.save_png(path)==OK,"create 4097 pixel source")
	var key:=Paint.texture_key(path,false,false)
	var requested:={key:[path,false,false]}
	var plan:=Prep.estimate(requested,root,true)
	check(plan.rows.has(key) and plan.rows[key].width==4097 and plan.estimated_bytes>plan.output_bytes,"wide source is budgeted for preparation")
	var token:=Drainer.CancelToken.new()
	var packet:=Prep.prepare(requested,plan,root,token,true,{},false,true)
	check(packet.get("error","failed").is_empty() and packet.get("images",{}).has(key) and packet.images[key].get_width()==4097,"wide pixels are prepared without resizing")
	var cancelled:=Drainer.CancelToken.new();cancelled.cancel()
	var stopped:=Prep.prepare(requested,plan,root,cancelled,true,{},false,true)
	check(stopped.get("cancelled",false) and stopped.get("images",{}).is_empty(),"cancelled preparation publishes no image")
	var over_cache:={"width":8192,"height":8192,"format":Image.FORMAT_RGBA8,"size":357913940}
	check(not Pixels.valid_pixels(over_cache),"large valid image remains an optional disk-cache miss")
	print("LARGE_TEXTURE_LIMITS ",JSON.stringify({"checks":checks,"failures":failures,"fixture":folder}))
	quit(0 if failures.is_empty() else 1)
