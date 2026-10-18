extends RefCounted
## Catalog and presentation-model initialization, shared with the remote HUD.

var ctrl
func _init(owner):
	ctrl = owner

## @server-constant
const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")
## @server-constant
const CombatEngine = preload("res://scripts/net/combat/combat_engine.gd")
## @server-constant
const SkillCatalog = preload("res://scripts/net/combat/skill_catalog.gd")
## @server-constant
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
## @server-constant
const Inventory = preload("res://scripts/net/combat/inventory.gd")
## @server-constant
const Warehouse = preload("res://scripts/net/combat/warehouse.gd")
## @server-constant
const FriendList = preload("res://scripts/net/combat/friend_list.gd")
## @server-constant
const Guild = preload("res://scripts/net/combat/guild.gd")
## @server-constant
const Mailbox = preload("res://scripts/net/combat/mailbox.gd")
## @server-constant
const Auction = preload("res://scripts/net/combat/auction.gd")
## @server-constant
const Equipment = preload("res://scripts/net/combat/equipment.gd")
## @server-constant
const LootCatalog = preload("res://scripts/net/combat/loot_catalog.gd")
## @server-constant
const QuestJournal = preload("res://scripts/net/combat/quest_journal.gd")
## @server-constant
const ShopCatalog = preload("res://scripts/net/combat/shop_catalog.gd")
## @server-constant
const EventRuntime = preload("res://scripts/net/combat/event_runtime.gd")
## @server-constant
const RecipeCatalog = preload("res://scripts/net/combat/recipe_catalog.gd")
## @server-constant
const GatherCatalog = preload("res://scripts/net/combat/gather_catalog.gd")
## @server-constant
const FishCatalog = preload("res://scripts/net/combat/fish_catalog.gd")
## @server-constant
const TitleCatalog = preload("res://scripts/net/combat/title_catalog.gd")
## @server-constant
const AchievementCatalog = preload("res://scripts/net/combat/achievement_catalog.gd")
## @server-constant
const SafeZoneCatalog = preload("res://scripts/net/combat/safe_zone_catalog.gd")
## @server-constant
const TileId = preload("res://scripts/map/tile_id.gd")
## @server-constant
const MobAI = preload("res://scripts/net/combat/mob_ai.gd")
## @server-constant
const WeatherGatherUtil = preload("res://scripts/game/weather_gather_util.gd")

## @server-api
func _init_combat_layers() -> void:
	ctrl.combat_stats = CombatStats.new()
	ctrl.skill_catalog = SkillCatalog.new()
	ctrl.skill_catalog.load_catalog()
	ctrl.item_catalog = ItemCatalog.new()
	ctrl.item_catalog.load_catalog()
	ctrl.recipe_catalog = RecipeCatalog.new()
	ctrl.recipe_catalog.load_catalog()
	ctrl.gather_catalog = GatherCatalog.new()
	ctrl.gather_catalog.load_catalog()
	ctrl._gather_state.clear()
	ctrl._gather_nodes.clear()
	ctrl.fish_catalog = FishCatalog.new()
	ctrl.fish_catalog.load_catalog()
	ctrl._fish_state.clear()
	ctrl._fish_spots.clear()
	ctrl._fish_busy_until = 0.0
	ctrl.title_catalog = TitleCatalog.new()
	ctrl.title_catalog.load_catalog()
	ctrl.achievement_catalog = AchievementCatalog.new()
	ctrl.achievement_catalog.load_catalog()
	ctrl.safe_zone_catalog = SafeZoneCatalog.new()
	ctrl.safe_zone_catalog.load_catalog()
	ctrl._safe_zone_known = false
	ctrl._safe_zone_inside = false
	ctrl.loot_catalog = LootCatalog.new()
	ctrl.loot_catalog.load_catalog()
	ctrl.inventory = Inventory.new()
	ctrl.inventory.set_catalog(ctrl.item_catalog)
	ctrl.inventory.grant_starter()
	ctrl.warehouse = Warehouse.new()
	ctrl.warehouse.set_catalog(ctrl.item_catalog)
	ctrl.warehouse.clear()
	ctrl.friend_list = FriendList.new()
	ctrl.friend_list.clear()
	ctrl.guild = Guild.new()
	ctrl.guild.clear()
	ctrl._guild_invites.clear()
	ctrl.mailbox = Mailbox.new()
	ctrl.mailbox.clear()
	ctrl.auction = Auction.new()
	ctrl.auction.clear()
	ctrl._auction_seed_npc_stubs()
	ctrl._mail_welcome_sent = false
	ctrl._attendance_last_ymd = ""
	ctrl.equipment = Equipment.new()
	ctrl.equipment.set_catalog(ctrl.item_catalog)
	ctrl.equipment.clear()
	ctrl.quest_journal = QuestJournal.new()
	ctrl.quest_journal.load_catalog()
	ctrl.quest_journal.grant_starter()
	ctrl.shop_catalog = ShopCatalog.new()
	ctrl.shop_catalog.set_catalog(ctrl.item_catalog)
	ctrl.shop_catalog.load_catalog()
	ctrl.event_runtime = EventRuntime.new()
	ctrl.combat_engine = CombatEngine.new()
	ctrl.combat_engine.setup(ctrl.combat_stats, ctrl.skill_catalog, ctrl.item_catalog, ctrl.inventory, ctrl.equipment)
	ctrl.combat_engine.combat_randf = ctrl._combat_randf_override
	ctrl.combat_stats.reset_player(1)
	ctrl.combat_stats.reset_titles()
	ctrl.combat_stats.reset_achievements()
	ctrl._reset_skill_book()



