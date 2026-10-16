"""Isolated receipt-chain regression; never opens or edits a map."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
from prepare_axel_layout_acceptance import Assembly


def run():
    with tempfile.TemporaryDirectory(prefix='axel_history_') as directory:
        out=Path(directory); history=out/'fortification_history';history.mkdir()
        formal=out/'formal.gltf';candidate=out/'candidate.gltf';baseline='a'*64
        def freeze(value):
            raw=json.dumps(value,sort_keys=True).encode();digest=hashlib.sha256(raw).hexdigest()
            p=history/(digest+'.json');p.write_bytes(raw)
            return {'path':str(p),'sha256':digest}
        initial={'saved':True,'apply':True,'failures':0,'source':str(formal),'source_sha256':baseline,
                 'candidate':str(candidate),'candidate_sha256':'b'*64,'phase':'native_candidate_complete_review_pending',
                 'operations':[{'tool':'set_object_transform','request':{'id':'grass'}}], 'plan_sha256':'c'*64}
        initial_desc=freeze(initial)
        def append(previous,output,alter=None):
            prev=freeze(previous)
            proof={'saved':True,'apply':True,'failures':0,'native_reopen_passed':True,
                   'phase':'native_fortification_regeneration_complete_review_pending',
                   'previous_build':prev,'previous_build_sha256':prev['sha256'],'initial_build':initial_desc,
                   'input_sha256':previous['candidate_sha256'],'output_sha256':output,'source':str(formal),
                   'source_sha256':baseline,'map':str(candidate),'method':'native whole-group replacement',
                   'transaction':dict.fromkeys(('undo_passed','redo_passed','save_reopen'),True),
                   'preservation':dict.fromkeys(('non_fortification_records_identical','non_fortification_metadata_identical','component_ids_stable'),True),
                   'operations':[{'tool':x,'request':{'keep_objects':False},'result':{'ok':True}} for x in
                                 ('remove_fortification','preview_fortification','generate_fortification')],
                   'frozen_comparison':[{'non_tangent_data_identical':True,'invalid_after':0,'valid_tangents_changed':0}],
                   'inputs':{'obsolete/mutable/map.gltf':'old','obsolete/fortification_build.json':'old'}}
            if alter:alter(proof)
            desc=freeze(proof);result=copy.deepcopy(previous)
            result.update(initial_build=initial_desc,candidate_sha256=output,latest_regeneration=desc)
            result.setdefault('regenerations',[]).append(dict(desc,input_sha256=proof['input_sha256'],output_sha256=output,method=proof['method']))
            return result
        def accepted(value):
            a=Assembly(out,formal,candidate);a.fortification_history(value,baseline);return not a.errors
        one=append(initial,'d'*64);two=append(one,'e'*64)
        checks={
            'legacy unchanged':accepted(initial),
            'one native regeneration':accepted(one),
            'two append-only regenerations, historical mutable inputs ignored':accepted(two),
            'failed save rejected':not accepted(append(initial,'d'*64,lambda p:p.update(saved=False))),
            'broken SHA chain rejected':not accepted(append(initial,'d'*64,lambda p:p.update(input_sha256='f'*64))),
            'geometry modification rejected':not accepted(append(initial,'d'*64,lambda p:p['frozen_comparison'][0].update(non_tangent_data_identical=False))),
            'missing preservation rejected':not accepted(append(initial,'d'*64,lambda p:p.update(preservation={}))),
        }
        changed=copy.deepcopy(two);changed['operations']=[]
        checks['original grass operations cannot be erased']=not accepted(changed)
        changed=copy.deepcopy(two);changed['regenerations']=changed['regenerations'][1:]
        checks['history prefix cannot be omitted']=not accepted(changed)
        changed=copy.deepcopy(two);changed['candidate_sha256']='f'*64
        checks['latest output cannot drift']=not accepted(changed)
        for name,ok in checks.items():print(('PASS ' if ok else 'FAIL ')+name)
        assert all(checks.values())
        print('FORTIFICATION_HISTORY',len(checks),'PASS / 0 FAIL')
if __name__=='__main__':run()
