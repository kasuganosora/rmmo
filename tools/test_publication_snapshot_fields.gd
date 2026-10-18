extends "res://tools/test_stream_index_retire.gd"
const Candidate=preload("res://scripts/world3d/stream_index_preparation.gd")
const FastIndex=preload("res://scripts/world3d/stream_index.gd")
const Retire=preload("res://scripts/world3d/resource_retirement.gd")
func rows()->Array:
	var result:Array=[];var mesh:=BoxMesh.new();var bulk:Array=[]
	for i:int in 10000:bulk.append([i,i+1,i+2])
	for i:int in 600:
		var item:=spec("guild__part%d"%i,Vector2i.ZERO,Vector2i.ONE,{"kind":"box","surface_id":"ground","size":[1,3,1],"building":{"id":"guild"},"unrelated":bulk},{"building":{"id":"guild"},"fixture":{"id":"fixture%d"%i,"kind":"window"}})
		item.mesh=mesh;result.append(item)
	return result
func prepare(values:Array)->RefCounted:
	var prep:RefCounted=Candidate.new();prep.begin_owned(values)
	while not prep.advance(500):pass
	check(prep.error.is_empty() and prep.valid_owned_snapshot(values),"candidate begins with an exact validated owned fragment")
	return prep
func run()->void:
	Candidate.native_snapshot_validation_enabled=true
	for mutation:String in ["none","pose","mesh_bounds","schema","fixture","fortification","record_group","size","identity","bounds_owner","irrelevant_nested"]:
		var values:=rows();var prep:RefCounted=prepare(values)
		check(is_same(prep.validation_snapshot[0].ground_batch_record.unrelated,values[0].ground_batch_record.unrelated),"large unrelated authored arrays remain borrowed, with no recursive copy")
		match mutation:
			"pose":values[0].transform.origin+=Vector3.UP
			"mesh_bounds":values[0].mesh.size+=Vector3.ONE
			"schema":values[0].extras.building.id=StringName("guild")
			"fixture":values[0].extras.fixture.id="changed"
			"fortification":values[0].extras.fortification={"id":"new"}
			"record_group":values[0].ground_batch_record.building.id="other"
			"size":values[0].ground_batch_record.size[1]="bad"
			"identity":values[0]=values[0].duplicate()
			"bounds_owner":values[0].render_bounds=values[0].render_bounds.duplicate()
			"irrelevant_nested":values[0].ground_batch_record.unrelated[0][0]=-1
		check(prep.valid_owned_snapshot(values)==(mutation in ["none","irrelevant_nested"]),"only index-irrelevant borrowed mutation may keep native proof: "+mutation)
		Candidate.native_snapshot_validation_enabled=false
		var a:=FastIndex.build([]);var ordinary:Dictionary=FastIndex.append(a,values,prep)
		if ordinary.ok:
			prep.dispose()
			for value:Dictionary in values:
				for field:String in Candidate.DERIVED_FIELDS:value.erase(field)
			Candidate.native_snapshot_validation_enabled=true;prep=prepare(values)
		Candidate.native_snapshot_validation_enabled=true
		var b:=FastIndex.build([]);var fast:Dictionary=FastIndex.append(b,values,prep)
		check(ordinary.ok==fast.ok and ordinary.get("error")==fast.get("error") and a==b,"full native/fallback result and index match: "+mutation)
		var borrowed:Array=values[0].ground_batch_record.unrelated;var count:=borrowed.size();prep.dispose();prep=null;values=[]
		var service:Node=root.get_node(Retire.NODE_NAME);service.set_process(false)
		while not service.pending.is_empty():
			if service._advance(service.pending[0],1000):service._finish_front()
		check(borrowed.size()==count and borrowed[0].size()==3,"bounded retirement never clears borrowed author arrays")
	print("NARROW_SNAPSHOT checks=",checks," failures=",failures);quit(1 if failures else 0)
