extends SceneTree
## Exact RG8 output oracle, including real map polygons; no GPU or source writes.
const Regions=preload("res://scripts/world3d/terrain_regions.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
var failures:Array[String]=[]
var checks:=0
var rows:Array=[]

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)

# Frozen pre-optimization implementation: independent pixel-first reference.
func oracle(record:Dictionary)->Image:
	var image:=Image.create(257,257,false,Image.FORMAT_RG8)
	var span:=Vector2(record.size[0],record.size[2]);var step:=span/256.
	for region:Dictionary in record.get("terrain_regions",{}).get("regions",[]):
		var polygon:=Regions.points(region);var feather:float=region.feather
		var rect:=Regions.bounds(polygon).grow(feather)
		var lo:=Vector2i(((rect.position+span*.5)/step).floor()).clamp(Vector2i.ZERO,Vector2i(256,256))
		var hi:=Vector2i(((rect.end+span*.5)/step).ceil()).clamp(Vector2i.ZERO,Vector2i(256,256))
		for z in range(lo.y,hi.y+1):
			for x in range(lo.x,hi.x+1):
				var p:=Vector2(x,z)*step-span*.5;var distance:=INF
				for i in polygon.size():distance=minf(distance,p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p,polygon[i],polygon[(i+1)%polygon.size()])))
				distance=sqrt(distance)*(1. if Geometry2D.is_point_in_polygon(p,polygon) else -1.)
				var weight:=smoothstep(-feather*.5,feather*.5,distance)*float(region.opacity)
				if weight<=0.:continue
				var c:=image.get_pixel(x,z)*(1.-weight);c[int(region.layer)]+=weight;image.set_pixel(x,z,c)
	return image

func shape(polygon:Array,feather:float=2.,layer:int=0,opacity:float=1.)->Dictionary:
	return {"polygon":polygon,"feather":feather,"layer":layer,"opacity":opacity}
func record(regions:Array,span:Vector2=Vector2(128,128))->Dictionary:
	return {"size":[span.x,1.,span.y],"terrain_regions":{"regions":regions}}
func real_records(map_path:String)->Array:
	var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(map_path))
	var found:Array=[];var seen:Dictionary={}
	for row:Dictionary in document.nodes[0].extras.rmmo_records:
		var ref:Dictionary=row.rmmo_ref
		if seen.has(ref.uri):continue
		seen[ref.uri]=true
		var decoded:=Store._read(map_path.get_base_dir().path_join(ref.uri),ref.sha256,int(ref.length),true,true)
		check(decoded.ok,"read trusted definition")
		if decoded.ok and decoded.definition.has("terrain_regions"):
			var hydrated:Dictionary=decoded.definition.merged(row,true)
			hydrated.merge(row.get("rmmo_state",{}),true)
			found.append(hydrated)
	found.sort_custom(func(a,b):return Regions.work(a)>Regions.work(b))
	return found
func verify(label:String,data:Dictionary)->void:
	var began:=Time.get_ticks_usec();var expected:=oracle(data);var oracle_us:=Time.get_ticks_usec()-began
	var work:={"enabled":true}
	began=Time.get_ticks_usec();var actual:=Regions.mask(data,work);var actual_us:=Time.get_ticks_usec()-began
	check(actual.get_size()==Vector2i(257,257) and actual.get_format()==Image.FORMAT_RG8 and not actual.has_mipmaps(),label+" image contract")
	check(actual.get_data()==expected.get_data(),label+" all RG8 bytes equal")
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(actual.get_data())
	rows.append({"case":label,"oracle_us":oracle_us,"actual_us":actual_us,"legacy_estimated_edge_work":Regions.work(data),"work":work,"sha256":hash.finish().hex_encode()})
func threaded(record_data:Dictionary)->PackedByteArray:return Regions.mask(record_data).get_data()
func run()->void:
	var output:="";var map_path:="";var quick:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--map="):map_path=arg.trim_prefix("--map=")
		elif arg=="--quick":quick=true
	var cases:Array=[
		record([]),record([shape([[-50,-50],[50,-50],[50,50],[-50,50]])]),
		record([shape([[-60,-8],[60,-8],[60,8],[-60,8]],1.,0,.43),shape([[-8,-60],[8,-60],[8,60],[-8,60]],24.,1,.68)]),
		record([shape([[-60,-60],[60,-60],[60,-40],[-40,-40],[-40,60],[-60,60]],3.)]),
		record([shape([[-200,-200],[200,-200],[200,200],[-200,200]])]),
		record([shape([[300,300],[310,300],[310,310],[300,310]])]),
		record([shape([[-.1,-70],[.1,-70],[.1,70],[-.1,70]],1.)],Vector2(16,128)),
		record([shape([[-70,-.1],[70,-.1],[70,.1],[-70,.1]],1.)],Vector2(128,16))]
	var rng:=RandomNumberGenerator.new();rng.seed=684827
	for sample in (2 if quick else 12):
		var polygon:Array=[]
		for i in 3+sample*4:
			var angle:=TAU*float(i)/float(3+sample*4);var radius:=rng.randf_range(22,58)
			polygon.append([cos(angle)*radius,sin(angle)*radius])
		cases.append(record([shape(polygon,[1.,2.,7.,24.][sample%4],sample%2,rng.randf_range(.01,1.))],Vector2(128,96)))
	for i in cases.size():verify("synthetic_"+str(i),cases[i])
	var map_sha:="";var real:Array=[]
	if not map_path.is_empty():
		map_sha=FileAccess.get_sha256(map_path);real=real_records(map_path)
		check(not real.is_empty(),"real map regions found")
		for i in mini(real.size(),2 if quick else real.size()):verify("real_"+str(i),real[i])
		check(FileAccess.get_sha256(map_path)==map_sha,"map source unchanged")
	var parallel_data:Dictionary=real[0] if not real.is_empty() else cases[2]
	var expected:=Regions.mask(parallel_data).get_data();var workers:Array[Thread]=[]
	for i in 2:
		var worker:=Thread.new();check(worker.start(threaded.bind(parallel_data))==OK,"worker start");workers.append(worker)
	for worker:Thread in workers:check(worker.wait_to_finish()==expected,"parallel exact output, no shared scratch")
	var report:={"checks":checks,"failures":failures,"rows":rows,"map":map_path,"map_sha256":map_sha,"scope":"CPU algorithm timings, byte exact RG8 oracle; not real-map wall-time improvement"}
	if not output.is_empty():
		if FileAccess.file_exists(output):push_error("Refusing to overwrite evidence");quit(1);return
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("TERRAIN_MASK_BAND ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
