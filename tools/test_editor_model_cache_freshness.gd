extends "res://tools/test_editor_native_only.gd"
## The old source-mutation/GLB fallback contract was retired. The replacement
## checks actual published-native identity, cache replacement and pinned owner
## handoff; original legacy fixture is archived outside the project.
func result_label()->String:return "EDITOR_MODEL_CACHE_FRESHNESS"
