extends "res://tools/test_stream_index_append.gd"
const CANDIDATE:="res://scripts/world3d/stream_index_preparation.gd"
func prepare(values:Array)->RefCounted:
	var script:Script=load(CANDIDATE);var cursor:RefCounted=script.new();cursor.begin(values)
	var before:=values.duplicate(true)
	var turns:=0
	while not cursor.advance(100):
		turns+=1
		check(values==before,"each preparation slice keeps all input specs and author records unchanged")
	check(cursor.error.is_empty() and cursor.valid_for(values),"completed private fragment retains current source identities")
	var expected:=Index.build(values.duplicate(true))
	check(cursor.result==expected,"all public indexes, group/support links and append bookkeeping equal the full reference build")
	return cursor
func run()->void:
	var values:Array=[ground("ground_a",Vector2i(-1,0),Vector2i(0,0)),ground("ground_b",Vector2i(0,0),Vector2i(2,0)),house("house_floor","house",Vector2i.ZERO),house("house_roof","house",Vector2i.ZERO,1),
		spec("tower__lower",Vector2i(3,0),Vector2i(3,0),{},{},8.,0.),spec("tower__upper",Vector2i(3,0),Vector2i(3,0),{},{},8.,8.),
		spec("lamp__base",Vector2i(2,0),Vector2i(2,0)),spec("lamp__crystal",Vector2i(2,0),Vector2i(2,0),{},{"rmmo_streetlamp_crystal":true,"rmmo_collision":"none"}),
		spec("tree__leaves",Vector2i(2,2),Vector2i(2,2),{},{"rmmo_wind":{},"rmmo_collision":"none"},18.),spec("road",Vector2i(-2,0),Vector2i(3,0),{"road_mesh":{}})]
	var cursor:RefCounted=prepare(values)
	var original:Dictionary=values[2];var transform:Transform3D=original.transform
	original.transform.origin+=Vector3.UP
	check(not cursor.valid_for(values),"late fixture/source pose mutation rejects the prepared fragment")
	original.transform=transform
	check(cursor.valid_for(values),"restored source still matches its independently captured signature")
	values.reverse();check(not cursor.valid_for(values),"source reordering cannot reuse a stale fragment");values.reverse()
	values.append(spec("late",Vector2i.ZERO,Vector2i.ZERO));check(not cursor.valid_for(values),"added source cannot alias the cursor's original array");values.pop_back()
	original.extras.building.id="changed";check(not cursor.valid_for(values),"nested authored group mutation rejects a stale fragment");original.extras.building.id="house"
	check(cursor.valid_for(values),"private preparation never changes nested author groups")
	var catalog:=Index.build([]);var before_catalog:=catalog.duplicate(true)
	original.transform.origin+=Vector3.RIGHT
	var changed_values:=values.duplicate(true)
	check(Index.append(catalog,values,cursor).get("error")=="stale_private_index" and catalog==before_catalog and values==changed_values,"stale private fragment fails atomically at the real append boundary")
	original.transform=transform
	var appended:=Index.append(catalog,values,cursor)
	var rebuilt:=Index.build(values.duplicate(true))
	check(appended.ok and public_index(catalog)==public_index(rebuilt) and catalog.stream_append_state==rebuilt.stream_append_state,"real prepared append equals the complete reference build")
	cursor.dispose()
	var random:=RandomNumberGenerator.new();random.seed=728418
	for batch:int in 16:
		var incoming:Array=[]
		for i:int in 8:
			var at:=Vector2i(random.randi_range(-6,6),random.randi_range(-6,6))
			incoming.append(ground("g_%d_%d"%[batch,i],at,at+Vector2i(random.randi_range(0,3),random.randi_range(0,3))))
			incoming.append(house("h_%d_%d"%[batch,i],"group_%d"%(i/2),at))
		cursor=prepare(incoming);cursor.dispose()
	var script:Script=load(CANDIDATE)
	for turns:int in [1,10,60]:
		var author:Array=[ground("large_cell",Vector2i(-40,-40),Vector2i(40,40))];var before:=author.duplicate(true)
		cursor=script.new();cursor.begin(author)
		for i:int in turns:cursor.advance(1)
		check(cursor.phase<7 and author==before,"large spatial ranges yield without modifying their caller before cancellation")
		cursor.dispose();check(author==before,"cancelling a partial cell scan preserves the complete source")
	print("STREAM_INDEX_PREPARATION failures=",failures);quit(1 if failures else 0)
