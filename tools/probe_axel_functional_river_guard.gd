extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Layer=preload("res://scripts/world3d/terrain_river_layer.gd")
const T=preload("res://scripts/world3d/terrain_surface.gd")
const Batch=preload("res://scripts/world3d/terrain_stroke_batch.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const MAP="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf"
const FORMAL="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
func _init()->void:call_deferred("run")
func location(record:Dictionary,index:int)->Array:
	var x:int=index%(int(record.terrain_mesh.columns)+1);var z:int=index/(int(record.terrain_mesh.columns)+1)
	return City.xyz(T.transform(record)*T.point(record,x,z))
func audit(doc:RefCounted,relevant:Dictionary)->Array:
	var result:Array=[];var layers:Array=doc.map_meta.terrain_rivers
	for li:int in layers.size():
		var layer:Dictionary=layers[li]
		for item:Dictionary in layer.terrains:
			var actual:Dictionary=doc._find(item.after.uuid);var restored:=Layer.restore(actual,item.before,item.after)
			if restored.ok:continue
			var count:=0;var points:Array=[];var attributed:=0
			for field:String in ["heights","holes"]:
				for i:int in item.after.terrain_mesh[field].size():
					if Layer.same(item.before.terrain_mesh[field][i],item.after.terrain_mesh[field][i]) or Layer.same(actual.terrain_mesh[field][i],item.after.terrain_mesh[field][i]):continue
					count+=1;var later:Array=[]
					for lj:int in range(li+1,layers.size()):
						for other:Dictionary in layers[lj].terrains:
							if other.after.uuid==actual.uuid and Layer.same(other.before.terrain_mesh[field][i],item.after.terrain_mesh[field][i]) and Layer.same(other.after.terrain_mesh[field][i],actual.terrain_mesh[field][i]):later.append({"id":layers[lj].id,"outlet":layers[lj].request.get("outlet",{})})
					if not later.is_empty():attributed+=1
					if points.size()<24:points.append({"field":field,"index":i,"xyz":location(actual,i) if field=="heights" else [],"layer_before":item.before.terrain_mesh[field][i],"layer_after":item.after.terrain_mesh[field][i],"current":actual.terrain_mesh[field][i],"later_owned_overlay":later})
			result.append({"river":layer.id,"tile":actual.uuid,"touched_by_new_building_grading":relevant.has(actual.uuid),"error":restored.error,"mismatch_count":count,"attributed_to_later_layers":attributed,"samples":points})
	return result
func run()->void:
	var sha:=FileAccess.get_sha256(MAP);var doc=Doc.open_file(MAP);var formal=Doc.open_file(FORMAL)
	if doc==null or formal==null:push_error("native input open failed");quit(1);return
	var proof:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/functional_buildings_apply_terrain_failure_first.json"))
	var working=Doc.new();working.apply_recovery(doc.recovery_snapshot());var touched:Dictionary={};var batches:Array=[]
	for request:Dictionary in proof.terrain_request.strokes:
		var prepared:=Batch.prepare(working.records,working._find(request.id),request)
		if not prepared.ok:push_error(str(prepared));quit(1);return
		batches.append({"request":request,"terrain_ids":prepared.entries.map(func(e):return e.record.uuid)})
		for entry:Dictionary in prepared.entries:
			touched[entry.record.uuid]=true
			for i:int in working.records.size():
				if working.records[i].uuid==entry.record.uuid:working.records[i]=entry.record;break
	var changed_owned:Array=[];var original_to_candidate:Array=[]
	for layer:Dictionary in doc.map_meta.terrain_rivers:
		for item:Dictionary in layer.terrains:
			var current:Dictionary=doc._find(item.after.uuid);var after:Dictionary=working._find(item.after.uuid);var old:Dictionary=formal._find(item.after.uuid)
			var changed:Array=[];var from_formal:Array=[]
			for i:int in item.after.terrain_mesh.heights.size():
				if Layer.same(item.before.terrain_mesh.heights[i],item.after.terrain_mesh.heights[i]):continue
				if not Layer.same(current.terrain_mesh.heights[i],after.terrain_mesh.heights[i]):changed.append({"index":i,"xyz":location(current,i),"before":current.terrain_mesh.heights[i],"after":after.terrain_mesh.heights[i]})
				if not Layer.same(current.terrain_mesh.heights[i],old.terrain_mesh.heights[i]):from_formal.append({"index":i,"xyz":location(current,i),"formal":old.terrain_mesh.heights[i],"candidate":current.terrain_mesh.heights[i]})
			if not changed.is_empty():changed_owned.append({"river":layer.id,"tile":item.after.uuid,"samples":changed})
			if not from_formal.is_empty():original_to_candidate.append({"river":layer.id,"tile":item.after.uuid,"samples":from_formal})
	var report:={"read_only":true,"candidate_sha256":sha,"formal_sha256":FileAccess.get_sha256(FORMAL),"requests":batches,"touched_tiles":touched.keys(),"candidate_restore_failures":audit(doc,touched),"formal_restore_failures":audit(formal,touched),"new_grading_changes_owned_samples":changed_owned,"formal_to_candidate_owned_changes":original_to_candidate,"candidate_unchanged":FileAccess.get_sha256(MAP)==sha}
	var file:=FileAccess.open(OUT+"/functional_river_guard_diagnostic.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0)
