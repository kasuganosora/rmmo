"""Dimensioned plan/section from the latest whitebox, not an illustration."""
import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, Polygon
from matplotlib import font_manager

BASE=Path(__file__).resolve().parents[1]
OUT=BASE/'docs/references/axel_guild_plan_20261007'
DATA=json.loads((BASE.parent/'rmmo_runtime/art_sources/axel_guild/whitebox_v3/manifest.json').read_text(encoding='utf8'))
font_manager.fontManager.addfont('C:/Windows/Fonts/msyh.ttc')
plt.rcParams.update({'font.family':'Microsoft YaHei','svg.fonttype':'path','font.size':10})
PAPER='#f7f4ec';INK='#263b43';BLUE='#2c738b';LIGHT='#dce8e9';WOOD='#cdb797'

def box(a,x,y,w,h,color=LIGHT,lw=1):
    a.add_patch(Rectangle((x,y),w,h,facecolor=color,edgecolor=INK,lw=lw))
def text(a,x,y,t,fs=10,c=INK):a.text(x,y,t,ha='center',va='center',fontsize=fs,color=c)
def dim(a,p,q,label,offset=(0,0)):
    a.annotate('',q,p,arrowprops={'arrowstyle':'|-|','color':BLUE})
    text(a,(p[0]+q[0])/2+offset[0],(p[1]+q[1])/2+offset[1],label,9,BLUE)
def canvas(title,subtitle):
    f=plt.figure(figsize=(16,11),facecolor=PAPER)
    f.text(.045,.94,title,fontsize=23,weight='bold',color=INK)
    f.text(.045,.9,subtitle,fontsize=10,color=INK)
    f.text(.045,.035,'RMMO / 2026-10-07 / v4：第三人称专项调整 / 尺寸为游戏提案，非动画官方测绘',fontsize=9,color=INK)
    return f
def ax(f,rect,limits):
    a=f.add_axes(rect);a.set_aspect('equal');a.set_xlim(*limits[0]);a.set_ylim(*limits[1]);a.axis('off');return a
def save(f,name):
    for ext in ['png','svg']:f.savefig(OUT/(name+'.'+ext),dpi=160,facecolor=PAPER)
    plt.close(f)

f=canvas('公会 · 二楼通行尺寸与剖面','A-05 | 保留 32 × 14 m 外轮廓、4 间客房 / 6 个床位；扩大通路、门洞和楼梯平台')
a=ax(f,[.045,.4,.91,.46],((-1,34),(-1,16)))
box(a,0,0,32,14,'#ebe5d6',2.5)
box(a,7.4,.5,14.35,10.5,PAPER,1)
text(a,14.575,4.8,'中央挑空\n名义 150.7 m²\n楼梯下段局部投影在其中',12)
names={'01 MEETING':'议事室','02 OFFICE':'公会办公室','201 SINGLE':'201 单床房','202 SINGLE':'202 单床房',
       '203 TWIN':'203 双床房','204 TWIN':'204 双床房','04 LINEN':'布草间','05 WASHROOM':'共用盥洗'}
for r in DATA['rooms']:
    x0,x1,y0,y1=r['bounds'];box(a,x0,y0,x1-x0,y1-y0,LIGHT)
    area=(x1-x0)*(y1-y0)
    text(a,(x0+x1)/2,(y0+y1)/2,names[r['code']]+f'\n{area:.1f} m²',9)
    x,y,w=r['door'];a.plot([x,x],[y,y+w],color=PAPER,lw=5)
    sign=1 if r['door_side']=='left' else -1
    if r['code']=='04 LINEN':
        for yy in [y-.06,y+w+.06]:a.plot([x,x+sign*.4],[yy,yy],color=BLUE,lw=1)
    else:a.plot([x+sign*.07]*2,[y+w,y+2*w-.02],color=BLUE,lw=1)
box(a,3,8.95,8.1,2,WOOD)
for i in range(28):a.plot([3+i*.3]*2,[8.95,10.95],color=INK,lw=.4)
box(a,.5,8.95,2.5,2,WOOD)
a.annotate('',(10.8,9.95),(1.7,9.95),arrowprops={'arrowstyle':'->','color':INK})
text(a,8,8.3,'楼梯净宽 2.0 m / 28 × 0.16 m',9)
text(a,1.75,11.45,'上平台深 2.5 m',8)
text(a,16,12.25,'后回廊有效净宽约 2.46 m',10)
dim(a,(.5,6),(2.9,6),'2.4 m',(0,-.45))
dim(a,(25.2,7),(27.6,7),'2.4 m',(0,-.5))
dim(a,(0,15),(32,15),'32 m',(0,.45))
dim(a,(33,0),(33,14),'14 m',(.0,0))

b=ax(f,[.045,.10,.50,.265],((-1,15),(-.4,15)))
box(b,0,-.3,14,.3,'#a2aaa6')
for x in [0,13.5]:box(b,x,0,.5,8.2,'#b9c2bb')
box(b,.5,4.23,13,.25,'#a2aaa6')
box(b,.5,8.08,13,.2,'#a2aaa6')
b.plot([-.45,7,14.45],[8.2-.45*5.8/7,14,8.2-.45*5.8/7],color=INK,lw=3)
box(b,.55,8.34,12.9,.22,WOOD)
text(b,7,11.3,'端部客房翼剖面\n屋架移到天花上方',9)
text(b,7,2.1,'首层板底 4.23 m\n局部梁下 3.91 m',9)
dim(b,(4.5,4.48),(4.5,8.08),'净高 3.6 m',(2,0))
text(b,11.7,4.8,'+4.48',8)
text(b,12.1,8.7,'檐口 8.2',8)
text(b,7,14.5,'屋脊 14 m 保留',8)
f.text(.55,.34,'第三人称专项尺寸',fontsize=14,weight='bold',color=INK)
f.text(.55,.30,'门洞 1.6 × 3.0 m；门扇贴墙停放，避免挡镜\n房间及主通道天花净高 3.60 m\n楼梯 2.0 m 宽，踏步 0.16 × 0.30 m\n默认室内镜头臂长 3.2 m，碰撞球半径 0.2 m\n侧向或大俯角转镜时仍会按墙顶自动收近',fontsize=11,linespacing=1.8,color=INK,va='top')
save(f,'05_third_person_clearance')

f=canvas('公会 · 首层楼梯与接待通路修订','A-06 | 白模 v3：雕像两侧改为独立薄装饰板；二楼楼板投影用虚线标示')
a=ax(f,[.045,.29,.91,.56],((-1,34),(-3,16)))
box(a,0,0,32,14,'#ebe5d6',2.5)
for x,y,w,h in [(.5,.5,6.9,13),(21.75,.5,9.75,13),(7.4,11,14.35,2.5)]:
    a.add_patch(Rectangle((x,y),w,h,fill=False,edgecolor=BLUE,lw=1.4,linestyle='--'))
box(a,3,8.95,8.1,2,WOOD)
for i in range(28):a.plot([3+i*.3]*2,[8.95,10.95],color=INK,lw=.4)
a.annotate('',(3.1,9.95),(11,9.95),arrowprops={'arrowstyle':'->','color':INK})
text(a,6.8,11.6,'楼梯上行 → +4.48 m',9)
for x,y in [(7,4.2),(11,4.2),(8,7.4),(11.1,7.4),(3.6,1.6),(7,1.6),(10.5,1.6)]:
    w=1.1 if y==1.6 else 2.4
    box(a,x-w/2,y-.4,w,.8,WOOD)
    for yy in [y-.94,y+.66]:box(a,x-w/2,yy,w,.28,WOOD)
box(a,.675,4.5,.85,4.6,WOOD);text(a,2.45,6.2,'酒吧',10)
box(a,14.9,6.4,2.2,2.2,'#bbc3af');text(a,16,7.5,'雕像',9)
for x,y,z in DATA['decorative_panels']['locations_blender']:box(a,x-.54,y-.05,1.08,.10,'#b5bdae')
text(a,16,10.1,'独立装饰板，非墙体',8)
box(a,20,10.02,9.1,.8,WOOD);text(a,24.5,11.9,'登记柜台 / 4 个拱窗',9)
a.plot([29.7,31.3],[10.9,10.9],color=BLUE,lw=3);text(a,30.5,12.0,'后台门\n1.6 m',8)
box(a,1.2,12.69,3.6,.22,'#ae9286');text(a,3,14.7,'独立任务板',9)
box(a,12.6,-1.2,6.8,1.2,'#c4c8bb');text(a,16,-2,'主入口 3.2 m',10)
path=[(16,-1.2),(16,3.5),(14.45,4.8),(14.45,9.95),(11.5,9.95)]
for p,q in zip(path,path[1:]):a.annotate('',q,p,arrowprops={'arrowstyle':'->','color':BLUE,'lw':1.3})
text(a,25,5,'开放招募 / 等候区',12)
f.text(.055,.19,'保持：长条外轮廓、中央挑空、登记区、餐饮区、任务板与雕像位置关系。',fontsize=12,color=INK)
f.text(.055,.14,'调整：楼梯加宽并移位；接待后台门加大，柜台缩短留出入口，角落植物箱移至后台侧。',fontsize=11,color=INK)
f.text(.055,.09,'变化代价：挑空名义面积由 165 降为约 150.7 m²；客房面积略调整，床位数量不变。',fontsize=11,color=INK)
save(f,'06_ground_floor_clearance')
print('Saved A-05 / A-06 PNG and SVG')
