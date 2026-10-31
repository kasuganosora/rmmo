extends SceneTree
## Runtime contract for a compiler/TLS change, without timing assertions.
var failures:Array[String]=[]
var checks:=0
var main_id:=0
var callbacks:Array[int]=[]

func _initialize()->void:run.call_deferred()

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);printerr("FAIL "+label)

static func sample(iterations:int)->Dictionary:
	var id:=OS.get_thread_caller_id()
	var stable:=true
	for i in iterations:
		if OS.get_thread_caller_id()!=id:stable=false
	return {"id":id,"stable":stable}

func receive()->void:callbacks.append(OS.get_thread_caller_id())

func pooled_sample(output:Array)->void:
	output[0]=sample(10000)
	receive.call_deferred()

func run()->void:
	main_id=OS.get_thread_caller_id()
	check(main_id==OS.get_main_thread_id(),"main identity matches engine main")
	var used:Dictionary={main_id:true}
	# Explicit Thread IDs are assigned before callback entry. Check simultaneous
	# readers and fresh thread generations, not just uniqueness in one batch.
	for generation in 3:
		var workers:Array[Thread]=[]
		var ids:Array[int]=[]
		for i in 12:
			var thread:=Thread.new()
			check(thread.start(sample.bind(20000))==OK,"thread starts")
			workers.append(thread);ids.append(int(thread.get_id()))
		for i in workers.size():
			var result:Dictionary=workers[i].wait_to_finish()
			check(result.stable and result.id==ids[i],"callback matches assigned stable identity")
			check(not used.has(result.id),"new Thread identity never reuses old or main ID")
			used[result.id]=true
		check(OS.get_thread_caller_id()==main_id,"joining keeps main identity")
	var tasks:Array[int]=[]
	var outputs:Array[Array]=[]
	for i in 48:
		var output:Array=[null]
		outputs.append(output)
		tasks.append(WorkerThreadPool.add_task(pooled_sample.bind(output)))
	for i in tasks.size():
		check(WorkerThreadPool.wait_for_task_completion(tasks[i])==OK,"pool task completes")
		var result:Dictionary=outputs[i][0]
		check(result.stable and result.id!=main_id and result.id>0,"pool callback has stable nonmain identity")
	for i in 4:await process_frame
	check(callbacks.size()==tasks.size(),"all deferred callbacks received")
	check(callbacks.all(func(id:int)->bool:return id==main_id),"deferred callbacks use main identity")
	print(JSON.stringify({"test":"thread_identity","checks":checks,"failures":failures,"main":main_id,"thread_generations":3,"threads_per_generation":12,"pool_tasks":tasks.size()}))
	quit(0 if failures.is_empty() else 1)
