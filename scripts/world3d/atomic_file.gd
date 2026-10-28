extends RefCounted
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
