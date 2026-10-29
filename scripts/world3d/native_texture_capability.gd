extends RefCounted
## Native output ownership can leave the project ledger only when the engine
## can prove that the particular texture has an actual streaming registration.
const MISSING_REGISTRATION_QUERY="Native split textures require StreamedTexture2D.is_streaming_active(); use the patched Godot 4.8 engine with streaming registration queries."
static func error_for(descriptor:Dictionary,custom_preparation:bool=false)->String:
	var count_:Variant=descriptor.get("textures",0)
	if custom_preparation or not (count_ is int or count_ is float) or count_<=0:return ""
	return "" if ClassDB.class_has_method("StreamedTexture2D","is_streaming_active") else MISSING_REGISTRATION_QUERY
