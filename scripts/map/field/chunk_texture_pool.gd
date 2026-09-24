extends RefCounted
## A small pool separate from the complete offscreen-node cache. Reuse only
## evicted, invisible textures after a few frames; never mutate active chunks.
const BUDGET := 32*1024*1024
var entries: Array=[]
var bytes:=0
var reused:=0
var created:=0
func offer(gpu: Dictionary) -> void:
	var seen: Dictionary={}
	for texture in gpu.values():
		if not texture is ImageTexture:continue
		var id: int=texture.get_instance_id()
		if seen.has(id):continue
		seen[id]=true
		var size: int=texture.get_width()*texture.get_height()*4
		if size>BUDGET:continue
		while bytes+size>BUDGET and not entries.is_empty():
			bytes-=int(entries.pop_front().bytes)
		entries.append({"texture":texture,"bytes":size,"after":Engine.get_process_frames()+3})
		bytes+=size
func upload(image: Image) -> ImageTexture:
	for i in range(entries.size()):
		var entry: Dictionary=entries[i]
		var texture: ImageTexture=entry.texture
		if Engine.get_process_frames()<entry.after:continue
		if texture.get_width()!=image.get_width() or texture.get_height()!=image.get_height() or texture.get_format()!=image.get_format():continue
		entries.remove_at(i);bytes-=int(entry.bytes)
		texture.update(image);reused+=1
		return texture
	created+=1
	return ImageTexture.create_from_image(image)
func clear() -> void:
	entries.clear();bytes=0
