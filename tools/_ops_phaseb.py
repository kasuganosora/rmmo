import re, json

SRC = "scripts/editor/adapters/editor_mcp_ops.gd"
OPDIR = "scripts/editor/adapters/ops/"

# op -> module file mapping (9 domains)
MODS = {
  "entity_ops": ["update_entity","place_chest"],
  "asset_ops": ["import_asset"],
  "history_ops": ["undo","redo","list_undo"],
  "map_crud_ops": ["create_map","delete_map","rename_map","duplicate_map","resize_map","reparent_map"],
  "stamp_ops": ["set_stamp","paint_stamp","stamp_from_tileset","save_stamp","apply_stamp_named","list_stamps"],
  "tiles_ops": ["copy_tiles","cut_tiles","paste_tiles","replace_tiles","rotate_tiles","flip_tiles"],
  "paint_ops": ["paint_rect","paint_fill","paint_cells","paint_polyline","paint_ellipse","paint_ring","paint_arc","scatter","set_passage","refresh_autotiles"],
  "map_settings_ops": ["set_map_settings","set_map_tileset","set_layer","set_layer_visible","set_layer_alpha","set_reference","set_weather_preview","add_region","list_regions","add_bookmark","list_bookmarks","goto_bookmark"],
  "inspect_ops": ["get_tile","get_tiles_rect","list_entities","list_layers","list_tilesets","get_map_settings","find_tiles","pick_tileset","get_weather","preview_tileset","preview_charset"],
}
NOARG = ["get_map_settings","get_weather","list_bookmarks","list_layers","list_regions","list_stamps","list_tilesets","list_undo","redo","refresh_autotiles","undo"]

src = open(SRC, encoding="utf-8").read()
tl = src[src.index("func tools_list("):src.index("func dispatch(")]
tll = tl.split("\n")

# extract per-op metadata block (ORIGINAL indentation preserved)
blocks = {}
i = 0
while i < len(tll):
    m = re.match(r'(\s*)mcp\._tool\("(\w+)"', tll[i])
    if m:
        name = m.group(2)
        buf = [tll[i]]
        depth = tll[i].count("(") - tll[i].count(")")
        j = i + 1
        while depth > 0 and j < len(tll):
            buf.append(tll[j])
            depth += tll[j].count("(") - tll[j].count(")")
            j += 1
        blocks[name] = buf  # list of original-indent lines
        i = j
    else:
        i += 1

def gen_tools(ops):
    metas = [blocks[o] for o in ops if o in blocks]
    if not metas:
        return None
    out = ["", "func tools() -> Array:", "\treturn ["]
    for blk in metas:
        # prefix first line's mcp._tool -> ctrl.mcp._tool (keep original indent)
        first = blk[0].replace("mcp._tool(", "ctrl.mcp._tool(", 1)
        out.append(first)
        out.extend(blk[1:])
    out.append("\t]")
    return out

for mod, ops in MODS.items():
    path = OPDIR + mod + ".gd"
    lines = open(path, encoding="utf-8").read().split("\n")
    # B2: standardize no-arg signatures  func op() -> X:  ->  func op(_args := {}) -> X:
    for idx, ln in enumerate(lines):
        for op in ops:
            if op in NOARG and re.match(r"^func %s\(\)" % re.escape(op), ln):
                lines[idx] = ln.replace("func %s()" % op, "func %s(_args := {})" % op, 1)
    # B1: append op_names() + tools()
    add = ["", "func op_names() -> Array:", "\treturn [%s]" % ", ".join('"%s"' % o for o in ops)]
    t = gen_tools(ops)
    if t:
        add += t
    # strip trailing blank lines then append
    while lines and lines[-1].strip() == "":
        lines.pop()
    lines += add + [""]
    open(path, "w", encoding="utf-8").write("\n".join(lines))
    print("updated %s (ops=%d, meta=%d)" % (mod, len(ops), sum(1 for o in ops if o in blocks)))

print("Phase B1+B2 done")
