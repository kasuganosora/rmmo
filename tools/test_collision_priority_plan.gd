extends "res://tools/test_collision_priority_reuse.gd"
const Plan=preload("res://scripts/world3d/collision_priority_plan.gd")
func compare(rows:Array,draw:Dictionary,origin:Vector3,label:String)->void:
	var expected:=rows.duplicate();Stream.prioritize_local_collisions(expected,1,origin,{"row19":true},draw,{"row7":true})
	var measurements:Array=[]
	for budget:int in [0,1,1000]:
		var jobs:=rows.duplicate();var work:=Plan.new(Stream,jobs,1,origin,{"row19":true},draw,{"row7":true})
		while not work.advance(budget):
			if jobs!=rows:check(false,"partial partition changed the active plan");break
		var same:=ids(jobs)==ids(expected)
		for i:int in rows.size():same=same and is_same(jobs[i],expected[i])
		check(same,label+" exact stable order, budget "+str(budget))
		check(work.profile.rows==rows.size()-2,"each pending row classified exactly once")
		measurements.append(work.profile)
	print("COLLISION_PRIORITY_PLAN ",JSON.stringify({"case":label,"trials":measurements}))
