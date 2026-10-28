extends SceneTree
# Test-only deterministic cross-process races against the actual import worker.
const Worker=preload("res://scripts/world_editor/surface_texture_import_worker.gd")
const DDS=preload("res://scripts/world3d/compressed_texture_source.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var checks:=0
var failures:Array[String]=[]
var fixture:=""
var python:=""
var helper:=""
class Gate extends RefCounted:
 var mutex:=Mutex.new()
 var suffix:=""
 var entered:=false
 var stage:=""
 var target:=""
 var proceed:=Semaphore.new()
 func observe(staged:String,destination:String)->void:
  if not destination.ends_with(suffix):return
  mutex.lock();stage=staged;target=destination;entered=true;mutex.unlock()
  proceed.wait()
 func waiting()->bool:
  mutex.lock();var value:=entered;mutex.unlock();return value
func check(value:bool,label:String)->void:
 checks+=1
 if value:print("PASS ",label)
 else:failures.append(label);print("FAIL ",label)
func _initialize()->void:run.call_deferred()
func wait_until(condition:Callable,ms:int=30000)->bool:
 var deadline:=Time.get_ticks_msec()+ms
 while Time.get_ticks_msec()<deadline:
  if condition.call():return true
  await process_frame
 return condition.call()
func work(task:Callable)->Dictionary:
 var thread:=Thread.new()
 if thread.start(task)!=OK:return {"ok":false,"error":"thread start"}
 while thread.is_alive():await process_frame
 return thread.wait_to_finish()
func finish(thread:Thread)->Dictionary:
 while thread.is_alive():await process_frame
 return thread.wait_to_finish()
func write_bytes(path:String,bytes:PackedByteArray)->bool:
 var f:=FileAccess.open(path,FileAccess.WRITE)
 if f==null:return false
 f.store_buffer(bytes);f.flush();var ok:=f.get_error()==OK;f.close();return ok
func compete(label:String,entries:Array)->bool:
 var manifest:=fixture.path_join(label+"_manifest.json")
 var marker:=fixture.path_join(label+"_marker.json")
 if not write_bytes(manifest,JSON.stringify(entries).to_utf8_buffer()):return false
 var pid:=OS.create_process(python,PackedStringArray([helper,manifest,marker]))
 print("DDS_RACE_CHILD ",label," ",pid)
 if pid<=0:return false
 var done:bool=await wait_until(func():return not OS.is_process_running(pid),10000)
 if not done:
  OS.kill(pid)
  return false
 # The child must have exited before its marker is read.
 if not FileAccess.file_exists(marker):return false
 var json:=JSON.new()
 if json.parse(FileAccess.get_file_as_string(marker))!=OK:return false
 return json.data is Dictionary and json.data.get("ok",false)
func encoded(image:Image)->Dictionary:
 return await work(Worker.encode_dds.bind(image))
func source_file(name:String,color:Color)->String:
 var image:=Image.create(32,32,false,Image.FORMAT_RGBA8);image.fill(color)
 var path:=fixture.path_join(name+".png")
 check(image.save_png(path)==OK,name+" source created")
 return path
func prepare_case(name:String,source:String,token:RefCounted)->Dictionary:
 var value:Dictionary=await work(Worker.prepare.bind(source,fixture.path_join(name),token,fixture))
 check(value.get("ok",false),name+" prepares canonical input")
 return value
func start_case(name:String,prepared:Dictionary,token:RefCounted,suffix:String)->Dictionary:
 var gate:=Gate.new();gate.suffix=suffix
 var thread:=Thread.new()
 var err:=thread.start(Worker.encode_publish.bind(prepared,token,fixture,Callable(),Callable(),true,Callable(gate,"observe")))
 if err!=OK:
  check(false,name+" worker starts")
  return {}
 var entered:bool=await wait_until(func():return gate.waiting() or not thread.is_alive())
 if not entered or not gate.waiting():
  gate.proceed.post();var value:Dictionary=await finish(thread)
  check(false,name+" reaches DDS staging gate; result="+str(value.get("error",value.get("dds_reason",""))))
  return {}
 check(true,name+" reaches DDS staging gate")
 return {"gate":gate,"thread":thread}
func identity(prepared:Dictionary,bytes:PackedByteArray)->PackedByteArray:
 return JSON.stringify({"version":1,"encoder_version":1,"source_sha256":prepared.content_id,"source_bytes":prepared.png.size(),"dds_sha256":Worker._digest(bytes),"dds_bytes":bytes.size(),"normal":false,"flip":false}).to_utf8_buffer()
func image_matches(result:Dictionary,prepared:Dictionary,expected_path:String)->bool:
 if not result.get("ok",false) or not result.get("dds_ready",false) or result.get("dds_path","")!=expected_path:return false
 var row:Dictionary=DDS.plan_mutable(prepared.texture_path,false,false,fixture,prepared.content_id)
 if row.is_empty() or row.get("sidecar","")!=expected_path:return false
 var on_disk:Image=DDS.read(row)
 var owner:Variant=result.get("prepared_image")
 return on_disk!=null and owner is Image and owner.get_width()==on_disk.get_width() and owner.get_height()==on_disk.get_height() and owner.get_format()==on_disk.get_format() and owner.get_data()==on_disk.get_data()
func race_identity(source:String,bbytes:PackedByteArray)->void:
 var token:=Drainer.CancelToken.new();var p:Dictionary=await prepare_case("identity",source,token)
 if not p.get("ok",false):return
 var started:Dictionary=await start_case("identity",p,token,".dxt1.dds.source.json")
 if started.is_empty():return
 var g:Gate=started.gate;var bidentity:=identity(p,bbytes)
 check(FileAccess.get_file_as_bytes(g.stage)!=bidentity,"competitor identity differs from staged A")
 var idsrc:=fixture.path_join("identity_b.json");var dsrc:=fixture.path_join("identity_b.dds")
 check(write_bytes(idsrc,bidentity) and write_bytes(dsrc,bbytes),"identity competitor bytes prepared")
 var ok:bool=await compete("identity",[{"target":g.target,"source":idsrc},{"target":g.target.trim_suffix(".source.json"),"source":dsrc}])
 check(ok and FileAccess.get_file_as_bytes(g.target)==bidentity,"identity competitor published B before release")
 var row:Dictionary=DDS.plan_mutable(p.texture_path,false,false,fixture,p.content_id)
 check(not row.is_empty() and DDS.read(row)!=null,"competitor identity and DDS form a valid readable pair")
 g.proceed.post();var result:Dictionary=await finish(started.thread)
 check(not result.get("ok",false),"different identity rejected")
 check(FileAccess.get_file_as_bytes(g.target)==bidentity and FileAccess.get_file_as_bytes(g.target.trim_suffix(".source.json"))==bbytes,"identity and valid DDS B preserved")
 check(not FileAccess.file_exists(g.stage),"identity loser stage removed")
func race_same(source:String)->void:
 var token:=Drainer.CancelToken.new();var p:Dictionary=await prepare_case("same",source,token)
 if not p.get("ok",false):return
 var started:Dictionary=await start_case("same",p,token,".dxt1.dds")
 if started.is_empty():return
 var g:Gate=started.gate;var contents:=FileAccess.get_file_as_bytes(g.stage)
 var ok:bool=await compete("same",[{"target":g.target,"source":g.stage}])
 check(ok and FileAccess.get_file_as_bytes(g.target)==contents,"same DDS competitor wins")
 g.proceed.post();var result:Dictionary=await finish(started.thread)
 check(image_matches(result,p,g.target),"identical winner reused with matching prepared image")
 check(FileAccess.get_file_as_bytes(g.target)==contents and not FileAccess.file_exists(g.stage),"same winner and loser cleanup preserved")
func race_different(source:String,bbytes:PackedByteArray)->void:
 var token:=Drainer.CancelToken.new();var p:Dictionary=await prepare_case("different",source,token)
 if not p.get("ok",false):return
 var started:Dictionary=await start_case("different",p,token,".dxt1.dds")
 if started.is_empty():return
 var g:Gate=started.gate;var id_before:=FileAccess.get_file_as_bytes(g.target+".source.json")
 var abytes:=FileAccess.get_file_as_bytes(g.stage)
 check(abytes.size()==bbytes.size() and abytes!=bbytes,"different competitor has same-size distinct DDS payload")
 var data:=fixture.path_join("different_b.dds");check(write_bytes(data,bbytes),"different DDS bytes prepared")
 var ok:bool=await compete("different",[{"target":g.target,"source":data}])
 check(ok and FileAccess.get_file_as_bytes(g.target)==bbytes,"different DDS competitor wins")
 g.proceed.post();var result:Dictionary=await finish(started.thread)
 check(not result.get("ok",false),"different DDS rejected")
 check(FileAccess.get_file_as_bytes(g.target)==bbytes and FileAccess.get_file_as_bytes(g.target+".source.json")==id_before,"different DDS and original identity preserved")
 check(not FileAccess.file_exists(g.stage),"different DDS loser stage removed")
func race_cancel(source:String)->void:
 var token:=Drainer.CancelToken.new();var p:Dictionary=await prepare_case("cancel",source,token)
 if not p.get("ok",false):return
 var started:Dictionary=await start_case("cancel",p,token,".dxt1.dds.source.json")
 if started.is_empty():return
 var g:Gate=started.gate;token.cancel();g.proceed.post()
 var result:Dictionary=await finish(started.thread)
 check(not result.get("ok",false) and not FileAccess.file_exists(g.target) and not FileAccess.file_exists(g.stage),"cancel identity stage leaves no identity or staged file")
 var retry:Dictionary=await work(Worker.encode_publish.bind(p,Drainer.CancelToken.new(),fixture,Callable(),Callable(),true,Callable()))
 var path:=str(p.texture_path)+".dxt1.dds"
 check(image_matches(retry,p,path),"same-content retry recovers and image matches actual DDS")
func race_priority(source:String,highbytes:PackedByteArray)->void:
 var token:=Drainer.CancelToken.new();var p:Dictionary=await prepare_case("priority",source,token)
 if not p.get("ok",false):return
 var started:Dictionary=await start_case("priority",p,token,".dxt1.dds")
 if started.is_empty():return
 var g:Gate=started.gate;var high:=str(p.texture_path)+".dxt5.dds"
 var idsrc:=fixture.path_join("priority_b.json");var dsrc:=fixture.path_join("priority_b.dds");var bidentity:=identity(p,highbytes)
 check(write_bytes(idsrc,bidentity) and write_bytes(dsrc,highbytes),"higher-priority competitor prepared")
 var ok:bool=await compete("priority",[{"target":high+".source.json","source":idsrc},{"target":high,"source":dsrc}])
 check(ok and DDS.sidecar_path(p.texture_path,false,false)==high,"higher-priority DDS becomes selected before release")
 g.proceed.post();var result:Dictionary=await finish(started.thread)
 check(not result.get("ok",false) or image_matches(result,p,high),"cannot report lower-priority DDS as ready")
 check(FileAccess.get_file_as_bytes(high)==highbytes and FileAccess.get_file_as_bytes(high+".source.json")==bidentity,"higher-priority winner preserved")
func race_orphan(source:String,bbytes:PackedByteArray)->void:
 var token:=Drainer.CancelToken.new();var p:Dictionary=await prepare_case("orphan_cancel",source,token)
 if not p.get("ok",false):return
 var started:Dictionary=await start_case("orphan_cancel",p,token,".dxt1.dds")
 if started.is_empty():return
 var g:Gate=started.gate;var idpath:=g.target+".source.json"
 var prior:=FileAccess.get_file_as_bytes(idpath)
 check(not prior.is_empty(),"identity is published before the gated DDS")
 token.cancel();g.proceed.post();var result:Dictionary=await finish(started.thread)
 check(not result.get("ok",false) and not FileAccess.file_exists(g.target) and not FileAccess.file_exists(g.stage) and FileAccess.get_file_as_bytes(idpath)==prior,"cancel after identity preserves only the reusable identity")
 var retry:Dictionary=await work(Worker.encode_publish.bind(p,Drainer.CancelToken.new(),fixture,Callable(),Callable(),true,Callable()))
 check(image_matches(retry,p,g.target) and FileAccess.get_file_as_bytes(idpath)==prior,"same identity orphan is recovered with matching pixels")
 var next_token:=Drainer.CancelToken.new();var other:Dictionary=await prepare_case("orphan_conflict",source,next_token)
 if not other.get("ok",false):return
 var next:Dictionary=await start_case("orphan_conflict",other,next_token,".dxt1.dds.source.json")
 if next.is_empty():return
 var ng:Gate=next.gate;var foreign:=identity(other,bbytes);var source_id:=fixture.path_join("orphan_foreign.json")
 check(write_bytes(source_id,foreign),"prepare different orphan identity")
 var ok:bool=await compete("orphan_conflict",[{"target":ng.target,"source":source_id}])
 check(ok and not FileAccess.file_exists(ng.target.trim_suffix(".source.json")),"competing identity exists without a DDS yet")
 ng.proceed.post();var failed:Dictionary=await finish(next.thread)
 check(not failed.get("ok",false) and FileAccess.get_file_as_bytes(ng.target)==foreign and not FileAccess.file_exists(ng.target.trim_suffix(".source.json")) and not FileAccess.file_exists(ng.stage),"different orphan identity is a conflict, never PNG success")
func run()->void:
 var root:=""
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--root="):root=arg.trim_prefix("--root=").replace("\\","/")
  elif arg.begins_with("--python="):python=arg.trim_prefix("--python=").replace("\\","/")
  elif arg.begins_with("--competitor="):helper=arg.trim_prefix("--competitor=").replace("\\","/")
 if root.is_empty() or not root.is_absolute_path() or not Paths.allowed(root):push_error("root must be an external-root subdirectory");quit(1);return
 if OS.get_name()=="Windows":python=python.get_base_dir().path_join("pythonw.exe")
 if not FileAccess.file_exists(python) or not FileAccess.file_exists(helper):push_error("missing hidden python or competitor helper");quit(1);return
 fixture=root.path_join("dds_race_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
 if DirAccess.dir_exists_absolute(fixture) or DirAccess.make_dir_recursive_absolute(fixture)!=OK:push_error("fixture creation failed");quit(1);return
 var source:=source_file("source_a",Color(.15,.3,.8,1))
 var b:=Image.create(32,32,false,Image.FORMAT_RGBA8);b.fill(Color(.9,.2,.1,1))
 var high:=Image.create(32,32,false,Image.FORMAT_RGBA8);high.fill(Color(.8,.1,.3,.4))
 var normal:Dictionary=await encoded(b);var alpha:Dictionary=await encoded(high)
 check(normal.get("ok",false) and normal.get("suffix","")==".dxt1.dds","real CPU DXT1 encoder available")
 check(alpha.get("ok",false) and alpha.get("suffix","")==".dxt5.dds","real CPU DXT5 encoder available")
 if normal.get("ok",false) and alpha.get("ok",false):
  await race_identity(source,normal.bytes)
  await race_same(source)
  await race_different(source,normal.bytes)
  await race_cancel(source)
  await race_priority(source,alpha.bytes)
  await race_orphan(source,normal.bytes)
 print("DDS_NO_REPLACE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"fixture":fixture}))
 quit(0 if failures.is_empty() else 1)
