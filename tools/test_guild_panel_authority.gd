extends SceneTree
## Headless UI boundary test: deferred authority, invite replacement and Mock actions.
const GuildPanel = preload("res://scripts/ui/panels/guild_panel.gd")
const GuildModule = preload("res://scripts/net/server/guild_module.gd")
const Net = preload("res://scripts/net/net.gd")
const RequestPipeline = preload("res://scripts/net/request_pipeline.gd")
var failures := 0

class Hud extends Control:
	var _guild_panel: PanelContainer
	var _guild_body: VBoxContainer
	var _guild_name_input: LineEdit
	var _guild_invite_input: LineEdit
	var _guild_pending_invite: Dictionary = {}
	var _guild_state: Dictionary = {}
	var _windows: Dictionary = {}
	var _world_combat = null
	var messages: Array[String] = []
	func _refresh_name_with_title() -> void: pass
	func _nudge_guild() -> void: pass
	func append_system(message: String) -> void: messages.append(message)
	func _add_label(parent: Node, text: String, _size: int, _color: Color) -> void:
		var label := Label.new(); label.text = text; parent.add_child(label)

class Remote extends Node:
	signal response_ready(request_id: int, result: Dictionary)
	var epoch := 1
	var calls: Array = []
	var state: Dictionary = {"supported": true, "loaded": false, "invites": []}
	func is_remote_transport() -> bool: return true
	func context() -> Dictionary: return {"session_epoch": epoch}
	func snapshot_guild() -> Dictionary: return state.duplicate(true)
	func request(operation: String, args: Array = []) -> Dictionary:
		calls.append([operation, args]); return {"deferred": true, "request_id": calls.size()}
	func try_guild_refresh() -> Dictionary: return request("refresh")
	func try_guild_create(guild_name: String) -> Dictionary: return request("create", [guild_name])
	func try_guild_transfer(member_id: String) -> Dictionary: return request("transfer", [member_id])
	func try_guild_invite_respond(invite_id: String, accept: bool) -> Dictionary: return request("respond", [invite_id, accept])
	func finish(result: Dictionary = {"ok": true, "actions": []}) -> void:
		response_ready.emit(calls.size(), result)

class Mock extends Node:
	var guild = null
	var _guild_invites: Array = []
	var _next_guild_seq := 1
	var module: RefCounted
	func _init() -> void: module = GuildModule.new(self)
	func _party_self_id() -> String: return "mock-self"
	func _party_self_name() -> String: return "Mock player"
	func snapshot_guild() -> Dictionary: return module.snapshot_guild()
	func try_guild_create(guild_name: String) -> Dictionary: return module.try_guild_create(guild_name)
	func try_guild_disband() -> Dictionary: return module.try_guild_disband()

class World extends Node:
	var panel: RefCounted
	var applied := 0
	func _apply_server_actions(actions: Array) -> void:
		applied += 1; panel._apply_guild_result_locally({"actions": actions})

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	print("PASS " if condition else "FAIL ", label)
	if not condition: failures += 1

func labels(node: Node) -> String:
	var text: String = node.text + "\n" if node is Label else ""
	for child in node.get_children(): text += labels(child)
	return text

func buttons(node: Node, text: String) -> Array:
	var result: Array = []
	if node is Button and node.text == text: result.append(node)
	for child in node.get_children(): result.append_array(buttons(child, text))
	return result

func run() -> void:
	RequestPipeline.reset()
	var server := Remote.new(); root.add_child(server); Net._server_override = server
	var hud := Hud.new(); root.add_child(hud)
	hud._guild_panel = PanelContainer.new(); hud.add_child(hud._guild_panel)
	hud._guild_body = VBoxContainer.new(); hud._guild_panel.add_child(hud._guild_body)
	var panel := GuildPanel.new(hud)
	panel._actions = HBoxContainer.new(); hud.add_child(panel._actions)
	panel._toggle_guild_panel(true)
	check(server.calls.size() == 1 and RequestPipeline.pending_count() == 1 and hud._guild_name_input == null, "opening unloaded remote guild fetches authority before offering creation")
	panel._toggle_guild_panel(true)
	check(server.calls.size() == 1, "opening during refresh does not issue another request")
	server.state = {"supported": true, "loaded": true, "creation_fee": 175, "max_members": 7, "self_id": "self", "id": "", "members": [], "invites": [
		{"invite_id": "first", "guild_name": "First", "from": "A"}, {"invite_id": "second", "guild_name": "Second", "from": "B"}]}
	server.finish()
	check(labels(hud).contains("175") and labels(hud).contains("7") and buttons(hud, "接受").size() == 2, "server fee/capacity and all incoming invitations are rendered")
	buttons(hud, "接受")[1].pressed.emit()
	check(server.calls.back() == ["respond", ["second", true]] and buttons(hud, "接受")[0].disabled, "invite response uses selected identity and blocks overlapping changes")
	server.state.invites = []; server.finish({"ok": false, "error": "邀请已过期", "actions": []})
	check(hud._guild_pending_invite.is_empty() and buttons(hud, "接受").is_empty() and labels(hud).contains("邀请已过期"), "failed expired invite clears stale controls and displays server error")
	panel.apply_guild_invite({"invite_id": "second", "status": "pending"})
	check(buttons(hud, "接受").is_empty(), "legacy notification cannot resurrect consumed remote invite")
	server.state.merge({"id": "guild", "name": "Guild", "leader_id": "self", "members": [
		{"id": "self", "name": "Self", "rank": "leader"}, {"id": "member", "name": "Member", "rank": "member"}]}, true)
	panel.apply_guild_update({"guild": server.snapshot_guild()})
	check(buttons(hud, "离开公会")[0].disabled and labels(hud).contains("人数 2 / 7"), "remote leader must transfer or disband and roster uses server capacity")
	var previous_calls := server.calls.size()
	buttons(hud, "转让")[0].pressed.emit()
	check(server.calls.size() == previous_calls and buttons(hud, "确认转让").size() == 1, "transfer first presents the selected member and loss of leader role")
	buttons(hud, "确认转让")[0].pressed.emit()
	check(server.calls.back() == ["transfer", ["member"]], "confirmed transfer sends member identity through deferred pipeline")
	server.state.leader_id = "member"; server.state.members[0].rank = "member"; server.state.members[1].rank = "leader"
	server.finish()
	check(buttons(hud, "转让").is_empty() and not buttons(hud, "离开公会")[0].disabled, "authoritative transfer immediately removes old leader controls")
	panel._dispatch_guild("try_guild_refresh"); server.epoch += 1
	server.state = {"supported": true, "loaded": false, "invites": []}
	server.finish({"ok": false, "error": "old session error", "actions": []})
	panel._toggle_guild_panel(true)
	check(hud._guild_state.get("id", "").is_empty() and panel._request_error.is_empty() and hud._guild_name_input == null, "reconnect discards stale guild, invitation and pending reply")
	server.state = {"supported": false, "loaded": true, "invites": []}; server.finish({"ok": false, "unsupported": true, "actions": []})
	check(buttons(hud, "创建公会").is_empty() and labels(hud).contains("尚未提供公会管理"), "unsupported server never renders a fake empty guild creation flow")

	RequestPipeline.reset()
	var mock := Mock.new(); root.add_child(mock); Net._server_override = mock
	panel._toggle_guild_panel(true)
	hud._guild_name_input.text = "Mock Guild"; panel._on_guild_create_pressed()
	check(hud._guild_state.name == "Mock Guild" and hud.messages.size() == 1 and panel._pending_request.is_empty(), "actual synchronous Mock guild module still applies creation and message once")
	var world := World.new(); root.add_child(world); world.panel = panel; hud._world_combat = world
	panel._on_guild_disband()
	check(hud._guild_state.id.is_empty() and world.applied == 1 and hud.messages.size() == 2, "world action path does not double apply synchronous Mock result")

	RequestPipeline.reset(); Net.clear_server_override()
	world.panel = null; hud._world_combat = null; mock.module = null
	hud.queue_free(); server.queue_free(); mock.queue_free(); world.queue_free()
	await process_frame
	print("GUILD_PANEL_AUTHORITY_TESTS failures=", failures)
	quit(0 if failures == 0 else 1)
