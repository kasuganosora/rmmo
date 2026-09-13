extends SceneTree
## Headless equipment equip/unequip / slot compatibility tests.

const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")
const Equipment = preload("res://scripts/net/combat/equipment.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_catalog_equipment()
	failed += _test_equip_unequip()
	failed += _test_incompatible()
	failed += _test_ring_family()
	failed += _test_starter_has_gear()
	failed += _test_find_slot_of()
	if failed == 0:
		print("test_equipment: PASS")
		quit(0)
	else:
		print("test_equipment: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _make() -> Dictionary:
	var cat = ItemCatalog.new()
	cat.load_catalog()
	var bag = Inventory.new()
	bag.set_catalog(cat)
	bag.clear()
	var eq = Equipment.new()
	eq.set_catalog(cat)
	eq.clear()
	return {"cat": cat, "bag": bag, "eq": eq}


func _test_catalog_equipment() -> int:
	var failed := 0
	var cat = ItemCatalog.new()
	cat.load_catalog()
	var sword = cat.get_item("wooden_sword")
	failed += _expect(not sword.is_empty(), "wooden_sword in catalog")
	failed += _expect(str(sword.get("type", "")) == "equipment", "type equipment")
	failed += _expect(str(sword.get("equip_slot", "")) == "weapon_main", "equip_slot weapon_main")
	failed += _expect(int(sword.get("stack_max", 0)) == 1, "stack_max 1")
	var bonus = sword.get("bonuses", {})
	failed += _expect(typeof(bonus) == TYPE_DICTIONARY and int(bonus.get("p_atk", 0)) == 3, "p_atk bonus 3")
	var ring = cat.get_item("copper_ring")
	failed += _expect(str(ring.get("equip_slot", "")) == "ring", "ring family key")
	return failed


func _test_equip_unequip() -> int:
	var failed := 0
	var m = _make()
	var bag = m.bag
	var eq = m.eq
	bag.add_item("wooden_sword", 1)
	bag.add_item("leather_vest", 1)
	var r = eq.try_equip_from_bag(bag, "wooden_sword", "weapon_main")
	failed += _expect(bool(r.get("ok", false)), "equip wooden_sword ok")
	failed += _expect(str(r.get("slot", "")) == "weapon_main", "slot weapon_main")
	failed += _expect(eq.get_item_in("weapon_main") == "wooden_sword", "equipped")
	failed += _expect(bag.get_qty("wooden_sword") == 0, "bag consumed sword")
	var snap = eq.snapshot()
	failed += _expect(snap.size() == Equipment.SLOT_IDS.size(), "snapshot size")
	var bons = eq.total_bonuses()
	failed += _expect(int(bons.get("p_atk", 0)) == 3, "total p_atk 3")
	# Equip vest
	r = eq.try_equip_from_bag(bag, "leather_vest", "chest")
	failed += _expect(bool(r.get("ok", false)), "equip vest")
	failed += _expect(int(eq.total_bonuses().get("p_def", 0)) == 2, "p_def 2")
	# Unequip sword
	r = eq.try_unequip_to_bag(bag, "weapon_main")
	failed += _expect(bool(r.get("ok", false)), "unequip sword")
	failed += _expect(bag.get_qty("wooden_sword") == 1, "sword back in bag")
	failed += _expect(eq.is_empty("weapon_main"), "slot empty")
	return failed


func _test_incompatible() -> int:
	var failed := 0
	var m = _make()
	var bag = m.bag
	var eq = m.eq
	bag.add_item("wooden_sword", 1)
	var r = eq.try_equip_from_bag(bag, "wooden_sword", "head")
	failed += _expect(not bool(r.get("ok", false)), "sword reject head")
	failed += _expect(str(r.get("reason", "")) == "incompatible_slot", "reason incompatible")
	failed += _expect(bag.get_qty("wooden_sword") == 1, "bag not consumed on reject")
	bag.add_item("potion_hp_small", 1)
	r = eq.try_equip_from_bag(bag, "potion_hp_small", "weapon_main")
	failed += _expect(not bool(r.get("ok", false)), "potion not equipment")
	return failed


func _test_ring_family() -> int:
	var failed := 0
	var m = _make()
	var bag = m.bag
	var eq = m.eq
	bag.add_item("copper_ring", 1)
	# Need two rings — add via try_add after first equip consumes
	var r = eq.try_equip_from_bag(bag, "copper_ring", "")
	failed += _expect(bool(r.get("ok", false)), "auto ring equip")
	failed += _expect(str(r.get("slot", "")) == "ring_l", "first empty ring_l")
	# Grant another ring (catalog stack_max 1 means separate — same id stacks to 1 only)
	# After consume, add again
	bag.add_item("copper_ring", 1)
	r = eq.try_equip_from_bag(bag, "copper_ring", "")
	failed += _expect(bool(r.get("ok", false)), "second ring equip")
	failed += _expect(str(r.get("slot", "")) == "ring_r", "second goes ring_r")
	# Preferred earring reject for ring item
	bag.add_item("copper_ring", 1)
	r = eq.try_equip_from_bag(bag, "copper_ring", "earring_l")
	failed += _expect(not bool(r.get("ok", false)), "ring reject earring")
	return failed


func _test_starter_has_gear() -> int:
	var failed := 0
	var cat = ItemCatalog.new()
	cat.load_catalog()
	var bag = Inventory.new()
	bag.set_catalog(cat)
	bag.grant_starter()
	failed += _expect(bag.get_qty("wooden_sword") >= 1, "starter wooden_sword")
	failed += _expect(bag.get_qty("leather_vest") >= 1, "starter leather_vest")
	failed += _expect(bag.get_qty("potion_hp_small") >= 1, "starter potions still")
	return failed


func _test_find_slot_of() -> int:
	var failed := 0
	var m = _make()
	var bag = m.bag
	var eq = m.eq
	bag.add_item("wooden_sword", 1)
	failed += _expect(eq.find_slot_of("wooden_sword") == "", "not equipped yet")
	var r = eq.try_equip_from_bag(bag, "wooden_sword", "")
	failed += _expect(bool(r.get("ok", false)), "auto equip sword")
	failed += _expect(eq.find_slot_of("wooden_sword") == "weapon_main", "find_slot_of weapon_main")
	r = eq.try_unequip_to_bag(bag, "weapon_main")
	failed += _expect(bool(r.get("ok", false)), "unequip after find")
	failed += _expect(eq.find_slot_of("wooden_sword") == "", "cleared find")
	return failed
