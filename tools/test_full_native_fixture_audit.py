"""Pure Python fixture identity and full-stage argument regressions; no Godot."""
import argparse,hashlib,json,tempfile,unittest
from pathlib import Path
from full_native_fixture_audit import verify_full_fixture
from run_axel_texture_phase import stage_arguments,full_stage_controls_match
from run_isolated_axel_sample import run_sample

class FullFixtureTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name).resolve();self.folder=self.root/'cache/world3d/compiled_assets_v1';(self.folder/'footprints_v1').mkdir(parents=True)
        self.map=self.root/'map.gltf';self.map_bytes=json.dumps({'nodes':[{'extras':{'rmmo_records':[{'uuid':'id'}],'rmmo_resource_dependencies':{}}}]}).encode();self.map.write_bytes(self.map_bytes);self.texture=self.root/'texture.png';self.texture.write_bytes(b'pixels')
        self.source=self.root/'packs/default/assets'/(('a'*64)+'.glb');self.source.parent.mkdir(parents=True)
        self.payload=self.folder/(('b'*64)+'.scn');self.payload.write_bytes(b'product')
        key=hashlib.sha256(self.source.as_posix().encode()).hexdigest();self.index=self.folder/(key+'.json');self.foot=self.folder/'footprints_v1'/(key+'.json')
        index={'version':1,'source_sha':'a'*64,'payload_sha':'b'*64,'bytes':7,'generator':'old'};self.index.write_text(json.dumps(index),encoding='utf8')
        descriptor=dict(index,source_path=self.source.as_posix(),model_metadata={'version':1,'file_length':42},source_bytes=42,estimated_bytes=100,resident_bytes=100);body=json.dumps(descriptor,separators=(',',':'));self.foot.write_text(json.dumps({'version':1,'body':body,'sha256':hashlib.sha256(body.encode()).hexdigest()}),encoding='utf8')
        self.manifest={'scope':'full_native_model_materials','target_root':str(self.root),'target_map':str(self.map),'target_map_sha256':hashlib.sha256(self.map_bytes).hexdigest(),'source_map':'original','source_map_sha256':'c'*64,'record_count':1,'resource_dependencies':{},'textures':[{'target':str(self.texture),'sha256':hashlib.sha256(b'pixels').hexdigest(),'bytes':6}],'relocation_semantics_verified':True,'relocation_semantics_scope':{'record_count':1,'different_records':0,'material_parameters_rewritten':False,'map_metadata_except_reference_closure_equal':True,'method':'record identifiers and fields except root paths'},'models':[{'logical_source':str(self.source),'source_sha256':'a'*64,'product_path':str(self.payload),'payload_sha256':'b'*64,'index_path':str(self.index),'descriptor_path':str(self.foot)}]}
        self.pin_metadata();self.save()
    def tearDown(self):self.temp.cleanup()
    def save(self):
        raw=json.dumps(self.manifest).encode();(self.root/'full_fixture_manifest.json').write_bytes(raw);self.manifest_sha=hashlib.sha256(raw).hexdigest()
    def pin_metadata(self):
        self.manifest['models'][0].update(index_sha256=hashlib.sha256(self.index.read_bytes()).hexdigest(),descriptor_sha256=hashlib.sha256(self.foot.read_bytes()).hexdigest())
    def test_manifest_pins_metadata_between_samples(self):
        row=self.manifest['models'][0]
        row['index_sha256']=hashlib.sha256(self.index.read_bytes()).hexdigest()
        row['descriptor_sha256']=hashlib.sha256(self.foot.read_bytes()).hexdigest();self.save()
        self.verify()
        original=self.foot.read_bytes();e=json.loads(original);d=json.loads(e['body'])
        d['direct_template_reuse']={'version':1,'safe':True}
        e['body']=json.dumps(d,separators=(',',':'));e['sha256']=hashlib.sha256(e['body'].encode()).hexdigest()
        self.foot.write_text(json.dumps(e),encoding='utf8')
        with self.assertRaisesRegex(ValueError,'manifest metadata identity'):self.verify()
        row['descriptor_sha256']=hashlib.sha256(self.foot.read_bytes()).hexdigest();self.save();self.verify()
        self.index.write_bytes(self.index.read_bytes()+b'\n')
        with self.assertRaisesRegex(ValueError,'manifest metadata identity'):self.verify()
    def verify(self):return verify_full_fixture(self.root,self.map,self.manifest_sha,1)
    def test_valid_and_stat_change_detected(self):
        before=self.verify();self.payload.write_bytes(b'PRODUCT');after=self.verify();self.assertNotEqual(before['products'],after['products'])
    def test_rejects_white_scope_and_bad_semantics(self):
        for field,value in [('scope','map-texture-stage'),('relocation_semantics_verified',False),('relocation_semantics_scope',{})]:
            old=self.manifest[field];self.manifest[field]=value;self.save()
            with self.assertRaises(ValueError):self.verify()
            self.manifest[field]=old
    def test_rejects_map_or_manifest_mismatch(self):
        self.map.write_bytes(b'changed')
        with self.assertRaises(ValueError):self.verify()
        self.map.write_bytes(self.map_bytes)
        with self.assertRaises(ValueError):verify_full_fixture(self.root,self.map,'0'*64,1)
    def test_rejects_logical_glb_but_allows_authoring_copy(self):
        authoring=self.root/'authoring/model.glb';authoring.parent.mkdir();authoring.write_bytes(b'allowed')
        self.verify();self.source.write_bytes(b'forbidden')
        with self.assertRaises(ValueError):self.verify()
    def test_rejects_missing_or_misbound_product(self):
        self.payload.unlink()
        with self.assertRaises(ValueError):self.verify()
        self.payload.write_bytes(b'product');self.manifest['models'][0]['payload_sha256']='d'*64;self.save()
        with self.assertRaises(ValueError):self.verify()
    def test_rejects_missing_full_metadata_and_wrong_count(self):
        with self.assertRaises(ValueError):verify_full_fixture(self.root,self.map,self.manifest_sha,2)
        e=json.loads(self.foot.read_text());d=json.loads(e['body']);d.pop('model_metadata');e['body']=json.dumps(d,separators=(',',':'));e['sha256']=hashlib.sha256(e['body'].encode()).hexdigest();self.foot.write_text(json.dumps(e))
        with self.assertRaises(ValueError):self.verify()
    def test_full_wrapper_passes_identity_and_isolates_state(self):
        with tempfile.TemporaryDirectory(dir=self.root.parent) as aux:
            aux=Path(aux);engine=aux/'gui.exe';engine.write_bytes(b'fake');settings=aux/'settings.cfg';settings.write_bytes(b'private')
            fake=aux/'fake.py';fake.write_text('import json,sys;print(json.dumps(sys.argv[1:]))',encoding='utf8')
            args=argparse.Namespace(engine=engine,sample_dir=aux/'sample',user_dir=aux/'user',content_root=self.root,map_path=self.map,settings=settings,settings_sha256=hashlib.sha256(b'private').hexdigest(),manifest_sha256=self.manifest_sha,expected_state=None,expected_candidates=1,expected_full_models=1,stage='full',timeout=5,traverse=True,cold_index=False,texture_profile=False,full_native_worker_prepack=True)
            result=run_sample(args,runner=fake,artifacts=self.root.parent)
            self.assertTrue(result['variants_unchanged']);self.assertEqual(result['exit_code'],0)
            child=json.loads((args.sample_dir/'isolation.runner.log').read_text())
            self.assertEqual(child[child.index('--stage')+1],'full');self.assertEqual(child[child.index('--full-fixture-manifest-sha256')+1],self.manifest_sha);self.assertEqual(child[child.index('--expected-full-models')+1],'1');self.assertIn('--traverse',child);self.assertIn('--full-native-worker-prepack',child)
            launch=json.loads((args.sample_dir/'isolation.launch.json').read_text());self.assertIs(launch['full_native_worker_prepack_requested'],True)
            args.sample_dir=aux/'sample_reuse';args.full_native_worker_prepack=False;args.full_native_template_reuse=True
            self.assertEqual(run_sample(args,runner=fake,artifacts=self.root.parent)['exit_code'],0)
            child=json.loads((args.sample_dir/'isolation.runner.log').read_text())
            self.assertIn('--full-native-template-reuse',child);self.assertNotIn('--full-native-worker-prepack',child)
            launch=json.loads((args.sample_dir/'isolation.launch.json').read_text());self.assertIs(launch['full_native_template_reuse_requested'],True)
            args.sample_dir=aux/'sample_plan_baseline';args.without_full_native_material_plan=True
            self.assertEqual(run_sample(args,runner=fake,artifacts=self.root.parent)['exit_code'],0)
            child=json.loads((args.sample_dir/'isolation.runner.log').read_text())
            self.assertIn('--without-full-native-material-plan',child)
            launch=json.loads((args.sample_dir/'isolation.launch.json').read_text());self.assertIs(launch['full_native_material_plan_requested'],False)
            args.without_full_native_material_plan=False
            args.sample_dir=aux/'mixed_experiments';args.full_native_worker_prepack=True
            with self.assertRaisesRegex(ValueError,'separate experiments'):run_sample(args,runner=fake,artifacts=self.root.parent)
            self.assertFalse((args.sample_dir/'isolation.runner.log').exists());args.full_native_worker_prepack=False
            args.sample_dir=aux/'sample2';args.expected_state='A'
            with self.assertRaises(ValueError):run_sample(args,runner=fake,artifacts=self.root.parent)
            args.expected_state=None;args.sample_dir=aux/'sample3'
            fake.write_text("import sys,pathlib;root=pathlib.Path(sys.argv[sys.argv.index('--content-root')+1]);(root/'texture.png').write_bytes(b'change')",encoding='utf8')
            altered=run_sample(args,runner=fake,artifacts=self.root.parent)
            self.assertFalse(altered['variants_unchanged'])
            self.assertIn('texture bytes mismatch',json.loads((args.sample_dir/'isolation.variants.after.json').read_text())['error'])

    def test_integral_float_footprints_match_production(self):
        e=json.loads(self.foot.read_text());d=json.loads(e['body']);d['estimated_bytes']=100.0;d['resident_bytes']=100.0
        e['body']=json.dumps(d,separators=(',',':'));e['sha256']=hashlib.sha256(e['body'].encode()).hexdigest();self.foot.write_text(json.dumps(e));self.pin_metadata();self.save();self.verify()
        d['estimated_bytes']=100.5;d['resident_bytes']=100.5;e['body']=json.dumps(d,separators=(',',':'));e['sha256']=hashlib.sha256(e['body'].encode()).hexdigest();self.foot.write_text(json.dumps(e))
        with self.assertRaises(ValueError):self.verify()

    def test_rejects_changed_texture_and_reference_closure(self):
        self.texture.write_bytes(b'change')
        with self.assertRaises(ValueError):self.verify()
        self.texture.write_bytes(b'pixels');self.manifest['resource_dependencies']={'bad.rmres':'d'*64};self.save()
        with self.assertRaises(ValueError):self.verify()

    def test_rejects_escaping_product(self):
        self.manifest['models'][0]['product_path']=str(self.root.parent/'outside.scn');self.save()
        with self.assertRaises(ValueError):self.verify()

class FullStageTest(unittest.TestCase):
    def test_old_stage_flags_unchanged(self):
        self.assertEqual(stage_arguments('white'),['--white-material','--without-map-textures']);self.assertEqual(stage_arguments('map'),['--map-texture-stage']);self.assertEqual(stage_arguments('full'),['--full-material-stage'])
        self.assertEqual(stage_arguments('full',True),['--full-material-stage','--full-native-worker-prepack'])
        self.assertEqual(stage_arguments('full',False,True),['--full-material-stage','--full-native-template-reuse'])
        self.assertEqual(stage_arguments('full',False,True,True),['--full-material-stage','--full-native-template-reuse','--without-full-native-material-plan'])
        with self.assertRaises(ValueError):stage_arguments('full',False,False,True)
        with self.assertRaises(ValueError):stage_arguments('map',True)
        with self.assertRaises(ValueError):stage_arguments('map',False,True)
        with self.assertRaises(ValueError):stage_arguments('full',True,True)
        with self.assertRaises(ValueError):stage_arguments('unsupported')
    def test_full_controls_and_actual_model_texture_evidence_required(self):
        c={'full_native_worker_prepack':False,'full_native_template_reuse':False,'full_native_material_plan':True,'full_material_stage':True,'map_texture_stage':False,'map_textures':True,'white_material':False,'white_native':False,'native_geometry_only':False,'compiled':True}
        report={'controls':c,'full_model_material_audit':{'after_real_draw':True,'visible_model_meshes':1,'base_textured_surfaces':1}}
        self.assertTrue(full_stage_controls_match(report))
        for k in c:
            old=c[k];c[k]=not old;self.assertFalse(full_stage_controls_match(report));c[k]=old
        c['full_native_worker_prepack']=True;self.assertTrue(full_stage_controls_match(report,True));self.assertFalse(full_stage_controls_match(report,False));c['full_native_worker_prepack']=False
        c['full_native_template_reuse']=True;self.assertTrue(full_stage_controls_match(report,False,True));self.assertFalse(full_stage_controls_match(report));c['full_native_template_reuse']=False
        c['full_native_material_plan']=False;self.assertTrue(full_stage_controls_match(report,False,False,False));self.assertFalse(full_stage_controls_match(report));c['full_native_material_plan']=True
        report['full_model_material_audit']['base_textured_surfaces']=0;self.assertFalse(full_stage_controls_match(report))

if __name__=='__main__':unittest.main()
