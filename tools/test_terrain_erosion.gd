extends "res://tools/test_terrain_surface.gd"
func _initialize() -> void:
	var r:=fixture()
	for z in 9:
		for x in 9: r.terrain_mesh.heights[z*9+x]=4. if x>=4 else 0.
	var args:={"id":r.uuid,"mode":"erode","points":[[0,0]],"radius":4.,"strength":2.,"iterations":12,"talus_angle":35.,"erosion_seed":17}
	var before:=r.duplicate(true); var result:=T.stroke(r,args)
	check(result.ok and result.changed and r==before,"erosion changes a copy only")
	check(result.record==T.stroke(r,args).record,"erosion repeats exactly with the same seed")
	check(result.record!=T.stroke(r,args.merged({"erosion_seed":81},true)).record,"seed changes spatial weathering")
	var sum_before:=0.; var sum_after:=0.; var pinned:=true; var footprint:=true
	for z in 9:
		for x in 9:
			var at:=z*9+x; sum_before+=r.terrain_mesh.heights[at]; sum_after+=result.record.terrain_mesh.heights[at]
			if x==0 or x==8 or z==0 or z==8: pinned=pinned and r.terrain_mesh.heights[at]==result.record.terrain_mesh.heights[at]
			if Vector2(x-4,z-4).length()>=4: footprint=footprint and r.terrain_mesh.heights[at]==result.record.terrain_mesh.heights[at]
	check(absf(sum_before-sum_after)<.0000001,"uniform-grid volume conserved including deposits")
	check(result.record.terrain_mesh.heights[4*9+4]<4 and result.record.terrain_mesh.heights[4*9+3]>0,"crest recedes and foot gains actual geometry")
	check(pinned and footprint,"patch borders and brush exterior unchanged")
	check(result.record.terrain_mesh.heights.min()>=0 and result.record.terrain_mesh.heights.max()<=4,"relaxation adds no spikes or bedrock underflow")
	check(T.mesh(r,null).get_faces().size()==T.mesh(result.record,null).get_faces().size(),"erosion adds no triangles or material surfaces")
	check(not T.stroke(fixture(),args).changed,"flat terrain is a no-op")
	var moved:=r.duplicate(true); moved.position=[12,7,-3]; moved.rotation=[0,90,0]; moved.size=[16,2,8]
	var transformed:=T.stroke(moved,args.merged({"points":[[12,-3]]},true))
	var largest_loss:=0.
	for at in r.terrain_mesh.heights.size(): largest_loss=maxf(largest_loss,(float(moved.terrain_mesh.heights[at])-float(transformed.record.terrain_mesh.heights[at]))*2.)
	check(transformed.ok and transformed.changed and largest_loss<=2.000001,"world brush coordinates and metre budget respect yaw and height scaling")
	var holed:=r.duplicate(true); holed.terrain_mesh.holes[3*8+3]=true
	var hole_result:=T.stroke(holed,args)
	check(hole_result.record.terrain_mesh.holes==holed.terrain_mesh.holes,"hole mask unchanged")
	for at in [3*9+3,3*9+4,4*9+3,4*9+4]: check(hole_result.record.terrain_mesh.heights[at]==holed.terrain_mesh.heights[at],"hole-edge vertex is pinned")
	for invalid in [{"iterations":33},{"talus_angle":0},{"erosion_seed":-1}]: check(not T.stroke(r,args.merged(invalid,true)).ok,"invalid erosion settings reject")
	var large:=r.duplicate(true); large.size=[64,1,64]; large.terrain_mesh.columns=64; large.terrain_mesh.rows=64
	large.terrain_mesh.heights.resize(4225); large.terrain_mesh.heights.fill(0.); large.terrain_mesh.holes.resize(4096); large.terrain_mesh.holes.fill(false)
	check(not T.stroke(large,args.merged({"points":[[-30,0],[30,0],[-30,0]],"radius":32.,"iterations":32},true)).ok,"excess work rejects before changing data")
	for z in 65:
		for x in 65: large.terrain_mesh.heights[z*65+x]=6. if x>=32 else 0.
	var begin:=Time.get_ticks_usec(); var timed:=T.stroke(large,args.merged({"radius":8.,"iterations":8},true))
	print("EROSION_CPU_64x64_LOCAL_MS=",(Time.get_ticks_usec()-begin)/1000.)
	check(timed.ok and timed.changed,"bounded 64x64 operation completes")
	print("TERRAIN_EROSION_FINISHED failures=",failures); quit(1 if failures else 0)
