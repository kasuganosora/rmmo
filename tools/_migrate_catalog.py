import re, sys

def remove_func(lines, name):
    """Remove func `name` (and trailing blank lines) by name. Returns new lines."""
    out = []
    i = 0
    while i < len(lines):
        if re.match(r"^(static )?func %s\(" % re.escape(name), lines[i]):
            # skip until next top-level func/const/var/enum/signal or EOF
            j = i + 1
            while j < len(lines) and not re.match(r"^(static )?func |^const |^var |^enum |^signal |^@|^class_name ", lines[j]):
                j += 1
            # also skip trailing blank lines
            while j < len(lines) and lines[j].strip() == "":
                j += 1
            i = j
            continue
        out.append(lines[i])
        i += 1
    return out

def first_param(sig):
    i = sig.index("(")
    inner = sig[i+1:sig.index(")", i)]
    if not inner.strip():
        return ""
    return inner.split(",")[0].split(":")[0].split("=")[0].strip()

def migrate(path, list_key):
    src = open(path, encoding="utf-8").read()
    lines = src.split("\n")
    report = []

    # 1. extends
    if lines[0].strip() == "extends RefCounted":
        lines[0] = 'extends "res://scripts/util/catalog_base.gd"'
        report.append("extends")

    # 2. hooks after DATA_PATHS (find end of DATA_PATHS const) or after extends
    data_paths = None
    for ln in lines:
        m = re.match(r"^const (DATA_PATHS)\b", ln)
        if m:
            data_paths = m.group(1); break
    hooks = []
    if data_paths:
        hooks = ["", "func _data_paths() -> Array:", "\treturn DATA_PATHS", "", "", "func _list_key() -> String:", "\treturn \"%s\"" % list_key, ""]
    else:
        hooks = ["", "func _list_key() -> String:", "\treturn \"%s\"" % list_key, ""]
    # insert hooks: after the DATA_PATHS const block (bracket-balanced) else after line 0
    ins = 1
    if data_paths:
        di = next(i for i, ln in enumerate(lines) if ln.startswith("const DATA_PATHS"))
        depth = lines[di].count("[") - lines[di].count("]")
        j = di + 1
        while depth > 0 and j < len(lines):
            depth += lines[j].count("[") - lines[j].count("]")
            j += 1
        ins = j
    lines[ins:ins] = hooks
    report.append("hooks")

    # 3. remove inherited funcs
    for fn in ["load_catalog", "all_ids", "list_all", "icon_index_of", "icon_id_of", "icon_ref_of", "_load_json_first"]:
        before = len(lines)
        lines = remove_func(lines, fn)
        if len(lines) != before:
            report.append("-" + fn)

    # 3b. remove `var _by_id` (the base provides it; redeclaring errors)
    cleaned = []
    for ln in lines:
        if re.match(r"^var _by_id\b", ln):
            if cleaned and cleaned[-1].strip().startswith("##"):
                cleaned.pop()
            report.append("-var _by_id")
            continue
        cleaned.append(ln)
    lines = cleaned

    # 4. wrap pure _by_id get/has/register
    for idx, ln in enumerate(lines):
        m = re.match(r"^func ((?:get|has|register)_\w+)\((.*)", ln)
        if not m:
            continue
        fname = m.group(1)
        # body is until next top-level func
        j = idx + 1
        while j < len(lines) and not re.match(r"^(static )?func ", lines[j]):
            j += 1
        body = "\n".join(lines[idx:j])
        if "_by_id" not in body:
            continue  # not a pure catalog getter; leave it
        p = first_param(ln)
        if fname.startswith("get_"):
            lines[idx:j] = [ln, "\treturn get_def(%s)" % p]
        elif fname.startswith("has_"):
            lines[idx:j] = [ln, "\treturn has_id(%s)" % p]
        elif fname.startswith("register_"):
            lines[idx:j] = [ln, "\treturn register_def(%s)" % p]
        report.append("wrap " + fname)

    open(path, "w", encoding="utf-8").write("\n".join(lines))
    print("%s: %s" % (path.split("/")[-1], ", ".join(report)))

if __name__ == "__main__":
    migrate(sys.argv[1], sys.argv[2])
