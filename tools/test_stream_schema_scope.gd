extends "res://tools/test_stream_index_retire.gd"
const Schema=preload("res://scripts/world3d/stream_spec_schema.gd")
func run()->void:
	var record:Dictionary={"kind":"asset","building":{"id":"guild"}}
	var extra:Dictionary={"building":{"id":"guild"}}
	var scope:=Schema.new();var rows:Array=[]
	var valid:=true
	for i:int in 2151:
		var item:=spec("guild__%d"%i,Vector2i.ZERO,Vector2i.ONE,record,extra);rows.append(item)
		valid=valid and Index._valid_append_spec(item,scope)
	check(valid,"all 2151 complete spec schemas checked")
	check(scope.extra_checks==1 and scope.record_checks==1,"2151 shared parts validate each exact authored owner once within one read-only scope")
	check(Index._schema_scope(rows,0,rows.size())!=null,"dense shared owners enable the transaction-local scope")
	var distinct:Array=[]
	for row:Dictionary in rows:distinct.append(row.duplicate(true))
	check(Index._schema_scope(distinct,0,distinct.size())==null,"equal values in distinct authored dictionaries do not pay identity-cache overhead")
	for field:String in ["uuid","mesh","transform","chunk_min","chunk_max","extras","ground_batch_record"]:
		for invalid:Variant in [null,17,[],"bad"]:
			var changed:Dictionary=rows[0].duplicate();changed[field]=invalid
			check(Index._valid_append_spec(changed)==Index._valid_append_spec(changed,scope),"cached records never bypass per-source schema: "+field)
	for kind:String in ["extra","record"]:
		for patch:Dictionary in [{"building":17},{"building":{"id":17}},{"fixture":17},{"fortification":17},{"rmmo_streetlamp_instance":17},{"kind":"box","surface_id":"ground","size":17},{"kind":"box","surface_id":"ground","size":[1]},{"kind":"box","surface_id":"ground","size":[1,"bad"]}]:
			var changed:Dictionary=rows[0].duplicate();changed["extras" if kind=="extra" else "ground_batch_record"]=patch
			check(Index._valid_append_spec(changed)==Index._valid_append_spec(changed,scope),"different owner uses complete validation for "+kind+str(patch))
	# A new public transaction must detect in-place mutation of the same object.
	var data:=Index.build(rows)
	var before:=data.duplicate(true)
	check(Index.validate_owned_retire(data,rows,[]).ok,"first complete scan accepts all resident identities")
	extra.building.id=17
	check(not Index.validate_owned_retire(data,rows,[]).ok,"next scan revalidates a shared object changed in place")
	check(not Index.append(Index.build([]),[rows[0].duplicate()]).ok,"a later append cannot inherit the former scope")
	extra.building.id="guild"
	check(data==before and Index.validate_owned_retire(data,rows,[]).ok,"validation changes neither indexes nor author data")
	scope=null
	print("STREAM_SCHEMA_SCOPE checks=",checks," failures=",failures);quit(1 if failures else 0)
