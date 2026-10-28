extends "res://tools/test_road_plan.gd"
## End styles change authored dead ends, not junctions or split-created nodes.
func run()->void:
	var g:=graph([[[0,0,0],[0,0,20]]])
	var legacy:=Plan.build(g,Plan.defaults())
	check(legacy.ok,"old roads retain their round default")
	for first in ["round","flat"]:
		for last in ["round","flat"]:
			var styled:=g.duplicate(true);styled.edges[0].cap_start=first;styled.edges[0].cap_end=last
			var result:=Plan.build(styled,Plan.defaults())
			check(result.ok,"build independent endpoints "+first+" / "+last)
			if not result.ok:continue
			check(covers(result.records,Vector3(0,1,-1))==(first=="round"),"start cap stops at its node when flat")
			check(covers(result.records,Vector3(0,1,21))==(last=="round"),"end cap stops at its node when flat")
			check(covers(result.records,Vector3(1.9,1,.05)) and covers(result.records,Vector3(1.9,1,19.95)),"flat corners retain full road width")
			if first=="round" and last=="round":check(result.records==legacy.records,"explicit round does not alter legacy generated records")
	var bad:=g.duplicate(true);bad.edges[0].cap_end="square"
	check(not Plan.build(bad,Plan.defaults()).ok,"unknown cap fails schema validation")
	var joined:=graph([[[0,0,0],[0,0,20],[10,0,30]]]);var before:=Plan.build(joined,Plan.defaults())
	joined.edges[0].cap_end="flat";joined.edges[1].cap_start="flat"
	var after:=Plan.build(joined,Plan.defaults())
	check(before.ok and after.ok and before.records==after.records,"endpoint styling cannot remove an actual junction fill")
	var crossed:=graph([[[0,0,0],[0,0,20]],[[-10,0,10],[10,0,10]]])
	crossed.edges[0].cap_start="flat";crossed.edges[0].cap_end="flat"
	var split:=Split.split(crossed)
	check(split.ok,"styled street splits at an intersection")
	if split.ok:
		var inherited:=true;var parts:=0
		for edge:Dictionary in split.graph.edges:
			if not edge.id.begins_with("edge_0"):continue
			parts+=1
			inherited=inherited and edge.get("cap_start","round")==("flat" if edge.from==crossed.edges[0].from else "round")
			inherited=inherited and edge.get("cap_end","round")==("flat" if edge.to==crossed.edges[0].to else "round")
		check(parts==2 and inherited,"only original outer endpoints inherit flat style")
		check(Split.split(split.graph).graph==split.graph,"styled split is idempotent")
	var curve:=g.duplicate(true);curve.edges[0].controls=[[0,0,6],[5,0,14]];curve.edges[0].cap_start="flat";curve.edges[0].cap_end="flat"
	var curved:=Plan.build(curve,Plan.defaults())
	check(curved.ok and not covers(curved.records,Vector3(0,1,-1)),"curved road supports flat sampled end sections")
	var slope:=g.duplicate(true);slope.nodes[1].position[1]=1.;slope.edges[0].cap_start="flat";slope.edges[0].cap_end="flat"
	check(Plan.build(slope,Plan.defaults()).ok,"flat ends preserve ramp platform and grade rules")
	var kerbed:=g.duplicate(true);kerbed.edges[0].cap_end="flat"
	var kerb:=Plan.build(kerbed,Plan.defaults().merged({"kerb_enabled":true},true))
	check(kerb.ok and kerb.kerb_length>0,"kerbs regenerate from the flat pavement boundary")
	var placement=preload("res://scripts/world_editor/residential_placement_tools.gd")
	var layout:=Data.defaults();layout.roads=graph([[[-20,0,0],[20,0,0]]])
	layout.roads.edges[0].cap_start="flat";layout.roads.edges[0].cap_end="flat"
	var original:=var_to_bytes(layout)
	var linked:Dictionary=placement._connect(layout,placement._target(layout.roads,"edge_0"),{"position":Vector3(0,0,10),"outward":Vector3.FORWARD},1.,1.6,"caps")
	check(linked.ok,"residential access can split a street with flat endpoints")
	if linked.ok:
		var inherited:=true;var count:=0
		for edge:Dictionary in linked.data.roads.edges:
			if edge.id not in linked.road_connection.child_edge_ids:continue
			count+=1
			inherited=inherited and edge.get("cap_start","round")==("flat" if edge.from==layout.roads.edges[0].from else "round")
			inherited=inherited and edge.get("cap_end","round")==("flat" if edge.to==layout.roads.edges[0].to else "round")
		check(count==2 and inherited,"residential split keeps only the original endpoint styles")
	check(var_to_bytes(layout)==original,"residential split does not mutate the original graph")
	print("ROAD_END_CAPS_FINISHED failures=",failed)
	quit(1 if failed else 0)
