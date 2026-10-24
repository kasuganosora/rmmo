extends "res://tools/test_chunk_reference_preparation.gd"
const Handoff=preload("res://scripts/world3d/reference_record_handoff.gd")
func run()->void:
	var helper:=Fixtures.new();helper.content_root=Paths.external_root();helper.folder=Paths.cache_directory("handoff_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(helper.folder)
	var authored:Array=[helper.box("a",0),helper.box("b",100),helper.box("c",200)]
	var fixture:Dictionary=helper.fixture("map",authored);var path:String=fixture.path
	var index:=Index.build(path,helper.content_root,authored)
	check(index.ok,"fixture index")
	if not index.ok:quit(1);return
	var compact:Array=index.extras.rmmo_records
	var full:=Store.read_records(compact,path,helper.content_root,null,1,true)
	var all:=entries(index,[0,1,2]);var pool=Handoff.create(index,full.records,all,full.definition_sizes)
	check(pool.records.size()==3 and pool.reserved_bytes>0 and pool.reserved_bytes<=Handoff.MAX_BYTES,"bounded private handoff accounts each instance")
	check(pool.take(index.duplicate(),all).is_empty() and pool.records.size()==3,"another map/index transaction cannot consume this handoff")
	var offered:Dictionary=pool.take(index,entries(index,[0,2]))
	check(offered.size()==2 and pool.records.size()==1 and pool.take(index,entries(index,[0,2])).is_empty(),"exclusive transfer occurs exactly once")
	var packet:=Prepare.prepare(index,all,path,helper.content_root,null,null,{}, {},0,true,offered)
	check(packet.error.is_empty() and packet.records==full.records and packet.record_indices==[0,1,2],"mixed handoff and file records preserve exact authored order and state")
	check(packet.read_profile.handoff_records==2 and packet.read_profile.reads_started==1,"only missing records read resource files")
	check(is_same(packet.records[0],full.records[0]) and is_same(packet.records[2],full.records[2]),"already private hydrated instances transfer without a deep copy")
	var second:=Prepare.prepare(index,entries(index,[1]),path,helper.content_root,null,null,{}, {},0,true,pool.take(index,entries(index,[1])))
	check(second.error.is_empty() and second.read_profile.reads_started==0 and second.read_profile.handoff_records==1,"complete handoff performs zero resource reads")
	packet.records[0].position[0]=1234
	check(packet.records[1].position[0]==100,"editing one instance cannot modify its sibling with the same definition")
	var limited=Handoff.create(index,full.records,all,full.definition_sizes,1)
	check(limited.records.is_empty() and limited.reserved_bytes==0,"over-budget records remain on the normal file route")
	var cancelled:=Prepare.prepare(index,all,path,helper.content_root,Token.new(),null,{}, {},0,true,{"a":full.records[0]})
	check(cancelled.cancelled and cancelled.records.is_empty(),"cancellation remains before handoff consumption")
	var diagnostic:=Prepare.prepare(index,entries(index,[0]),path,helper.content_root,null,null,{}, {},0,false,{"a":full.records[0]})
	check(diagnostic.error.is_empty() and diagnostic.records[0].position[0]==0 and diagnostic.read_profile.reads_started==1,"diagnostic ignores supplied runtime handoff")
	pool.retire();limited.retire()
	for temporary:String in helper.created:
		if Paths.allowed(temporary,helper.content_root):DirAccess.remove_absolute(temporary)
	helper.free()
	print("REFERENCE_RECORD_HANDOFF passed=",passed," failures=",failures);quit(1 if failures else 0)
