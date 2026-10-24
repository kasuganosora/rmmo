extends "res://tools/test_selected_terrain_context.gd"
const Selected=preload("res://scripts/world3d/selected_terrain_context.gd")
func run()->void:
	Controls.enable_white_materials()
	var source:=records();var original:=var_to_bytes(source);var trials:Array=[]
	for ids:Dictionary in [{"tile11":true},{"tile00":true,"tile11":true,"tile22":true},{},{"missing":true}]:
		compare(source,ids)
	# Equal-height shared corners, open boundaries, disjoint and tilted tiles,
	# translated/rotated grids and incompatible resolutions retain exact seams.
	for tile:Dictionary in source:
		for i:int in tile.terrain_mesh.heights.size():tile.terrain_mesh.heights[i]=0.
	compare(source,{"tile11":true,"tile00":true})
	source[0].terrain_mesh.holes.fill(true)
	source[0].terrain_mesh.holes[85]=false # Valid tile with an entirely open outer boundary.
	compare(source,{"tile11":true,"tile00":true})
	source[1].rotation[0]=12.;source[2].position[0]+=400.;source[3].size[0]=16.
	compare(source,{"tile11":true,"tile10":true,"tile01":true})
	source=records()
	for tile:Dictionary in source:
		var at:=Vector2(tile.position[0],tile.position[2]).rotated(-PI*.25)
		tile.position=[at.x+100.,3.,at.y-70.];tile.rotation=[0.,45.,0.]
	compare(source,{"tile11":true,"tile22":true})
	source=records()
	for optimized:bool in [false,true,true,false]:
		var started:=Time.get_ticks_usec();var normals:=0;var contexts:=0
		for repeat:int in 96:
			if optimized:
				var packet:=Selected.prepare(source,{"tile11":true});normals+=packet.work.boundary_normals;contexts+=packet.work.contexts
			else:
				var context:=Neighbors.new();context.prepare_selected(source,{"tile11":true});normals+=context.last_work.boundary_vertices;contexts+=context.last_work.contexts
		trials.append({"optimized":optimized,"us":Time.get_ticks_usec()-started,"boundary_normals":normals,"contexts":contexts})
	check(var_to_bytes(source)==original,"preparation does not alter authoring records")
	# The exact operation can run independently in concurrent private workers.
	var workers:Array[Thread]=[];var expected:Dictionary=Selected.prepare(source,{"tile11":true}).data
	for i:int in 4:
		var worker:=Thread.new();check(worker.start(Selected.prepare.bind(source,{"tile11":true}))==OK,"private context worker starts");workers.append(worker)
	for worker:Thread in workers:check(worker.wait_to_finish().data==expected,"parallel result remains exact")
	print("SELECTED_TERRAIN_STRESS ",JSON.stringify({"trials":trials,"failures":failures}))
	Controls.white_materials=false;quit(1 if failures else 0)

func compare(source:Array,ids:Dictionary)->void:
	var reference:=Neighbors.new();reference.prepare_selected(source,ids)
	var packet:=Selected.prepare(source,ids);var actual:Dictionary=packet.data
	check(actual.keys()==reference.data.keys(),"requested context identity and order")
	for id:String in actual:
		var expected:Dictionary=reference.data[id].duplicate();expected.signature=[]
		check(actual[id]==expected,"exact normals, padding and neighbor order for "+id)
		var record:Dictionary={}
		for candidate:Dictionary in source:
			if candidate.uuid==id:record=candidate
		check(var_to_bytes(Terrain.arrays(record,actual[id]))==var_to_bytes(Terrain.arrays(record,expected)),"all geometry channels byte-identical for "+id)
