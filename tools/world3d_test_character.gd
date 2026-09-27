extends RefCounted
## Physics/world tests explicitly select an actor; production never invents one.
static func ensure(tree: SceneTree) -> void:
	var session = tree.root.get_node("GameSession")
	if session.has_active_character(): return
	session.selected_character = {"id": -100, "name": "测试角色", "gender": "male", "customization": {}}
	session.spawn_data = {}
