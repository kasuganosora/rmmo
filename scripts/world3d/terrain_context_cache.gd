extends RefCounted
## Plain derived images and seam normals, covered by the runtime source/code hash.
const Neighbors=preload("res://scripts/world3d/terrain_neighbors.gd")
static func pack(context:RefCounted)->Dictionary:
	var result:Dictionary={}
	for id:String in context.data:
		var row:Dictionary=context.data[id].duplicate()
		for field in ["image","region_mask"]:
			if not row.has(field):continue
			var image:Image=row[field]
			row[field]={"width":image.get_width(),"height":image.get_height(),"format":image.get_format(),"bytes":image.get_data()}
		result[id]=row
	return result

static func valid_image(value:Variant,mask:bool)->bool:
	if not value is Dictionary or not value.get("width") is int or not value.get("height") is int or not value.get("bytes") is PackedByteArray:return false
	var width:int=value.width;var height:int=value.height
	if width<1 or height<1 or width>257 or height>257:return false
	if value.get("format")!=(Image.FORMAT_RG8 if mask else Image.FORMAT_RF):return false
	if mask and (width!=257 or height!=257):return false
	return value.bytes.size()==width*height*(2 if mask else 4)

static func restore(snapshot:Variant,records:Array)->RefCounted:
	if not snapshot is Dictionary:return null
	var context:=Neighbors.new();var targets:Dictionary={}
	for r:Dictionary in records:
		if not r.has("terrain_mesh"):continue
		if absf(r.rotation[0])<=.00001 and absf(r.rotation[2])<=.00001:
			context.sources[r.uuid]=r;context.signature.append([r.uuid,r.position,r.rotation,r.size,r.terrain_mesh]);targets[r.uuid]=r
		elif r.has("terrain_regions"):targets[r.uuid]=r
	if snapshot.size()!=targets.size():return null
	# Validate the whole snapshot before allocating images or publishing data.
	for id in snapshot:
		if not id is String or not targets.has(id) or not snapshot[id] is Dictionary:return null
		var row:Dictionary=snapshot[id];var record:Dictionary=targets[id]
		if record.has("terrain_regions")!=row.has("region_mask"):return null
		if row.has("region_mask") and not valid_image(row.region_mask,true):return null
		if not context.sources.has(id):
			if row.size()!=1:return null
			continue
		if not valid_image(row.get("image"),false) or not row.get("normals") is Dictionary or not row.get("neighbors") is Array or not row.get("signature") is Array or not row.get("padding") is Vector2:return null
		var t:Dictionary=record.terrain_mesh;var pad:Vector2=row.padding
		if pad.x<1 or pad.y<1 or pad.x>33 or pad.y>33 or pad!=pad.floor():return null
		if row.image.width!=int(t.columns)+1+int(pad.x)*2 or row.image.height!=int(t.rows)+1+int(pad.y)*2:return null
		for index in row.normals:
			if not index is int or index<0 or index>=(int(t.columns)+1)*(int(t.rows)+1) or not row.normals[index] is Vector3 or not row.normals[index].is_finite():return null
		var expected:Array=[record.position,record.rotation,record.size,record.terrain_mesh];var seen:Dictionary={}
		for other in row.neighbors:
			if not other is String or other==id or not context.sources.has(other) or seen.has(other):return null
			seen[other]=true
			var neighbor:Dictionary=context.sources[other];expected.append([neighbor.position,neighbor.rotation,neighbor.size,neighbor.terrain_mesh])
		if expected!=row.signature:return null
	for id:String in snapshot:
		var row:Dictionary=snapshot[id].duplicate()
		for field in ["image","region_mask"]:
			if not row.has(field):continue
			var pixels:Dictionary=row[field]
			row[field]=Image.create_from_data(pixels.width,pixels.height,false,pixels.format,pixels.bytes)
		context.data[id]=row
	return context
