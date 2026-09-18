extends SceneTree
## Headless two-hand / offhand equip rules.

const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")
const Equipment = preload("res://scripts/net/combat/equipment.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_catalog_hands()
	failed += _test_two_hand_clears_off()
	failed += _test_off_blocked_by_two_hand()
	failed += _test_off_only_not_main()
	failed += _test_two_hand_bonuses_main_only()
	failed += _test_mock_message()
	if failed == 0:
		print("test_weapon_hands: PASS")
		quit(0)
	else:
		print("test_weapon_hands: FAIL count=", failed)
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


func _test_catalog_hands() -> int:
	var failed := 0
	var cat = ItemCatalog.new()
	cat.load_catalog()
	var club = cat.get_item("great_club")
	failed += _expect(not club.is_empty(), "great_club in catalog")
	failed += _expect(str(club.get("name", "")) == "大木棒", "great_club name")
	failed += _expect(str(club.get("hand", "")) == "both", "great_club hand both")
	failed += _expect(str(club.get("equip_slot", "")) == "weapon_main", "great_club slot main")
	var shield = cat.get_item("wood_shield")
	failed += _expect(not shield.is_empty(), "wood_shield in catalog")
	failed += _expect(str(shield.get("name", "")) == "木盾", "wood_shield name")
	failed += _expect(str(shield.get("hand", "")) == "off", "wood_shield hand off")
	failed += _expect(str(shield.get("equip_slot", "")) == "weapon_off", "wood_shield slot off")
	failed += _expect(Equipment.hand_of_def(club) == "both", "hand_of_def both")
	failed += _expect(Equipment.hand_of_def(shield) == "off", "hand_of_def off")
	return failed


func _test_two_hand_clears_off() -> int:
	var failed := 0
	var m = _make()
	var bag = m.bag
	var eq = m.eq
	bag.add_item("wood_shield", 1)
	bag.add_item("great_club", 1)
	var r = eq.try_equip_from_bag(bag, "wood_shield", "weapon_off")
	failed += _expect(bool(r.get("ok", false)), "equip shield first")
	failed += _expect(eq.get_item_in("weapon_off") == "wood_shield", "shield on off")
	r = eq.try_equip_from_bag(bag, "great_club", "weapon_main")
	failed += _expect(bool(r.get("ok", false)), "equip great_club ok")
	failed += _expect(eq.get_item_in("weapon_main") == "great_club", "club on main")
	failed += _expect(eq.is_empty("weapon_off"), "off cleared by two-hand")
	failed += _expect(bag.get_qty("wood_shield") == 1, "shield back in bag")
	failed += _expect(str(r.get("unequipped_offhand_item_id", "")) == "wood_shield", "reports cleared off")
	return failed


func _test_off_blocked_by_two_hand() -> int:
	var failed := 0
	var m = _make()
	var bag = m.bag
	var eq = m.eq
	bag.add_item("great_club", 1)
	bag.add_item("wood_shield", 1)
	var r = eq.try_equip_from_bag(bag, "great_club", "weapon_main")
	failed += _expect(bool(r.get("ok", false)), "equip club")
	failed += _expect(eq.main_is_two_handed(), "main_is_two_handed")
	r = eq.try_equip_from_bag(bag, "wood_shield", "weapon_off")
	failed += _expect(not bool(r.get("ok", false)), "shield rejected while two-hand")
	failed += _expect(str(r.get("reason", "")) == "two_hand_blocks_off", "reason two_hand_blocks_off")
	failed += _expect(str(r.get("message", "")) == "双手武器占用副手。", "message 双手武器占用副手。")
	failed += _expect(bag.get_qty("wood_shield") == 1, "shield not consumed")
	failed += _expect(eq.is_empty("weapon_off"), "off still empty")
	return failed


func _test_off_only_not_main() -> int:
	var failed := 0
	var m = _make()
	var bag = m.bag
	var eq = m.eq
	bag.add_item("wood_shield", 1)
	var r = eq.try_equip_from_bag(bag, "wood_shield", "weapon_main")
	failed += _expect(not bool(r.get("ok", false)), "offhand reject main")
	failed += _expect(str(r.get("reason", "")) == "incompatible_slot", "reason incompatible_slot")
	failed += _expect(bag.get_qty("wood_shield") == 1, "shield stays in bag")
	r = eq.try_equip_from_bag(bag, "wood_shield", "")
	failed += _expect(bool(r.get("ok", false)), "auto equip shield to off")
	failed += _expect(eq.get_item_in("weapon_off") == "wood_shield", "shield on off via auto")
	return failed


func _test_two_hand_bonuses_main_only() -> int:
	var failed := 0
	var m = _make()
	var bag = m.bag
	var eq = m.eq
	bag.add_item("great_club", 1)
	var r = eq.try_equip_from_bag(bag, "great_club", "weapon_main")
	failed += _expect(bool(r.get("ok", false)), "equip club for bonuses")
	var bons = eq.total_bonuses()
	failed += _expect(int(bons.get("p_atk", 0)) == 6, "two-hand p_atk 6 from main")
	# Safety: rogue off piece while two-hand must not add bonuses.
	eq._equipped["weapon_off"] = "wood_shield"
	bons = eq.total_bonuses()
	failed += _expect(int(bons.get("p_def", 0)) == 0, "off bonuses skipped under two-hand")
	failed += _expect(int(bons.get("p_atk", 0)) == 6, "main two-hand atk unchanged")
	eq._equipped["weapon_off"] = ""
	return failed


func _test_mock_message() -> int:
	var failed := 0
	# Verify MockServer maps two_hand_blocks_off → 「双手武器占用副手。」
	# Prefer message field from equipment; also cover reason match.
	var src := FileAccess.get_file_as_string("res://scripts/net/mock_server.gd")
	failed += _expect(src.find("two_hand_blocks_off") >= 0, "mock_server handles two_hand_blocks_off")
	failed += _expect(src.find("双手武器占用副手。") >= 0, "mock_server has 双手武器占用副手。")
	# Runtime path via equipment result message (same text MockServer prefers).
	var m = _make()
	var bag = m.bag
	var eq = m.eq
	bag.add_item("great_club", 1)
	bag.add_item("wood_shield", 1)
	eq.try_equip_from_bag(bag, "great_club", "weapon_main")
	var r = eq.try_equip_from_bag(bag, "wood_shield", "weapon_off")
	failed += _expect(str(r.get("message", "")) == "双手武器占用副手。", "equipment message for mock")
	# Simulate MockServer message selection.
	var reason := str(r.get("reason", "fail"))
	var msg := str(r.get("message", "")).strip_edges()
	if msg.is_empty():
		msg = "无法装备。"
		match reason:
			"two_hand_blocks_off":
				msg = "双手武器占用副手。"
			_:
				msg = "无法装备（%s）。" % reason
	failed += _expect(msg == "双手武器占用副手。", "mock-style message resolve")
	return failed
