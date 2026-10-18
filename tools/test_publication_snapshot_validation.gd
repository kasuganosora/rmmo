extends "res://tools/test_owned_stream_index_preparation.gd"
func run()->void:
	Preparation.native_snapshot_validation_enabled=true
	var saved:=Preparation.native_snapshot_validation_enabled
	for mutation:String in ["none","pose","mesh_bounds","identity","order","group","bounds_owner","supports_owner","nested_type","uuid_type","chunk_type","irrelevant"]:
		var values:=source();var cursor:RefCounted=prepared(values)
		check(cursor.valid_owned_snapshot(values),"native snapshot matches before "+mutation)
		match mutation:
			"pose":values[0].transform.origin+=Vector3.RIGHT
			"mesh_bounds":values[0].mesh.size+=Vector3.ONE
			"identity":values[0]=values[0].duplicate()
			"order":values.reverse()
			"group":values[0].extras.building.id="other"
			"bounds_owner":values[0].render_bounds=values[0].render_bounds.duplicate()
			"supports_owner":values[0].render_supports=[]
			"nested_type":values[0].extras.building.id=StringName(values[0].extras.building.id)
			"uuid_type":values[0].uuid=StringName(values[0].uuid)
			"chunk_type":values[0].chunk_min=Vector2(values[0].chunk_min)
			"irrelevant":values[0].metadata_note="allowed ordinary fallback"
		check(cursor.valid_owned_snapshot(values)==(mutation=="none"),"late "+mutation+" cannot bypass current ownership or schema validation")
		var old_index:=Index.build([]);var new_index:=Index.build([])
		Preparation.native_snapshot_validation_enabled=false
		var old:Dictionary=Index.append(old_index,values,cursor)
		# Accepted appends consume the cursor; rebuild the same private input for
		# native comparison, preserving the exact mutation rejection otherwise.
		if old.ok:
			cursor.dispose()
			for value:Dictionary in values:
				for field:String in Preparation.DERIVED_FIELDS:value.erase(field)
			Preparation.native_snapshot_validation_enabled=true;cursor=prepared(values)
		Preparation.native_snapshot_validation_enabled=true
		var current:Dictionary=Index.append(new_index,values,cursor)
		check(old.ok==current.ok and old.get("error")==current.get("error") and public_index(old_index)==public_index(new_index),"native/ordinary append result and public index agree for "+mutation)
		cursor.dispose()
	Preparation.native_snapshot_validation_enabled=saved
	print("PUBLICATION_SNAPSHOT_VALIDATION failures=",failures);quit(1 if failures else 0)
