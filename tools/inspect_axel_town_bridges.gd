extends SceneTree
## Read-only headless bridge content probe. Writes only its independent report.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Tools=preload("res://scripts/world_editor/bridge_tools.gd")
const Data=preload("res://scripts/world3d/bridge_data.gd")
const Clear=preload("res://scripts/world_editor/bridge_clearance.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const FORMAL="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const OUTPUT="D:/code/rmmo_runtime/review_artifacts/axel_town_terrain_20261014/bridge_site_probe.json"
const ENDS=[[[219,83],[244,60]],[[301,165],[329,159]],[[274,235],[296,256]],[[229,275],[247,295]],[[200,325],[230,325]]]
func _initialize()->void:call_deferred("run")
func run()->void:
	var doc=Doc.open_file(FORMAL)
	if doc==null:push_error("formal map unreadable");quit(1);return
	var library=preload("res://scripts/world_editor/surface_material_library.gd").new()
	var materials:Dictionary={}
	for role:String in Data.default_materials():materials[role]=library.find(Data.default_materials()[role])
	var grounds:Array=doc.records.filter(func(r):return r.has("terrain_mesh"))
	if "--final" in OS.get_cmdline_user_args():
		var helper=preload("res://tools/axel_town_bridge_recipe.gd")
		var final:Dictionary={"requests":helper.requests(),"notes":helper.notes(),"checks":[],"formal_sha256":FileAccess.get_sha256(FORMAL),"module_path":"D:/code/rmmo_runtime/packs/default/assets/bridges/medieval_stone/stone_segmental.glb"}
		final.module_sha256=FileAccess.get_sha256(final.module_path)
		var failures:=0
		for request:Dictionary in final.requests:
			var record:=Tools.make_record(request,Data.preset("stone_segmental"));record.bridge_materials=materials
			var result:Dictionary=Clear.fit(record,doc.records,false)
			var mesh=preload("res://scripts/world3d/bridge_mesh.gd").new().build(record)
			var counts:Array=[]
			for slot in mesh.get_surface_count():counts.append(mesh.surface_get_array_index_len(slot)/3)
			var checked:Dictionary={"id":request.id,"schema_valid":Data.S.validate(request,Data.request_schema()).is_empty(),"geometry_valid":Data.valid(record),"navigation":result,"max_grade":(record.bridge_mesh.camber*PI+absf(record.bridge_mesh.rise))/record.bridge_mesh.length,"triangles_per_surface":counts,"lod_triangle_counts":mesh.get_meta("bridge_lods",[]),"foundation_bottom":record.position[1]-record.bridge_mesh.depth,"support_and_visual_status":"Pending actual raised/levelled road approaches and GPU integration; headless checks do not prove placement support."}
			if not result.ok or not checked.schema_valid or not checked.geometry_valid:failures+=1
			final.checks.append(checked);print(JSON.stringify(checked))
		final.failures=failures
		var out_path:="D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014/bridges.json"
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var output:=FileAccess.open(out_path,FileAccess.WRITE);output.store_string(JSON.stringify(final,"\t"));output.close()
		print("AXEL_BRIDGE_FINAL ",out_path," failures=",failures);quit(0 if failures==0 else 1);return
	var report:Dictionary={"formal_path":FORMAL,"formal_sha256":FileAccess.get_sha256(FORMAL),"bridges":[],"map_unchanged":true,"scope":"Read-only native height samples and actual native bridge geometry clearance; no map writes, GPU or runtime visual approval."}
	for i in 5:
		var a:=Vector3(ENDS[i][0][0],0,ENDS[i][0][1]);var b:=Vector3(ENDS[i][1][0],0,ENDS[i][1][1])
		a.y=Tools.ground_height(grounds,a);b.y=Tools.ground_height(grounds,b)
		var direction:Vector3=(b-a).normalized();direction.y=0;direction=direction.normalized()
		var cross_axis:=Vector3(-direction.z,0,direction.x)
		var width:float=[7.2,7.2,8.2,6.2,6.2][i]
		var site:Dictionary={"number":i+1,"start_terrain":City.xyz(a),"end_terrain":City.xyz(b),"width":width,"length":Vector2(b.x-a.x,b.z-a.z).length(),"support":[],"axis":[],"trials":[]}
		var low:=INF
		for j in 61:
			var p:Vector3=a.lerp(b,j/60.)
			var ground:float=Tools.ground_height(grounds,p)
			low=minf(low,ground)
			site.axis.append({"t":j/60.,"ground":ground})
		for end in [0,1]:
			var p:Vector3=(a if end==0 else b)+direction*(-.06 if end==0 else .06)
			var heights:Array=[]
			for side in [-1,0,1]:heights.append(Tools.ground_height(grounds,p+cross_axis*side*(width*.5-.6)))
			site.support.append(heights)
		site.bed_min=low
		var args:Dictionary={"id":"axel_bridge_%d"%(i+1),"prefab_id":"stone_segmental","start":City.xyz(a+Vector3.UP*.04),"end":City.xyz(b+Vector3.UP*.04),"width":width,"depth":maxf(1.5,(a.y+b.y)*.5+.04-low+.5),"camber":.25,"arches":[4,3,3,3,3][i],"wing_length":0.,"wear":.12,"moss":.12,"variation_seed":14100+i,"auto_clearance":true}
		site.request=args.duplicate(true)
		for raise_ in ([0.] if i<2 else [0.,.5,1.,1.5]):
			var trial:=args.duplicate(true)
			trial.start[1]+=raise_;trial.end[1]+=raise_;trial.depth+=raise_
			var record:=Tools.make_record(trial,Data.preset("stone_segmental"));record.bridge_materials=materials
			var result:Dictionary=Clear.fit(record,doc.records,true)
			site.trials.append({"raised_heads":raise_,"result":result,"final_camber":record.bridge_mesh.camber,"depth":record.bridge_mesh.depth,"grade":(record.bridge_mesh.camber*PI+absf(record.bridge_mesh.rise))/record.bridge_mesh.length})
			print("BRIDGE ",i+1," raise=",raise_," ",JSON.stringify(site.trials[-1]))
		report.bridges.append(site)
	var f:=FileAccess.open(OUTPUT,FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("AXEL_BRIDGE_SITE_PROBE ",OUTPUT)
	quit(0)
