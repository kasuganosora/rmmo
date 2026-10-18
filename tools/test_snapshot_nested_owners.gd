extends "res://tools/test_stream_index_retire.gd"
const Preparation=preload("res://scripts/world3d/stream_index_preparation.gd")
func run()->void:
	var bulk:Array=[]
	for i:int in 5000:bulk.append([i,i+1,i+2])
	var nested_id:Array=["fixture",[1,2]]
	var value:=spec("nested",Vector2i.ZERO,Vector2i.ONE,{"building":{"id":"record","bulk":bulk}},{"building":{"id":"building","bulk":bulk},"fixture":{"id":nested_id,"bulk":bulk},"fortification":{"id":"fort","bulk":bulk}})
	var snapshot:Dictionary=Preparation._validation_copy(value)
	for field:String in ["building","fixture","fortification"]:check(is_same(snapshot.extras[field].bulk,bulk),"unrelated nested "+field+" author arrays remain borrowed")
	check(is_same(snapshot.ground_batch_record.building.bulk,bulk),"unrelated nested record arrays remain borrowed")
	nested_id[1][0]=9
	check(snapshot.extras.fixture.id[1][0]==1,"the mutable identity actually consumed by the index is independently captured")
	print("NESTED_SNAPSHOT_OWNERS checks=",checks," failures=",failures);quit(1 if failures else 0)
