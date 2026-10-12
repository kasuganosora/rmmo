extends RefCounted
## User interface preferences only; never part of the map or its undo history.
var config := ConfigFile.new()
var path := "user://world_editor_layout.cfg"
var writable := true

func setup(editor: Node) -> void:
	path = str(editor.get_meta("layout_preferences_path", path))
	writable = not bool(editor.get_meta("layout_preferences_readonly", false))
	config.load(path)

func read(key: String, fallback: Variant) -> Variant:
	return config.get_value("layout", key, fallback)

func write(key: String, value: Variant) -> void:
	config.set_value("layout", key, value)
	if writable: config.save(path)
