extends SceneTree
const City=preload("res://scripts/world3d/city_layout.gd")
const Placement=preload("res://scripts/world_editor/residential_placement_tools.gd")
const CurveSolver=preload("res://scripts/world_editor/residential_curve_connection.gd")
const Split=preload("res://scripts/world3d/road_intersections.gd")
var checks:Array=[]
var failures:=0
var cases:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks.append({"ok":ok,"label":label});if not ok:failures+=1
	print("PASS: " if ok else "FAIL: ",label)
func graph(points:Array)->Dictionary:
	return {"nodes":[{"id":"a","position":points[0]},{"id":"b","position":points[3]}],"edges":[{"id":"street","from":"a","to":"b","kind":"ground","width_start":3.,"width_end":5.,"controls":[points[1],points[2]]}]}
func reference(points:Array,t:float)->Array:
	var result:Array=[]
	for axis in 3:result.append((1-t)*(1-t)*(1-t)*float(points[0][axis])+3*(1-t)*(1-t)*t*float(points[1][axis])+3*(1-t)*t*t*float(points[2][axis])+t*t*t*float(points[3][axis]))
	return result
func audit(points:Array,query:Vector3,label:String)->void:
	var g:=graph(points);var nodes:Dictionary={"a":g.nodes[0],"b":g.nodes[1]};var edge:Dictionary=g.edges[0]
	var bytes:=var_to_bytes(g);var result:=CurveSolver.nearest(edge,nodes,query)
	check(result.ok,label+": bounded projection succeeds")
	if not result.ok:return
	var dense:=INF
	for i in 16385:
		var at:=reference(points,float(i)/16384.);var dx:float=at[0]-query.x;var dz:float=at[2]-query.z;dense=minf(dense,sqrt(dx*dx+dz*dz))
	check(result.distance<=dense+.0002,label+": no worse than independent dense reference within declared scalar search bound")
	check(var_to_bytes(result)==var_to_bytes(CurveSolver.nearest(edge,nodes,query)),label+": projection deterministic")
	var t:float=result.t
	if t>0 and t<1:
		var controls:=CurveSolver.controls(edge,nodes,t)
		var left:Dictionary=edge.duplicate(true);var right:Dictionary=edge.duplicate(true);left.to="mid";right.from="mid";left.controls=controls[0];right.controls=controls[1]
		nodes.mid={"id":"mid","position":result.position}
		var max_error:=0.;var author_error:=0.
		for i in 257:
			var u:=float(i)/256.;max_error=maxf(max_error,Split.position(left,nodes,u).distance_to(Split.position(edge,nodes,u*t)))
			max_error=maxf(max_error,Split.position(right,nodes,u).distance_to(Split.position(edge,nodes,t+u*(1-t))))
			var left_ref:=reference([points[0],controls[0][0],controls[0][1],result.position],u);var source_ref:=reference(points,u*t)
			var right_ref:=reference([result.position,controls[1][0],controls[1][1],points[3]],u);var end_ref:=reference(points,t+u*(1-t))
			for axis in 3:author_error=maxf(author_error,maxf(absf(left_ref[axis]-source_ref[axis]),absf(right_ref[axis]-end_ref[axis])))
		check(author_error<1e-9,label+": double authoring child curves preserve original XYZ independently of native rendering")
		var coordinate_scale:=1.
		for p:Array in points:
			for value:float in p:coordinate_scale=maxf(coordinate_scale,absf(value))
		check(max_error<=maxf(.0001,coordinate_scale*8.*pow(2.,-23)),label+": native float32 deviation within explicit coordinate-scaled tolerance")
		check(Split.derivative(left,nodes,1.).normalized().dot(Split.derivative(right,nodes,0.).normalized())>.99999,label+": join preserves tangent continuity")
		cases.append({"case":label,"t":t,"visits":result.visits,"max_shape_error":max_error,"max_authoring_error":author_error})
	check(var_to_bytes(g)==bytes,label+": source authoring graph unchanged")
func run()->void:
	var s:Array=[[-24.,0.,-20.],[-12.,.3,-10.],[12.,-.3,-30.],[24.,0.,-20.]]
	audit(s,Vector3(-3.,0.,-8.),"S bend with vertical guide and tapered width")
	audit([[-20.,0.,0.],[-20.,0.,20.],[20.,0.,20.],[20.,0.,0.]],Vector3(0,0,30),"symmetric arch")
	audit([[0.,0.,0.],[30.,0.,30.],[-30.,0.,30.],[2.,0.,0.]],Vector3(0,0,10),"multiple nearby branches")
	audit(s,Vector3(-80,0,-20),"endpoint minimum")
	var far:Array=s.map(func(p):return [p[0]+5000.,p[1],p[2]-7000.])
	audit(far,Vector3(4997,0,-7008),"translated curve")
	var rotated:Array=s.map(func(p):return [-p[2],p[1],p[0]])
	audit(rotated,Vector3(8,0,-3),"rotated curve")
	var g:=graph(s);var nodes:Dictionary={"a":g.nodes[0],"b":g.nodes[1]}
	check(not CurveSolver.nearest(g.edges[0],nodes,Vector3(-3,0,-8),0).ok,"exhausted projection budget refuses, never succeeds with partial samples")
	var data:=City.defaults();data.roads=g;var before:=var_to_bytes(data)
	var target:=Placement._target(g,"street");check(target.ok,"shared target filter accepts ordinary cubic")
	var linked:=Placement._connect(data,target,{"position":Vector3(-3,0,0),"outward":Vector3(0,0,-1)},1.,1.6,"fixture")
	check(linked.ok,"real residential connection splits cubic and adds connector")
	if linked.ok:
		var c:Dictionary=linked.road_connection;var parts:Array=linked.data.roads.edges.filter(func(e):return e.id in c.child_edge_ids)
		check(parts.size()==2 and parts.all(func(e):return e.has("controls")),"both editable children retain cubic controls")
		check(absf(parts[0].width_end-lerpf(3.,5.,c.parameter))<1e-10 and parts[0].width_end==parts[1].width_start,"split interpolates native parameter-based width without widening")
		check(City.analyze(linked.data.roads).ok and City.analyze(linked.data.roads).diagnostics.is_empty(),"native graph accepts complete curved junction")
	check(var_to_bytes(data)==before,"connection never mutates source graph")
	var endpoint:=Placement._connect(data,target,{"position":Vector3(60,0,-20),"outward":Vector3(-1,0,0)},1.,1.6,"endpoint")
	check(endpoint.ok and not endpoint.road_connection.split and endpoint.road_connection.parameter==1. and endpoint.data.roads.edges[0]==data.roads.edges[0],"endpoint attachment retains entire original cubic unchanged")
	var near_data:=City.defaults();near_data.roads=graph([[0.,0.,0.],[5.,0.,0.],[10.,0.,0.],[16.,0.,0.]])
	var near_target:=Placement._target(near_data.roads,"street")
	var reused:=Placement._connect(near_data,near_target,{"position":Vector3(.03,0,2.1),"outward":Vector3.FORWARD},1.,1.6,"reuse")
	check(reused.ok and not reused.road_connection.split and reused.road_connection.parameter==0. and reused.data.roads.edges[0]==near_data.roads.edges[0],"near-endpoint reconnect reuses node and preserves cubic instead of making a degenerate child")
	check(reused.ok and reused.road_connection.projection.endpoint_adjustment_m>0. and reused.road_connection.projection.endpoint_adjustment_m<.05 and reused.road_connection.projection.nearest_parameter>0.,"endpoint reuse reports separate raw projection and bounded topological adjustment")
	check(not Placement._connect(near_data,near_target,{"position":Vector3(.1,0,4.),"outward":Vector3.FORWARD},1.,1.6,"beyond").ok,"endpoint reuse does not silently extend beyond five centimetres")
	var bridge_data:=data.duplicate(true);bridge_data.roads.edges.append({"id":"bridge","from":"b","to":"bridge_end","kind":"bridge","bridge_ref":{"waterway_id":"water","bridge_id":"span"}})
	check(Placement._connect(bridge_data,target,{"position":Vector3(60,0,-20),"outward":Vector3(-1,0,0)},1.,1.6,"bridgehead").get("code")=="bridgehead_target","curved endpoint cannot attach directly to protected bridgehead")
	var crossing:=graph([[-10.,0.,0.],[20.,0.,20.],[-20.,0.,20.],[10.,0.,0.]])
	check(not Placement.Plan.build(crossing,Placement.Plan.defaults()).ok,"native full-road validator rejects a self-crossing cubic")
	g.edges[0].locked=true;check(Placement._target(g,"street").get("code")=="protected_scope","locked curve refuses")
	g.edges[0].erase("locked");g.nodes[0].hidden=true;check(Placement._target(g,"street").get("code")=="protected_scope","hidden endpoint refuses")
	check(not Placement.supports_target({"kind":"bridge","controls":s.slice(1,3)}) and not Placement.supports_target({"kind":"ground","bridge_ref":{}}),"bridge targets still excluded")
	var output:="D:/code/rmmo_runtime/review_artifacts/residential_curves_20261017/cpu.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):output=arg.trim_prefix("--report=")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir());FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases},"\t"))
	print("RESIDENTIAL_CURVES_CPU checks=",checks.size()," failures=",failures);quit(1 if failures else 0)
