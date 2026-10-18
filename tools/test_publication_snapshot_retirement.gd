extends "res://tools/test_owned_stream_index_preparation.gd"
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
func run()->void:
	Preparation.native_snapshot_validation_enabled=true
	for cancelled:bool in [false,true]:
		var values:=source();var cursor:RefCounted=prepared(values)
		var watch:WeakRef=weakref(values[0].mesh);var snapshot:Array=cursor.validation_snapshot
		if not cancelled:cursor.accept()
		cursor.dispose();cursor=null
		check(not cancelled or clean(values),"cancelled owned annotations are removed before snapshot retirement")
		values=[]
		var service:Node=root.get_node(Retirement.NODE_NAME);service.set_process(false)
		check(not snapshot.is_empty() and watch.get_ref()!=null,"tree service owns private snapshot resources after cursor disposal")
		service._advance(service.pending[0],1)
		check(not service.pending.is_empty() and not snapshot.is_empty(),"tiny retirement slice cannot collapse the whole snapshot")
		var count:=0
		while not service.pending.is_empty() and count<10000:
			if service._advance(service.pending[0],1):service._finish_front()
			count+=1
		check(count<10000 and snapshot.is_empty() and watch.get_ref()==null and service.known.is_empty(),"published/cancelled snapshot releases every mesh owner and ticket")
		service.free()
	var values:=source();var cursor:RefCounted=prepared(values);var watch:WeakRef=weakref(values[0].mesh)
	cursor=null
	check(clean(values),"implicit cursor destruction cleans unpublished annotations")
	values=[];root.get_node(Retirement.NODE_NAME).free()
	check(watch.get_ref()==null,"service exit drains implicit-destruction snapshot owners")
	print("PUBLICATION_SNAPSHOT_RETIREMENT failures=",failures);quit(1 if failures else 0)
