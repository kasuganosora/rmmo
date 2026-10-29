extends SceneTree
const Social=preload("res://scripts/net/remote/social.gd")
const Real=preload("res://scripts/net/real_server.gd")
const QuestPanel=preload("res://scripts/ui/panels/quest_panel.gd")
const Net=preload("res://scripts/net/net.gd")
var failures:=0

class Transport extends Node:
	signal reply
	var business_snapshots:Dictionary={}
	var _connection_revision:=1
	var _snapshot_published_serial:=0
	var _session_character_id:="42"
	var epoch:=1
	var reads:=0
	var delayed:=false
	var status:=200
	var request:Dictionary={}
	var data:Dictionary={}
	func context()->Dictionary:return {"session_epoch":epoch}
	func request_api(path:String,method:int=HTTPClient.METHOD_GET,body:Dictionary={})->Dictionary:
		reads+=1;request={"path":path,"method":method,"body":body.duplicate(true)}
		if delayed:await reply
		return {"ok":status==200,"status":status,"body":{"data":data.duplicate(true)}}

class Hud extends Control:
	var _quest_tab:="completed"
	var _server_quests:Array=[]
	var _selected_quest_id:=""
	var _quest_drawer=null
	var _quest_drawer_tween=null
	var _quest_drawer_body=null
	var _windows:Dictionary={}
	var _world_combat=null
	var _abandon_confirm_id:=""
	var guild_updates:Array=[]
	var guild_invites:Array=[]
	var messages:Array=[]
	func apply_guild_update(action:Dictionary)->void:guild_updates.append(action)
	func apply_guild_invite(action:Dictionary)->void:guild_invites.append(action)
	func append_system(message:String)->void:messages.append(message)
	func _add_label(parent:Node,text:String,_size:int,_color:Color)->void:
		var node:=Label.new();node.text=text;parent.add_child(node)

class QuestTransport extends Real:
	var quest_calls:Array=[]
	func try_turn_in_quest(id:String)->Dictionary:
		quest_calls.append(["complete",id]);return {"deferred":true,"request_id":700+quest_calls.size()}
	func try_abandon_quest(id:String)->Dictionary:
		quest_calls.append(["abandon",id]);return {"deferred":true,"request_id":700+quest_calls.size()}

class WorldBridge extends Node:
	var received:Array=[]
	func apply_actions(actions:Array)->void:received.append_array(actions)

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func capture(social:RefCounted,result:Dictionary)->void:
	result.value=await social.execute("quest_history",["",20]);result.done=true
func capture_guild(social:RefCounted,result:Dictionary)->void:
	result.value=await social.execute("guild_refresh",[]);result.done=true

func run()->void:
	var transport:=Transport.new();root.add_child(transport)
	var social:=Social.new(transport)
	transport.status=404
	var result:Dictionary=await social.execute("quest_history",["",20])
	await social.execute("quest_history",["",20])
	check(result.get("unsupported",false) and transport.reads==1,"old server history unsupported is remembered without polling")
	transport.status=200;social.reset()
	transport.data={"entries":[{"id":"20","quest":"q","name":"Frozen completed name","gold":5}],"next_cursor":"20","has_more":true}
	result=await social.execute("quest_history",["21",1])
	check(result.ok and result.data.quests[0].id=="history:20" and result.data.quests[0].title=="Frozen completed name" and transport.request.path.ends_with("cursor=21&limit=1"),"history projects frozen title and stable page cursor without active journal mutation")
	result=await social.execute("quest_history",["",0])
	check(result.ok and not transport.request.path.contains("limit=") and result.data.quests.size()==1,"default history page leaves size to a server with a smaller configured limit")
	transport.delayed=true
	var pending:={"done":false};capture(social,pending)
	transport.epoch=2;transport.reply.emit();await process_frame
	check(pending.done and not pending.value.ok and pending.value.error=="stale_world_response","delayed history from previous world rejected")
	transport.delayed=false
	transport.business_snapshots={"progression":{"guild":{"id":"g","revision":3,"next_request_id":"9","invites":[{"invite_id":"i"}]}}}
	check(social.snapshot_guild().id=="g" and social.actions().size()==1 and social.actions().is_empty(),"nested guild snapshot emits one update without rebuilding unchanged UI")
	transport.data={"id":"g","revision":4,"next_request_id":"10","members":[]}
	result=await social.execute("guild_change",[{"action":"kick","target_id":"7","guild_id":"old-guild","expected_revision":2}])
	check(result.ok and transport.request.body.request_id=="9" and transport.request.body.guild_id=="old-guild" and transport.request.body.expected_revision==2,"guild request keeps observed identity and revision while allocating next receipt")
	transport.delayed=true
	var waiting_guild:={"done":false};capture_guild(social,waiting_guild)
	transport.business_snapshots.progression.guild={"id":"","revision":0,"next_request_id":"12","members":[],"invites":[{"invite_id":"new-invite"}]}
	transport._snapshot_published_serial+=1
	transport.reply.emit();await process_frame
	check(waiting_guild.done and waiting_guild.value.ok and waiting_guild.value.data.id=="" and social.snapshot_guild().invites[0].invite_id=="new-invite","same-context delayed guild HTTP cannot undo an already published kick and invitation")
	check(transport.business_snapshots.progression.guild.next_request_id=="12" and waiting_guild.value.data.next_request_id=="12","late guild read cannot rewind the next request receipt")
	var same_value:={"done":false};capture_guild(social,same_value)
	transport._snapshot_published_serial+=1
	transport.reply.emit();await process_frame
	check(same_value.done and same_value.value.data.next_request_id=="12","new runtime publication fences old HTTP even when the current guild value is unchanged")
	transport.delayed=false
	social.reset();check(not social.snapshot_guild().is_empty(),"live authoritative nested guild remains available after presentation reset")
	transport.queue_free()
	var server:=QuestTransport.new();root.add_child(server)
	server.world_session={"boot_id":"test","session_epoch":1,"map_generation":1,"map_ref":"test/map"}
	server.business_snapshots={"progression":{"quests":[{"definition":{"uuid":"q","name":"Objectives","objectives":[{"id":"level","kind":"reach_level","count":3},{"id":"environment","kind":"environment_operate","object":"gate","action":"open","count":1},{"id":"instance","kind":"complete_instance","target":"test/dungeon","count":1}]},"progress":{"level":3,"environment":1,"instance":0},"accepted_at_key":"exact-key","acceptance_id":"77"}]}}
	server.gameplay.projection.apply()
	var quest:Dictionary=server.snapshot_quest_journal()[0]
	check(quest.status=="in_progress" and quest.objectives[0].text=="达到等级 3" and quest.objectives[1].text.contains("打开") and quest.objectives[2].text.contains("test/dungeon"),"new objectives show actionable text and authoritative incomplete progress")
	server.business_snapshots.progression.quests[0].progress.instance=1;server.gameplay.projection.apply()
	check(server.snapshot_quest_journal()[0].status=="ready","all authoritative objectives make quest deliverable")
	check(server.gameplay.projection.acceptance("q")=={"accepted_at_key":"exact-key","acceptance_id":"77"},"quest mutation preserves exact acceptance identifiers")
	Net._server_override=server
	var hud:=Hud.new();root.add_child(hud)
	var panel:=QuestPanel.new(hud);panel._ensure_history_context();panel._history_loaded=true
	panel._history_rows=[{"id":"history:1","title":"History","status":"completed"}];panel._history_next="1"
	var body:=VBoxContainer.new();hud.add_child(body);panel._fill_quest(body,{})
	check(body.get_child_count()==2 and body.get_child(0).get_child(0).disabled and not body.get_child(0).get_child(2).disabled,"completed tab renders page controls and history row")
	check(panel._quest_by_id("history:1").title=="History","history detail selection is independent of active journal")
	server.world_session.session_epoch=2;panel._ensure_history_context()
	check(panel._history_rows.is_empty() and not panel._history_loaded,"reconnect context clears completed page cache")
	var world=load("res://scripts/world3d/world_3d.gd").new()
	world._hud=hud
	world.apply_actions([{"type":"guild_update","guild":{"id":"live"}},{"type":"guild_invite","invite_id":"live-invite"}])
	check(hud.guild_updates.size()==1 and hud.guild_invites.size()==1,"real 3D world forwards unsolicited guild updates to HUD")
	world.free()
	var bridge:=WorldBridge.new();root.add_child(bridge);hud._world_combat=bridge
	panel._on_quest_turn_in("q");server.response_ready.emit(701,{"ok":false,"actions":[{"type":"system_message","text":"rejected"}]})
	hud._abandon_confirm_id="q";panel._on_quest_abandon("q");server.response_ready.emit(702,{"ok":true,"actions":[]})
	check(server.quest_calls==[["complete","q"],["abandon","q"]] and bridge.received.size()==1,"3D quest drawer submits deferred turn-in and confirmed abandonment")
	bridge.queue_free()
	Net.clear_server_override();hud.queue_free();server.queue_free()
	print("REMOTE_QUEST_SOCIAL_TESTS failures=",failures);quit(0 if failures==0 else 1)
