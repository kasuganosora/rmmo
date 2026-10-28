import argparse
import contextlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import run_isolated_stream_sync_trace as m

class CaptureContract(unittest.TestCase):
    def test_snapshot_covers_new_scripts_and_inherited_probe(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp).resolve()
            rels=('scripts/world3d/existing.gd','scripts/world3d/new_untracked.gd',
                  'tools/profile_axel_stream_sync_trace.gd','tools/run_isolated_stream_sync_trace.py',
                  'tools/profile_axel_predictive_streaming.gd','tools/run_godot_background.py',
                  'tools/full_native_fixture_audit.py','tools/run_axel_texture_phase.py','tools/isolated_fixture_lock.py','tools/run_isolated_axel_sample.py')
            for rel in rels:
                path=base/rel; path.parent.mkdir(parents=True,exist_ok=True); path.write_text(rel)
            with patch.object(m,'ROOT',base):
                before=m.source_snapshot({'source_before':{'scripts/world3d/existing.gd':'old'}})
                self.assertEqual(len(before),len(rels))
                (base/'scripts/world3d/new_untracked.gd').write_text('changed')
                after=m.source_snapshot({'source_before':{'scripts/world3d/existing.gd':'old'}})
            self.assertNotEqual(before,after)

    def test_rewrite_is_narrow_and_rejects_wrong_fixture(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp).resolve(); fixture=base/'fixture'; fixture.mkdir(); map_path=fixture/'map.gltf'; map_path.touch()
            sample=base/'sample'
            original=['engine','--path',str(m.ROOT),'--script','res://tools/profile_axel_worker_capacity.gd','--','--output=old', '--test-map='+str(map_path),'--test-content-root='+str(fixture),'--native-departure','--mesh-only','--native-only','--full-material-stage']
            cmd=m.make_command(original,sample,'white_native_return',fixture,map_path)
            self.assertIn('--output='+str(sample/'sample.json'),cmd)
            self.assertIn('--sync-trace-phase=white_native_return',cmd)
            self.assertNotIn('--suppress-sync-slow-logs',cmd)
            suppressed=m.make_command(original,sample,'white_native_return',fixture,map_path,True)
            self.assertEqual(suppressed,cmd+['--suppress-sync-slow-logs'])
            self.assertEqual(original[4],'res://tools/profile_axel_worker_capacity.gd')
            with self.assertRaises(ValueError): m.make_command(original,sample,'white_native_return',base,map_path)
            with self.assertRaises(ValueError): m.make_command(original,sample,'unknown',fixture,map_path)
            with self.assertRaises(ValueError): m.make_command(original+['--output=other'],sample,'white_native_return',fixture,map_path)
            with self.assertRaises(ValueError): m.make_command(original+['--suppress-sync-slow-logs'],sample,'white_native_return',fixture,map_path)
            with self.assertRaises(ValueError): m.make_command(['engine_console.exe']+original[1:],sample,'white_native_return',fixture,map_path)

    def test_lock_env_a_state_and_postcheck_with_synthetic_fixture(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp).resolve(); content=base/'content'; content.mkdir(); map_path=content/'map.gltf'; map_path.write_bytes(b'map'); manifest=content/'full_fixture_manifest.json'; manifest.write_text('{}')
            settings=base/'settings'; settings.write_bytes(b'settings'); engine=base/'engine'; engine.write_bytes(b'engine')
            template=base/'template.json'
            cmd=[str(engine),'--path',str(m.ROOT),'--script','res://tools/profile_axel_worker_capacity.gd','--','--output=old','--test-map='+str(map_path),'--test-content-root='+str(content),'--mesh-only','--native-only','--full-material-stage']
            template.write_text(json.dumps({'command':cmd,'map_path':str(map_path),'map_sha256':m.sha(map_path),'engine_sha256':m.sha(engine),'source_before':{'source':'same'}}))
            a=argparse.Namespace(sample_dir=base/'sample',user_dir=base/'private',content_root=content,settings=settings,template=template,settings_sha256=m.sha(settings),manifest_sha256=m.sha(manifest),expected_full_models=1,phase='white_native_return',timeout=2,suppress_slow_logs=True)
            active=[]
            @contextlib.contextmanager
            def lock(root, **kwargs):
                self.assertEqual(kwargs.get('manifest_name'),'full_fixture_manifest.json')
                active.append('held')
                try: yield
                finally: active.pop()
            def run_child(command,**kw):
                self.assertEqual(active,['held'])
                for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR'):
                    self.assertTrue(Path(kw['env'][key]).is_relative_to(base))
                self.assertNotIn('RMMO_FILE_TRACE',kw['env'])
                self.assertIn('--suppress-sync-slow-logs',json.loads((a.sample_dir/'command.json').read_text()))
                (a.sample_dir/'sample.json').write_text(json.dumps({'stream_sync_trace_status':'complete_leg','stream_sync_trace':{'dropped':0},'failures':[],'sync_slow_logs_suppressed':True,'controls':{'full_native_worker_prepack':False,'full_native_template_reuse':False,'full_native_material_plan':True,'full_material_stage':True,'map_textures':True,'compiled':True},'full_model_material_audit':{'after_real_draw':True,'visible_model_meshes':1,'base_textured_surfaces':1}}))
                return argparse.Namespace(returncode=0,stdout=b'child')
            with patch.object(m,'ARTIFACTS',base),patch.object(m,'fixture_lock',lock),patch.object(m,'verify_full_fixture',return_value={'scope':'full_native_model_materials','map':m.sha(map_path)}),patch.object(m,'source_snapshot',return_value={'source':'same'}),patch.object(m.subprocess,'run',side_effect=run_child),patch.dict(m.os.environ,{'RMMO_FILE_TRACE':'must_remove'}):
                result=m.run(a)
            self.assertTrue(result['fixture_unchanged']); self.assertTrue(result['settings_unchanged']); self.assertTrue(result['engine_unchanged']); self.assertTrue(result['template_unchanged'])
            self.assertEqual(result['exit_code'],0); self.assertTrue(result['capture']['valid']); self.assertEqual(active,[])
            self.assertTrue(result['capture']['sync_slow_logs_suppressed'])
            self.assertTrue(json.loads((a.sample_dir/'launch.json').read_text())['suppress_slow_logs'])
            self.assertEqual(json.loads((a.sample_dir/'before.json').read_text()),json.loads((a.sample_dir/'after.json').read_text()))

    def test_full_fixture_before_after_and_failures_are_preserved(self):
        from test_full_native_fixture_audit import FullFixtureTest
        fixture=FullFixtureTest('test_manifest_pins_metadata_between_samples');fixture.setUp()
        self.addCleanup(fixture.tearDown)
        with tempfile.TemporaryDirectory(dir=fixture.root.parent) as aux:
            base=Path(aux).resolve();settings=base/'settings';settings.write_bytes(b'settings');engine=base/'engine';engine.write_bytes(b'engine')
            template=base/'template.json'
            cmd=[str(engine),'--path',str(m.ROOT),'--script','res://tools/profile_axel_worker_capacity.gd','--','--output=old','--test-map='+str(fixture.map),'--test-content-root='+str(fixture.root),'--mesh-only','--native-only','--full-material-stage']
            template.write_text(json.dumps({'command':cmd,'map_path':str(fixture.map),'map_sha256':m.sha(fixture.map),'engine_sha256':m.sha(engine),'source_before':{'source':'same'}}))
            sample_data={'stream_sync_trace_status':'complete_leg','stream_sync_trace':{'dropped':0},'failures':[], 'sync_slow_logs_suppressed':False,'controls':{'full_native_worker_prepack':False,'full_native_template_reuse':False,'full_native_material_plan':True,'full_material_stage':True,'map_textures':True,'compiled':True},'full_model_material_audit':{'after_real_draw':True,'visible_model_meshes':1,'base_textured_surfaces':1}}
            def args(name):
                return argparse.Namespace(sample_dir=base/(name+'_sample'),user_dir=base/(name+'_user'),content_root=fixture.root,settings=settings,template=template,settings_sha256=m.sha(settings),manifest_sha256=fixture.manifest_sha,expected_full_models=1,phase='white_native_return',timeout=2,suppress_slow_logs=False)
            action={'name':'ok'}
            def run_child(command,**kw):
                target=base/(action['name']+'_sample')/'sample.json'
                payload=json.loads(json.dumps(sample_data))
                if action['name']=='bad_controls':payload['controls']['full_material_stage']=False
                target.write_text(json.dumps(payload))
                if action['name']=='mutated_texture':fixture.texture.write_bytes(b'changed')
                if action['name']=='mutated_template':template.write_text(template.read_text()+' ')
                return argparse.Namespace(returncode=0,stdout=b'child')
            with patch.object(m,'ARTIFACTS',fixture.root.parent),patch.object(m,'source_snapshot',return_value={'source':'same'}),patch.object(m.subprocess,'run',side_effect=run_child):
                ok=m.run(args('ok'))
                self.assertTrue(ok['fixture_unchanged'] and ok['template_unchanged'] and ok['capture']['valid'])
                action['name']='bad_controls';bad=m.run(args('bad_controls'))
                self.assertFalse(bad['capture']['valid']);self.assertFalse(bad['capture']['full_material_valid'])
                action['name']='mutated_template';changed=m.run(args('mutated_template'))
                self.assertFalse(changed['template_unchanged']);self.assertTrue(changed['fixture_unchanged'])
                action['name']='mutated_texture';changed=m.run(args('mutated_texture'))
                self.assertFalse(changed['fixture_unchanged']);self.assertIn('texture bytes mismatch',changed['postcheck_error'])
                self.assertTrue((base/'mutated_texture_sample'/'result.json').is_file())

    def test_rejects_retired_template_and_stale_source(self):
        valid=['--mesh-only','--native-only','--full-material-stage']
        m.require_full_template(valid)
        for extra in ('--white-material','--map-texture-stage','--without-map-textures','--without-compiled'):
            with self.assertRaises(ValueError):m.require_full_template(valid+[extra])
        with self.assertRaises(ValueError):m.require_full_template(['--mesh-only','--native-only'])
        with self.assertRaises(ValueError):m.verify_template_sources({'source_before':{'a':'old'}},{'a':'new'})
        m.verify_template_sources({'source_before':{'a':'same'}},{'original':{'a':'same'},'overlay':{}})

    def test_incomplete_or_dropped_traces_are_not_valid(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'sample.json'
            self.assertFalse(m.capture_status(path)['valid'])
            for status,dropped,failures in [('capturing',0,[]),('complete_leg',1,[]),('complete_leg',0,['failure'])]:
                path.write_text(json.dumps({'stream_sync_trace_status':status,'stream_sync_trace':{'dropped':dropped},'failures':failures}))
                self.assertFalse(m.capture_status(path)['valid'])

    def test_capture_fails_closed_if_gate_is_missing_or_mismatched(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'sample.json'
            sample={'stream_sync_trace_status':'complete_leg','stream_sync_trace':{'dropped':0},'failures':[]}
            for actual in (None, False, True):
                sample['sync_slow_logs_suppressed']=actual
                path.write_text(json.dumps(sample))
                self.assertEqual(m.capture_status(path, True)['valid'],actual is True)
                self.assertEqual(m.capture_status(path, False)['valid'],actual is False)

    def test_capture_rejects_non_object_root_and_trace(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'sample.json'
            for data in ([], None, {'stream_sync_trace':[]}, {'stream_sync_trace':None}):
                path.write_text(json.dumps(data))
                status=m.capture_status(path, False)
                self.assertEqual(status['status'], 'unreadable')
                self.assertFalse(status['valid'])

if __name__=='__main__': unittest.main()
