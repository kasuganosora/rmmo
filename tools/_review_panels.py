import re, glob, os

hud = open("scripts/ui/game_hud.gd", encoding="utf-8").read()
hud_members = set(re.findall(r"(?m)^(?:@\w+(?:\([^\n]*\))?\s+)*var\s+(\w+)", hud))
hud_members |= set(re.findall(r"(?m)^signal\s+(\w+)", hud))
hud_members |= set(re.findall(r"(?m)^(?:static\s+)?func\s+(\w+)", hud))
hud_members |= set(re.findall(r"(?m)^const\s+(\w+)", hud))
hud_members |= set(re.findall(r"(?m)^enum\s+(\w+)", hud))

# Godot Object/Node/Control builtins + globals (generous; avoids false positives)
BUILTINS = set("""add_child get_node_or_null create_tween is_inside_tree queue_free remove_child
get_parent get_tree has_method emit_signal connect disconnect get_meta set_meta has_meta remove_meta
modulate global_position position to_local to_global get_child get_children get_child_count move_child
get_viewport get_global_mouse_position get_local_mouse_position get_viewport_rect get_canvas_transform
get_screen_transform get_window set_process set_physics_process get_index raise show hide is_visible_in_tree
call_deferred set_deferred is_node_ready request_ready get_path get_name set_name duplicate free
get_instance_id notify_property_list_changed has_node find_child find_children get_last_child add_sibling
reparent force_update_transform update_configuration_warnings get_signal_list get_method_list get_property_list
get_script set_script tr to_string get_class is_class is_queued_for_deletion cancel_free
visible name size anchors_preset mouse_filter clip_contents custom_minimum_size theme text value
add_theme_stylebox_override add_theme_color_override add_theme_font_size_override add_theme_constant_override
add_theme_icon_override grab_focus release_focus set_anchors_preset gui_input pressed toggled text_changed
item_selected value_changed scrolling timeout append_text clear get_line_count scroll_to_line get_v_scroll_bar
set_block_signals propagate_call get_global_rect get_rect get_combined_minimum_size size_flags_horizontal
size_flags_vertical set_h_size_flags set_v_size_flags set_text set_pressed set_disabled set_tooltip_text
add_item select get_selected_id get_item_count set_item_text set_item_metadata get_selected_metadata
is_instance_valid str int float bool len range print printt prints push_error push_warning
set_process_input set_process_unhandled_input set_process_unhandled_key_input warp_mouse
get_local_mouse_position get_global_mouse_position queue_redraw get_theme_color get_theme_stylebox""".split())

issues = []
for f in sorted(glob.glob("scripts/ui/panels/*.gd")):
    src = open(f, encoding="utf-8").read()
    base = os.path.basename(f)
    for m in sorted(set(re.findall(r"\bctrl\.(\w+)", src))):
        if m not in hud_members and m not in BUILTINS:
            issues.append("%s: ctrl.%s  (not a HUD member/builtin)" % (base, m))
    for ln in src.split("\n"):
        code = ln.split("#")[0]
        code = re.sub(r'"[^"\n]*"', '""', code)
        code = re.sub(r"'[^'\n]*'", "''", code)
        if re.search(r"\bself\b", code):
            issues.append("%s: bare self -> %s" % (base, ln.strip()))

# delegation vs panel method consistency
panel_methods = {}
for f in glob.glob("scripts/ui/panels/*.gd"):
    src = open(f, encoding="utf-8").read()
    panel_methods[os.path.basename(f)[:-3]] = set(re.findall(r"(?m)^func (\w+)\(", src))
for m in re.finditer(r"\b_(\w+)_logic\.(\w+)\(", hud):
    snake, meth = m.group(1), m.group(2)
    if snake in panel_methods and meth not in panel_methods[snake]:
        issues.append("hud: _%s_logic.%s  (missing in panel)" % (snake, meth))

print("HUD members:", len(hud_members))
print("ISSUES:", len(issues))
for i in issues:
    print("  " + i)
