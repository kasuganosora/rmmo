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
