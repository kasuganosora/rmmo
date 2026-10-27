"""Validate an isolated full-native fixture; never inspect authoring GLB bytes.

Product content hashes come from the authored fixture manifest/index; this
lightweight pre/post guard checks exact metadata, map and product stat identity,
not a new scan of every large SCN. It does not certify visual fidelity.
"""
import hashlib
import json
import math
from pathlib import Path


def _sha(data):
    return hashlib.sha256(data).hexdigest()


def _digest(value):
    return isinstance(value, str) and len(value) == 64 and all(c in '0123456789abcdef' for c in value)


def _positive_integral(value, maximum):
    return (type(value) in (int, float) and math.isfinite(value) and value >= 1
            and value <= maximum and value == int(value))


def _inside(path, root):
    path = Path(path).resolve()
    if path == root or not path.is_relative_to(root):
        raise ValueError('fixture path escapes content root')
    return path


def verify_full_fixture(root, map_path, manifest_sha256, expected_models=49):
    root = Path(root).resolve(strict=True)
    selected_map = _inside(map_path, root)
    manifest_path = root / 'full_fixture_manifest.json'
    raw = manifest_path.read_bytes()
    if not _digest(manifest_sha256) or _sha(raw) != manifest_sha256:
        raise ValueError('full fixture manifest SHA mismatch')
    data = json.loads(raw)
    if not isinstance(data, dict) or data.get('scope') != 'full_native_model_materials':
        raise ValueError('not a full-native model-material fixture')
    evidence = data.get('relocation_semantics_scope')
    if (data.get('relocation_semantics_verified') is not True or not isinstance(evidence, dict)
            or type(evidence.get('record_count')) is not int or evidence.get('record_count') != data.get('record_count')
            or type(evidence.get('different_records')) is not int or evidence.get('different_records') != 0
            or evidence.get('material_parameters_rewritten') is not False
            or evidence.get('map_metadata_except_reference_closure_equal') is not True
            or not isinstance(evidence.get('method'), str) or not evidence['method'].strip()):
        raise ValueError('relocation comparison evidence required')
    if Path(data.get('target_root', '')).resolve() != root or _inside(data.get('target_map', ''), root) != selected_map:
        raise ValueError('full fixture root or map mismatch')
    if not selected_map.is_file() or not _digest(data.get('target_map_sha256')) or _sha(selected_map.read_bytes()) != data['target_map_sha256']:
        raise ValueError('full fixture map identity mismatch')
    if not _digest(data.get('source_map_sha256')) or not isinstance(data.get('source_map'), str):
        raise ValueError('source map identity missing')
    if not isinstance(data.get('record_count'), int) or isinstance(data['record_count'], bool) or data['record_count'] <= 0:
        raise ValueError('record count missing')
    models = data.get('models')
    if not isinstance(models, list) or len(models) != expected_models or expected_models <= 0:
        raise ValueError('full fixture model coverage mismatch')
    stable = {str(manifest_path): _sha(raw), str(selected_map): data['target_map_sha256']}
    try:
        document = json.loads(selected_map.read_bytes())
        nodes = document.get('nodes', []) if isinstance(document, dict) else []
        roots = [node['extras'] for node in nodes if isinstance(node, dict) and isinstance(node.get('extras'), dict) and isinstance(node['extras'].get('rmmo_records'), list)]
    except (ValueError, KeyError, TypeError):
        raise ValueError('invalid full fixture map reference header') from None
    dependencies = data.get('resource_dependencies')
    if len(roots) != 1 or len(roots[0]['rmmo_records']) != data['record_count'] or not isinstance(dependencies, dict) or roots[0].get('rmmo_resource_dependencies') != dependencies:
        raise ValueError('relocated map reference closure mismatch')
    for uri, identity in dependencies.items():
        if not isinstance(uri, str) or Path(uri).is_absolute() or not _digest(identity): raise ValueError('invalid map reference identity')
        reference = _inside(selected_map.parent / uri, root)
        if not reference.is_relative_to(selected_map.parent.resolve()) or not reference.is_file() or _sha(reference.read_bytes()) != identity:
            raise ValueError('map reference bytes mismatch')
        stable[str(reference)] = identity
    textures = data.get('textures')
    if not isinstance(textures, list) or not textures: raise ValueError('full fixture texture closure missing')
    for texture in textures:
        if not isinstance(texture, dict) or not _digest(texture.get('sha256')) or type(texture.get('bytes')) is not int or texture['bytes'] <= 0:
            raise ValueError('invalid texture identity')
        target = _inside(texture.get('target', ''), root)
        if not target.is_file() or target.stat().st_size != texture['bytes'] or _sha(target.read_bytes()) != texture['sha256']:
            raise ValueError('texture bytes mismatch')
        stable[str(target)] = texture['sha256']
    products = {}; seen = set(); folder = (root / 'cache/world3d/compiled_assets_v1').resolve()
    for model in models:
        if not isinstance(model, dict): raise ValueError('model row is not an object')
        source = _inside(model.get('logical_source', ''), root)
        payload = _inside(model.get('product_path', ''), root)
        index = _inside(model.get('index_path', ''), root)
        descriptor = _inside(model.get('descriptor_path', ''), root)
        source_sha = model.get('source_sha256'); payload_sha = model.get('payload_sha256')
        if source in seen or source.exists() or source.suffix.lower() != '.glb' or not _digest(source_sha) or not _digest(payload_sha):
            raise ValueError('duplicate, present or invalid logical model source')
        seen.add(source)
        normalized = source.as_posix()
        key = _sha(normalized.encode())
        if payload != folder / (payload_sha + '.scn') or index != folder / (key + '.json') or descriptor != folder / 'footprints_v1' / (key + '.json'):
            raise ValueError('native product path/identity mismatch')
        index_bytes = index.read_bytes(); desc_bytes = descriptor.read_bytes()
        if (not _digest(model.get('index_sha256')) or not _digest(model.get('descriptor_sha256'))
                or _sha(index_bytes) != model['index_sha256'] or _sha(desc_bytes) != model['descriptor_sha256']):
            raise ValueError('manifest metadata identity mismatch')
        info = json.loads(index_bytes); envelope = json.loads(desc_bytes)
        body = envelope.get('body') if isinstance(envelope, dict) else None
        if not isinstance(info, dict) or info.get('version') != 1 or info.get('source_sha') != source_sha or info.get('payload_sha') != payload_sha or not isinstance(info.get('bytes'), int) or isinstance(info['bytes'], bool) or info['bytes'] <= 0:
            raise ValueError('full native index identity mismatch')
        if envelope.get('version') != 1 or not isinstance(body, str) or envelope.get('sha256') != _sha(body.encode()):
            raise ValueError('full footprint envelope mismatch')
        desc = json.loads(body)
        if not isinstance(desc, dict) or desc.get('version') != 1 or desc.get('source_path') != normalized or any(desc.get(k) != info.get(k) for k in ('source_sha','payload_sha','generator','bytes')) or not isinstance(desc.get('model_metadata'), dict):
            raise ValueError('full footprint identity or model metadata mismatch')
        metadata = desc['model_metadata']
        if (metadata.get('version') != 1 or not _positive_integral(desc.get('estimated_bytes'), 1024 * 1024 * 1024 * 1024)
                or desc.get('resident_bytes') != desc['estimated_bytes']
                or metadata.get('file_length') != desc.get('source_bytes')):
            raise ValueError('full native bounds or budget missing')
        if 'product_bytes' in model and model['product_bytes'] != info['bytes']:
            raise ValueError('manifest payload size differs from index')
        if not payload.is_file() or payload.stat().st_size != info['bytes']:
            raise ValueError('full native payload missing or wrong size')
        st = payload.stat(); products[str(payload)] = {'bytes': st.st_size, 'mtime_ns': st.st_mtime_ns, 'published_sha256': payload_sha}
        stable[str(index)] = _sha(index_bytes); stable[str(descriptor)] = _sha(desc_bytes)
    return {'scope': data['scope'], 'target_map_sha256': data['target_map_sha256'], 'source_map_sha256': data['source_map_sha256'], 'record_count': data['record_count'], 'model_count': len(models), 'reference_count': len(dependencies), 'texture_count': len(textures), 'stable_files': stable, 'products': products, 'relocation_semantics_scope': data['relocation_semantics_scope'], 'cache_note': 'Manifest, map, reference records, declared texture files, indices and footprints are hashed. Large products use published SHA plus file size/mtime, not a fresh content hash; hashing warms OS caches. Not a physical cold-IO sample.'}
