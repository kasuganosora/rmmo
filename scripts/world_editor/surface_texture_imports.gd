extends Node
## Editor-wide asynchronous import service. CPU preparation, encoding and
## file publication run in the existing preparation queue under its ledger.
signal finished(request_id:int,result:Dictionary)
const Queue=preload("res://scripts/world_editor/load_preparation_queue.gd")
const Worker=preload("res://scripts/world_editor/surface_texture_import_worker.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")

const PROBE_WORK_BYTES:=64*1024
const LABEL_WORK_BASE:=512*1024

class CommitToken extends RefCounted:
	var _mutex:=Mutex.new()
	var _cancelled:=false
	var _committing:=false
	func cancel()->bool:
		_mutex.lock()
		var accepted:=not _committing
		if accepted:_cancelled=true
		_mutex.unlock()
		return accepted
	func is_cancelled()->bool:
		_mutex.lock();var result:=_cancelled;_mutex.unlock()
		return result
	func begin_commit()->bool:
		_mutex.lock();var accepted:=not _cancelled
		if accepted:_committing=true
		_mutex.unlock()
		return accepted

class ContentBroker extends RefCounted:
	var mutex:=Mutex.new()
	var entries:Dictionary={}
	var producers:=0
	var joined:=0
	func claim(key:String)->bool:
		mutex.lock();var producer:=not entries.has(key)
		if producer:entries[key]={"ready":false};producers+=1
		else:joined+=1
		mutex.unlock();return producer
	func complete(key:String,result:Dictionary)->void:
		mutex.lock();entries[key]={"ready":true,"result":result};mutex.unlock()
	func read(key:String)->Dictionary:
		mutex.lock();var value:Dictionary=entries.get(key,{}).duplicate();mutex.unlock()
		return value
	func clear()->void:
		mutex.lock();entries.clear();mutex.unlock()
	func forget(key:String)->void:
		mutex.lock();entries.erase(key);mutex.unlock()
	func snapshot()->Dictionary:
		mutex.lock();var value:={"producers":producers,"joined":joined,"entries":entries.size()};mutex.unlock()
		return value

var _queue:Node
var _broker:=ContentBroker.new()
var _groups:Dictionary={}
var _requests:Dictionary={}
var _label_jobs:Dictionary={}
var _commits:Dictionary={}
var _completed_commits:Dictionary={}
var _notified_content:Dictionary={}
var _next_id:=0
var _serial:=0
var _commits_started:=0
var _stopping:=false
var producer_observer:Callable # Optional CPU contract-test gate; unset in editor.
var publication_observer:Callable # Optional scalar-only lease contract probe.

func configure(ledger:RefCounted)->void:
	assert(_queue==null and ledger!=null)
	_queue=Queue.new();_queue.ledger=ledger;_queue.shared_ledger_enabled=true
	add_child(_queue)

func submit(library:RefCounted,path:String,label:String="")->Dictionary:
	if _stopping or not is_instance_valid(_queue) or library==null:return {"ok":false,"error":"贴图导入服务不可用"}
	_queue.set_process(true)
	_next_id+=1;var id:=_next_id
	var directory:String=library.directory
	# Resolve the autoload-backed root on main; worker threads only receive the
	# immutable string and never traverse the SceneTree.
	var content_root:String=preload("res://scripts/world3d/map_paths.gd").external_root()
	var dir_key:=directory.replace("\\","/").simplify_path()
	var path_key:=path.replace("\\","/").simplify_path()
	if OS.get_name()=="Windows":dir_key=dir_key.to_lower();path_key=path_key.to_lower()
	var key:=JSON.stringify([dir_key,path_key])
	if _groups.has(key) and _groups[key].token.is_cancelled():
		# A cancelled in-flight generation can still own a worker and lease.
		# Retire it under its own key; a new request must get a fresh token.
		_serial+=1;var retired_key:=key+"#retired:%d"%_serial
		var retired:Dictionary=_groups[key];_groups.erase(key);_groups[retired_key]=retired
		for old_id:int in retired.subscribers:
			if _requests.has(old_id):_requests[old_id].group=retired_key
	_requests[id]={"group":key,"label":label,"fallback_name":path.get_file().get_basename(),"token":CommitToken.new(),"state":"preparing"}
	if _groups.has(key):
		_groups[key].subscribers.append(id)
	else:
		var token:=Drainer.CancelToken.new()
		_groups[key]={"subscribers":[id],"token":token,"path":path,"directory":directory,"root":content_root}
		if not _start_probe(_groups[key]):
			_groups.erase(key);_requests.erase(id)
			return {"ok":false,"error":"贴图导入任务无法启动"}
	set_process(true)
	return {"ok":true,"pending":true,"request_id":id}

func snapshot()->Dictionary:
	return {"broker":_broker.snapshot(),"queue":_queue.snapshot(),"requests":_requests.size(),"groups":_groups.size(),"commits_started":_commits_started}

func cancel(request_id:int)->bool:
	if not _requests.has(request_id):return false
	var request:Dictionary=_requests[request_id]
	if request.state=="publishing" and _commits.has(request.commit):
		var commit:Dictionary=_commits[request.commit]
		var others:=false
		for id:int in commit.subscribers:
			if id!=request_id and _requests.has(id) and _requests[id].state!="cancelled":others=true;break
		if not others and not commit.token.cancel():return false
	if not request.token.cancel():return false # already in atomic commit
	request.state="cancelled"
	var group:Dictionary=_groups.get(request.group,{})
	if not group.is_empty():
		var live:=false
		for id:int in group.subscribers:
			if _requests.has(id) and _requests[id].state!="cancelled":live=true;break
		if not live:group.token.cancel()
	return true

func _start_probe(group:Dictionary)->bool:
	_serial+=1;var job:="surface_import_probe:%d:%d"%[get_instance_id(),_serial]
	group.job=job;group.state="probing"
	return _queue.enqueue(job,Worker.probe.bind(group.path,group.directory,group.token,group.root),{"estimated_bytes":PROBE_WORK_BYTES,"exclusive":false,"cpu_only":true,"stage":"surface_import_probe"},"texture")

func _start_prepare(group:Dictionary,probe:Dictionary)->bool:
	_serial+=1;var job:="surface_import:%d:%d"%[get_instance_id(),_serial]
	group.job=job;group.state="preparing"
	var estimate:={"estimated_bytes":int(probe.estimated_bytes),"exclusive":false,"cpu_only":true,"stage":"surface_texture_import"}
	return _queue.enqueue(job,_prepare_and_publish.bind(group.path,group.directory,group.token,_broker,probe,group.root,producer_observer),estimate,"texture")

static func _prepare_and_publish(path:String,directory:String,token:RefCounted,broker:RefCounted,probe:Dictionary,root:String,observer:Callable)->Dictionary:
	var prepared:Dictionary=Worker.prepare(path,directory,token,root,probe)
	if not prepared.get("ok",false):return prepared
	var key:String=prepared.texture_path
	if not broker.claim(key):
		# Another producer owns this canonical content. Do not wait on it while
		# consuming a worker slot; the scene thread observes the small result.
		return {"ok":true,"broker_key":key,"waiting":true}
	if observer.is_valid():observer.call(path)
	var result:Dictionary=Worker.encode_publish(prepared,token,root,Callable(),Callable(),true)
	prepared.clear()
	# Producer alone carries the Image back under its joined queue lease.
	# Followers receive no Image and cannot complete until main publishes it.
	return {"ok":true,"broker_key":key,"producer":true,"result":result}

func _process(_delta:float)->void:
	if _stopping or not is_instance_valid(_queue):return
	for key:String in _groups.keys():
		var group:Dictionary=_groups[key]
		if group.state=="probing" and _queue.is_ready(group.job):
			var probe:Dictionary=_queue.acquire(group.job).duplicate()
			_queue.release(group.job);_queue.forget_terminal(group.job)
			if not probe.get("ok",false):_finish_group(key,probe)
			elif not _start_prepare(group,probe):_finish_group(key,{"ok":false,"error":"贴图导入任务无法启动"})
		if not _groups.has(key):continue
		if group.state=="preparing" and _queue.is_ready(group.job):
			var packet:Dictionary=_queue.acquire(group.job).duplicate()
			if packet.get("producer",false):
				var produced:Dictionary=packet.result
				if group.token.is_cancelled():
					produced.erase("prepared_image");produced={"ok":false,"error":"贴图导入已取消"}
				elif produced.get("ok",false):
					if produced.get("prepared_image") is Image:
						if publication_observer.is_valid():publication_observer.call(group.job,_queue.ledger.reserved_bytes)
						if produced.get("dds_ready",false):
							var generation:=JSON.stringify([produced.texture_path,produced.dds_sha])
							var changed:bool=not produced.get("dds_reused",false) and not _notified_content.has(generation)
							_notified_content[generation]=true
							preload("res://scripts/world3d/surface_materials.gd").refresh_texture_source_if_needed(produced.texture_path,produced.dds_path,produced.dds_sha,changed)
						if not preload("res://scripts/world3d/surface_materials.gd").publish_import_texture(produced.texture_path,produced.prepared_image):
							produced.erase("prepared_image");produced={"ok":false,"error":"贴图上传失败或不受当前渲染设备支持"}
					else:produced={"ok":false,"error":"贴图像素准备失败"}
				# Remove every CPU Image alias before returning its admission credit.
				produced.erase("prepared_image");packet.erase("result")
				_queue.release(group.job);_queue.forget_terminal(group.job)
				_broker.complete(packet.broker_key,produced)
				group.state="waiting";group.broker_key=packet.broker_key
				continue
			_queue.release(group.job);_queue.forget_terminal(group.job)
			if packet.get("waiting",false):group.state="waiting";group.broker_key=packet.broker_key
			elif packet.get("retry_probe",false):
				if not _start_probe(group):_finish_group(key,{"ok":false,"error":"贴图导入任务无法重新启动"})
			else:_finish_group(key,packet)
		if not _groups.has(key):continue
		if group.state=="waiting":
			var entry:Dictionary=_broker.read(group.broker_key)
			if entry.is_empty():
				# Another follower retired a cancelled producer. Every follower
				# must re-probe independently if that replacement disappears.
				if not _start_probe(group):_finish_group(key,{"ok":false,"error":"贴图导入任务无法重新启动"})
			elif entry.get("ready",false):
				if entry.result.get("error","")=="贴图导入已取消" and not group.token.is_cancelled():
					_broker.forget(group.broker_key)
					if not _start_probe(group):_finish_group(key,{"ok":false,"error":"贴图导入任务无法重新启动"})
				else:_finish_group(key,entry.result)
	for id:int in _label_jobs.keys():
		var job:String=_label_jobs[id]
		if not _queue.is_ready(job):continue
		var label_result:Dictionary=_queue.acquire(job).duplicate()
		_queue.release(job);_queue.forget_terminal(job);_label_jobs.erase(id)
		if not _requests.has(id):continue
		var request:Dictionary=_requests[id]
		if request.state=="cancelled":_requests.erase(id);continue
		if not label_result.get("ok",false):
			_requests.erase(id);finished.emit(id,label_result);continue
		_start_commit(id,request,label_result)
	for commit_key:String in _commits.keys():
		var commit:Dictionary=_commits[commit_key]
		if not _queue.is_ready(commit.job):continue
		var result:Dictionary=_queue.acquire(commit.job).duplicate()
		_queue.release(commit.job);_queue.forget_terminal(commit.job);_commits.erase(commit_key)
		if result.get("ok",false) and not commit.get("retired",false):_completed_commits[commit_key]=result
		for id:int in commit.subscribers:
			if not _requests.has(id):continue
			var request:Dictionary=_requests[id];_requests.erase(id)
			if request.state!="cancelled":finished.emit(id,result)
	if _groups.is_empty() and _requests.is_empty() and _commits.is_empty() and _label_jobs.is_empty():
		_broker.clear();_completed_commits.clear();_notified_content.clear();_queue.set_process(false);set_process(false)

func _finish_group(key:String,result:Dictionary)->void:
	var group:Dictionary=_groups[key];_groups.erase(key)
	if result.get("ok",false) and result.get("dds_ready",false):
		var generation:=JSON.stringify([result.texture_path,result.dds_sha])
		var changed:bool=not result.get("dds_reused",false) and not _notified_content.has(generation)
		_notified_content[generation]=true
		preload("res://scripts/world3d/surface_materials.gd").refresh_texture_source_if_needed(result.texture_path,result.dds_path,result.dds_sha,changed)
	for id:int in group.subscribers:
		if not _requests.has(id):continue
		var request:Dictionary=_requests[id]
		if request.state=="cancelled":_requests.erase(id);continue
		if not result.get("ok",false):
			_requests.erase(id);finished.emit(id,result);continue
		_serial+=1;var job:="surface_import_label:%d:%d"%[get_instance_id(),_serial]
		request.state="labeling";request.published=result;request.root=group.root
		var bytes:int=LABEL_WORK_BASE+request.label.length()*32
		var estimate:={"estimated_bytes":bytes,"exclusive":false,"cpu_only":true,"stage":"surface_material_label"}
		if not _queue.enqueue(job,Worker.prepare_label.bind(result,request.label,request.token,request.fallback_name),estimate,"neutral"):
			_requests.erase(id);finished.emit(id,{"ok":false,"error":"材质名称准备任务无法启动"})
		else:_label_jobs[id]=job

func _start_commit(id:int,request:Dictionary,label_result:Dictionary)->void:
	var label:String=request.label
	var commit_key:=JSON.stringify([request.published.texture_path.get_base_dir(),label_result.material_id])
	if _completed_commits.has(commit_key):
		_requests.erase(id);finished.emit(id,_completed_commits[commit_key]);return
	request.commit=commit_key;request.state="publishing"
	if _commits.has(commit_key) and _commits[commit_key].token.is_cancelled():
		_serial+=1;var retired_key:=commit_key+"#retired:%d"%_serial
		var retired:Dictionary=_commits[commit_key];retired.retired=true;_commits.erase(commit_key);_commits[retired_key]=retired
		for old_id:int in retired.subscribers:
			if _requests.has(old_id):_requests[old_id].commit=retired_key
	if _commits.has(commit_key):
		_commits[commit_key].subscribers.append(id)
		return
	_serial+=1;var job:="surface_import_commit:%d:%d"%[get_instance_id(),_serial]
	var token:=CommitToken.new()
	_commits[commit_key]={"job":job,"token":token,"subscribers":[id]}
	var estimate:={"estimated_bytes":LABEL_WORK_BASE+maxi(label.length(),request.fallback_name.length())*32,"exclusive":false,"cpu_only":true,"stage":"surface_material_publish"}
	if not _queue.enqueue(job,Worker.publish_material.bind(request.published,label,token,request.root,label_result.material_id,request.fallback_name),estimate,"neutral"):
		_commits.erase(commit_key);_requests.erase(id);finished.emit(id,{"ok":false,"error":"材质发布任务无法启动"})
	else:_commits_started+=1

func _exit_tree()->void:
	_stopping=true
	for id:int in _requests: _requests[id].token.cancel()
	for commit:Dictionary in _commits.values():commit.token.cancel()
	for group:Dictionary in _groups.values():group.token.cancel()
	if is_instance_valid(_queue):_queue.cancel()
