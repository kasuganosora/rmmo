extends SceneTree
const T=preload("res://scripts/world3d/terrain_surface.gd")
const P=preload("res://scripts/world_editor/terrain_mesh_incremental.gd")
var failed:=0
var comparisons:=0
func check(ok:bool,label:String)->void:
	comparisons+=1
	if not ok:failed+=1;push_error(label)
func compare(r:Dictionary,next:Dictionary,context:Dictionary,label:String)->Dictionary:
	var arrays:=T.arrays(r,context);var original:=var_to_bytes(arrays)
	var state:={"record":r,"arrays":arrays,"normals":context.get("normals",{}),"vertex_map":P.mapping(r,arrays)}
	var patch:=P.patch(state,next,context)
	check(not patch.is_empty(),label+" eligible")
	if not patch.is_empty():check(patch.arrays==T.arrays(next,context),label+" exact all channels")
	check(original==var_to_bytes(arrays),label+" immutable input")
	return patch
func _initialize()->void:
	var rng:=RandomNumberGenerator.new();rng.seed=101718
	var exact:=0;var fallback:=0;var noops:=0;var worst:=0.;var old_us:=0;var new_us:=0
	for trial in 80:
		comparisons+=2 # Full-array equivalence and source immutability.
		var r:=preload("res://tools/test_terrain_incremental.gd").fixture()
		if trial%3!=0:
			for z in 65:
				for x in 65:r.terrain_mesh.heights[z*65+x]=sin(x*.17)*cos(z*.13)*2.
		var arrays:=T.arrays(r);var state:={"record":r,"arrays":arrays,"normals":{},"vertex_map":P.mapping(r,arrays)}
		var args:={"id":r.uuid,"mode":["raise","lower","smooth","flatten"][trial%4],"points":[[rng.randf_range(-20,20),rng.randf_range(-20,20)]],"radius":rng.randf_range(.5,4.),"strength":.3,"target_height":.5}
		var old_bytes:=var_to_bytes(arrays)
		var next:Dictionary=T.stroke(r,args).record;var start:=Time.get_ticks_usec();var current:=P.patch(state,next,{})
		if next!=r:new_us+=Time.get_ticks_usec()-start
		else:noops+=1
		start=Time.get_ticks_usec();var full:=T.arrays(next)
		if next!=r:old_us+=Time.get_ticks_usec()-start
		if current.is_empty():fallback+=1;continue
		if current.arrays==full:exact+=1
		else:
			for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT]:
				var a:Variant=current.arrays[0][channel];var b:Variant=full[0][channel]
				for i in a.size():
					if a[i]!=b[i]:worst=maxf(worst,absf(a[i]-b[i]) if channel==Mesh.ARRAY_TANGENT else a[i].distance_to(b[i]))
			failed+=1;push_error("CPU arrays differ %d"%trial)
		if var_to_bytes(state.arrays)!=old_bytes:failed+=1;push_error("source array mutated")
	for trial in 24:
		var n:int=[16,32,64][trial%3];var r:=preload("res://tools/test_terrain_incremental.gd").fixture(n)
		r.size=[.01 if trial%4==0 else 47.,.1 if trial%2==0 else 3.,71.]
		for at in r.terrain_mesh.heights.size():r.terrain_mesh.heights[at]=sin(at*.23)*.5
		r.terrain_mesh.holes[2*n+2]=true
		var next:Dictionary=r.duplicate(true);var middle:int=(n/2)*(n+1)+n/2
		next.terrain_mesh.heights[middle]+=.13
		# Stable seam/override normals must also participate in local tangents.
		var context:={"normals":{0:Vector3.UP,middle:Vector3(.1,1,.2).normalized()}}
		compare(r,next,context,"nonuniform/hole/normal %d"%trial)
	var r:=preload("res://tools/test_terrain_incremental.gd").fixture()
	var a:=T.arrays(r);var state:={"record":r,"arrays":a,"normals":{},"vertex_map":P.mapping(r,a)}
	for step in 8:
		var next:Dictionary=r.duplicate(true);next.terrain_mesh.heights[(32+step)*65+32]+=.2
		var bytes:=var_to_bytes(state.arrays);var result:=P.patch(state,next,{})
		check(not result.is_empty() and result.arrays==T.arrays(next),"sequential publication %d"%step)
		check(bytes==var_to_bytes(state.arrays),"sequential source immutable %d"%step)
		if not result.is_empty():state.arrays=result.arrays;state.record=next;r=next
	for kind in ["boundary","hole_edge","large","topology","normal_context"]:
		var next:Dictionary=r.duplicate(true);var context:Dictionary={}
		match kind:
			"boundary":next.terrain_mesh.heights[0]+=.2
			"hole_edge":
				state.record=r.duplicate(true);state.record.terrain_mesh.holes[32*64+32]=true
				next=state.record.duplicate(true);next.terrain_mesh.heights[32*65+32]+=.2
			"large":
				for z in range(2,63):
					for x in range(2,63):next.terrain_mesh.heights[z*65+x]+=.2
			"topology":next.terrain_mesh.holes[0]=true
			"normal_context":context={"normals":{0:Vector3.UP}}
		check(P.patch(state,next,context).is_empty(),kind+" selects full canonical fallback")
		state.record=r
	check(exact==80 and fallback==0,"representative internal edits stay eligible")
	var report:={"failed":failed,"checks":comparisons,"exact":exact,"fallback":fallback,"unchanged_cases":noops,"timed_changed_cases":80-noops,"worst":worst,"old_us":old_us,"new_us":new_us,"method":"80 deterministic interior brush differentials with full-array equality and input immutability, separate 24 nonuniform/hole/stable-normal cases, 8 sequential publications and 5 canonical fallback cases. Aggregate timings exclude no-op strokes and only cover changed original cases; not end-to-end, no formal statistical claim."}
	DirAccess.make_dir_recursive_absolute("D:/code/rmmo_runtime/review_artifacts/editor_runtime_followup_20261017")
	FileAccess.open("D:/code/rmmo_runtime/review_artifacts/editor_runtime_followup_20261017/cpu_patch.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CPU_PATCH ",JSON.stringify(report));quit(1 if failed else 0)
