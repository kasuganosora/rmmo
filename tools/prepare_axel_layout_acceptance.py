"""Assemble evidence for publish_axel_town_layout.gd; never edit/publish a map.

Default: write layout_acceptance.draft.json with passed=false and an unreviewed
review_template. Copy/fill that template only after actually viewing the images
and assessing each resource scope, then run --review FILE --finalize. A flag or
successful runtime alone cannot supply visual/resource approval. Native document
ownership, unchanged-record and atomic-save checks remain the publisher's job.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys

DEFAULT_OUT = Path('D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016')
FORMAL = Path('D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf')
CANDIDATE = Path('D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf')
SCOPES = ('fortification', 'market', 'vegetation')
RESOURCE_FILES = {
    'fortification': 'fortification_resource_audit.json',
    'market': 'market_resource_acceptance_index.json',
    'vegetation': 'vegetation_reused_model_evidence.json',
}


def canonical(path):
    return os.path.normpath(str(path).replace('\\', '/')).replace('\\', '/').casefold()


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    pending = path.with_name(path.name + '.pending')
    pending.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    os.replace(pending, path)


class Assembly:
    def __init__(self, out, formal, candidate):
        self.out, self.formal, self.candidate = out, formal, candidate
        self.errors, self.pins, self.cache = [], {}, {}
        self.scopes = list(SCOPES)
        self.buildings = {}

    def check(self, condition, description):
        if not condition and description not in self.errors:
            self.errors.append(description)
        return bool(condition)

    def sha(self, path):
        path = Path(path)
        if not path.is_file():
            self.check(False, f'Missing file: {path}')
            return ''
        stat = path.stat()
        key = (canonical(path), stat.st_size, stat.st_mtime_ns)
        if key not in self.cache:
            with path.open('rb') as stream:
                self.cache[key] = hashlib.file_digest(stream, 'sha256').hexdigest()
        return self.cache[key]

    def pin(self, path, expected=None):
        if not path:
            self.check(False, 'Evidence path is empty')
            return ''
        actual = self.sha(path)
        if expected is not None:
            self.check(bool(re.fullmatch('[0-9a-f]{64}', str(expected))) and actual == expected,
                       f'SHA mismatch: {path}')
        if actual:
            key = canonical(path)
            self.check(key not in self.pins or self.pins[key]['sha256'] == actual,
                       f'Evidence changed during assembly: {path}')
            self.pins[key] = {'path': str(path), 'sha256': actual}
        return actual

    def read(self, path):
        if not self.pin(path):
            return {}
        try:
            data = json.loads(Path(path).read_text(encoding='utf-8-sig'))
            if not isinstance(data, dict):
                raise ValueError('expected object')
            return data
        except (ValueError, OSError) as error:
            self.check(False, f'Invalid JSON {path}: {error}')
            return {}

    def ref(self, path, role=None):
        result = {'path': str(path), 'sha256': self.pin(path)}
        if role:
            result['role'] = role
        return result

    def nested_references(self, value):
        """Recheck explicit path/SHA descriptors; do not infer historical verdicts."""
        if isinstance(value, dict):
            if value.get('path') and 'sha256' in value:
                self.pin(value['path'], value['sha256'])
            for child in value.values():
                self.nested_references(child)
        elif isinstance(value, list):
            for child in value:
                self.nested_references(child)

    def q90(self, path, expected):
        self.pin(path, expected)
        receipt = self.read(str(path) + '.review-image.json')
        self.check(Path(path).suffix.lower() == '.webp' and receipt.get('sha256') == expected
                   and receipt.get('quality') == 90 and receipt.get('lossless') is False,
                   f'Missing exact lossy WebP quality90 receipt: {path}')
        try:
            from PIL import Image
            with Image.open(path) as image:
                self.check(image.format == 'WEBP' and list(image.size) == receipt.get('dimensions'),
                           f'Actual image format/dimensions differ from receipt: {path}')
                image.verify()
        except (ImportError, OSError, ValueError) as error:
            self.check(False, f'Cannot verify actual WebP {path}: {error}')

    def metadata(self):
        data = self.read(self.candidate)
        metas = [node.get('extras', {}) for node in data.get('nodes', [])
                 if node.get('extras', {}).get('rmmo_format')]
        self.check(len(metas) == 1, 'Candidate must have one authoritative rmmo metadata node')
        return metas[0] if len(metas) == 1 else {}

    def fortification_history(self, fort, baseline):
        history = fort.get('regenerations', [])
        if not history:
            self.check(not fort.get('initial_build'), 'Initial build requires a nonempty regeneration chain')
            return
        def immutable(desc):
            path, sha = desc.get('path',''), desc.get('sha256','')
            self.check(canonical(Path(path).parent) == canonical(self.out/'fortification_history')
                       and Path(path).name == sha+'.json', 'Immutable fortification history path')
            self.pin(path,sha)
            return self.read(path)
        initial_desc = fort.get('initial_build',{})
        initial = immutable(initial_desc)
        self.check(initial.get('saved') is True and initial.get('apply') is True
                   and initial.get('failures') == 0 and initial.get('source_sha256') == baseline
                   and initial.get('phase') == 'native_candidate_complete_review_pending'
                   and not initial.get('regenerations') and not initial.get('initial_build'), 'Exact original native construction receipt')
        mutable = {'candidate_sha256','native_reopen_passed','initial_build','regenerations','latest_regeneration','visual','runtime','history_note'}
        stable = lambda d: {k:v for k,v in d.items() if k not in mutable}
        self.check(stable(initial) == stable(fort), 'Original construction recipe/source/operations/relocations unchanged')
        output = initial.get('candidate_sha256','')
        prior = []
        for entry in history:
            proof = immutable(entry)
            prev_desc = proof.get('previous_build',{})
            previous = immutable(prev_desc)
            self.check(proof.get('previous_build_sha256') == prev_desc.get('sha256')
                       and previous.get('candidate_sha256') == output and stable(previous) == stable(initial)
                       and previous.get('regenerations',[]) == prior, 'Exact prior receipt and append-only history')
            self.check((not prior and prev_desc == initial_desc)
                       or (bool(prior) and previous.get('initial_build') == initial_desc), 'Regeneration initial receipt identity')
            self.check(proof.get('initial_build') == initial_desc
                       and proof.get('input_sha256') == output == entry.get('input_sha256')
                       and proof.get('output_sha256') == entry.get('output_sha256')
                       and bool(re.fullmatch('[0-9a-f]{64}',str(proof.get('output_sha256','')))), 'Continuous regeneration input/output chain')
            self.check(proof.get('saved') is True and proof.get('apply') is True and proof.get('failures') == 0
                       and proof.get('native_reopen_passed') is True
                       and proof.get('phase') == 'native_fortification_regeneration_complete_review_pending'
                       and all(proof.get('transaction',{}).get(k) is True for k in ('undo_passed','redo_passed','save_reopen')), 'Completed native regeneration transaction')
            self.check(proof.get('source_sha256') == baseline and canonical(proof.get('source','')) == canonical(self.formal)
                       and canonical(proof.get('map','')) == canonical(self.candidate)
                       and entry.get('method') == proof.get('method') and bool(proof.get('method')), 'Regeneration target/source/method')
            ops = proof.get('operations',[])
            self.check([x.get('tool') for x in ops] == ['remove_fortification','preview_fortification','generate_fortification']
                       and all(x.get('result',{}).get('ok') is True for x in ops)
                       and ops[0].get('request',{}).get('keep_objects') is False, 'Actual native whole-group replacement operations')
            comparison = proof.get('frozen_comparison',[])
            self.check(bool(comparison) and all(x.get('non_tangent_data_identical') is True and x.get('invalid_after') == 0
                       and x.get('valid_tangents_changed') == 0 for x in comparison), 'Only invalid tangent bases repaired')
            self.check(all(proof.get('preservation',{}).get(k) is True for k in
                       ('non_fortification_records_identical','non_fortification_metadata_identical','component_ids_stable')), 'Non-fortification state and component identities preserved')
            # proof.inputs describes history, including the then-current map and
            # mutable build receipt. Its immutable receipt is pinned above; never
            # require those paths to still contain historical bytes today.
            output = proof.get('output_sha256','')
            prior.append(entry)
        self.check(fort.get('candidate_sha256') == output and fort.get('latest_regeneration') ==
                   {k:history[-1][k] for k in ('path','sha256')}, 'Final wall output is last proven regeneration')

    def native_chain(self, baseline, final_sha):
        paths = {
            'fortification_build': self.out / 'fortification_build.json',
            'market_build': self.out / 'market_build.json',
            'vegetation_build': self.out / 'functional_vegetation_build.json',
        }
        fort, market, vegetation = (self.read(path) for path in paths.values())
        self.fortification_history(fort, baseline)
        self.check(fort.get('saved') is True and fort.get('apply') is True
                   and fort.get('failures') == 0
                   and fort.get('phase') == 'native_candidate_complete_review_pending',
                   'Fortification native save/reopen is incomplete or failed')
        self.check(market.get('saved') is True and market.get('apply') is True
                   and market.get('failures') == 0
                   and market.get('phase') == 'native_market_complete_review_pending',
                   'Market native save/reopen is incomplete or failed')
        self.check(vegetation.get('saved') is True and vegetation.get('dry_run') is False
                   and vegetation.get('failures') == 0 and vegetation.get('native_reopen_passed') is True
                   and vegetation.get('native_save_validation') == 0
                   and vegetation.get('input_unchanged') is True and 'error' not in vegetation,
                   'Vegetation native save/reopen is incomplete or failed')
        self.check(canonical(fort.get('source', '')) == canonical(self.formal)
                   and fort.get('source_sha256') == baseline, 'Formal baseline differs from fortification input')
        self.check(all(canonical(path) == canonical(self.candidate) for path in
                       [fort.get('candidate', ''), market.get('map', ''), vegetation.get('map_path', '')]),
                   'Native stages do not target the same candidate')
        self.check(bool(fort.get('candidate_sha256'))
                   and market.get('input_sha256') == fort.get('candidate_sha256'),
                   'Broken fortification output -> market input SHA chain')
        self.check(market.get('formal_before_sha256') == baseline, 'Market baseline changed')
        middle_sha = market.get('candidate_sha256', '')
        if vegetation.get('input_sha256') != middle_sha:
            building_path = self.out / 'functional_buildings_apply.json'
            buildings = self.read(building_path)
            self.buildings = buildings
            paths['functional_buildings_build'] = building_path
            self.scopes.append('functional_buildings')
            self.check(buildings.get('saved') is True and buildings.get('apply') is True
                       and buildings.get('failures') == 0 and buildings.get('native_reopen_passed') is True
                       and buildings.get('phase') == 'native_functional_buildings_complete_outdoor_review_pending'
                       and buildings.get('blocking_findings') == [], 'Functional buildings native stage not complete')
            self.check(canonical(buildings.get('map','')) == canonical(self.candidate)
                       and buildings.get('formal_before_sha256') == baseline
                       and buildings.get('input_sha256') == middle_sha,
                       'Broken market -> functional buildings chain')
            self.check(all(buildings.get('transaction',{}).get(k) is True for k in ('undo_passed','redo_passed','save_reopen')), 'Functional building native undo/redo/save-reopen evidence missing')
            middle_sha = buildings.get('output_sha256','')
            inputs = buildings.get('inputs', {})
            self.check(bool(inputs), 'Functional building input pins missing')
            for path, sha in inputs.items(): self.pin(path, sha)
            self.check({p.get('key') for p in buildings.get('placements',[])} == {'guardhouse','church','watermill'}
                       and len(buildings.get('placements',[])) == 3, 'Three functional building placements required')
        self.check(bool(middle_sha) and vegetation.get('input_sha256') == middle_sha,
                   'Broken preceding native output -> vegetation input SHA chain')
        self.check(bool(final_sha) and vegetation.get('output_sha256') == final_sha,
                   'Vegetation output is not the actual final candidate')
        if fort:
            self.pin(fort.get('plan_path', ''), fort.get('plan_sha256', ''))
        if fort.get('relocation_plan'):
            descriptor = fort['relocation_plan']
            self.pin(descriptor.get('path', ''), descriptor.get('sha256', ''))
            moves = self.read(descriptor.get('path', ''))
            self.check(moves.get('ok') is True and moves.get('source_sha256') == baseline
                       and moves.get('recipe_sha256') == fort.get('plan_sha256'),
                       'Grass relocation plan is not accepted for the same baseline/recipe')
        inputs = market.get('inputs', {})
        self.check(isinstance(inputs, dict) and bool(inputs), 'Market input identity manifest is empty')
        if isinstance(inputs, dict):
            for path, sha in inputs.items():
                self.pin(path, sha)
        plan_path = self.out / 'functional_vegetation_plan.json'
        plan = self.read(plan_path)
        self.pin(plan_path, vegetation.get('plan_sha256', ''))
        self.check(plan.get('formal_source_sha256') == baseline, 'Vegetation plan has a different formal baseline')
        for asset in plan.get('assets', []):
            self.pin(asset.get('asset_id', ''), asset.get('sha256', ''))
        if vegetation.get('future_sites_sha256'):
            self.pin(self.out / 'functional_building_sites.json', vegetation['future_sites_sha256'])
        return [self.ref(path, role) for role, path in paths.items()]

    def building_inventory(self):
        descriptor = self.buildings.get('building_inputs', {})
        path, sha = descriptor.get('path', ''), descriptor.get('sha256', '')
        self.check(bool(path) and canonical(Path(path).parent) == canonical(self.out / 'functional_inputs')
                   and Path(path).name == str(sha) + '.json', 'Building inputs must be a content-addressed immutable descriptor')
        self.pin(path, sha)
        self.check(self.buildings.get('inputs', {}).get(path) == sha,
                   'Building descriptor must be pinned by the successful native receipt')
        data = self.read(path)
        keys = {'guardhouse', 'church', 'watermill'}
        self.check(data.get('schema') == 1 and set(data.get('formal_publications', {})) == keys
                   and set(data.get('designs', {})) == keys, 'Incomplete scoped building descriptor')
        for key in keys:
            design = data.get('designs', {}).get(key, {})
            source_field = {'church': 'source', 'guardhouse': 'candidate', 'watermill': 'candidate_glb'}[key]
            self.check(design.get(source_field, {}).get('sha256') == data.get('formal_publications', {}).get(key, {}).get('source', {}).get('sha256')
                       and bool(design.get({'church': 'entrances', 'guardhouse': 'main_entrance', 'watermill': 'front_door'}[key])),
                       'Building anchors must match the actual published source: ' + key)
        return Path(path), data

    def resources(self, review, final_sha, accepted_views):
        outputs, template = [], []
        decisions = review.get('resources', [])
        self.check(isinstance(decisions, list), 'Resource reviews must be a list')
        decisions = decisions if isinstance(decisions, list) else []
        self.check(len({x.get('scope') for x in decisions}) == len(decisions), 'Duplicate resource scope review')
        self.check(all(x.get('scope') in self.scopes for x in decisions), 'Unknown resource scope review')
        for scope in self.scopes:
            if scope == 'functional_buildings':
                path, data = self.building_inventory()
            else:
                path = self.out / RESOURCE_FILES[scope]
                data = self.read(path)
            descriptor = self.ref(path)
            decision = next((x for x in decisions if x.get('scope') == scope), {})
            template.append({'scope': scope, 'passed': False, 'reviewed': False,
                             'findings': '', 'lod_necessity': '', 'view_ids': [],
                             'source_evidence': [descriptor]})
            self.check(decision.get('passed') is True and decision.get('reviewed') is True
                       and bool(str(decision.get('findings', '')).strip())
                       and bool(str(decision.get('lod_necessity', '')).strip()),
                       f'Explicit resource assessment/LOD verdict missing: {scope}')
            view_ids = decision.get('view_ids', [])
            self.check(isinstance(view_ids, list) and bool(view_ids)
                       and all(x in accepted_views for x in view_ids),
                       f'Resource scope must cite actually reviewed final images: {scope}')
            sources = decision.get('source_evidence', [])
            self.check(isinstance(sources, list) and descriptor in sources,
                       f'Resource review must pin its actual scope inventory: {scope}')
            if isinstance(sources, list):
                for source in sources:
                    self.pin(source.get('path', ''), source.get('sha256', ''))
            if scope == 'functional_buildings':
                template[-1]['building_view_ids'] = {k: [] for k in ('guardhouse','church','watermill')}
            self.nested_references(data)
            if scope == 'fortification':
                self.check(data.get('passed') is True and data.get('map_sha256') == final_sha
                           and data.get('errors') == [] and data.get('pending_unfrozen_records') == []
                           and bool(data.get('rows')), 'Current final fortification resource audit not passed')
            elif scope == 'market':
                self.check(bool(data.get('houses')) and bool(data.get('stalls_active_resource_cost')),
                           'Market model inventory lacks houses or active stalls')
                for house in data.get('houses', []):
                    self.pin(house.get('template_path', ''), house.get('template_sha256', ''))
                    self.pin(house.get('per_template_review_path', ''), house.get('per_template_review_sha256', ''))
                    self.check(house.get('source_resource_visual_same_sha') is True
                               and house.get('previous_visual_passed') is True,
                               'Market template lacks same-version visual evidence: ' + house.get('house_id', '?'))
                    for image in house.get('previous_images', []):
                        self.q90(image.get('path', ''), image.get('sha256', ''))
            elif scope == 'functional_buildings':
                view_map = decision.get('building_view_ids', {})
                for key in ('guardhouse','church','watermill'):
                    self.check(bool(view_map.get(key)) and all(v in accepted_views for v in view_map.get(key,[])),
                               'Actual final exterior images required for '+key)
                    model = data.get('formal_publications',{}).get(key,{})
                    self.check(model.get('status',{}).get('resource') == 'passed'
                               and model.get('status',{}).get('visual') == 'passed', 'Published model not accepted: '+key)
                    for field in ('source','manifest','acceptance','formal_catalog_use','publication_receipt'):
                        desc=model.get(field,{})
                        self.pin(desc.get('path',''),desc.get('sha256',''))
                    source=model.get('source',{}).get('sha256','')
                    self.pin(model.get('asset_id',''),source)
                    proof=self.read(model.get('acceptance',{}).get('path',''))
                    self.check(proof.get('passed') is True and proof.get('source_sha256') == source
                               and proof.get('asset') == key and all(proof.get(f) == 'passed' for f in
                               ('resource_status','visual_status','pipeline_status')), 'Exact model acceptance incomplete: '+key)
                    self.nested_references(proof)
                    publication=self.read(model.get('publication_receipt',{}).get('path',''))
                    self.check(publication.get('ok') is True and publication.get('completed') is True
                               and publication.get('failures') == [] and publication.get('source_sha256') == source,
                               'Formal model publication incomplete: '+key)
                    matches=[p for p in self.buildings.get('placements',[]) if p.get('key') == key]
                    self.check(len(matches)==1 and matches[0].get('source_sha256') == source
                               and canonical(matches[0].get('asset_path','')) == canonical(model.get('asset_id','')),
                               'Placed model differs from accepted formal source: '+key)
            else:
                self.check(data.get('all_current_identities_match') is True and bool(data.get('assets')),
                           'Vegetation model inventory does not verify current resource identities')
            outputs.append({'scope': scope, 'passed': False, 'candidate_sha256': final_sha,
                            'assessment': decision, 'scope_inventory': descriptor,
                            'limits': 'Source model reuse and current placement are distinct; no new model fabrication, '
                                      'whole-town benchmark or final publication is implied.'})
        return outputs, template

    def assemble(self, review_path=None, runtime_path=None, finalize=False):
        baseline, final_sha = self.pin(self.formal), self.pin(self.candidate)
        evidence = self.native_chain(baseline, final_sha)
        meta = self.metadata()
        has_buildings = bool(meta.get('town_reference',{}).get('functional_buildings'))
        self.check(has_buildings == bool(self.buildings), 'Functional building metadata and authoring chain differ')
        instances = meta.get('building_instances', {})
        self.check(isinstance(instances, dict) and bool(instances), 'Native candidate house instances missing')
        runtime_path = runtime_path or self.out / 'fortification_runtime/result.json'
        runtime = self.read(runtime_path)
        evidence.append(self.ref(runtime_path, 'runtime'))
        self.nested_references(runtime.get('child_reports', []))
        for child in runtime.get('child_reports', []):
            source_runtime=self.read(child.get('path',''))
            self.nested_references(source_runtime.get('source_reports', []))
            self.check(source_runtime.get('map_sha256') == final_sha and source_runtime.get('phase') == 'complete'
                       and source_runtime.get('status') == 'passed' and source_runtime.get('failures') == 0,
                       'Aggregated child runtime failed/incomplete/stale: '+str(child.get('path','')))
            self.check(all(shot in runtime.get('screenshots',[]) for shot in source_runtime.get('screenshots',[])),
                       'Aggregate omitted/changed actual child screenshots')
        self.check(runtime.get('map_sha256') == final_sha and runtime.get('phase') == 'complete'
                   and runtime.get('status') == 'passed' and runtime.get('failures') == 0,
                   'Final exact candidate has not passed the complete outdoor runtime review')
        if self.buildings:
            exterior=runtime.get('functional_buildings',{})
            self.check(exterior.get('passed') is True and exterior.get('build_receipt_sha256') == self.sha(self.out/'functional_buildings_apply.json'),
                       'Functional building final outdoor runtime receipt missing or stale')
            for key in ('guardhouse','church','watermill'):
                self.check(any(c.get('key') == key and c.get('passed') is True for c in exterior.get('checks',[])),
                           'Actual outdoor entry runtime check missing: '+key)
        review = self.read(review_path) if review_path else {}
        self.check(bool(review_path), 'No explicit visual/resource review supplied')
        self.check(bool(final_sha) and review.get('candidate_sha256') == final_sha,
                   'Explicit review does not pin the final candidate SHA')
        views = review.get('views', [])
        views = views if isinstance(views, list) else []
        shots = runtime.get('screenshots', [])
        self.check(bool(shots), 'Runtime screenshots are empty')
        ids = [shot.get('id', '') for shot in shots]
        self.check(all(ids) and len(ids) == len(set(ids)), 'Runtime image IDs are empty or duplicated')
        self.check(len(views) == len(shots) and len({x.get('id') for x in views}) == len(views),
                   'Explicit image review must cover every runtime image exactly once')
        accepted, actual_views, view_template = set(), [], []
        for shot in shots:
            identity = {key: shot.get(key, '') for key in ('id', 'path', 'sha256')}
            self.q90(identity['path'], identity['sha256'])
            decision = next((x for x in views if x.get('id') == identity['id']), {})
            good = (decision.get('passed') is True and decision.get('reviewed') is True
                    and bool(str(decision.get('observations', '')).strip())
                    and decision.get('sha256') == identity['sha256']
                    and canonical(decision.get('path', '')) == canonical(identity['path']))
            self.check(good, 'Explicit exact-image observation missing/failed: ' + identity['id'])
            if good:
                accepted.add(identity['id'])
            actual_views.append({**identity, 'passed': good, 'observations': decision.get('observations', '')})
            view_template.append({**identity, 'passed': False, 'reviewed': False, 'observations': ''})
        resources, resource_template = self.resources(review, final_sha, accepted)
        # Catch an authoring run replacing receipts or map bytes while we were reading.
        for descriptor in list(self.pins.values()):
            self.check(self.sha(descriptor['path']) == descriptor['sha256'],
                       'Evidence changed before output: ' + descriptor['path'])
        passed = finalize and not self.errors
        if passed:
            for resource in resources:
                resource['passed'] = True
                path = self.out / 'acceptance_resources' / (resource['scope'] + '_' + final_sha[:12] + '.json')
                atomic_json(path, resource)
                evidence.append({**self.ref(path, 'resource_review'), 'passed': True,
                                 'scopes': [resource['scope']]})
            # The publisher pins every evidence entry, including supporting source
            # files. Keep nested inventories/encoding receipts from changing in the
            # gap between this assembly and the native atomic-save operation.
            included = {canonical(item['path']) for item in evidence}
            for descriptor in self.pins.values():
                if canonical(descriptor['path']) not in included:
                    role = 'support_' + hashlib.sha256(canonical(descriptor['path']).encode()).hexdigest()[:20]
                    evidence.append({**descriptor, 'role': role})
                    included.add(canonical(descriptor['path']))
        result = {
            'passed': passed, 'status': 'accepted_for_native_publication' if passed else 'pending',
            'source_sha256': baseline, 'candidate_sha256': final_sha,
            'house_count': len(instances), 'runtime_report': str(runtime_path),
            'evidence': evidence, 'views': actual_views, 'pending': self.errors,
            'evidence_pins': list(self.pins.values()),
            'review_template': {'candidate_sha256': final_sha, 'views': view_template, 'resources': resource_template},
            'scope_limits': ['Candidate acceptance only; native publisher must recheck unchanged source records, '
                             'ownership, startup map, relocation tokens and atomic save/reopen.',
                             'Original residential interiors are not retested. Fixed-view timings are not a '
                             'whole-town performance or RSS/VRAM measurement.',
                             'This stage does not claim the whole town or detailed finishing is complete; functional buildings require their own pinned stage and outdoor review.'],
            'deferred_checks': runtime.get('deferred_checks', []),
            'all_work_complete': runtime.get('all_work_complete', True),
        }
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=DEFAULT_OUT)
    parser.add_argument('--formal', type=Path, default=FORMAL)
    parser.add_argument('--candidate', type=Path, default=CANDIDATE)
    parser.add_argument('--runtime', type=Path)
    parser.add_argument('--review', type=Path, help='Explicit completed review_template JSON, not an automatic verdict')
    parser.add_argument('--finalize', action='store_true', help='Write acceptance only if every gate passes')
    args = parser.parse_args()
    assembly = Assembly(args.out, args.formal, args.candidate)
    result = assembly.assemble(args.review, args.runtime, args.finalize)
    # Failed finalization must not overwrite an earlier accepted manifest.
    target = args.out / ('layout_acceptance.json' if result['passed'] else 'layout_acceptance.draft.json')
    atomic_json(target, result)
    print(json.dumps({'path': str(target), 'passed': result['passed'], 'pending_count': len(result['pending']),
                      'candidate_sha256': result['candidate_sha256']}, ensure_ascii=False))
    return 1 if args.finalize and not result['passed'] else 0


if __name__ == '__main__':
    sys.exit(main())
