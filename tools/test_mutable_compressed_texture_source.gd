extends SceneTree
## CPU-only mutable DDS contract; outputs stay in the caller's external folder.
const Source=preload("res://scripts/world3d/compressed_texture_source.gd")
var directory:=""
var checks:=0
var failures:Array[String]=[]

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)

func _initialize()->void:run.call_deferred()

func put(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()

func sha(bytes:PackedByteArray)->String:
	var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(bytes)
	return hash_.finish().hex_encode()

func dds(kind:String="DXT1")->PackedByteArray:
	# One complete 1x1 compressed mip: valid DDS, but its block exceeds 4 RGBA bytes.
	var bytes:=PackedByteArray();bytes.resize(128+(8 if kind=="DXT1" else 16))
	for i:int in 4:bytes[i]="DDS ".to_ascii_buffer()[i];bytes[84+i]=kind.to_ascii_buffer()[i]
	bytes.encode_u32(4,124);bytes.encode_u32(8,0x000A1007)
	bytes.encode_u32(12,1);bytes.encode_u32(16,1);bytes.encode_u32(28,1)
	bytes.encode_u32(76,32);bytes.encode_u32(80,4);bytes.encode_u32(108,0x1000)
	for i:int in bytes.size()-128:bytes[128+i]=17+i
	return bytes

func certify(target:String,source_bytes:PackedByteArray,dds_bytes:PackedByteArray,normal:bool=false,flip:bool=false)->Dictionary:
	var record:={"version":1,"encoder_version":1,"source_sha256":sha(source_bytes),"source_bytes":source_bytes.size(),"dds_sha256":sha(dds_bytes),"dds_bytes":dds_bytes.size(),"normal":normal,"flip":flip}
	put(target+".source.json",JSON.stringify(record).to_utf8_buffer())
	return record

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):directory=arg.trim_prefix("--output=").replace("\\","/")
	if directory.is_empty() or not directory.is_absolute_path() or directory.begins_with(ProjectSettings.globalize_path("res://")):
		push_error("external --output=<directory> required");quit(2);return
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("editable.png");var target:=path+".dxt1.dds"
	var original:="snapshot-A".to_utf8_buffer();var changed:="snapshot-B".to_utf8_buffer()
	put(path,original);var compressed:=dds();put(target,compressed)
	check(not Source.plan(path,false,false,directory).is_empty(),"trusted package DDS remains available without metadata")
	check(Source.plan_mutable(path,false,false,directory,sha(original)).is_empty(),"mutable legacy DDS cannot claim freshness")
	var record:=certify(target,original,compressed)
	var row:=Source.plan_mutable(path,false,false,directory,sha(original))
	check(not row.is_empty() and Source.read(row)!=null,"source and DDS identity permit mutable candidate")
	check(row.output_bytes>4,"caller must retain RGBA fallback when a tiny DDS exceeds PNG budget")
	put(path,changed)
	check(original.size()==changed.size() and Source.plan_mutable(path,false,false,directory,sha(changed)).is_empty(),"same-length source replacement rejects stale DDS")
	# Caller passes its existing snapshot identity; the helper never rereads PNG.
	DirAccess.remove_absolute(path)
	check(not Source.plan_mutable(path,false,false,directory,sha(original)).is_empty(),"candidate uses caller snapshot without second source read")
	var replacement:=compressed.duplicate();replacement[128]^=1;put(target,replacement)
	check(Source.read(row)==null,"same-header same-length DDS replacement rejects captured identity")
	check(Source.read(Source.plan(path,false,false,directory))!=null,"mutable hash gate does not change trusted game read")
	row=Source.plan_mutable(path,false,false,directory,sha(original))
	check(not row.is_empty() and Source.read(row)==null,"interrupted DDS-first publication cannot certify old metadata")
	certify(target,changed,replacement)
	row=Source.plan_mutable(path,false,false,directory,sha(changed))
	check(not row.is_empty() and Source.read(row)!=null,"completed rebuild binds replacement source and blocks")
	for field:String in ["source_sha256","dds_sha256","version","encoder_version","source_bytes","dds_bytes","normal","flip"]:
		var broken:=record.duplicate();broken.erase(field);put(target+".source.json",JSON.stringify(broken).to_utf8_buffer())
		check(Source.plan_mutable(path,false,false,directory,sha(original)).is_empty(),"missing metadata field rejected: "+field)
	put(target+".source.json",PackedByteArray([1,2,3]))
	check(Source.plan_mutable(path,false,false,directory,sha(original)).is_empty(),"malformed metadata rejected")
	put(target+".source.json",(" ".repeat(2049)).to_utf8_buffer())
	check(Source.plan_mutable(path,false,false,directory,sha(original)).is_empty(),"metadata read remains bounded")
	var normal:=dds("ATI2");var flipped:=normal.duplicate();flipped[128]^=7
	put(path+".bc5.dds",normal);put(path+".flip.bc5.dds",flipped)
	certify(target,changed,replacement)
	certify(path+".bc5.dds",changed,normal,true,false)
	certify(path+".flip.bc5.dds",changed,flipped,true,true)
	for role:Array in [[false,false],[false,true],[true,true]]:
		row=Source.plan_mutable(path,role[0],role[1],directory,sha(changed))
		check(not row.is_empty() and Source.read(row)!=null,"each color/normal/flip identity remains independent")
	certify(path+".flip.bc5.dds",changed,flipped,true,false)
	check(Source.plan_mutable(path,true,true,directory,sha(changed)).is_empty(),"wrong flip metadata cannot certify normal variant")
	check(Source.plan_mutable(path,false,false,directory.path_join("outside"),sha(changed)).is_empty(),"mutable metadata obeys root boundary")
	print("MUTABLE_COMPRESSED_TEXTURE_SOURCE ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
