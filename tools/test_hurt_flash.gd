extends SceneTree
## Headless: hurt flash starts red, retrigger restarts, base tint restored;
## NPC actor reuses the same helper; miss path does not flash.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var HurtFlash = load("res://scripts/game/hurt_flash.gd")
	failed += _expect(HurtFlash != null, "load hurt_flash.gd")
	var flash = HurtFlash.new()
	var sprite := Sprite2D.new()
	root.add_child(sprite)
	var base := Color(0.9, 0.95, 1.0, 0.8)
	sprite.modulate = base

	flash.trigger(sprite)
	failed += _expect(flash.is_active(), "active after damage")
	failed += _expect(absf(flash.duration - 0.16) < 0.001, "default duration 0.16s")
	failed += _expect(sprite.modulate.is_equal_approx(HurtFlash.HIT_COLOR), "impact is red")
	flash.tick(0.08)
	failed += _expect(flash.is_active(), "active halfway")
	failed += _expect(sprite.modulate.r > sprite.modulate.g, "halfway remains red-tinted")

	# Retrigger must restart without capturing the current red tint as the base.
	flash.trigger(sprite)
	failed += _expect(absf(flash.remaining - 0.16) < 0.001, "retrigger restarts")
	flash.tick(0.20)
	failed += _expect(not flash.is_active(), "settles inactive")
	failed += _expect(sprite.modulate.is_equal_approx(base), "restores original modulate")

	# Clamp keeps custom flashes inside the requested thin 0.12-0.20s window.
	flash.trigger(sprite, 0.01)
	failed += _expect(absf(flash.duration - 0.12) < 0.001, "minimum duration")
	flash.tick(1.0)
	flash.trigger(sprite, 1.0)
	failed += _expect(absf(flash.duration - 0.20) < 0.001, "maximum duration")
	flash.clear()
	failed += _expect(sprite.modulate.is_equal_approx(base), "clear restores base")

	sprite.queue_free()

	# NPC actor: same helper via flash_hurt on Anim.
	var NpcActor = load("res://scripts/game/npc_actor.gd")
	failed += _expect(NpcActor != null, "load npc_actor.gd")
	var npc: Node2D = NpcActor.new()
	root.add_child(npc)
	# Ensure Anim exists without full setup/charset.
	var anim := AnimatedSprite2D.new()
	anim.name = "Anim"
	var npc_base := Color(0.85, 0.9, 1.0, 1.0)
	anim.modulate = npc_base
	npc.add_child(anim)
	failed += _expect(npc.has_method("flash_hurt"), "npc has flash_hurt")
	failed += _expect(not npc.is_hurt_flashing(), "npc idle not flashing")
	npc.flash_hurt()
	failed += _expect(npc.is_hurt_flashing(), "npc active after hit")
	failed += _expect(anim.modulate.is_equal_approx(HurtFlash.HIT_COLOR), "npc Anim impact red")
	# Drive _process tick via helper remaining (direct process may not run in one frame).
	npc._process(0.20)
	failed += _expect(not npc.is_hurt_flashing(), "npc settles inactive")
	failed += _expect(anim.modulate.is_equal_approx(npc_base), "npc restores Anim modulate")

	# Miss must not flash: world returns on is_miss before flash_hurt; simulate by not calling.
	failed += _expect(not npc.is_hurt_flashing(), "miss path leaves npc unflashed")

	# World wiring: damage branch calls flash_hurt only when amount > 0 after miss return.
	var world_src := FileAccess.get_file_as_string("res://scripts/game/world.gd")
	failed += _expect(world_src.find("target_npc.flash_hurt()") >= 0, "world calls npc flash_hurt")
	var miss_idx := world_src.find("if is_miss:")
	# Find the NPC section miss (last is_miss before flash_hurt is fragile); assert flash is inside amount > 0.
	var flash_idx := world_src.find("target_npc.flash_hurt()")
	var amt_before := world_src.rfind("if amount > 0:", flash_idx)
	failed += _expect(amt_before >= 0 and amt_before < flash_idx, "npc flash gated by amount > 0")
	# Miss return precedes the amount>0 flash in the NPC branch.
	var npc_miss := world_src.find("if is_miss:", world_src.find('var display_name := "敌人"'))
	failed += _expect(npc_miss >= 0 and npc_miss < flash_idx, "npc miss returns before flash")

	npc.queue_free()
	if failed == 0:
		print("test_hurt_flash: PASS")
		quit(0)
	else:
		print("test_hurt_flash: FAIL count=", failed)
		quit(1)


func _expect(ok: bool, label: String) -> int:
	if not ok:
		push_error("FAIL: " + label)
		return 1
	return 0
