extends SceneTree
const Order=preload("res://scripts/world3d/publication_order.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	var order:=Order.new()
	var a:={"path":"house","record":{"uuid":"house_part"}}
	var b:={"path":"grass","record":{"uuid":"grass_instance"}}
	var c:={"path":"tree","record":{"uuid":"tree_instance"}}
	var heads:Array=[a,b,c]
	var ranks:={"house_part":0,"grass_instance":100,"tree_instance":1000}
	var priorities:={"house_part":0,"grass_instance":0,"tree_instance":0}
	var jobs:={"house":{},"grass":{},"tree":{}}
	var selected:Array=[]
	for i in 12:selected.append(order.choose(heads,priorities,ranks,jobs).path)
	check(selected==["house","house","house","house","grass","grass","grass","grass","tree","tree","tree","tree"],"distant ready closures receive service within one bounded visual round")
	check(order.choose(heads,priorities,ranks,jobs).path=="house","oldest served closure starts the next round")
	priorities.tree_instance=-1
	check(order.choose([c,a,b],priorities,ranks,jobs).path=="tree","new safety demand immediately interrupts a visual burst")
	priorities.house_part=-1
	for i in 6:check(order.choose([a,c,b],priorities,ranks,jobs).path=="house","negative-priority requests retain distance order")
	priorities={"house_part":0,"grass_instance":10,"tree_instance":10}
	for i in 9:check(order.choose(heads,priorities,ranks,jobs).path=="house","background priority never overtakes nearby priority")
	jobs.erase("house")
	check(order.choose([b,c],priorities,ranks,jobs).path in ["grass","tree"] and not order._served.has("house"),"retired closures release scheduler state")
	check(order.choose([],priorities,ranks,jobs).is_empty() and order._burst_path.is_empty(),"no ready heads produces no work or retained burst")
	priorities.grass_instance=0;priorities.tree_instance=0
	var only:Array=[b]
	for i in 5:check(order.choose(only,priorities,ranks,jobs).path=="grass","collision-blocked siblings never prevent the ready head progressing")
	var next:={"path":"new","record":{"uuid":"new_instance"}}
	jobs.new={};priorities.new_instance=0;ranks.new_instance=2000
	var reached:=false
	for i in Order.MAX_BURST+1:
		if order.choose([b,next],priorities,ranks,jobs).path=="new":reached=true;break
	check(reached,"newly ready closure obtains a turn without waiting for old path exhaustion")
	check(jobs.grass.is_empty() and a.record.size()==1,"scheduling does not alter author data or admitted resource jobs")
	order=Order.new();a.group_id="building:near";c.group_id="building:far"
	jobs={"house":{},"grass":{},"tree":{}};priorities={"house_part":0,"grass_instance":0,"tree_instance":0}
	selected=[]
	for i in 16:selected.append(order.choose(heads,priorities,ranks,jobs).path)
	check(selected.count("house")==8 and selected.count("grass")==8 and not selected.has("tree"),"props share turns without changing the ready-building material order")
	jobs.erase("house")
	var reached_far:=false
	for i in 8:
		if order.choose([b,c],priorities,ranks,jobs).path=="tree":reached_far=true
	check(reached_far,"next ready building advances after its nearer predecessor retires")
	print("PUBLICATION_ORDER checks=",checks," failures=",failures)
	quit(1 if failures else 0)
