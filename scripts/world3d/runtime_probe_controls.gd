extends RefCounted
## Diagnostic controls set by dedicated profiling tools before workers start.
## Never exposed in game/editor UI; ordinary production keeps all features.
static var discard_map_textures:=false
static var hud_enabled:=true

static func configure_gltf(state:GLTFState)->void:
	if discard_map_textures:state.handle_binary_image=GLTFState.HANDLE_BINARY_DISCARD_TEXTURES
