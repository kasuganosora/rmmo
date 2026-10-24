extends RefCounted
## Logical packed storage only. One owner/thread per instance; no arrays retained.
const LIMIT:=4096
var sizes:Dictionary={}
var hits:=0
var scans:=0
var channels:=0

func measure(surfaces:Array,lods:Array,geometry_key:String="")->int:
	if not geometry_key.is_empty():
		var cached:int=sizes.get(geometry_key,-1)
		if cached>=0:hits+=1;return cached
	var bytes:=0
	var wide:=OS.has_feature("double")
	for surface:Array in surfaces:
		channels+=surface.size()
		for channel:Variant in surface:
			match typeof(channel):
				TYPE_PACKED_BYTE_ARRAY:bytes+=channel.size()
				TYPE_PACKED_INT32_ARRAY,TYPE_PACKED_FLOAT32_ARRAY:bytes+=channel.size()*4
				TYPE_PACKED_INT64_ARRAY,TYPE_PACKED_FLOAT64_ARRAY:bytes+=channel.size()*8
				TYPE_PACKED_VECTOR2_ARRAY:bytes+=channel.size()*(16 if wide else 8)
				TYPE_PACKED_VECTOR3_ARRAY:bytes+=channel.size()*(24 if wide else 12)
				TYPE_PACKED_COLOR_ARRAY:bytes+=channel.size()*16
				TYPE_PACKED_VECTOR4_ARRAY:bytes+=channel.size()*(32 if wide else 16)
	for levels:Dictionary in lods:
		for indices:PackedInt32Array in levels.values():bytes+=indices.size()*4
	scans+=1
	# This internal identity already covers channels and LODs. The collision
	# soup is a separate lazy owner and must be charged by the caller each time.
	if not geometry_key.is_empty():
		if sizes.size()>=LIMIT:sizes.clear()
		sizes[geometry_key]=bytes
	return bytes
