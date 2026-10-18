extends "res://tools/test_stream_index_append.gd"
const Preparation=preload("res://scripts/world3d/stream_index_preparation.gd")
func source()->Array:
	var values:Array=[];var mesh:=BoxMesh.new()
	for i:int in 600:
		var value:=house("large__part%d"%i,"group%d"%(i%7),Vector2i(i%3,0));value.mesh=mesh;values.append(value)
	values.append(spec("anchor",Vector2i(8,0),Vector2i(8,0)))
	return values
func prepared(values:Array)->RefCounted:
	var cursor:=Preparation.new();cursor.begin_owned(values)
	while not cursor.advance(100):pass
	check(cursor.error.is_empty() and cursor.valid_for(values),"owned projection validates its complete private input")
	return cursor
func clean(values:Array)->bool:
	for value:Dictionary in values:
		for field:String in Preparation.DERIVED_FIELDS:
			if value.has(field):return false
	return true
func run()->void:
	var values:=source();var author:=values.duplicate(true);var cursor:RefCounted=prepared(values)
	check(is_same(values[0],cursor.projection[0]) and values[0].extras==author[0].extras and values[0].ground_batch_record==author[0].ground_batch_record,"only unpublished spec dictionaries receive derived fields; authored graphs stay unchanged")
	var catalog:=Index.build([ground("existing_ground",Vector2i.ZERO,Vector2i(3,0))])
	var old:Array=catalog.stream_by_id.values()
	check(Index.append(catalog,values,cursor).ok,"owned fragment appends beside existing ground with normal dependency binding")
	cursor.dispose()
	var rebuilt:=Index.build((old+values).duplicate(true))
	check(public_index(catalog)==public_index(rebuilt) and catalog.stream_append_state==rebuilt.stream_append_state,"owned transfer and disposal equal the complete reference build")
	check(is_same(catalog.stream_by_id[values[0].uuid],values[0]) and is_same(catalog.stream_building_groups.group0[0],values[0]),"published dictionary and bucket references keep the original runtime identity")
	for mutation:String in ["pose","bounds","group","supports","ungrouped"]:
		values=source();cursor=prepared(values);var before:=Index.build([]);var frozen:=before.duplicate(true)
		match mutation:
			"pose":values[0].transform.origin+=Vector3.RIGHT
			"bounds":values[0].render_bounds.chunk_max+=Vector2i.ONE
			"group":values[0].render_building="changed"
			"supports":values[0].render_supports.append({})
			"ungrouped":values[-1].render_dependents=[]
		check(not cursor.valid_for(values) and Index.append(before,values,cursor).get("error")=="stale_private_index" and before==frozen,"late "+mutation+" mutation rejects without public writes")
		var pose:Transform3D=values[0].transform;cursor.dispose()
		check(clean(values) and values[0].transform==pose,"cancelled "+mutation+" projection removes owned fields and preserves current author pose")
	values=source();cursor=Preparation.new();cursor.begin_owned(values)
	while cursor.phase<3:cursor.advance(1)
	check(not clean(values),"partial owned preparation has private derived state to release")
	cursor=null;check(clean(values),"cursor destruction cleans unpublished annotations even with external source aliases")
	values=source();values[1].render_building="preexisting";author=values.duplicate(true);cursor=Preparation.new();cursor.begin_owned(values);cursor.advance(0);cursor.dispose()
	check(values==author,"preexisting derived input is preserved for the ordinary append fallback")
	values=source();values.append(ground("landscape",Vector2i.ZERO,Vector2i.ZERO));author=values.duplicate(true);cursor=Preparation.new();cursor.begin_owned(values);cursor.advance(0)
	check(cursor.error=="owned_projection_ineligible","landscape stays on copied projection path")
	cursor.dispose();check(values==author,"ineligible owned preparation preserves every input")
	values=source();cursor=Preparation.new();cursor.begin_owned(values);cursor.advance(1);var watch:WeakRef=weakref(values[0].mesh);values=[];cursor.dispose()
	check(watch.get_ref()==null,"cancelled cursor releases all private mesh owners")
	print("OWNED_STREAM_INDEX_PREPARATION failures=",failures);quit(1 if failures else 0)
