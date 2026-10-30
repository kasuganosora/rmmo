"""Skill/attribute acceptance content; only writes the runner's temporary copy."""
import json
from real_gameplay_fixture import NS, QUEST, NPC, write_rows

HEAL=NS+'00000000-0000-4000-8000-00000000f101'
DEPENDENT=NS+'00000000-0000-4000-8000-00000000f102'
PASSIVE=NS+'00000000-0000-4000-8000-00000000f103'
BUFF=NS+'00000000-0000-4000-8000-00000000f104'
BURST=NS+'00000000-0000-4000-8000-00000000f105'
REVIVE=NS+'00000000-0000-4000-8000-00000000f106'
HURT=NS+'00000000-0000-4000-8000-00000000f111'
KILLER=NS+'00000000-0000-4000-8000-00000000f112'

def configure(content,directory):
    pack=content/'packs/tutorial/gameplay'
    header=json.loads((pack/'skills.jsonl').read_text().splitlines()[0])
    def skill(uuid,name,mode,relation,effects,mp=0):
        return {'uuid':uuid,'name':name,'description':'Disposable real-client acceptance fixture',
                'target':{'mode':mode,'relation':relation,'range_m':30 if mode=='unit' else 0,'line_of_sight':True},
                'timing':{'cast_ms':0,'recovery_ms':0,'cooldown_ms':0,'gcd_group':'','gcd_ms':0},
                'cost':{'mp':mp},'conditions':{'allow_airborne':True,'interrupt_on_move':True},'effects':effects}
    rows=[header,
          skill(HEAL,'Learned party heal','unit','party',[{'type':'heal_hp','base':20,'formula':{'version':1,'channel':'healing'}}],2),
          skill(DEPENDENT,'Dependent strike','unit','hostile',[{'type':'damage','base':20}]),
          skill(PASSIVE,'Guard training','self','self',[{'type':'heal_hp','base':2}]),
          skill(BUFF,'Battle stance','self','self',[{'type':'status','status':{
              'key':'battle_stance','kind':'modifiers','duration_ms':10000,'interval_ms':0,'stacking':'refresh','max_stacks':1,'base':0,
              'policy':{'group':'stance','strength':2,'class':'buff','dispel_category':'magic','cancel':'allow'},
              'modifiers':{'flat':{'attack':20,'defense':-5,'magic_attack':10},'percent_bp':{'attack':1000},'move_speed_bp':2000}}}]),
          skill(BURST,'Fixture finisher','unit','hostile',[{'type':'damage','base':2000,'formula':{'version':1,'channel':'fixed','hit_chance_bp':10000}}]),
          skill(REVIVE,'Party resurrection','unit','party',[{'type':'resurrect','resurrect':{'hp_bp':5000,'mp_bp':2500}}])]
    write_rows(pack/'integration_skill_system.jsonl',rows)
    npc_header=json.loads((pack/'integration_monsters.jsonl').read_text().splitlines()[0])
    write_rows(pack/'integration_monsters.jsonl',[npc_header,
        {'uuid':HURT,'name':'Sparring source','level':1,'hp_max':100,'attack':20,'defense':0,'respawn_seconds':600,'aggressive':True,
         'ai':{'sight_m':1.6,'attack_range_m':1.6,'speed_mps':.1,'attack_interval_seconds':1}},
        {'uuid':KILLER,'name':'Resurrection source','level':1,'hp_max':100,'attack':1000,'defense':0,'respawn_seconds':600,'aggressive':True,
         'ai':{'sight_m':1.6,'attack_range_m':1.6,'speed_mps':.1,'attack_interval_seconds':1}}])
    spawns=[json.loads(line) for line in (pack/'spawns.jsonl').read_text().splitlines()]
    spawns=[row for row in spawns if '$schema' in row or row.get('kind')=='npcs']
    spawns += [{'uuid':NS+'00000000-0000-4000-8000-00000000f121','map':'yard','kind':'monsters','definition':HURT,'position_m':{'x':-5,'y':0,'z':6}},
               {'uuid':NS+'00000000-0000-4000-8000-00000000f122','map':'yard','kind':'monsters','definition':KILLER,'position_m':{'x':-10,'y':0,'z':6}}]
    write_rows(pack/'spawns.jsonl',spawns)
    quests=[json.loads(line) for line in (pack/'integration_quests.jsonl').read_text().splitlines()]
    for row in quests:
        if row.get('uuid')==QUEST:row['experience']=100
    write_rows(pack/'integration_quests.jsonl',quests)
    training=directory/'skill-training.json'
    training.write_text(json.dumps({'version':1,'initial_points':8,'points_per_level':2,'respec_gold':7,'attribute_respec_gold':3,'entries':[
        {'skill_uuid':HEAL,'category':'magic','ranks':[{'level':1,'sp':1,'gold':2},{'level':1,'sp':2,'gold':3,'modifiers':{'healing_bp':5000,'mp_cost_reduction_bp':1000}}]},
        {'skill_uuid':DEPENDENT,'category':'physical','ranks':[{'level':1,'sp':1,'gold':1,'requires':[{'skill_uuid':HEAL,'rank':2}]}]},
        {'skill_uuid':PASSIVE,'category':'passive','ranks':[{'level':1,'sp':1,'gold':1,'passives':[{'key':'training_guard','trigger':'take_damage','cooldown_ms':1000,'effects':[{'type':'heal_hp','base':2}]}]}]}]}))
    return ['-skill-training',str(training),'-starter-skills',','.join([BUFF,BURST,REVIVE])]
