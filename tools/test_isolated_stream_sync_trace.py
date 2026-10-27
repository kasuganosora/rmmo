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
                  'tools/isolated_sidecar_switch.py','tools/isolated_fixture_lock.py','tools/run_isolated_axel_sample.py')
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
            original=['engine','--path',str(m.ROOT),'--script','res://tools/profile_axel_worker_capacity.gd','--','--output=old', '--test-map='+str(map_path),'--test-content-root='+str(fixture),'--native-departure']
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
            base=Path(tmp).resolve(); content=base/'content'; content.mkdir(); map_path=content/'map.gltf'; map_path.write_bytes(b'map'); manifest=content/'fixture_manifest.json'; manifest.write_text('{}')
            settings=base/'settings'; settings.write_bytes(b'settings'); engine=base/'engine'; engine.write_bytes(b'engine')
            template=base/'template.json'
            cmd=[str(engine),'--path',str(m.ROOT),'--script','res://tools/profile_axel_worker_capacity.gd','--','--output=old','--test-map='+str(map_path),'--test-content-root='+str(content)]
            template.write_text(json.dumps({'command':cmd,'map_path':str(map_path),'map_sha256':m.sha(map_path),'engine_sha256':m.sha(engine),'source_before':{}}))
            a=argparse.Namespace(sample_dir=base/'sample',user_dir=base/'private',content_root=content,settings=settings,template=template,settings_sha256=m.sha(settings),manifest_sha256=m.sha(manifest),expected_candidates=1,phase='white_native_return',timeout=2,suppress_slow_logs=True)
            active=[]
            @contextlib.contextmanager
            def lock(root):
                active.append('held')
                try: yield
                finally: active.pop()
            def run_child(command,**kw):
                self.assertEqual(active,['held'])
                for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR'):
                    self.assertTrue(Path(kw['env'][key]).is_relative_to(base))
                self.assertNotIn('RMMO_FILE_TRACE',kw['env'])
                self.assertIn('--suppress-sync-slow-logs',json.loads((a.sample_dir/'command.json').read_text()))
                (a.sample_dir/'sample.json').write_text(json.dumps({'stream_sync_trace_status':'complete_leg','stream_sync_trace':{'dropped':0},'failures':[],'sync_slow_logs_suppressed':True}))
                return argparse.Namespace(returncode=0,stdout=b'child')
            with patch.object(m,'ARTIFACTS',base),patch.object(m,'fixture_lock',lock),patch.object(m,'load_fixture',return_value=(content,{'target_map':str(map_path)}, {map_path:m.sha(map_path)})),patch.object(m,'check_state',return_value=('A',[{'sidecar':'a'}])),patch.object(m,'source_snapshot',return_value={'source':'same'}),patch.object(m.subprocess,'run',side_effect=run_child),patch.dict(m.os.environ,{'RMMO_FILE_TRACE':'must_remove'}):
                result=m.run(a)
            self.assertTrue(result['fixture_unchanged']); self.assertTrue(result['settings_unchanged']); self.assertTrue(result['engine_unchanged'])
            self.assertEqual(result['exit_code'],0); self.assertTrue(result['capture']['valid']); self.assertEqual(active,[])
            self.assertTrue(result['capture']['sync_slow_logs_suppressed'])
            self.assertTrue(json.loads((a.sample_dir/'launch.json').read_text())['suppress_slow_logs'])
            self.assertEqual(json.loads((a.sample_dir/'before.json').read_text()),json.loads((a.sample_dir/'after.json').read_text()))

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
