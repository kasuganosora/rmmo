extends SceneTree
const Blocks=preload("res://scripts/world3d/city_blocks.gd")
const Split=preload("res://scripts/world3d/road_intersections.gd")
var failed:=0
func check(value: bool,label_: String) -> void:
	if not value: failed+=1
	print(("PASS " if value else "FAIL ")+label_)
func loop(points: Array,prefix: String="a") -> Dictionary:
	var graph:={"nodes":[],"edges":[]}
	for i in points.size():
		graph.nodes.append({"id":prefix+str(i),"position":[points[i][0],0,points[i][1]]})
		graph.edges.append({"id":prefix+"e"+str(i),"from":prefix+str(i),"to":prefix+str((i+1)%points.size()),"width_start":4,"width_end":4,"kind":"ground"})
	return graph
func _initialize() -> void:
	var graph:=loop([[-40,-40],[40,-40],[40,40],[-40,40]])
	var result:=Blocks.extract(graph)
	check(preload("res://scripts/world3d/road_plan.gd").build(graph,preload("res://scripts/world3d/road_plan.gd").defaults()).ok,"80m ring pavement removes numeric corner slivers")
	check(result.ok and result.blocks.size()==1,"square is one bounded face")
	if not result.ok or result.blocks.is_empty(): quit(1); return
	var block: Dictionary=result.blocks[0]
	check(is_equal_approx(block.area,6400),"exterior face excluded")
	var lots:=Blocks.lots(block,result.blocks,graph,Blocks.defaults())
	print("LOTS ",lots.get("lots",[]).size())
	check(lots.ok and lots.lots.size()>=8,"four-sided frontage parcels available")
	for lot in lots.lots:
		check(Blocks.inside(Blocks.unpack(lot.polygon),Blocks.unpack(block.polygon)),"lot stays inside block")
		var basis:=Basis(Vector3.UP,deg_to_rad(lot.yaw)); var outward:=basis*Vector3.FORWARD
		check(outward.dot(Blocks.Data.vec(lot.street)-Blocks.Data.vec(lot.position))>0,"local entrance faces its road")
	for i in lots.lots.size():
		for j in range(i+1,lots.lots.size()): check(not Blocks.overlaps(Blocks.unpack(lots.lots[i].polygon),Blocks.unpack(lots.lots[j].polygon)),"parcels never overlap")
	var reversed:=graph.duplicate(true); reversed.nodes.reverse(); reversed.edges.reverse()
	check(Blocks.extract(reversed).blocks==result.blocks,"array reordering preserves block identity and geometry")
	graph.nodes.append({"id":"dead","position":[0,0,-10]}); graph.edges.append({"id":"spur","from":"a0","to":"dead","kind":"ground","width_start":4,"width_end":4})
	var spur:=Blocks.extract(graph)
	check(spur.ok and spur.blocks.size()==1 and spur.open_edges==1,"cul-de-sac excluded from face walk")
	graph.edges.append({"id":"cross","from":"a0","to":"a2","kind":"ground","width_start":4,"width_end":4})
	graph.edges.pop_back(); graph.edges.pop_back(); graph.nodes.pop_back()
	graph.edges.append({"id":"diagonal","from":"a0","to":"a2","kind":"ground","width_start":4,"width_end":4})
	check(Blocks.extract(graph).blocks.size()==2,"diagonal splits square into two bounded faces")
	var curved:=loop([[-50,-40],[50,-40],[50,40],[-50,40]])
	curved.edges[0].controls=[[-20,0,-55],[20,0,-55]]
	var curve:=Blocks.extract(curved)
	check(curve.ok and curve.blocks.size()==1 and curve.blocks[0].polygon.size()>4,"cubic boundary retained")
	var parcels:=Blocks.lots(curve.blocks[0],curve.blocks,curved,Blocks.defaults())
	check(parcels.ok and parcels.lots.size()>4,"curved road frontage yields conservative lots")
	var concave:=loop([[-50,-50],[50,-50],[50,-5],[5,-5],[5,50],[-50,50]])
	var notch:=Blocks.extract(concave)
	check(notch.ok and notch.blocks.size()==1,"concave city block supported")
	check(not Blocks.inside([Vector2(-10,-10),Vector2(20,-10),Vector2(20,20),Vector2(-10,20)],Blocks.unpack(notch.blocks[0].polygon)),"concave notch cannot be bridged by parcel")
	var inner:=loop([[-20,-20],[20,-20],[20,20],[-20,20]],"b")
	var nested:=loop([[-60,-60],[60,-60],[60,60],[-60,60]])
	nested.nodes.append_array(inner.nodes); nested.edges.append_array(inner.edges)
	var rings:=Blocks.extract(nested); check(rings.ok and rings.blocks.size()==2,"disconnected nested rings identified")
	for face in rings.blocks:
		var split:=Blocks.lots(face,rings.blocks,nested,Blocks.defaults())
		if face.area>2000:
			for lot in split.lots: check(not Blocks.overlaps(Blocks.unpack(lot.polygon),[Vector2(-20,-20),Vector2(20,-20),Vector2(20,20),Vector2(-20,20)]),"inner ring is a hole in outer district")
	for edge in nested.edges: edge.kind="bridge"
	check(Blocks.extract(nested).blocks.is_empty(),"bridge loops never become buildable districts")
	var sloped:=loop([[-20,-20],[20,-20],[20,20],[-20,20]]); sloped.nodes[0].position[1]=2
	check(not Blocks.extract(sloped).ok,"sloped ground rejected")
	var operations:=preload("res://scripts/world_editor/block_tools.gd").new()
	var access:=operations.volume([[-1,-1],[1,-1],[1,1],[-1,1]],.06,3)
	var pavement:={"kind":"box","position":[0,-.075,0],"size":[4,.2,4],"rotation":[0,0,0],"road_mesh":{"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]],"uv_origin":[0,0,0]}}
	var obstacles:Array=[]
	for shape in operations.Footprint.record_shapes(pavement): obstacles.append({"record":pavement,"shape":shape})
	check(not operations.blocked([access],obstacles,0,true),"entrance connection permits its ground pavement")
	pavement.position[1]=1.8; obstacles=[]
	for shape in operations.Footprint.record_shapes(pavement): obstacles.append({"record":pavement,"shape":shape})
	check(operations.blocked([access],obstacles,0,true),"low overhead road still blocks entrance headroom")
	pavement.position[1]=5.0; obstacles=[]
	for shape in operations.Footprint.record_shapes(pavement): obstacles.append({"record":pavement,"shape":shape})
	check(not operations.blocked([access],obstacles,0,true),"high overhead road leaves entrance headroom")
	print("CITY_BLOCKS_FINISHED failures=%d"%failed); quit(0 if failed==0 else 1)
