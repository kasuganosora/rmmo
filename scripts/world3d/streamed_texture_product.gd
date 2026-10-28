extends RefCounted
## CPU-only GSTF v1 writer for Godot 4.8 StreamedTexture2D. The caller owns the
## Image, admission lease, private staging file, cancellation and publication.
## Reuse already prepared pixels / DDS blocks: never reopen a source, recompress,
## regenerate mipmaps, or create a GPU resource here. Ordinary loads only read
## the published product; they must not also decode the complete source Image.
const FORMAT_VERSION:=1

static func write(file:FileAccess,image:Image)->Error:
	if file==null or image==null or image.is_empty():return ERR_INVALID_PARAMETER
	var width:=image.get_width();var height:=image.get_height()
	var count:=image.get_mipmap_count();var size:=image.get_data_size()
	# These are the 4.8 reader / GSTF uint32 limits, not authoring policy limits.
	if width>16384 or height>16384 or count>16 or size>0xffffffff:return ERR_UNAVAILABLE
	var header:=PackedByteArray();header.resize(44+8*(count+1))
	header[0]=71;header[1]=83;header[2]=84;header[3]=70 # GSTF
	var values:=[FORMAT_VERSION,width,height,size,image.get_format(),count]
	for index:int in values.size():header.encode_u32(4+index*4,values[index])
	for mip:int in count+1:
		var start:=image.get_mipmap_offset(mip)
		var end:=image.get_mipmap_offset(mip+1) if mip<count else size
		header.encode_u32(28+mip*8,start)
		header.encode_u32(32+mip*8,end-start)
	# The final four uint32 fields are flags, min/max overrides, reserved.
	# Zero preserves automatic streaming; no import-detection callbacks are needed.
	var began:=file.get_position()
	if not file.store_buffer(header) or not file.store_buffer(image.get_data()):return ERR_FILE_CANT_WRITE
	return OK if file.get_error()==OK and file.get_position()==began+header.size()+size else ERR_FILE_CANT_WRITE
