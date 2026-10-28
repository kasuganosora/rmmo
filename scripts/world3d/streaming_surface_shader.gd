extends RefCounted
## Two shared variants, created by main-thread material construction only.
## CPU batching recognizes both identities without creating shaders on workers.
## The streaming project setting is fixed before loading a map, not toggled live.
const TERRAIN=preload("res://scripts/world3d/river_terrain.gdshader")
const BANK=preload("res://scripts/world3d/river_bank.gdshader")
static var _terrain:Shader
static var _bank:Shader

static func enabled()->bool:
	return ClassDB.class_exists("StreamedTexture2D") and Engine.has_singleton("TextureStreaming") and bool(ProjectSettings.get_setting("rendering/textures/streaming/enabled",false)) and RenderingServer.get_current_rendering_method() in ["forward_plus","mobile"]

static func _variant(source:Shader)->Shader:
	var shader:=Shader.new()
	shader.code="#define RMMO_TEXTURE_STREAMING\n"+source.code
	return shader

static func terrain()->Shader:
	if not enabled():return TERRAIN
	if _terrain==null:_terrain=_variant(TERRAIN)
	return _terrain

static func bank()->Shader:
	if not enabled():return BANK
	if _bank==null:_bank=_variant(BANK)
	return _bank

static func is_terrain(shader:Shader)->bool:
	return shader!=null and (shader==TERRAIN or shader==_terrain)
