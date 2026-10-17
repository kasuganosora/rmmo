"""Bind selected S12 structural-stage reviews to actual immutable source bytes.

This records manual visual decisions; it never infers final art approval from
the runtime check's passed flag. Run after inspecting the listed WebP views.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path('D:/code/rmmo_runtime')
SRC = ROOT / 'art_sources/s12_residential_details_20261017'
OUT = ROOT / 'review_artifacts/s12_residential_details_20261017'
MODELS = [
    ('s12_freestanding_courtyard_gate', 'v4', 'S12 独立细柱院门', '建筑装饰', '石面纹理尺度与矿物纹理对比待细化'),
    ('s12_riverside_residence', 'v4', 'S12 河岸长侧门住宅', '住宅', '窗框、石阶与屋顶近景材质待细化'),
    ('s12_red_gold_pennant_a', 'v4', 'S12 红金短三角墙旗 A', '建筑装饰', '近景织纹强度待细化'),
    ('s12_red_gold_pennant_b', 'v4', 'S12 红金短三角墙旗 B', '建筑装饰', '近景织纹强度待细化'),
    ('s12_doorstep_jar', 'v5', 'S12 门前赭色陶罐', '道具', None),
]


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def identity(path):
    path = Path(path)
    return {'path': path.as_posix(), 'sha256': sha(path), 'bytes': path.stat().st_size}


def write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def images(folder, skip=()):
    result = []
    for path in sorted(folder.glob('*.webp')):
        if path.stem in skip:
            continue
        receipt = read(str(path) + '.review-image.json')
        assert receipt['sha256'] == sha(path)
        assert receipt['quality'] == 90 and receipt['method'] == 6 and receipt['lossless'] is False
        result.append({**identity(path), 'compression_receipt': identity(str(path) + '.review-image.json'),
                       'manually_viewed': True})
    assert result
    return result


def main():
    rows = []
    for model, version, label, category, pending in MODELS:
        source = SRC / version / (model + '.glb')
        author = read(SRC / version / (model + '_authoring.json'))
        cpu_path = OUT / version / (model + '_cpu_audit.json')
        gpu_path = OUT / version / model / 'report.json'
        cpu, gpu = read(cpu_path), read(gpu_path)
        assert author['sha256'] == cpu['sha256'] == gpu['identity']['sha256'] == sha(source)
        assert cpu['resource_passed'] and gpu['passed']
        native = gpu_path.parent / 'asset.scn'
        assert sha(native) == gpu['native_sha']
        master = Path(author['master'])
        assert sha(master) == author['master_sha256']
        views = images(gpu_path.parent, ('back',) if 'pennant' in model else ())
        addenda = []
        if 'pennant' in model:
            extra = OUT / 'v4_extra' / model
            views.extend(images(extra))
            addenda.append(identity(extra / 'report.json'))
            assert read(extra / 'report.json')['identity']['sha256'] == sha(source)
        if model == 's12_riverside_residence':
            extra = OUT / 'v4_final_assembly' / model
            views.extend(images(extra))
            addenda.append(identity(extra / 'report.json'))
            assert read(extra / 'report.json')['passed']
        stats = cpu['statistics']
        cost = {'source_bytes': source.stat().st_size, 'native_bytes': native.stat().st_size,
                'unique_triangles': stats['triangles'], 'visible_triangles_one_instance': stats['triangles'],
                'mesh_nodes': cpu['mesh_nodes'], 'material_count': cpu['materials'],
                'surface_count': stats['primitives'], 'actual_draw_calls': '未测',
                'rgba8_mip_budget_bytes': stats['rgba8_mip_budget_bytes'],
                'image_dimensions_sha': stats['embedded_images'], 'actual_RSS_VRAM': '未测；上述为保守解码预算',
                'LOD_decision': '保留曲线轮廓、活动件和布面风场分段；未强制减面或添加 LOD；无整城性能结论'}
        proof = {'id': model, 'passed': True, 'acceptance_stage': 'structure_and_layout_candidate',
                 'scope': '本轮参考、结构、源资源、隔离导入保存重开与所列画面通过；不代表最终材质或正式地图通过。',
                 'source_path': source.as_posix(), 'source_sha256': sha(source),
                 'master': identity(master), 'native': identity(native),
                 'cpu_report': identity(cpu_path), 'gpu_report': identity(gpu_path), 'runtime_addenda': addenda,
                 'generator': gpu['generator'], 'bounds': gpu['bounds'], 'anchors': author.get('anchors', {}),
                 'cost': cost, 'visual_evidence': views,
                 'status': {'resources': '通过', 'reference_structure': '通过本轮范围',
                            'near_material': pending or '通过所拍范围', 'runtime_pipeline': '通过',
                            'formal_library': '待实际发布收据', 'formal_map': '未部署，本任务不修改地图'},
                 'final_material_accepted': pending is None,
                 'near_material_pending': pending,
                 'placement_semantics': 'authoring anchors are root transforms. MCP place_asset.position is bottom surface: for upright placement input_y = root_y + bounds.position.y * scale.y.',
                 'formal_publication_intent': '独立候选供布局；保留母版与旧版本；不关闭近景材质待细化。'}
        path = OUT / 'acceptance' / (model + '.json')
        write(path, proof)
        rows.append({'id': model, 'version': version, 'label': label, 'category': category,
                     'source': identity(source), 'acceptance': identity(path), 'master': identity(master),
                     'native': identity(native), 'bounds': gpu['bounds'], 'anchors': author.get('anchors', {}),
                     'cost': cost, 'near_material_pending': pending})
    write(OUT / 'handoff.json', {'date': '2026-10-17', 'stage': 'structural layout candidates',
                               'items': rows, 'formal_map_modified': False,
                               'formal_library_status': 'await publication receipts',
                               'reference_report': 'D:/code/rmmo/docs/s12_residential_details_review_20261017.md',
                               'rejected': {'v1_v2': '深拱廊与贴墙结构误读；不再使用',
                                            'v3': '人工画面退回：深拱廊、屋顶小窗交接、锯齿金边与陶罐耳柄',
                                            'v4_jar': '耳柄端部切口露出；改用 v5',
                                            'v4_pennant_back': '背景墙遮挡，不计证据；以 v4_extra 代替'},
                               'assembly': {'house_root_example': [351.9, 8.025, 111], 'house_yaw_degrees': -90,
                                            'gate_local_root': [2.75, 0, 8.6],
                                            'formal_wall_alignment': '待布局会话按真实柱脚与院墙衔接，示例不是最终落点'}})
    print(json.dumps({'items': len(rows), 'handoff': str(OUT / 'handoff.json')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
