extends RefCounted
const BatchPaths=preload("res://scripts/world3d/map_paths.gd")
## Replace one published file without first removing its live version.
static func publish(staged: String, destination: String) -> Error:
	if OS.get_name() != "Windows": return DirAccess.rename_absolute(staged, destination)
	# Godot's directory rename is not a replacement transaction on every platform.
	# File.Replace uses the Windows replacement primitive and retains a recovery copy.
	var command := "$ErrorActionPreference='Stop'; $source='%s'; $target='%s'; if ([System.IO.File]::Exists($target)) { [System.IO.File]::Replace($source,$target,$target+'.previous',$true) } else { [System.IO.File]::Move($source,$target) }" % [ProjectSettings.globalize_path(staged).replace("'", "''"), ProjectSettings.globalize_path(destination).replace("'", "''")]
	var output: Array = []
	var code := OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", command]), output, true, false)
	return OK if code == 0 else ERR_FILE_CANT_WRITE

# Create one absent canonical file without replacing a concurrent owner.
# Linux uses the POSIX link utility, whose sole operation is link(2). macOS
# uses Perl's direct link builtin: Apple link(1)'s directory recheck can turn
# a raced destination directory into a different path. A missing utility or
# unsupported filesystem fails; never fall back to replace/rename.
static func publish_new(staged:String,destination:String)->Error:
	var source:=ProjectSettings.globalize_path(staged)
	var target:=ProjectSettings.globalize_path(destination)
	var output:Array=[]
	var code: int
	match OS.get_name():
		"Windows":
			var command := "$ErrorActionPreference='Stop'; $source='%s'; $target='%s'; try { [System.IO.File]::Move($source,$target); exit 0 } catch { if ([System.IO.File]::Exists($target) -or [System.IO.Directory]::Exists($target)) { exit 17 }; exit 1 }" % [source.replace("'", "''"),target.replace("'", "''")]
			code=OS.execute("powershell.exe",PackedStringArray(["-NoProfile","-NonInteractive","-Command",command]),output,true,false)
		"Linux":
			var link_path:="/usr/bin/link" if FileAccess.file_exists("/usr/bin/link") else "/bin/link"
			if not FileAccess.file_exists(link_path):return ERR_UNAVAILABLE
			code=OS.execute(link_path,PackedStringArray([source,target]),output,true,false)
			if code!=0 and (FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target)):return ERR_ALREADY_EXISTS
		"macOS","FreeBSD","OpenBSD","NetBSD":
			# No shell interpolation and no path-as-program-text. If the system Perl
			# is absent this platform reports unsupported instead of replacing.
			if not FileAccess.file_exists("/usr/bin/perl"):return ERR_UNAVAILABLE
			var script:="use Errno qw(EEXIST); if (link($ARGV[0], $ARGV[1])) { exit 0 } exit($! == EEXIST ? 17 : 1);"
			code=OS.execute("/usr/bin/perl",PackedStringArray(["-e",script,source,target]),output,true,false)
		_:
			return ERR_UNAVAILABLE
	if code==0:return OK
	if code==17:return ERR_ALREADY_EXISTS
	if code<0:return ERR_UNAVAILABLE
	return ERR_FILE_CANT_WRITE

## Publish already-written immutable files with one Windows process. Callers
## own their staging files and must clean only those files afterwards. Existing
## targets are never replaced, even when another publisher wins after preflight.
## A partial failure leaves successful immutable products in place; the caller
## must withhold its visible descriptor/index until this result is successful.
static func publish_new_batch(rows:Array,content_root:String,token:RefCounted=null)->Dictionary:
	var result:Dictionary={"ok":false,"error":ERR_INVALID_PARAMETER,"results":[],"processes":0,"metadata_bytes":0}
	if _batch_cancelled(token):result.error=ERR_SKIP;return result
	if content_root.is_empty() or not content_root.is_absolute_path() or not DirAccess.dir_exists_absolute(content_root):result.error=ERR_FILE_BAD_PATH;return result
	var root:=content_root.replace("\\","/").simplify_path().trim_suffix("/")
	var normalized:Array=[];var paths:Array=[];var sources:Dictionary={};var destinations:Dictionary={}
	for row:Variant in rows:
		if not row is Dictionary or not row.get("staged") is String or not row.get("destination") is String:return result
		var source:String=row.staged.replace("\\","/").simplify_path()
		var target:String=row.destination.replace("\\","/").simplify_path()
		if not source.is_absolute_path() or not target.is_absolute_path():result.error=ERR_FILE_BAD_PATH;return result
		var source_key:=source.to_lower() if OS.get_name()=="Windows" else source
		var target_key:=target.to_lower() if OS.get_name()=="Windows" else target
		if sources.has(source_key) or destinations.has(target_key):return result
		sources[source_key]=true;destinations[target_key]=true
		normalized.append({"staged":source,"destination":target});paths.append(source);paths.append(target)
	for source_key:String in sources:
		if destinations.has(source_key):return result
	# Invalid paths/rows are rejected before writing even the small IPC manifest.
	paths.append(root)
	if not BatchPaths.allowed_many(paths,root):result.error=ERR_FILE_BAD_PATH;return result
	var all_existing:=true
	for row:Dictionary in normalized:
		if not FileAccess.file_exists(row.staged) or not DirAccess.dir_exists_absolute(row.destination.get_base_dir()) or DirAccess.dir_exists_absolute(row.destination):result.error=ERR_FILE_BAD_PATH;return result
		all_existing=all_existing and FileAccess.file_exists(row.destination)
	if _batch_cancelled(token):result.error=ERR_SKIP;return result
	if normalized.is_empty() or all_existing:
		for row:Dictionary in normalized:result.results.append(ERR_ALREADY_EXISTS)
		result.ok=true;result.error=OK;return result
	if normalized.size()==1:
		# A single product already needs only one process. Avoid JSON IPC setup
		# for common one-texture models while retaining the same batch contract.
		var row:Dictionary=normalized[0]
		var error:=publish_new(row.staged,row.destination);result.processes=1
		if error==ERR_ALREADY_EXISTS and not FileAccess.file_exists(row.destination):error=ERR_FILE_BAD_PATH
		result.results=[error];result.error=OK if error in [OK,ERR_ALREADY_EXISTS] else error
		if _batch_cancelled(token):result.error=ERR_SKIP
		result.ok=result.error==OK;return result
	if OS.get_name()!="Windows":
		var stopped:=false
		for row:Dictionary in normalized:
			var error:Error=ERR_SKIP
			if not stopped:
				if _batch_cancelled(token):result.error=ERR_SKIP;stopped=true
				else:
					error=publish_new(row.staged,row.destination);result.processes+=1
					if error==ERR_ALREADY_EXISTS and not FileAccess.file_exists(row.destination):error=ERR_FILE_BAD_PATH
					if error not in [OK,ERR_ALREADY_EXISTS]:result.error=error;stopped=true
			result.results.append(error)
		if not stopped:
			result.error=ERR_SKIP if _batch_cancelled(token) else OK;result.ok=result.error==OK
		return result
	# An atomically-created owned directory prevents accidental reuse/overwrite
	# of another invocation's IPC file. The JSON contains paths, never pixels.
	var base:=root.path_join(".immutable-publish-%d-%d-%d"%[OS.get_process_id(),OS.get_thread_caller_id(),Time.get_ticks_usec()])
	var temporary_dir:=base;var suffix:=0
	while true:
		if not BatchPaths.allowed(temporary_dir,root):result.error=ERR_FILE_BAD_PATH;return result
		var error:=DirAccess.make_dir_absolute(temporary_dir)
		if error==OK:break
		if error!=ERR_ALREADY_EXISTS:result.error=error;return result
		suffix+=1;temporary_dir=base+"-"+str(suffix)
	var manifest:=temporary_dir.path_join("paths.json")
	var file:=FileAccess.open(manifest,FileAccess.WRITE)
	if file==null:
		result.error=FileAccess.get_open_error();_cleanup_batch_manifest(manifest,temporary_dir,root);return result
	var encoded:=JSON.stringify({"rows":normalized}).to_utf8_buffer();result.metadata_bytes=encoded.size()
	var stored:=file.store_buffer(encoded);file.close();encoded.clear()
	if not stored or _batch_cancelled(token):
		result.error=ERR_SKIP if stored else ERR_FILE_CANT_WRITE;_cleanup_batch_manifest(manifest,temporary_dir,root);return result
	# No path is evaluated as code. Only the owned manifest path is quoted here;
	# all source/destination paths are data passed directly to File.Move.
	var command:="$ErrorActionPreference='Stop'; $batch=Get-Content -LiteralPath '%s' -Raw -Encoding UTF8 | ConvertFrom-Json; $codes=New-Object 'System.Collections.Generic.List[int]'; $failed=$false; foreach($row in $batch.rows) { if($failed) { $codes.Add(2); continue }; try { if([System.IO.File]::Exists($row.destination)) { $codes.Add(17); continue }; [System.IO.File]::Move($row.staged,$row.destination); $codes.Add(0) } catch { if([System.IO.File]::Exists($row.destination)) { $codes.Add(17) } else { $codes.Add(1); $failed=$true } } }; [Console]::Out.Write((ConvertTo-Json -InputObject @{codes=$codes.ToArray()} -Compress)); exit 0"%manifest.replace("'","''")
	var output:Array=[];result.processes=1
	var code:=OS.execute("powershell.exe",PackedStringArray(["-NoProfile","-NonInteractive","-Command",command]),output,true,false)
	_cleanup_batch_manifest(manifest,temporary_dir,root)
	var decoded:Variant=JSON.parse_string("".join(output)) if code==0 else null
	if not decoded is Dictionary or not decoded.get("codes") is Array or decoded.codes.size()!=normalized.size():
		for row:Dictionary in normalized:result.results.append(ERR_UNAVAILABLE)
		result.error=ERR_UNAVAILABLE if code<0 else ERR_FILE_CANT_WRITE;return result
	result.error=OK
	for value:Variant in decoded.codes:
		var error:Error=OK if value==0 else (ERR_ALREADY_EXISTS if value==17 else (ERR_SKIP if value==2 else ERR_FILE_CANT_WRITE))
		result.results.append(error)
		if result.error==OK and error not in [OK,ERR_ALREADY_EXISTS]:result.error=error
	if _batch_cancelled(token):result.error=ERR_SKIP
	result.ok=result.error==OK
	return result

static func _batch_cancelled(token:RefCounted)->bool:
	return token!=null and token.is_cancelled()

static func _cleanup_batch_manifest(manifest:String,directory:String,root:String)->void:
	if not BatchPaths.allowed_many([manifest,directory],root):return
	if FileAccess.file_exists(manifest):DirAccess.remove_absolute(manifest)
	DirAccess.remove_absolute(directory) # Owned empty directory only; never recursive.
