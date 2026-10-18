#!/usr/bin/env python3
"""Check client-derived server dimensions without external art or rendering."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    with tempfile.TemporaryDirectory(prefix='rmmo-body-policy-') as temporary:
        directory = Path(temporary)
        topology = directory/'assets/characters/base/female_base_v2/female_display_topology.json'
        topology.parent.mkdir(parents=True)
        topology.write_text(json.dumps({'points': [[0, 1.8, 0]] + [[0, 0, 0]]*21555}))
        morph = directory/'assets/characters/morphs/female_base_v2/source_native_01/height.json'
        morph.parent.mkdir(parents=True)
        morph.write_text(json.dumps({'id':'height', 'formulas':[], 'source':{'min':-1, 'max':1},
                                     'deltas':[{'vertex':0,'delta':{'x':0,'y':.4,'z':0}}]}))
        manifest = directory/'manifest.json'
        manifest.write_text(json.dumps([
            {'gender':'male','look_id':'1'},
            *[{'gender':'female','look_id':name,'body_shapes':{'height':value}}
              for name,value in [('short',-1),('normal',0),('tall',1)]]]))
        output = directory/'body-profiles.json'
        run = subprocess.run(['godot','--headless','--path',str(ROOT),'--script',
                              'res://tools/export_server_body_profiles.gd','--','--backend=real',
                              '--manifest='+str(manifest),'--output='+str(output),'--content-root='+str(directory)],
                             text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
        if run.returncode or 'ERROR:' in run.stdout:
            print(run.stdout)
            raise SystemExit(run.returncode or 1)
        profiles = json.loads(output.read_text())['profiles']
        for name,height in [('male/1',1.9),('female/short',1.8),('female/normal',1.88),('female/tall',2.1)]:
            assert abs(profiles[name]['height']-height)<1e-6, profiles
            assert profiles[name]['radius']==.3
        provenance = json.loads(Path(str(output)+'.sources.json').read_text())
        assert len(provenance['client_rule_sha256'])==64
        assert len(provenance['profiles_sha256'])==64
        print('PASS body export: default, morph, clamps, radius and provenance')

if __name__=='__main__':main()
