"""Synthetic policy and gameplay records in a disposable content copy only."""
import json

NS='11111111-1111-4111-8111-111111111111:92205a4714219670:'
NPC=NS+'00000000-0000-4000-8000-000000000005'
HERB=NS+'00000000-0000-4000-8000-000000000001'
POTION=NS+'00000000-0000-4000-8000-000000000002'
SWORD=NS+'00000000-0000-4000-8000-00000000000c'
QUEST=NS+'00000000-0000-4000-8000-000000000f01'
DUMMY=NS+'00000000-0000-4000-8000-000000000f02'
KILLER=NS+'00000000-0000-4000-8000-000000000f03'
HEAL=NS+'7de8d659-52d1-4d13-81fd-a72b5c5ad031'
STRIKE=NS+'935ae5bb-e846-44ca-9f8a-90f9aa2f5161'

def write_rows(path,rows):
    path.write_text('\n'.join(json.dumps(row,ensure_ascii=False) for row in rows)+'\n')

def configure(content,directory):
    pack=content/'packs/tutorial/gameplay'
    rows=[json.loads(line) for line in (pack/'npcs.jsonl').read_text().splitlines()]
    header=rows[0]
    rows[1].pop('ai',None)
    rows[1]['quests']=[QUEST]
    write_rows(pack/'npcs.jsonl',rows)
    write_rows(pack/'integration_quests.jsonl',[dict(header,kind='quests'),{
        'uuid':QUEST,'name':'Integration dialogue quest',
        'objectives':[{'id':'talk','kind':'talk','target':NPC,'count':1}],
        'items':[{'item':HERB,'qty':4},{'item':POTION,'qty':2},{'item':SWORD,'qty':1}], 'gold':100}])
    write_rows(pack/'integration_monsters.jsonl',[dict(header,kind='monsters'),
        {'uuid':DUMMY,'name':'Integration dummy','level':1,'hp_max':30,'attack':0,'defense':0,'respawn_seconds':60,'loot':[{'item':HERB,'min':1,'max':1,'chance':1}]},
        {'uuid':KILLER,'name':'Integration death source','level':1,'hp_max':1000,'attack':200,'defense':0,
         'aggressive':True,'ai':{'sight_m':1.5,'attack_range_m':1.5,'speed_mps':1,'attack_interval_seconds':.2}}])
    rows=[json.loads(line) for line in (pack/'spawns.jsonl').read_text().splitlines()]
    rows += [{'uuid':NS+'00000000-0000-4000-8000-000000000f12','map':'yard','kind':'monsters','definition':DUMMY,'position_m':{'x':0,'y':0,'z':6}},
             {'uuid':NS+'00000000-0000-4000-8000-000000000f13','map':'yard','kind':'monsters','definition':KILLER,'position_m':{'x':-6,'y':0,'z':4}}]
    write_rows(pack/'spawns.jsonl',rows)
    map_path=content/'packs/tutorial/maps/yard/map.gltf'
    document=json.loads(map_path.read_text())
    document['nodes'][0]['extras']['rmmo_records'].append({
        'uuid':'integration-door','kind':'box','position':[1,1,2.5],
        'size':[.8,2,.12],'rotation':[0,0,0],
        'building':{'id':'integration-building','part':'door'},
        'fixture':{'id':'gate','kind':'door','pivot':[-.4,0,0],'angle':90,'open':0}})
    document['nodes'][0]['extras']['rmmo_records'].append({
        'uuid':'integration-window','kind':'box','position':[1.8,1.5,2.5],
        'size':[.5,.7,.1],'rotation':[0,0,0],
        'building':{'id':'integration-building','part':'window'},
        'fixture':{'id':'casement','kind':'window','pivot':[-.25,0,0],'angle':90,'open':0}})
    document['nodes'][0]['extras']['building_instances']={'integration-building':{'parts':{'door':'integration-door','window':'integration-window'}}}
    map_path.write_text(json.dumps(document))
    # Prices, grants and dimensions are trusted startup policy, not client claims.
    vendors=directory/'vendors.json'
    vendors.write_text(json.dumps({'$schema':'rmmo.vendors/v1','vendors':{NPC:{'name':'Integration shop','buyback_limit':8,'offers':[{'item':HERB,'price':5}]}}}))
    bodies=directory/'body-profiles.json'
    bodies.write_text(json.dumps({'$schema':'rmmo.body-profiles/v1','profiles':{'male/1':{'radius':.3,'height':2.05}}}))
    housing=directory/'housing.json'
    housing.write_text(json.dumps({'$schema':'rmmo.housing/v1','houses':[{
        'id':'integration-home','name':'共享测试住宅','map':'tutorial/yard','building':'integration-building',
        'kind':'personal','owner':'1','entrances':['gate'],
        'bounds':[{'min':[-.2,0,-.1],'max':[2.2,3,2.8]}]}]}))
    return ['-housing',str(housing),'-vendors',str(vendors),'-body-profiles',str(bodies),'-starter-skills',','.join([HEAL,STRIKE])]
