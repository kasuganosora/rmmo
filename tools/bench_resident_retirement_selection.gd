extends SceneTree
const Selection=preload("res://scripts/world3d/resident_retirement_selection.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var output:="";var results:Array=[];var candidate:Script
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--candidate="):candidate=load(arg.trim_prefix("--candidate="))
	for count_:int in [2200,8800]:
		for dense:bool in [false,true]:
			var by_id:Dictionary={};var ids:Array=[];var ground:Dictionary={}
			for i:int in count_:
				var id:="guild__part%d"%i
				var extra:Dictionary={"kind":"asset","building":{"id":"group%d"%(i%10)}}
				if i%100==0:extra.fixture={"id":"door%d"%i,"kind":"door","open":float(i)/count_}
				var record:Dictionary={"uuid":"part%d"%i,"asset_path":"model%d.res"%(i%8),"house_prefab":{"sha256":"digest%d"%(i%32)}} if dense else {}
				by_id[id]={"uuid":id,"extras":extra,"ground_batch_record":record,"render_building":"group%d"%(i%10)};ids.append(id)
			var reference:=Selection.rows(by_id,ground,ids,true)
			var unit:Dictionary={"members":reference.selected,"member_groups":{},"group_counts":reference.groups,"ground_members":ground}
			for id:String in ids:unit.member_groups[id]=by_id[id].render_building
			for workers:int in ([1,2,4,8,0,0,8,4,2,1] if candidate!=null else [1,2,4,8,8,4,2,1]):
				var samples:Array=[]
				for repeat:int in 7:
					var began:=Time.get_ticks_usec()
					var result:Dictionary=candidate.catalogued(by_id,ids,unit,"guild",true) if workers==0 else Selection.prepare(by_id,ground,ids,true,workers)
					samples.append(Time.get_ticks_usec()-began)
					if result!=reference:push_error("Retirement projection differs");quit(1);return
				samples.sort()
				var row:={"count":count_,"dense":dense,"workers":workers,"median_us":samples[3],"max_us":samples[-1],"min_us":samples[0]}
				results.append(row);print(JSON.stringify(row))
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
	quit()
