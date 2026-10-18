extends SceneTree
const Removal=preload("res://scripts/world3d/source_list_retirement.gd")
func old_erase(values:Array,selected:Dictionary)->void:
	var write:=0
	for read:int in values.size():
		if selected.has(values[read].uuid):continue
		values[write]=values[read];write+=1
	values.resize(write)
func _initialize()->void:
	var original:Array=[];var members:Dictionary={}
	for i:int in 10000:
		var id:="source_%d"%i
		original.append({"uuid":id,"extras":{"arbitrary":true}});members[id]=true
	var failures:=0
	for count:int in [1,8,16]:
		var selected:Dictionary={}
		for i:int in count:selected[original[(i*313)%10000].uuid]=true
		var expected:Array=original.duplicate();old_erase(expected,selected)
		var trial:Array=original.duplicate();Removal.erase_small(trial,members,selected)
		if trial!=expected:failures+=1
		for fast:bool in [false,true,true,false]:
			var began:=Time.get_ticks_usec()
			for repeat:int in 30:
				trial=original.duplicate()
				if fast:Removal.erase_small(trial,members,selected)
				else:old_erase(trial,selected)
			print("SPARSE_REMOVE count=",count," fast=",fast," us=",Time.get_ticks_usec()-began)
	var reversed:Array=original.duplicate();reversed.reverse();var before:Array=reversed.duplicate()
	if Removal.erase_small(reversed,members,{"source_0":true}) or reversed!=before:failures+=1
	print("SPARSE_REMOVE failures=",failures);quit(1 if failures else 0)
