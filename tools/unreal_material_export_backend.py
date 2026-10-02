"""Run ONLY inside the isolated Unreal Python commandlet created by the driver."""
import hashlib
import json
from pathlib import Path
import unreal


def plain(value):
    if isinstance(value, unreal.LinearColor):
        return [value.r, value.g, value.b, value.a]
    if isinstance(value, unreal.Object):
        return value.get_path_name()
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return str(value)


def prop(obj, name):
    return plain(obj.get_editor_property(name))


def main():
    config = json.loads(Path(__file__).with_name("export_request.json").read_text(encoding="utf-8"))
    output = Path(config["output"])
    registry = unreal.AssetRegistryHelpers.get_asset_registry()
    registry.scan_paths_synchronous(["/Game"], force_rescan=True)
    report = {"version": 1, "engine": unreal.SystemLibrary.get_engine_version(),
              "source_content": config["source_content"], "source_url": config["source_url"],
              "source_files": config["source_files"], "textures": [], "materials": [], "errors": [],
              "limitations": ["Parameter export is not an arbitrary shader-graph bake.",
                              "Only global parameters are resolved; layer overrides are retained as text for review.",
                              "Channel packing and UV meaning require review before installing a runtime material."]}
    textures = {}
    materials = []
    assets = (config["assets"] or [str(a.package_name) for a in registry.get_assets_by_path(config["asset_root"], recursive=True)
              if str(a.asset_class_path.asset_name) in ("Texture2D", "Material", "MaterialInstanceConstant")])
    for path in sorted(set(assets)):
        try:
            asset = unreal.load_asset(path)
            if asset is None:
                raise ValueError("Unreal could not load asset")
            if isinstance(asset, unreal.Texture2D):
                textures[asset.get_path_name()] = asset
            elif isinstance(asset, (unreal.Material, unreal.MaterialInstanceConstant)):
                materials.append(asset)
            else:
                raise ValueError("Selected asset is not a 2D texture or material")
        except Exception as error:
            report["errors"].append({"asset": path, "error": str(error)})
    lib = unreal.MaterialEditingLibrary
    for material in materials:
        path = material.get_path_name()
        row = {"asset": path, "class": material.get_class().get_name(), "parameters": {}, "warnings": []}
        instance = isinstance(material, unreal.MaterialInstanceConstant)
        try:
            # Compiled GetUsedTextures can be empty under NullRHI. Registry
            # dependencies remain available, including textures in functions.
            pending = [path.split(".")[0]]
            visited = set()
            dependencies = []
            options = unreal.AssetRegistryDependencyOptions(
                include_soft_package_references=True, include_hard_package_references=True,
                include_searchable_names=False, include_soft_management_references=False,
                include_hard_management_references=False)
            while pending:
                package = pending.pop()
                if package in visited:
                    continue
                visited.add(package)
                for dependency in registry.get_dependencies(package, options):
                    dep = str(dependency)
                    if dep.startswith("/Script/") or dep in visited:
                        continue
                    info = registry.get_assets_by_package_name(dep)
                    for item in info:
                        cls = str(item.asset_class_path.asset_name)
                        if cls == "Texture2D":
                            tex = item.get_asset()
                            if tex:
                                textures[tex.get_path_name()] = tex
                                dependencies.append(tex.get_path_name())
                        elif cls in ("Material", "MaterialInstanceConstant", "MaterialFunction"):
                            pending.append(dep)
            row["dependency_textures"] = sorted(set(dependencies))
            base = material
            if instance:
                row["parent"] = prop(material, "parent")
                # Retain association/index and overrides for manual review of layers.
                row["raw_overrides"] = {k: str(material.get_editor_property(k + "_parameter_values"))
                                        for k in ("texture", "scalar", "vector")}
                seen = set()
                while isinstance(base, unreal.MaterialInstanceConstant):
                    if base.get_path_name() in seen:
                        raise ValueError("Cyclic material parent")
                    seen.add(base.get_path_name())
                    base = base.get_editor_property("parent")
            if isinstance(base, unreal.Material):
                row["base_material"] = base.get_path_name()
                row["base_properties"] = {k: prop(base, k) for k in ("blend_mode", "two_sided", "shading_model")}
                used = list(lib.get_used_textures(base))
                row["base_used_textures"] = [t.get_path_name() for t in used if t]
                for tex in used:
                    if isinstance(tex, unreal.Texture2D):
                        textures[tex.get_path_name()] = tex
            for kind in ("texture", "scalar", "vector", "static_switch"):
                values = {}
                for name in getattr(lib, "get_" + kind + "_parameter_names")(material):
                    getter = "get_material_instance_" if instance else "get_material_default_"
                    value = getattr(lib, getter + kind + "_parameter_value")(material, name)
                    values[str(name)] = plain(value)
                    if isinstance(value, unreal.Texture2D):
                        textures[value.get_path_name()] = value
                row["parameters"][kind] = values
        except Exception as error:
            report["errors"].append({"asset": path, "error": str(error)})
        report["materials"].append(row)
    for path, tex in sorted(textures.items()):
        try:
            # Preserve mount/folder identity. Same-named textures cannot overwrite.
            relative = Path("textures") / (path.split(".")[0].lstrip("/") + ".png")
            destination = (output / relative).resolve()
            if not destination.is_relative_to(output.resolve()) or destination.exists():
                raise ValueError("Unsafe or duplicate texture output")
            destination.parent.mkdir(parents=True, exist_ok=True)
            task = unreal.AssetExportTask()
            task.object = tex
            task.filename = str(destination)
            task.automated = True
            task.prompt = False
            task.replace_identical = False
            task.exporter = unreal.TextureExporterPNG()
            if not unreal.Exporter.run_asset_export_task(task) or not destination.is_file():
                raise RuntimeError(str(list(task.errors)))
            with destination.open("rb") as stream:
                sha = hashlib.file_digest(stream, "sha256").hexdigest()
            report["textures"].append({"asset": path, "file": relative.as_posix(), "sha256": sha,
                "srgb": prop(tex, "srgb"), "compression": prop(tex, "compression_settings"),
                "flip_green_channel": prop(tex, "flip_green_channel"),
                "address_x": prop(tex, "address_x"), "address_y": prop(tex, "address_y"),
                "note": "PNG exports source pixels; UE texture adjustment and shader parameters are not baked."})
        except Exception as error:
            report["errors"].append({"asset": path, "error": str(error)})
    (output / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    unreal.log("RMMO_EXPORT_COMPLETE textures=%d materials=%d errors=%d" %
               (len(report["textures"]), len(report["materials"]), len(report["errors"])))


main()
