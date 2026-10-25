extends SceneTree
## Tiny CPU fixtures only: cache integrity policy and admitted decode bounds.
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
var failures:=0
var folder:=""
var path:=""
var target:=""
var original:=PackedByteArray()
var valid_cache:=PackedByteArray()
var expected_pixels:=PackedByteArray()
var requested:Dictionary={}
var plan:Dictionary={}
var pool:RefCounted
var serial:=0
var measurements:Dictionary={}
class Admission extends RefCounted:
	func release(_id:String)->void:pass
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func write_bytes(file_path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(file_path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func count(name:String)->int:return int(Pixels.profile_snapshot().counters.get("texture."+name,0))
func shared()->Dictionary:
	serial+=1;var consumer:="trust_%d"%serial;var offer:Dictionary=pool.offer(plan)
	pool.commit(consumer,offer)
	return {"pool":pool,"consumer":consumer,"leaders":offer.leaders,"cached":offer.cached}
func prepare(mounted:bool=true)->Dictionary:
	var scope:=shared();var packet:=Prep.prepare(requested,plan,folder,null,true,scope,mounted)
	var pixels_equal:bool=packet.error.is_empty() and packet.images.has(path) and packet.images[path].get_data()==expected_pixels
	var result:={"error":packet.error,"images":packet.images.size(),"profile":packet.profile.duplicate(),"pixels_equal":pixels_equal}
	packet.clear();pool.release(scope.consumer)
	return result
func write_payload(value:Variant,bad_checksum:bool=false)->void:
	var payload:=var_to_bytes(value)
	var checksum:=Pixels.Envelope.checksum(payload)
	if bad_checksum:checksum[0]^=1
	write_bytes(target,checksum+payload)
func run()->void:
	var previous_policy:bool=Policy.verify_packages;var previous_profile:bool=Pixels.profile_enabled
	Policy.verify_packages=false;Pixels.profile_enabled=true
	folder=Prep.Paths.cache_directory("texture_cache_trust_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(folder)
	path=folder.path_join("source.png");target=Pixels.cache_path(path,false)
	var image:=Image.create(19,13,false,Image.FORMAT_RGBA8);image.fill(Color(.2,.4,.7,1.))
	check(image.save_png(path)==OK,"write isolated source PNG")
	original=FileAccess.get_file_as_bytes(path);requested={path:[path,false]};plan=Prep.estimate(requested,folder)
	pool=Pool.new();pool.admission=Admission.new()
	var seed_scope:=shared();var seed:=Prep.prepare(requested,plan,folder,null,true,seed_scope,true)
	check(seed.error.is_empty() and seed.images.size()==1,"seed a real bounded cache and operation source identity")
	expected_pixels=seed.images[path].get_data();seed.clear();pool.release(seed_scope.consumer)
	valid_cache=FileAccess.get_file_as_bytes(target)
	var valid_data:Dictionary=bytes_to_var(valid_cache.slice(32))
	Pixels.reset_profile();var mounted:=prepare()
	measurements.mounted={"checksums":count("cache_payload_checksum_checks"),"header_reads":count("prefab_source_header_reads"),"source_reads":mounted.profile.get("source_sha_reads",-1)}
	check(mounted.pixels_equal and mounted.profile.cache_hits==1,"mounted cache returns exact pixels")
	check(count("cache_payload_checksum_checks")==0,"ordinary prefab cache skips the full payload checksum")
	check(count("prefab_source_header_reads")==0 and mounted.profile.source_sha_reads==0,"mounted cache hit reuses the admitted header plan without source reads")
	Pixels.reset_profile();var runtime:=Pixels.image(path,false)
	measurements.runtime={"checksums":count("cache_payload_checksum_checks"),"source_sha_calls":Pixels.profile_snapshot().stages.get("texture.image.source_sha",{}).get("calls",0)}
	check(runtime!=null and runtime.get_data()==expected_pixels and count("cache_payload_checksum_checks")==0,"ordinary RuntimeTextureCache uses the same checksum policy")
	check(measurements.runtime.source_sha_calls==0,"ordinary RuntimeTextureCache does not read a source SHA")
	runtime=null
	Policy.verify_packages=true
	var strict_target=Pixels.cache_path(path,false)
	Pixels.reset_profile();var strict_seed:=prepare(false)
	var strict_cache=FileAccess.get_file_as_bytes(strict_target)
	var strict_data:Dictionary=bytes_to_var(strict_cache.slice(32))
	Pixels.reset_profile();var strict:=prepare(false)
	measurements.strict_prefab={"checksums":count("cache_payload_checksum_checks"),"header_reads":count("prefab_source_header_reads")}
	check(strict.pixels_equal and count("cache_payload_checksum_checks")==1 and count("prefab_source_header_reads")==1,"strict prefab still checks payload checksum and source header")
	Pixels.reset_profile();runtime=Pixels.image(path,false)
	measurements.strict_runtime={"checksums":count("cache_payload_checksum_checks")}
	check(runtime!=null and runtime.get_data()==expected_pixels and count("cache_payload_checksum_checks")==1,"strict RuntimeTextureCache still checks the full payload checksum")
	runtime=null;Policy.verify_packages=false;target=Pixels.cache_path(path,false)
	write_payload(valid_data,true);Pixels.reset_profile();var unchecked:=prepare()
	check(unchecked.pixels_equal and unchecked.profile.cache_hits==1 and unchecked.profile.decoded==0,"ordinary cache trusts valid payload despite an obsolete checksum field")
	Pixels.reset_profile();runtime=Pixels.image(path,false)
	check(runtime!=null and runtime.get_data()==expected_pixels and count("image.cache_hit")==1 and count("cache_payload_checksum_checks")==0,"ordinary RuntimeTextureCache also ignores only the checksum field")
	runtime=null
	Policy.verify_packages=true;target=strict_target
	write_payload(strict_data,true);Pixels.reset_profile();var repaired:=prepare(false)
	check(repaired.pixels_equal and repaired.profile.decoded==1 and count("cache_payload_checksum_checks")==1,"strict checksum mismatch falls back to source and repairs cache")
	write_payload(strict_data,true);Pixels.reset_profile();runtime=Pixels.image(path,false)
	check(runtime!=null and runtime.get_data()==expected_pixels and count("image.cache_miss")==1 and count("cache_payload_checksum_checks")==1,"strict RuntimeTextureCache repairs a mismatched checksum")
	runtime=null
	Policy.verify_packages=false;target=Pixels.cache_path(path,false)
	for mode:String in ["missing","truncated","not_dictionary","wrong_source","wrong_format","oversize_dimensions","mip_size"]:
		var bad:Dictionary=valid_data.duplicate(true)
		match mode:
			"missing":DirAccess.remove_absolute(target)
			"truncated":write_bytes(target,PackedByteArray([1,2,3]))
			"not_dictionary":write_payload("not pixel metadata")
			"wrong_source":bad.source="f".repeat(64);write_payload(bad)
			"wrong_format":bad.format=999;write_payload(bad)
			"oversize_dimensions":bad.width=8192;write_payload(bad)
			"mip_size":bad.size=1;write_payload(bad)
		var malformed:=FileAccess.get_file_as_bytes(target) if mode!="missing" else PackedByteArray()
		Pixels.reset_profile();var restored:=prepare()
		check(restored.pixels_equal and restored.profile.decoded==1 and restored.profile.source_sha_reads==1,"trusted cache still rejects "+mode+" and decodes once")
		if mode=="missing":DirAccess.remove_absolute(target)
		else:write_bytes(target,malformed)
		Pixels.reset_profile();runtime=Pixels.image(path,false)
		check(runtime!=null and runtime.get_data()==expected_pixels and count("image.cache_miss")==1,"RuntimeTextureCache retains "+mode+" fallback")
		runtime=null
	# Admission came from the small source. Actual bytes, not a second file
	# header read, must reject dimensions changed before entering the codec.
	check(pool.snapshot().outputs==0 and pool.snapshot().consumers==0,"cache variants retire before a new stale-plan operation")
	pool=Pool.new();pool.admission=Admission.new()
	DirAccess.remove_absolute(target)
	var enlarged:=original.duplicate();enlarged[16]=0;enlarged[17]=0;enlarged[18]=32;enlarged[19]=0
	write_bytes(path,enlarged);Pixels.reset_profile();var stale:=prepare()
	check(not stale.error.is_empty() and stale.images==0 and count("prefab_source_header_reads")==0,"stale mounted plan rejects oversized actual PNG dimensions without re-reading headers")
	write_bytes(path,original+PackedByteArray([0]));Pixels.reset_profile();var longer:=prepare()
	check(not longer.error.is_empty() and longer.images==0,"source length change cannot exceed the admitted read buffer")
	write_bytes(path,original);write_bytes(target,valid_cache)
	var cancelled:=shared();pool.cancel(cancelled.consumer);Pixels.reset_profile()
	var rejected:=Prep.prepare(requested,plan,folder,null,true,cancelled,true)
	check(not rejected.error.is_empty() and rejected.images.is_empty() and count("prefab_source_header_reads")==0 and count("cache_payload_checksum_checks")==0,"cancelled mounted consumer cannot use the header-plan fast path")
	rejected.clear();pool.release(cancelled.consumer)
	check(pool.snapshot().outputs==0 and pool.snapshot().consumers==0,"all cache/miss/error paths release pixel leases")
	Policy.verify_packages=previous_policy;Pixels.profile_enabled=previous_profile
	DirAccess.remove_absolute(target);DirAccess.remove_absolute(path);DirAccess.remove_absolute(folder)
	print("TEXTURE_CACHE_TRUST ",JSON.stringify({"failures":failures,"measurements":measurements}));quit(0 if failures==0 else 1)
