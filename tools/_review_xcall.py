import re, glob, os

names = ['AuctionPanel','CastBarPanel','ChatPanel','CraftPanel','DeathPanel','DuelPanel',
         'DungeonPanel','EmotePanel','EquipmentPanel','FriendsPanel','GroundDropPanel',
         'GuildPanel','InventoryPanel','LootPanel','MailPanel','MinimapPanel',
         'NpcDialoguePanel','PartyPanel','QuestPanel','ShopPanel','SkillsPanel',
         'StatusPanel','TargetPanel','TitlesPanel','TradePanel','WarehousePanel']
pat = re.compile(r"\b(" + "|".join(names) + r")\.(\w+)\(")

hits = []
for f in sorted(glob.glob("scripts/ui/panels/*.gd")):
    for i, ln in enumerate(open(f, encoding="utf-8").read().split("\n"), 1):
        s = ln.strip()
        if s.startswith("const ") or s.startswith("#"):
            continue
        code = re.sub(r'"[^"\n]*"', '""', ln)  # strip string literals
        if pat.search(code):
            hits.append("%s:%d  %s" % (os.path.basename(f), i, ln.strip()))

print("static-style cross-panel calls:", len(hits))
for h in hits:
    print("  " + h)
