extends SceneTree
func _initialize()->void:
	var failures:=0
	for count:int in [2000,8000,16000]:
		var parent:=Node.new();var nodes:Array[Node]=[]
		for i:int in count:
			var child:=Node.new();parent.add_child(child);nodes.append(child)
		var service:=Node.new();parent.add_child(service,false,Node.INTERNAL_MODE_FRONT)
		for fast:bool in [false,true,true,false]:
			var total:=0
			for round_:int in 60:
				var child:Node=nodes[(round_*127)%count]
				parent.remove_child(child);parent.add_child(child)
				var began:=Time.get_ticks_usec();var actual:=parent.get_child_count(fast);total+=Time.get_ticks_usec()-began
				if actual!=count+(1 if fast else 0):failures+=1
			print("CHILD_COUNT count=",count," total=",fast," query_us=",total)
		parent.free()
	print("CHILD_COUNT failures=",failures);quit(1 if failures else 0)
