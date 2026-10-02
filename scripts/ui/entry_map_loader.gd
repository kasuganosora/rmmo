extends Node
## Import the map's already-exported presentation meshes, without rebuilding
## editable geometry, event actors, collision or navigation from authoring records.
signal finished(scene: Node, path: String, error: String)
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
var _thread: Thread
var _document: GLTFDocument
var _state: GLTFState
var _path := ""
var _error := OK
var _cancelled := false

func start(path: String) -> void:
	_path = path
	_thread = Thread.new()
	_error = _thread.start(_parse)
	if _error != OK:
		_thread = null
		finished.emit(null, _path, "无法启动入口地图读取")
		queue_free()

func _parse() -> void:
	_document = GLTFDocument.new(); _state = GLTFState.new()
	_error = _document.append_from_file(_path, _state, 0, _path.get_base_dir())

func _process(_delta: float) -> void:
	if _thread == null or _thread.is_alive(): return
	_thread.wait_to_finish(); _thread = null
	if not _cancelled:
		var scene: Node = Io.generate_scene(_document, _state) if _error == OK else null
		finished.emit(scene, _path, "" if scene != null else "入口地图读取失败：" + error_string(_error))
	queue_free()

func cancel() -> void: _cancelled = true

func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish(); _thread = null
