extends SceneTree
const Cached=preload("res://review_artifacts/probe_bridge_texture_cache_20261011.gd")
const Original=preload("res://review_artifacts/probe_bridge_source_decode_20261011.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var report:Dictionary={"scope":"same-process read-only warm pixel cache vs original decode+mips without any cache-store; ABBA twice; no GPU or world","rounds":[],"failures":0}
	for round_index:int in 8:
		var cached:bool=round_index%4 in [0,3]
		var began:=Time.get_ticks_usec();var rows:Array=[]
		for name:String in Original.FILES:
			var row:Dictionary=Cached.probe(name) if cached else Original.probe(name)
			if row.has("error"):report.failures+=1
			rows.append(row)
		report.rounds.append({"mode":"warm_cache" if cached else "source_no_write","round":round_index,"batch_wall_us":Time.get_ticks_usec()-began,"images":rows})
		print("PAIR ",round_index," ",report.rounds[-1].mode," ",report.rounds[-1].batch_wall_us)
	var file:=FileAccess.open("res://review_artifacts/bridge_texture_cache_source_pair_20261011.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("PAIR failures=",report.failures);quit(1 if report.failures else 0)
