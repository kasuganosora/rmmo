import re
src = open("scripts/editor/adapters/editor_mcp_ops.gd", encoding="utf-8").read()
tl = src[src.index("func tools_list("):src.index("func dispatch(")]
for op in ["apply_stamp_named", "set_meta_batch", "set_weather_preview"]:
    in_tl = ('"%s"' % op) in tl
    m = re.search(r'"%s":\s*\n\s*return %s\(' % (op, op), src)
    print("%-22s in_tools_list=%s  in_dispatch=%s" % (op, in_tl, bool(m)))
