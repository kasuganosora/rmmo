extends RefCounted
## Only the explicit UI file picker uses this entry. MCP keeps its root guard.
const Paths=preload("res://scripts/world3d/map_paths.gd")
static func run(source:String,root:String,token:RefCounted)->Dictionary:
	var directory:=root.path_join("assets/banner_streetlamp/designs/import_sources")
	if not source.is_absolute_path() or source.get_extension().to_lower() not in ["png","jpg","jpeg","webp"] or not Paths.allowed(directory,root):return {"ok":false,"error":"图片路径无效"}
	var input:=FileAccess.open(source,FileAccess.READ)
	if input==null:return {"ok":false,"error":"图片无法读取"}
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:return {"ok":false,"error":"资源目录无法创建"}
	var staged:=directory.path_join(".copy-%d-%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec()])
	var output:=FileAccess.open(staged,FileAccess.WRITE)
	if output==null:return {"ok":false,"error":"图片无法写入"}
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	var remaining:=input.get_length();var good:=remaining>0
	while good and remaining>0 and not token.is_cancelled():
		var bytes:=input.get_buffer(mini(remaining,1024*1024))
		good=not bytes.is_empty() and output.store_buffer(bytes)
		hash.update(bytes);remaining-=bytes.size()
	input.close();output.close()
	var target:=directory.path_join(hash.finish().hex_encode()+"."+source.get_extension().to_lower())
	var error:int=ERR_SKIP
	if good and remaining==0 and not token.is_cancelled():error=preload("res://scripts/world3d/atomic_file.gd").publish_new(staged,target)
	if FileAccess.file_exists(staged):DirAccess.remove_absolute(staged)
	return {"ok":true,"path":target} if error in [OK,ERR_ALREADY_EXISTS] else {"ok":false,"error":"图片导入已取消或复制失败"}
