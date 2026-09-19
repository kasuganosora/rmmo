import re, io
from collections import defaultdict

SRC = "d:/code/rmmo/scripts/ui/game_hud.gd"
lines = io.open(SRC, "r", encoding="utf-8").read().split("\n")

funcs = []
for i, ln in enumerate(lines):
    m = re.match(r"^func (\w+)\(", ln)
    if not m:
        continue
    j = i + 1
    while j < len(lines):
        s = lines[j].strip()
        if s == "":
            j += 1
            continue
        if len(lines[j]) - len(lines[j].lstrip(" \t")) == 0:
            break
        j += 1
    funcs.append((m.group(1), i, j - i - 1))

# keyword -> panel (checked in order; first match wins)
PANELS = [
    ("shop", ["shop"]),
    ("loot", ["loot"]),
    ("inventory", ["inventory", "_inv_", "inv_qty", "bag_", "_qty_mode", "inv_search", "_server_gold", "gold_float", "wallet"]),
    ("equipment", ["equip", "paperdoll"]),
    ("skills", ["skill", "hotbar", "passive"]),
    ("quest", ["quest"]),
    ("party", ["party"]),
    ("trade", ["trade"]),
    ("warehouse", ["warehouse"]),
    ("friends", ["friend"]),
    ("mail", ["mail"]),
    ("craft", ["craft", "gather"]),
    ("emote", ["emote"]),
    ("titles", ["title", "achievement", "daily"]),
    ("guild", ["guild"]),
    ("auction", ["auction"]),
    ("duel", ["duel"]),
    ("dungeon", ["dungeon", "safe_zone"]),
    ("mappins", ["map_pin", "pin_", "radar", "minimap", "map_overview", "map_info"]),
    ("chat", ["chat", "combat_log", "dps_meter", "system_message", "append_system"]),
    ("toasts", ["toast", "float", "afk", "level_up", "exp_gain"]),
    ("npcchat", ["npc_chat", "dialogue"]),
    ("castbar", ["cast_"]),
    ("target", ["target", "threat"]),
    ("statuspanel", ["status", "_hp", "_mp", "_cp", "hp_bar", "mp_bar", "cp_bar", "xp_bar", "rested"]),
    ("playermenu", ["player_ctx", "inspect"]),
    ("death", ["death", "respawn"]),
    ("grounddrop", ["ground", "drop_qty"]),
    ("settings", ["system_tab", "menu_popup", "menu_dim", "game_settings", "settings"]),
]

ROOT_KEEP = ["_ready", "_process", "_unhandled_input", "_input", "bind_", "blocks_", "_notification"]

groups = defaultdict(list)
unclassified = []

for name, idx, size in funcs:
    lname = name.lower()
    if any(name.startswith(k) or k in name for k in ROOT_KEEP):
        groups["<root>"].append((name, idx, size))
        continue
    placed = False
    for panel, kws in PANELS:
        for kw in kws:
            if kw in lname:
                groups[panel].append((name, idx, size))
                placed = True
                break
        if placed:
            break
    if not placed:
        unclassified.append((name, idx, size))

print("%-16s %5s %8s" % ("panel", "funcs", "lines"))
tot = 0
for g in sorted(groups, key=lambda k: -sum(s for _, _, s in groups[k])):
    n = len(groups[g])
    s = sum(x[2] for x in groups[g])
    tot += s
    print("%-16s %5d %8d" % (g, n, s))
print("TOTAL classified:", tot)
print()
import sys
if len(sys.argv) > 1:
    want = sys.argv[1]
    names = [n for n, _, _ in groups.get(want, [])]
    print("CSV:" + ",".join(names))
    sys.exit(0)
else:
    print("UNCLASSIFIED:", len(unclassified), "lines:", sum(x[2] for x in unclassified))
for n, i, s in unclassified:
    print("   %-40s L%-5d %d" % (n, i + 1, s))
