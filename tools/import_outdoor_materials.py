"""Install the eight Shaded Spectrum ZIP materials as <=2K shared PBR assets.

Read archive members in memory; never extract or execute untrusted package files.
Keep one complete original archive, including unused height/specular channels.
"""
import argparse
import io
import json
from pathlib import Path
import shutil
from zipfile import ZipFile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from import_fab_materials import digest, write_json


def install(manifest, archive, pack):
    spec = json.loads(manifest.read_text(encoding="utf-8"))
    metadata = json.loads((pack / "metadata.json").read_text(encoding="utf-8-sig"))
    project = Path(__file__).resolve().parents[1]
    if metadata.get("id") != "default" or pack.is_relative_to(project):
        raise ValueError("An existing external default pack is required")
    if archive.name != spec["archive"]:
        raise ValueError("Unexpected source archive")
    origin = pack / "sources/fab/collections/shaded_spectrum_outdoor"
    origin.mkdir(parents=True, exist_ok=True)
    source_sha = digest(archive)
    preserved = origin / archive.name
    if preserved.exists() and digest(preserved) != source_sha:
        raise ValueError("Original archive differs; refusing replacement")
    rows = []
    audit = []
    with ZipFile(archive) as z:
        if z.testzip() is not None:
            raise ValueError("Archive CRC failure")
        for item in spec["materials"]:
            folder = Path(item["folder"])
            if folder.is_absolute() or ".." in folder.parts or len(folder.parts) != 2:
                raise ValueError("Unsafe material folder")
            target = (pack / "assets/materials" / folder).resolve()
            if not target.is_relative_to(pack / "assets/materials"):
                raise ValueError("Material path escapes library")
            descriptor = target / "material.json"
            if descriptor.exists():
                previous = json.loads(descriptor.read_text(encoding="utf-8"))
                if previous.get("source", {}).get("archive_sha256") != source_sha:
                    raise ValueError("Refusing to overwrite another material")
            target.mkdir(parents=True, exist_ok=True)
            prefix = "Assets/{0}/{0}".format(item["source"])

            def read(suffix):
                member = prefix + suffix + ".png"
                if z.getinfo(member).file_size > 134217728:
                    raise ValueError("Oversized source member")
                im = Image.open(io.BytesIO(z.read(member)))
                if im.size != (4096, 4096):
                    raise ValueError("Unexpected source dimensions")
                im.load()
                return im

            height = np.asarray(read("DisplacementMap").convert("L").resize((1024,1024)), dtype=np.float32)
            original_normal = read("NormalMap").convert("RGB")
            n = np.asarray(original_normal.resize((1024,1024)), dtype=np.float32) / 127.5 - 1
            dy, dx = np.gradient(height)
            cx = float(np.corrcoef(dx.ravel(),n[:,:,0].ravel())[0,1])
            cy = float(np.corrcoef(dy.ravel(),n[:,:,1].ravel())[0,1])
            # These source normals point along +dH/dU, +dH/d(image Y).
            # OpenGL tangent normals require -dH/dU, +dH/d(image Y).
            # Preserve source detail and correct R, not an arbitrary green flip.
            if cx < .75 or cy < .75:
                raise ValueError("Normal/height orientation changed; manual review required")
            n = np.asarray(original_normal.resize((2048,2048),Image.Resampling.LANCZOS),dtype=np.float32)/127.5-1
            n[:,:,0] *= -1
            n /= np.maximum(np.linalg.norm(n,axis=2,keepdims=True),1e-6)
            Image.fromarray(np.clip((n+1)*127.5,0,255).astype(np.uint8)).save(target / "normal.png")
            read("Albedo").convert("RGB").resize((2048,2048),Image.Resampling.LANCZOS).save(target / "texture.jpg",quality=95,subsampling=0)
            read("AmbientOcclusionMap").convert("L").resize((2048,2048),Image.Resampling.LANCZOS).save(target / "ao.png")
            files = {key: {"path": filename,"sha256":digest(target/filename),"size":[2048,2048]}
                     for key, filename in [("texture_path","texture.jpg"),("normal_path","normal.png"),("ao_path","ao.png")]}
            source = {"type":"fab_texture_archive","listing_url":"https://www.fab.com/listings/"+spec["listing_id"],
                      "title":spec["title"],"seller":spec["seller"],"owned_library_verified":"2026-10-02",
                      "license_url":"https://www.fab.com/eula","ai_generated_on_listing":True,
                      "archive":preserved.relative_to(pack).as_posix(),"archive_sha256":source_sha,
                      "source_material":item["source"],"normal_adaptation":"Flip R, then normalize after 2K downsample; OpenGL +Y output; original normal preserved in ZIP.",
                      "normal_height_correlation_before":[cx,cy],"roughness_source":"authored scalar; source SpecularMap is NOT roughness",
                      "runtime_maps":files}
            material={"name":item["name"],"color":[1,1,1,1],"roughness":item["roughness"],"metallic":0,
                      "normal_format":"opengl","normal_strength":1.0,"tile_size":item["tile_size"],
                      "texture_path":"texture.jpg","normal_path":"normal.png","ao_path":"ao.png"}
            write_json(descriptor,{"category":item["category"],"usage":item["usage"]+" 米制尺寸为编辑建议；原包无粗糙度图，使用参数值。高度与高光原件保留，未启用位移。", "source":source,"material":material})
            rows.append({"material_id":"pack:default:"+folder.as_posix()+"/material","folder":target.relative_to(pack).as_posix(),"category":item["category"],"name":item["name"],"source":source,"usage":item["usage"]})
            audit.append({"name":item["name"],"normal_correlation_before":[cx,cy],"normal_flip":"R","roughness":item["roughness"],"maps":files})
            print("Installed",item["source"],flush=True)
        (origin / "README.pdf").write_bytes(z.read("README.pdf"))
    if not preserved.exists(): shutil.copy2(archive,preserved)
    write_json(origin / "import_audit.json",{"materials":audit,"original_archive_sha256":source_sha,"runtime_limit":2048})
    write_json(origin / "catalog.json",{"materials":rows})
    catalog_path = pack / "sources/fab/catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8")) if catalog_path.exists() else {}
    merged = {r["material_id"]:r for r in catalog.get("materials",[])}
    merged.update({r["material_id"]:r for r in rows})
    catalog["materials"] = list(merged.values())
    write_json(catalog_path,catalog)
    sheet=Image.new("RGB",(1600,880),"#20252b"); draw=ImageDraw.Draw(sheet)
    font=ImageFont.truetype("C:/Windows/Fonts/msyh.ttc",20)
    for i,row in enumerate(rows):
        x,y=(i%4)*400,(i//4)*440
        im=Image.open(pack/row["folder"]/"texture.jpg")
        sheet.paste(im.resize((390,390),Image.Resampling.LANCZOS),(x+5,y+45))
        draw.text((x+7,y+8),row["name"],font=font,fill="white")
    sheet.save(origin / "contact_sheet.jpg",quality=94)
    print(json.dumps({"installed":len(rows),"source_archive":str(preserved),"runtime_bytes":sum((pack/r["folder"]/f).stat().st_size for r in rows for f in ["texture.jpg","normal.png","ao.png"])},ensure_ascii=False))


if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--manifest",type=Path,default=Path(__file__).with_name("fab_outdoor_materials.json"))
    parser.add_argument("--archive",type=Path,required=True)
    parser.add_argument("--pack",type=Path,required=True)
    args=parser.parse_args()
    install(args.manifest,args.archive.resolve(),args.pack.resolve())
