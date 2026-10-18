extends SceneTree
const Store=preload("res://scripts/world3d/map_resource_store.gd")
var cases:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func compare(value:Variant,limit:int=2000000)->void:
	var old_budget:=[limit];var new_budget:=[limit];var old_stack:Array=[];var new_stack:Array=[]
	Store.inline_numeric_safety_enabled=false;var expected:=Store._safe(value,old_stack,old_budget)
	Store.inline_numeric_safety_enabled=true;var actual:=Store._safe(value,new_stack,new_budget)
	cases+=1
	if expected!=actual or old_budget!=new_budget or not old_stack.is_empty() or not new_stack.is_empty():failures+=1;print("MISMATCH case=",cases)
func run()->void:
	var values:Array=[null,true,false,0,-1,9223372036854775807,1.5,NAN,INF,"s",StringName("s"),Vector3(NAN,0,0),PackedFloat32Array([NAN]),PackedStringArray(["s"]),RefCounted.new(),Callable(self,"run"),RID()]
	for value:Variant in values:
		for limit:int in [0,1,2,3,8,100]:
			compare([value],limit);compare({"v":[value]},limit)
	for depth:int in [62,63,64,65,66]:
		var nested:Variant=1
		for i in depth:nested=[nested]
		compare(nested)
	var cycle:Array=[];cycle.append(cycle);compare(cycle);cycle.clear()
	var alias:Array=[1,2,3];compare([alias,alias]);compare([alias,alias],8)
	var object_array:Array[RefCounted]=[];compare([object_array])
	var rows:Array=[]
	for i in 20000:rows.append([float(i),i,true,null,[1.0,2.0,3.0]])
	compare(rows);compare(rows,179999);rows[-1][-1][-1]=NAN;compare(rows)
	Store.inline_numeric_safety_enabled=true
	print("RESOURCE_SCALAR_SAFETY cases=",cases," failures=",failures)
	quit(0 if failures==0 else 1)
