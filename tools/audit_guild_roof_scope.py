"""Independently prove the one roof-normal amendment permits scoped evidence reuse.

All other buffer views and JSON semantics must match the e24 window repair.
This does not approve the changed appearance, current native or HTTP import.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import io
import json
import struct

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
BEFORE_SHA = 'e24b27bea05a283b3518f659f017f18868336117812674d3ee725eb8008fb7a7'
MATERIAL, TEXTURE, IMAGE, VIEW = 135, 178, 54, 3637


def sha(value):
    return hashlib.sha256(value).hexdigest()


def read(path):
    raw = Path(path).read_bytes()
    magic, version, length = struct.unpack_from('<III', raw)
    assert magic == 0x46546C67 and version == 2 and length == len(raw)
    size, kind = struct.unpack_from('<II', raw, 12)
    assert kind == 0x4E4F534A
    doc = json.loads(raw[20:20+size])
    offset = 20+size
    binary_size, kind = struct.unpack_from('<II', raw, offset)
    assert kind == 0x004E4942 and offset+8+binary_size == len(raw)
    return doc, raw[offset+8:], sha(raw)


def payload(doc, binary, view):
    row = doc['bufferViews'][view]
    assert row.get('buffer', 0) == 0
    offset = row.get('byteOffset', 0)
    value = binary[offset:offset+row['byteLength']]
    assert len(value) == row['byteLength']
    return value


def canonical(doc):
    result = copy.deepcopy(doc)
    # Byte placement is not geometry/material semantics. Every view's content
    # and all remaining descriptor fields are compared separately below.
    for view in result['bufferViews']:
        view.pop('byteOffset', None)
    result['bufferViews'][VIEW]['byteLength'] = '<changed roof normal image length>'
    result['buffers'][0]['byteLength'] = '<changed packed buffer length>'
    result['materials'][MATERIAL]['normalTexture']['scale'] = '<declared normal strength amendment>'
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--expected-sha', required=True)
    parser.add_argument('--out', type=Path, required=True)
    options = parser.parse_args()
    assert options.out.resolve().is_relative_to((REPO/'review_artifacts').resolve())
    options.out.mkdir(parents=True, exist_ok=True)
    before, bb, bsha = read(options.before)
    after, ab, asha = read(options.after)
    assert bsha == BEFORE_SHA and asha == options.expected_sha
    assert len(before['buffers']) == len(after['buffers']) == 1
    assert len(before['bufferViews']) == len(after['bufferViews'])
    assert canonical(before) == canonical(after), 'JSON change beyond normal scale/byte layout'
    for doc in [before, after]:
        assert doc['materials'][MATERIAL]['normalTexture']['index'] == TEXTURE
        assert doc['textures'][TEXTURE]['source'] == IMAGE
        assert doc['images'][IMAGE]['bufferView'] == VIEW
    assert abs(before['materials'][MATERIAL]['normalTexture']['scale']-.8) < .00001
    assert after['materials'][MATERIAL]['normalTexture']['scale'] == 1.0
    views=[]
    for index in range(len(before['bufferViews'])):
        a, b = payload(before, bb, index), payload(after, ab, index)
        exact = a == b
        assert exact or index == VIEW, f'unexpected buffer payload change: {index}'
        views.append(dict(index=index, before_sha256=sha(a), after_sha256=sha(b),
                          before_bytes=len(a), after_bytes=len(b), bytes_identical=exact))
    images=[]
    for index, image in enumerate(before['images']):
        a=payload(before,bb,image['bufferView'])
        b=payload(after,ab,after['images'][index]['bufferView'])
        with Image.open(io.BytesIO(a)) as old, Image.open(io.BytesIO(b)) as new:
            assert old.size == new.size
            images.append(dict(index=index,before_sha256=sha(a),after_sha256=sha(b),
                               bytes_identical=a==b,dimensions=list(old.size),
                               before_rgba_sha256=sha(old.convert('RGBA').tobytes()),
                               after_rgba_sha256=sha(new.convert('RGBA').tobytes())))
        if index==IMAGE:
            (options.out/'before_normal.png').write_bytes(a)
            (options.out/'after_normal.png').write_bytes(b)
    assert [row['index'] for row in images if not row['bytes_identical']] == [IMAGE]
    manifest=json.loads((options.after.parent/'repair_manifest.json').read_text('utf8'))
    unchanged=[]
    for row in [dict(asset_id='guild_alarm_tower',**manifest['tower']),*manifest['library']]:
        actual=sha(Path(row['path']).read_bytes())
        accepted=json.loads((REPO/'review_artifacts/guild_reference_recheck_20261013/acceptance'/(row['asset_id']+'.json')).read_text('utf8'))
        assert actual==row['sha256']==accepted['source_sha256']
        unchanged.append(dict(id=row['asset_id'],sha256=actual))
    result=dict(schema=1,scope='one embedded terracotta normal image and scale only',passed=True,
                before=dict(path=str(options.before.resolve()),sha256=bsha),
                after=dict(path=str(options.after.resolve()),sha256=asha),
                material_index=MATERIAL,texture_index=TEXTURE,image_index=IMAGE,buffer_view_index=VIEW,
                before_normal_scale=before['materials'][MATERIAL]['normalTexture']['scale'],after_normal_scale=1.0,
                json_except_declared_fields_identical=True,all_non_image_buffer_views_identical=True,
                all_geometry_attributes_and_extras_identical=True,all_other_material_channels_identical=True,
                buffer_views=views,images=images,unchanged_deliveries=unchanged,
                inherited_scopes=['runtime_component_semantics','runtime_lighting','nonroof_materials','optimization_contract'],
                fresh_evidence_required=['source_resource_audit','native_cost','actual_import_HTTP','roof_normal_native_pixels','roof_near_mid_far_raking_visual'],
                limitation='Scope proof is not visual approval. Prior GPU evidence keeps its original e24 SHA; changed roof appearance and current import require new evidence.')
    # Freeze the explicit earlier verdicts. The live decisions file will later
    # describe the successor; no previous evidence is silently re-labelled.
    root=REPO/'review_artifacts/guild_reference_recheck_20261013'
    prior_visual=json.loads((root/'visual_decisions.json').read_text('utf8'))['axel_guild_repaired']
    prior_lighting=json.loads((root/'lighting_decision.json').read_text('utf8'))
    result['prior_decisions']={}
    for name,value in [('manual',prior_visual),('lighting',prior_lighting)]:
        assert value['source_sha256']==bsha, f'{name} prior decision must remain bound to e24'
        saved=options.out/f'before_{name}_decision.json'
        saved.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf8')
        result['prior_decisions'][name]=dict(path=str(saved.resolve()),sha256=sha(saved.read_bytes()))
    result['audit_tool_sha256']=sha(Path(__file__).read_bytes())
    path=options.out/'independent_scope_audit.json'
    path.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps(dict(passed=True,before=bsha,after=asha,unchanged_buffer_views=len(views)-1,unchanged_images=len(images)-1,unchanged_deliveries=len(unchanged),report=str(path))))


if __name__=='__main__':
    main()
