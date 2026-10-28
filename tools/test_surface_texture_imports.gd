extends SceneTree
const Imports=preload("res://scripts/world_editor/surface_texture_imports.gd")
const Library=preload("res://scripts/world_editor/surface_material_library.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var results:Dictionary={}
var checks:=0
var failures:=0
var publication_observations:Array[Dictionary]=[]
var observed_imports:Node
class ProducerGate extends RefCounted:
	var mutex:=Mutex.new()
	var entered:=false
	var release:=Semaphore.new()
	func block(_path:String)->void:
		mutex.lock();var first:=not entered;entered=true;mutex.unlock()
		if first:release.wait()
	func is_entered()->bool:
		mutex.lock();var value:=entered;mutex.unlock();return value
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+label)
	else:print("PASS ",label)
func receive(id:int,result:Dictionary)->void:results[id]=result
func observe_publication(key:String,reserved:int)->void:
	var queue:Node=observed_imports._queue
	publication_observations.append({"held":queue.rows.has(key) and queue.rows[key].state=="held","charged":queue.ledger._entries.has(queue._ledger_key(key)),"reserved":reserved})
func run()->void:
	var parent:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):parent=arg.trim_prefix("--root=").replace("\\","/")
	if parent.is_empty() or not parent.is_absolute_path():push_error("--root must be a fresh external directory");quit(1);return
	var fixture:=parent.path_join("imports_%d"%OS.get_process_id())
	if DirAccess.dir_exists_absolute(fixture):push_error("fixture already exists");quit(1);return
	check(DirAccess.make_dir_recursive_absolute(fixture)==OK,"create external fixture")
	var source:=fixture.path_join("first.png");var other:=fixture.path_join("second.png")
	var image:=Image.create(16,8,false,Image.FORMAT_RGBA8);image.fill(Color(.2,.4,.7,1.0))
	check(image.save_png(source)==OK and image.save_png(other)==OK,"create two same-content sources")
	var ledger:=Admission.new();ledger.worker_limit=2;ledger.byte_limit=64*1024*1024
	var imports:=Imports.new();root.add_child(imports);imports.configure(ledger);imports.finished.connect(receive)
	observed_imports=imports;imports.publication_observer=Callable(self,"observe_publication")
	var library:=Library.new(fixture.path_join("materials"))
	var a:Dictionary=imports.submit(library,source,"alpha")
	var b:Dictionary=imports.submit(library,source,"beta")
	var c:Dictionary=imports.submit(library,other,"gamma")
	var same_label:Dictionary=imports.submit(library,other,"alpha")
	var cancelled:Dictionary=imports.submit(library,other,"cancelled")
	check(a.ok and b.ok and c.ok and cancelled.ok and imports.cancel(cancelled.request_id),"accept shared requests and cancel one subscriber")
	var retry_source:=fixture.path_join("retry.png")
	image.fill(Color(.8,.1,.3));check(image.save_png(retry_source)==OK,"create independent retry source")
	var old:Dictionary=imports.submit(library,retry_source,"old")
	check(old.ok and imports.cancel(old.request_id),"cancel the last subscriber of a source")
	var retry:Dictionary=imports.submit(library,retry_source,"new")
	check(retry.ok,"immediate resubmission gets an independent generation")
	var deadline:=Time.get_ticks_msec()+30000
	while results.size()<5 and Time.get_ticks_msec()<deadline:await process_frame
	check(results.size()==5 and not results.has(cancelled.request_id) and not results.has(old.request_id),"only live subscribers receive completion")
	if results.size()==5:
		check(results[retry.request_id].get("ok",false),"resubmission does not inherit the cancelled token")
		var first:Dictionary=results[a.request_id];var second:Dictionary=results[b.request_id];var third:Dictionary=results[c.request_id]
		check(results[same_label.request_id].get("ok",false) and results[same_label.request_id].get("material_id","")==first.get("material_id",""),"same content and label coalesce publication for both subscribers")
		check(imports.snapshot().commits_started==4,"same-label subscribers run one material publisher, not two")
		check(first.get("ok",false) and second.get("ok",false) and third.get("ok",false),"all retained imports succeed")
		if first.get("ok",false) and second.get("ok",false) and third.get("ok",false):
			check(first.material_id!=second.material_id and second.material_id!=third.material_id,"labels produce independent material identities")
			check(first.material.texture_path==second.material.texture_path and first.material.texture_path==third.material.texture_path,"same canonical content shares the texture")
			check(imports.snapshot().broker.producers==2 and imports.snapshot().broker.joined==1,"one DDS producer for two identical source paths plus independent retry content")
			check(library.find(first.material_id).texture_path==first.material.texture_path,"published material reopens from catalog")
			var key:String=Paint.texture_key(first.material.texture_path)
			var texture:Texture2D=Paint.retained_texture(key)
			check(texture!=null and texture.get_meta("runtime_source_sha256","")==first.material.texture_path.get_file().get_basename(),"joined producer publishes the exact source identity before signaling subscribers")
			check(not first.has("prepared_image") and not second.has("prepared_image") and not third.has("prepared_image"),"Image never enters HTTP subscriber results")
			var thumbnail_path:String=first.material.texture_path+".thumbnail.png"
			var thumbnail_identity:String=first.material.texture_path+".thumbnail.json"
			var thumbnail:=Image.load_from_file(thumbnail_path) if FileAccess.file_exists(thumbnail_path) else null
			var thumb_file:=FileAccess.open(thumbnail_identity,FileAccess.READ)
			var thumb_meta:Variant=JSON.parse_string(thumb_file.get_as_text()) if thumb_file!=null else null
			check(thumbnail!=null and thumbnail.get_width()<=104 and thumbnail.get_height()<=64 and thumbnail.get_width()*8==thumbnail.get_height()*16,"one aspect-preserving small thumbnail is published")
			check(thumb_meta is Dictionary and thumb_meta.get("source_sha256","")==first.material.texture_path.get_file().get_basename() and int(thumb_meta.get("source_bytes",0))==FileAccess.get_file_as_bytes(first.material.texture_path).size() and int(thumb_meta.get("source_modified_time",0))==FileAccess.get_modified_time(first.material.texture_path),"thumbnail identity binds the canonical source length and modification time")
	check(ledger.count()==0 and ledger.reserved_bytes==0,"all shared admission leases return")
	check(not publication_observations.is_empty() and publication_observations.all(func(row):return row.held and row.charged and row.reserved>0),"main publication runs only while joined CPU result remains charged")
	check(imports.snapshot().requests==0 and imports.snapshot().groups==0,"coordinator releases request and group state")
	check(imports._queue.rows.is_empty() and imports._queue.order.is_empty() and not imports._queue.is_processing(),"completed queue retires history and stops idle processing")
	for iteration in 5:
		var again:Dictionary=imports.submit(library,source,"repeat %d"%iteration)
		deadline=Time.get_ticks_msec()+30000
		while not results.has(again.request_id) and Time.get_ticks_msec()<deadline:await process_frame
		check(results.has(again.request_id) and results[again.request_id].get("ok",false),"repeat import completes after idle %d"%iteration)
		check(imports._queue.rows.is_empty() and imports._queue.order.is_empty() and not imports._queue.is_processing(),"repeat import leaves no historical scan %d"%iteration)
	# Three different paths encode identical content. Kill the original producer
	# and remove the first follower; the other follower must not wait forever.
	var one:=fixture.path_join("producer.png");var two:=fixture.path_join("removed.png");var three:=fixture.path_join("survivor.png")
	image.fill(Color(.1,.2,.9));image.save_png(one);image.save_png(two);image.save_png(three)
	ledger.worker_limit=3
	var gate:=ProducerGate.new();imports.producer_observer=gate.block
	var producer:Dictionary=imports.submit(library,one,"producer")
	deadline=Time.get_ticks_msec()+30000
	while not gate.is_entered() and Time.get_ticks_msec()<deadline:await process_frame
	check(gate.is_entered(),"original producer reached controlled gate")
	var follower1:Dictionary=imports.submit(library,two,"removed")
	var follower2:Dictionary=imports.submit(library,three,"survivor")
	var waiting:=0
	while Time.get_ticks_msec()<deadline and waiting<2:
		await process_frame;waiting=0
		for group:Dictionary in imports._groups.values():
			if group.state=="waiting":waiting+=1
	check(waiting==2,"two other source paths joined the pending producer")
	var waiting_packets_clean:=true
	for group:Dictionary in imports._groups.values():
		if group.state=="waiting":
			var entry:Dictionary=imports._broker.read(group.broker_key)
			if entry.has("result") and entry.result.has("prepared_image"):waiting_packets_clean=false
	check(waiting_packets_clean,"waiting broker never exposes a CPU Image without an owning queue lease")
	check(imports.cancel(producer.request_id),"cancel original producer")
	check(DirAccess.remove_absolute(two)==OK,"remove first follower before retry")
	gate.release.post();imports.producer_observer=Callable()
	deadline=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline and (not results.has(follower1.request_id) or not results.has(follower2.request_id)):await process_frame
	check(results.has(follower1.request_id) and not results[follower1.request_id].get("ok",false),"removed follower returns an error")
	check(results.has(follower2.request_id) and results[follower2.request_id].get("ok",false),"remaining follower retries and completes")
	check(imports._queue.rows.is_empty() and ledger.count()==0,"retry scenario retires all queue rows and leases")
	var long_label:="纹理".repeat(150000)
	var long_request:Dictionary=imports.submit(library,source,long_label)
	deadline=Time.get_ticks_msec()+30000
	while not results.has(long_request.request_id) and Time.get_ticks_msec()<deadline:await process_frame
	check(results.has(long_request.request_id) and results[long_request.request_id].get("ok",false) and results[long_request.request_id].material.name==long_label,"large legal label is preserved")
	check(ledger.peak_bytes>=Imports.LABEL_WORK_BASE+long_label.length()*32,"large label receives a size-dependent admission envelope")
	check(imports._queue.rows.is_empty() and ledger.count()==0,"large label lease and history are released")
	imports.queue_free()
	print("SURFACE_TEXTURE_IMPORTS checks=%d failures=%d fixture=%s"%[checks,failures,fixture])
	quit(1 if failures else 0)
