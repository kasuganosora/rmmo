extends SceneTree
## CPU-only, read-only inventory. Never loads a model or saves the source map.
func _initialize()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2:
		push_error("Expected map path and new output path");quit(2);return
	var source:=args[0]
	var output:=args[1]
	if FileAccess.file_exists(output):
		push_error("Refusing to overwrite an inventory snapshot");quit(2);return
	var before:=FileAccess.get_sha256(source)
	var document:Variant=JSON.parse_string(FileAccess.get_file_as_string(source))
	if not document is Dictionary:
		quit(2);return
	var metadata:Dictionary=document.nodes[0].extras
	assert(metadata.rmmo_storage=="references_v1")
	var definitions:Dictionary={}
	var evidence:Array=[]
	for record:Dictionary in metadata.rmmo_records:
		var ref:Dictionary=record.rmmo_ref
		if definitions.has(ref.sha256):continue
		assert(ref.uri==source.get_file()+".resources/"+ref.sha256+".rmres")
		var path:=source.get_base_dir().path_join(ref.uri)
		assert(FileAccess.get_sha256(path)==ref.sha256)
		var packed:=FileAccess.get_file_as_bytes(path)
		assert(packed.size()==int(ref.length) and packed.size()>16)
		assert(packed.slice(0,8).get_string_from_ascii()=="RMMORES1")
		var size:=packed.decode_u64(8)
		assert(size>0 and size<=64*1024*1024)
		var raw:=packed.slice(16).decompress(size,FileAccess.COMPRESSION_ZSTD)
		assert(raw.size()==size)
		var definition:Variant=bytes_to_var(raw)
		assert(definition is Dictionary)
		definitions[ref.sha256]=definition
		evidence.append({"path":path,"sha256":ref.sha256,"bytes":packed.size()})
	var after:=FileAccess.get_sha256(source)
	if before!=after:
		push_error("Map changed during read-only snapshot; retry with a new output");quit(3);return
	var file:=FileAccess.open(output,FileAccess.WRITE)
	assert(file!=null)
	file.store_string(JSON.stringify({"scope":"Read-only CPU definition decode; no model load", "map":source,"map_sha256":before,"map_unchanged":true,"record_count":metadata.rmmo_records.size(),"definitions":definitions,"resources":evidence},"\t"))
	file.close()
	print(JSON.stringify({"ok":true,"definitions":definitions.size(),"records":metadata.rmmo_records.size(),"output":output}))
	quit()
