extends SceneTree
## CPU-only, real temporary rmres files. No map/native generation or GPU work.
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failed:=0
var passed:=0
var directory:=""
var files:Array[String]=[]

class Errors extends Logger:
	var count:=0
	func _log_error(_function:String,_file:String,_line:int,_code:String,_rationale:String,_notify:bool,_type:int,_backtraces:Array)->void:count+=1

class DelayedReader extends RefCounted:
	# Gate request zero on request one completing its real read. The delay is
	# deterministic and local to this fixture, never a production timing hook.
	var second_done:=Semaphore.new()
	var first_entered:=Semaphore.new()
	var fail_second:=false
	func read(job:Dictionary,decode:bool)->Dictionary:
		if job.id==0:
			first_entered.post();second_done.wait();OS.delay_msec(40)
		elif job.id==1:first_entered.wait()
		var result:Dictionary
		if job.id==1 and fail_second:
			var missing:=job.duplicate();missing.location=job.location+".missing"
			result=Store._read_package_job(missing,decode)
		else:result=Store._read_package_job(job,decode)
		if job.id==1:second_done.post()
		return result

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if value:passed+=1
	else:failed+=1

func fixture(count:int)->Array:
	var jobs:Array=[]
	for i:int in count:
		var payload:=PackedByteArray();payload.resize(65536)
		for j:int in payload.size():payload[j]=(j*17+i)%251
		var bytes:=Store._compressed(var_to_bytes({"kind":"timing_fixture","id":i,"nested":{"values":[i,i+1]},"payload":payload}))
		var digest:=Store._sha(bytes)
		var target:=directory.path_join(digest+".rmres")
		var file:=FileAccess.open(target,FileAccess.WRITE)
		file.store_buffer(bytes);file.close();files.append(target)
		jobs.append({"id":i,"location":target,"sha256":digest,"length":bytes.size()})
	return jobs

func row_for(profile:Dictionary,index:int)->Dictionary:
	for row:Dictionary in profile.rows:
		if row.index==index:return row
	return {}

func total_bytes(jobs:Array)->int:
	var value:=0
	for job:Dictionary in jobs:value+=job.length
	return value

func validate_timeline(profile:Dictionary,label:String)->void:
	var valid:bool=profile.end_us>=profile.start_us and profile.wall_us==profile.end_us-profile.start_us
	for worker:Dictionary in profile.workers:
		valid=valid and worker.thread_id>0 and worker.start_us>=profile.start_us and worker.end_us<=profile.end_us
	for row:Dictionary in profile.rows:
		valid=valid and row.start_us<=row.claim_end_us and row.claim_end_us<=row.read_start_us and row.read_start_us<=row.read_end_us and row.read_end_us<=row.end_us and row.end_us<=profile.end_us
		valid=valid and row.claim_lock_wait_us>=0 and row.claim_lock_wait_us<=row.claim_us
		var stages:=0
		for key:String in Store.READ_TIMING_STAGES:stages+=row[key];valid=valid and row[key]>=0
		valid=valid and stages+row.reader_other_us==row.reader_us
	for join:Dictionary in profile.joins:valid=valid and join.start_us<=join.end_us and join.end_us<=profile.end_us
	check(valid,label)

func run()->void:
	var errors:=Errors.new();OS.add_logger(errors)
	check(not Store.read_timing_enabled,"fine read timing is disabled by default")
	var previous_limit:=Store.read_timing_row_limit
	directory=Paths.cache_directory("read_timing_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	check(DirAccess.make_dir_recursive_absolute(directory)==OK,"temporary external fixture directory created")
	var jobs:=fixture(8);var original:=jobs.duplicate(true)
	var normal:=Store._read_many(jobs,true,2,Store._read_package_job)
	check(normal.ok and not normal.read_profile.has("diagnostics"),"disabled reader keeps the normal report contract")
	Store.read_timing_enabled=true;Store.read_timing_row_limit=256
	var measured:=Store._read_many(jobs,true,2,Store._read_package_job)
	check(measured.ok and measured.entries==normal.entries and jobs==original,"diagnostic reads preserve definitions, source identities and caller requests")
	check(measured.read_profile.completed==normal.read_profile.completed and measured.read_profile.unique_resources==normal.read_profile.unique_resources,"diagnostics do not add reads or decoded work")
	var profile:Dictionary=measured.read_profile.diagnostics
	check(profile.rows.size()==jobs.size() and profile.rows_omitted==0 and profile.workers.size()==2 and profile.launches.size()==2 and profile.joins.size()==2,"each real request and each worker boundary is reported once")
	check(profile.totals.file_bytes==total_bytes(jobs) and profile.totals.payload_bytes==total_bytes(jobs) and profile.totals.raw_bytes>profile.totals.payload_bytes,"actual file bytes and decompressed workload are counted separately")
	check(profile.totals.zstd_us>0 and profile.totals.bytes_to_var_us>0,"real compressed fixtures exercise ZSTD and object-free Variant decoding")
	validate_timeline(profile,"wall stages and absolute worker/request/join timestamps are internally consistent")
	var delayed:=DelayedReader.new()
	measured=Store._read_many(jobs,true,2,delayed.read)
	profile=measured.read_profile.diagnostics
	var first:=row_for(profile,0);var second:=row_for(profile,1)
	check(measured.ok and measured.entries==normal.entries,"two workers with a delayed first request still return the complete original order")
	check(second.read_end_us<first.read_end_us and second.thread_id!=first.thread_id,"the second worker completes independently of the stalled first request")
	check(first.reader_other_us>=40000 and first.reader_us>second.reader_us,"injected delay is attributed to reader remainder, not file/ZSTD/Variant stages")
	validate_timeline(profile,"delayed out-of-order reads preserve timeline accounting")
	delayed=DelayedReader.new();delayed.fail_second=true
	measured=Store._read_many(jobs,true,2,delayed.read)
	profile=measured.read_profile.diagnostics
	check(not measured.ok and measured.error==ERR_FILE_CANT_READ and measured.read_profile.completed==2 and measured.read_profile.workers_joined==2,"a real missing-file error stops new claims and joins the delayed sibling")
	check(profile.rows.size()==2 and row_for(profile,0).ok and not row_for(profile,1).ok and row_for(profile,0).end_us<=profile.end_us,"failure reports retain both completed requests after join, including the successful sibling")
	Store.read_timing_row_limit=2
	measured=Store._read_many(jobs,true,2,Store._read_package_job)
	profile=measured.read_profile.diagnostics
	var summaries:=0
	for worker:Dictionary in profile.workers:
		summaries+=worker.requests
		check(worker.requests==0 or not worker.slowest_row.is_empty(),"bounded report retains the worker's slowest request")
	check(profile.rows.size()==2 and profile.rows_omitted==6 and summaries==8 and profile.totals.file_bytes==total_bytes(jobs),"row cap does not truncate workload totals or completed reads")
	measured=Store._read_many(jobs,true,2,Store._read_package_job,func(_worker:Thread,_task:Callable)->int:return ERR_CANT_CREATE)
	profile=measured.read_profile.diagnostics
	check(measured.ok and profile.launches.size()==2 and profile.joins.is_empty() and profile.workers.size()==1 and profile.workers[0].kind=="fallback" and measured.read_profile.fallback_count==2,"failed launches retain boundaries and report the caller fallback without fictitious joins")
	# A mounted bundle uses real file IO at an offset; supplied bytes perform no IO.
	var bundle_path:=directory.path_join("fixture.bundle")
	var bundle:=FileAccess.open(bundle_path,FileAccess.WRITE);bundle.store_buffer(PackedByteArray([1,2,3,4]))
	bundle.store_buffer(FileAccess.get_file_as_bytes(jobs[0].location));bundle.close();files.append(bundle_path)
	Store._mutex.lock();Store._bundled[jobs[0].location]=[bundle_path,4,jobs[0].length];Store._mutex.unlock()
	measured=Store._read_many([jobs[0]],true,1,Store._read_package_job)
	profile=measured.read_profile.diagnostics
	check(measured.ok and profile.rows[0].source=="bundle" and profile.totals.bundle_bytes==jobs[0].length and profile.totals.file_bytes==0,"bundle lookup/read and bytes are separate from direct file IO")
	Store._mutex.lock();Store._bundled.erase(jobs[0].location);Store._mutex.unlock()
	var supplied:Dictionary=jobs[0].duplicate();supplied.bytes=FileAccess.get_file_as_bytes(supplied.location)
	measured=Store._read_many([supplied],true,1,Store._read_package_job)
	profile=measured.read_profile.diagnostics
	check(measured.ok and profile.rows[0].source=="supplied" and profile.totals.supplied_bytes==jobs[0].length and profile.totals.file_bytes==0 and profile.totals.bundle_bytes==0,"pre-read payload counts bytes without inventing worker disk reads")
	measured=Store._read_many([])
	check(measured.ok and measured.read_profile.diagnostics.rows.is_empty() and measured.read_profile.diagnostics.workers.is_empty(),"empty measured request starts no workers")
	Store.read_timing_enabled=false;Store.read_timing_row_limit=previous_limit
	measured=Store._read_many(jobs,true,2,Store._read_package_job)
	check(measured.ok and not measured.read_profile.has("diagnostics") and measured.entries==normal.entries,"disabling after diagnostics restores the exact ordinary output shape")
	check(errors.count==0,"no GDScript runtime errors occurred")
	for target:String in files:DirAccess.remove_absolute(target)
	DirAccess.remove_absolute(directory)
	OS.remove_logger(errors)
	print("MAP_RESOURCE_READ_TIMING passed=",passed," failures=",failed)
	quit(1 if failed else 0)
