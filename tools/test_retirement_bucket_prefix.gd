extends SceneTree
const Index=preload("res://scripts/world3d/stream_index.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func fixture(count:int,by_spec:bool)->Array:
	var result:Array=[]
	for i:int in count:result.append({"uuid":str(i),"owner":RefCounted.new()} if by_spec else str(i))
	return result
func run()->void:
	for reuse:bool in [false,true]:
		Index.retirement_bucket_prefix_reuse_enabled=reuse
		var empty:={Vector2i.ZERO:[]}
		check(Index._retire_bucket(empty,Vector2i.ZERO,{},false)==0 and empty.is_empty(),"empty bucket is removed in both implementations")
		check(Index._retire_bucket(empty,Vector2i.ZERO,{},false)==0 and empty.is_empty(),"missing bucket stays absent")
	for by_spec:bool in [false,true]:
		for removed:Array in [[],[0],[3],[7],[0,3,7],[0,1,2,3,4,5,6,7],[99]]:
			var original:=fixture(8,by_spec);var selected:Dictionary={};var expected:Array=[]
			for i:int in removed:selected[str(i)]=true
			for i:int in 8:
				if not removed.has(i):expected.append(original[i])
			for reuse:bool in [false,true]:
				Index.retirement_bucket_prefix_reuse_enabled=reuse
				var bucket:=original.duplicate();var borrowed:Array=bucket;var table:={Vector2i.ZERO:bucket}
				var writes:=Index._retire_bucket(table,Vector2i.ZERO,selected,by_spec)
				check(bucket==expected and borrowed==expected,"exact stable survivors and borrowed Array identity")
				check(table.has(Vector2i.ZERO)==not expected.is_empty(),"empty bucket removed")
				for i:int in expected.size():
					if by_spec:check(is_same(bucket[i],expected[i]) and bucket[i].owner==expected[i].owner,"resource owners remain exact, no clone")
				if removed.is_empty() or removed==[99]:check(writes==(0 if reuse else 8),"unaffected bucket does zero self assignments")
				if removed==[7]:check(writes==(0 if reuse else 7),"tail deletion does zero survivor self assignments")
	var values:=fixture(8192,true);var selected:Dictionary={}
	for i:int in range(7168,8192):selected[str(i)]=true
	var trials:Array=[]
	for reuse:bool in [false,true,true,false]:
		Index.retirement_bucket_prefix_reuse_enabled=reuse
		var elapsed:=0;var writes:=0
		for repeat:int in 32:
			var bucket:=values.duplicate();var table:={Vector2i.ZERO:bucket}
			var began:=Time.get_ticks_usec()
			writes+=Index._retire_bucket(table,Vector2i.ZERO,selected,true)
			elapsed+=Time.get_ticks_usec()-began
			check(bucket.size()==7168 and is_same(bucket[0],values[0]) and is_same(bucket[7167],values[7167]),"large shared bucket keeps exact prefix")
		trials.append({"reuse":reuse,"us":elapsed,"visited_rows":32*8192,"writes":writes})
	Index.retirement_bucket_prefix_reuse_enabled=true
	print("RETIREMENT_BUCKET_PREFIX ",JSON.stringify({"trials":trials,"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
