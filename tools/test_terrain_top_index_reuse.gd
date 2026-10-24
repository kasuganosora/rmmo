extends SceneTree
## Headless CPU-only reproduction. No Mesh, authored resource writes or GPU.
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Bulk=preload("res://scripts/world3d/terrain_surface_arrays.gd")
const Fixture=preload("res://tools/test_terrain_surface.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func make_case(columns:int,rows:int,pattern:int,holes_mode:int)->Dictionary:
	var record:=Fixture.fixture();var t:Dictionary=record.terrain_mesh
	t.columns=columns;t.rows=rows;t.heights.resize((columns+1)*(rows+1));t.holes.resize(columns*rows)
	record.size=[.01 if pattern==3 else 47.,.1 if pattern==2 else 3.,71.]
	record.position=[173.,9.,-257.];record.rotation=[0.,37.,0.]
	record.terrain_material={"tile_size":[.37,7.1]}
	for z in rows+1:
		for x in columns+1:
			var height:=0.
			if pattern==1:height=sin(x*.23)*cos(z*.17)*.5
			elif pattern==2:height=x*.003+z*.007
			elif pattern==3:height=sin((z*(columns+1)+x)*.13)*.7
			t.heights[z*(columns+1)+x]=height
	for z in rows:
		for x in columns:
			var hole:=false
			if holes_mode==1:hole=(x+z)%3==0
			elif holes_mode==2:hole=x>0 and x<columns-1 and z>0 and z<rows-1
			elif holes_mode==3:hole=(x!=0 or z!=0) and (x!=columns-1 or z!=rows-1)
			t.holes[z*columns+x]=hole
	var context:={"normals":{0:Vector3.UP,columns+2:Vector3(.1,1.,.2).normalized(),rows*(columns+1)+columns:Vector3(-.2,1.,.1).normalized()}}
	return {"record":record,"context":context,"label":"%dx%d pattern=%d holes=%d"%[columns,rows,pattern,holes_mode]}

func referenced_vertices(record:Dictionary)->int:
	var t:Dictionary=record.terrain_mesh;var stride:=int(t.columns)+1;var seen:Dictionary={}
	for z in int(t.rows):
		for x in int(t.columns):
			if t.holes[z*int(t.columns)+x]:continue
			var at:=z*stride+x
			for index in [at,at+1,at+stride+1,at+stride]:seen[index]=true
	return seen.size()

func run()->void:
	var previous_top:=Bulk.indexed_top_enabled;var previous_bulk:=Terrain.bulk_arrays_enabled
	Terrain.bulk_arrays_enabled=true
	var cases:Array=[]
	for dims:Vector2i in [Vector2i(2,2),Vector2i(16,16),Vector2i(64,64),Vector2i(2,64),Vector2i(64,2),Vector2i(3,7),Vector2i(63,31)]:
		for pattern:int in [0,1]:
			cases.append(make_case(dims.x,dims.y,pattern,0 if pattern==0 else 1))
	cases.append(make_case(32,17,2,2))
	cases.append(make_case(31,16,3,3))
	var snapshots:Array=[];var expected:Array=[];var old_writes:=0;var new_writes:=0
	for sample:Dictionary in cases:
		var record:Dictionary=sample.record;var context:Dictionary=sample.context
		var snapshot:=var_to_bytes([record,context]);snapshots.append(snapshot)
		Bulk.indexed_top_enabled=false
		var old:=Terrain.arrays(record,context)
		Bulk.indexed_top_enabled=true
		var current:=Terrain.arrays(record,context)
		var legacy:=Terrain.arrays_legacy(record,context)
		check(var_to_bytes(current)==var_to_bytes(old),"all surfaces exactly match previous bulk "+sample.label)
		check(var_to_bytes(current)==var_to_bytes(legacy),"all surfaces exactly match independent legacy generator "+sample.label)
		var channels_exact:=current.size()==old.size()
		if channels_exact:
			for surface in current.size():
				for slot in Mesh.ARRAY_MAX:
					channels_exact=channels_exact and var_to_bytes(current[surface][slot])==var_to_bytes(old[surface][slot])
		check(channels_exact,"vertices, normals, UV, tangents and indices remain byte-identical "+sample.label)
		var cells:int=record.terrain_mesh.holes.count(false);var unique:=referenced_vertices(record)
		check(current[0][Mesh.ARRAY_INDEX]==old[0][Mesh.ARRAY_INDEX] and current[0][Mesh.ARRAY_INDEX].size()==cells*6,"first-use vertex order and every triangle index preserved "+sample.label)
		check(current[0][Mesh.ARRAY_VERTEX].size()==unique,"holes omit unused grid vertices "+sample.label)
		check(var_to_bytes([record,context])==snapshot,"source heights, holes, transforms and seam normals untouched "+sample.label)
		old_writes+=cells*6;new_writes+=unique
		expected.append(current)
	# The diagnostic flag stays fixed while independent workers share only read
	# inputs. Every invocation owns its lookup, indices and output arrays.
	var workers:Array[Thread]=[]
	for i in 4:
		var worker:=Thread.new();worker.start(Terrain.arrays.bind(cases[i+8].record,cases[i+8].context));workers.append(worker)
	for i in 4:
		check(var_to_bytes(workers[i].wait_to_finish())==var_to_bytes(expected[i+8]),"independent indexed worker output "+str(i))
		check(var_to_bytes([cases[i+8].record,cases[i+8].context])==snapshots[i+8],"worker leaves shared source unchanged "+str(i))
	var trials:Array=[]
	if "--bench" in OS.get_cmdline_user_args():
		# Same frozen inputs and full terrain operation in A1/B1/B2/A2 order;
		# no resource-cache hits or changes to underside/wall generation.
		for indexed:bool in [false,true,true,false]:
			Bulk.indexed_top_enabled=indexed
			var began:=Time.get_ticks_usec();var vertices:=0
			for repeat in 12:
				for sample:Dictionary in [cases[4],cases[5],cases[12],cases[13]]:
					var arrays:=Terrain.arrays(sample.record,sample.context)
					vertices+=arrays[0][Mesh.ARRAY_VERTEX].size()
			trials.append({"indexed":indexed,"us":Time.get_ticks_usec()-began,"top_vertices":vertices})
	Bulk.indexed_top_enabled=previous_top;Terrain.bulk_arrays_enabled=previous_bulk
	print("TERRAIN_TOP_INDEX_REUSE ",JSON.stringify({"cases":cases.size(),"checks":checks,"failures":failures,"top_channel_vertices_written_before":old_writes,"top_channel_vertices_written_after":new_writes,"generic_index_passes_before":cases.size()*2,"generic_index_passes_after":cases.size(),"trials":trials}))
	quit(1 if failures else 0)
