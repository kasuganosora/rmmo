extends SceneTree
const City=preload("res://scripts/world3d/city_layout.gd")
const Ports=preload("res://scripts/world3d/road_bridges.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Cut=preload("res://scripts/world_editor/bridge_road_cut.gd")
var failed:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failed+=1
func _initialize()->void:
	var edge:={"id":"bound","from":"a","to":"b","width_start":6.,"width_end":6.,"kind":"bridge"}
	var neighbor:={"id":"approach","from":"c","to":"a","width_start":6.,"width_end":6.,"kind":"ground"}
	var nodes:={"a":{"id":"a","position":[0,0,0]},"b":{"id":"b","position":[40,2,0]},"c":{"id":"c","position":[-20,0,0]}}
	var line:=Ports.deck_line(edge,nodes,[edge,neighbor]);var a:Vector3=line[0].lerp(line[1],.2);var b:Vector3=line[0].lerp(line[1],.8)
	var lift:=.04;edge.stone_bridge={"id":"bridge","start":City.xyz(a+Vector3.UP*lift),"end":City.xyz(b+Vector3.UP*lift),"width":7.2,"signature":"a".repeat(64),"source_token":Ports.stone_source(edge,nodes)}
	var layout:={"roads":{"nodes":nodes.values(),"edges":[edge,neighbor]},"road_surface":{"settings":{"lift":lift}}}
	check(Ports.resolve(layout).ok,"bound sloped bridge accepts original custom lift")
	neighbor.width_end=12.;check(not Ports.resolve(layout).ok,"neighbor widening rejects changed ramp without source token change")
	neighbor.width_end=4.;check(Ports.resolve(layout).ok,"narrow neighbor preserving ramp remains valid")
	layout.road_surface.settings.lift=.02;check(not Ports.resolve(layout).ok,"binding rejects detached deck height")
	var road:={"uuid":"road","kind":"box","position":[0,0,0],"rotation":[0,0,0],"size":[32,.2,32],"road_mesh":{"polygons":[[[-.4,-.2],[.4,-.2],[.4,.2],[-.4,.2]]],"uv_origin":[0,0,0]},"terrain_follow":{"version":1,"terrain_ids":["ground"],"polygons":[[[-.4,-.2],[.4,-.2],[.4,.2],[-.4,.2]]],"offset":.025,"max_grade":.15}}
	var section_a:Array=[];var section_b:Array=[]
	for point:Vector2 in [Vector2(0,-.04),Vector2(0,.05),Vector2(.01,.06),Vector2(.25,.06),Vector2(.26,.05),Vector2(.26,-.04)]:
		section_a.append([-12,.1+point.y,-6.4+point.x]);section_b.append([12,.1+point.y,-6.4+point.x])
	var kerb:={"a":section_a,"b":section_b,"u":7.,"length":24.,"cap_a":false,"cap_b":false}
	road.road_mesh.kerbs=[kerb];road.terrain_follow.kerbs=[kerb.duplicate(true)]
	var mask:Array=[Vector2(-5,-7),Vector2(5,-7),Vector2(5,7),Vector2(-5,7)]
	var clipped:=Cut.cut(road,mask,.1,[Vector3(-5,.1,0),Vector3(5,.1,0)])
	check(clipped.ok and clipped.changed,"road with automatic kerb clips")
	if clipped.ok and clipped.changed:
		var parts:Array=clipped.record.road_mesh.get("kerbs",[])
		check(parts.size()==2 and absf(parts[0].length+parts[1].length-14.)<.001,"kerb crossing bridge removed with road slab")
		check(parts.size()==2 and absf(parts[1].u-24.)<.001 and parts[0].cap_b and parts[1].cap_a and not parts[0].cap_a and not parts[1].cap_b,"kerb UV continuity and end caps retained")
		check(clipped.record.terrain_follow.kerbs==parts,"terrain re-fit cannot restore removed kerb")
	var graph:={"nodes":[{"id":"left","position":[-26,0,0]},{"id":"right","position":[26,1,0]}],"edges":[{"id":"ramp","from":"left","to":"right","width_start":6.,"width_end":6.,"kind":"bridge"}]}
	var settings:=Plan.defaults();var baseline:=Plan.build(graph,settings)
	check(baseline.ok,"ramp baseline")
	var portal:={"road_stone":true,"edge_id":"other_road","endpoints":[[-15,.5+.025-15./46.,0],[15,.5+.025+15./46.,0]],"polygon":[Vector2(-15,-4),Vector2(15,-4),Vector2(15,4),Vector2(-15,4)]}
	var rebuilt:=Plan.build(graph,settings,[portal]);check(rebuilt.ok and City.token(rebuilt.records)==City.token(baseline.records),"bridge mask cannot erase a different crossing road")
	portal.edge_id="ramp";portal.endpoints=[[-15,.525,0],[15,.525,0]]
	rebuilt=Plan.build(graph,settings,[portal]);check(rebuilt.ok and City.token(rebuilt.records)==City.token(baseline.records),"matching midpoint alone cannot erase different slope")
	portal.endpoints=[[-15,.5+.025-15./46.,0],[15,.5+.025+15./46.,0]]
	rebuilt=Plan.build(graph,settings,[portal]);check(rebuilt.ok and City.token(rebuilt.records)!=City.token(baseline.records),"matching bound slope still cuts")
	print("STRUCTURE_BOUNDARY_REVIEW_FINISHED failures=",failed);quit(failed)
