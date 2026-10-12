"""Guild plans: referenced ground floor plus proposed second-floor functions."""
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.patches import Rectangle, Circle, Arc, Polygon

OUT=Path(__file__).resolve().parents[1]/'docs/references/axel_guild_plan_20261007'
OUT.mkdir(parents=True,exist_ok=True)
font_manager.fontManager.addfont('C:/Windows/Fonts/msyh.ttc')
plt.rcParams.update({'font.family':'Microsoft YaHei','font.size':10,'svg.fonttype':'path'})
INK='#303f43'; PAPER='#f7f4ec'; HALL='#eee3cd'; EXTRA='#dce9eb'; WOOD='#ae8c62'; BLUE='#327d93'; RED='#ab604a'
def rect(a,x,y,w,h,fc='none',ec=INK,lw=1,**kw): a.add_patch(Rectangle((x,y),w,h,facecolor=fc,edgecolor=ec,lw=lw,**kw))
def line(a,xs,ys,c=INK,lw=1,**kw): a.plot(xs,ys,color=c,lw=lw,**kw)
def txt(a,x,y,s,size=10,c=INK,**kw): a.text(x,y,s,ha='center',va='center',fontsize=size,color=c,**kw)
def wall(a,x1,y1,x2,y2): line(a,[x1,x2],[y1,y2],lw=4)
def door(a,x,y,w=1.2):
    line(a,[x,x+w],[y,y],PAPER,6); line(a,[x,x],[y,y+w])
    a.add_patch(Arc((x,y),w*2,w*2,theta1=0,theta2=90,color=INK,lw=.7))
def dim(a,x1,y1,x2,y2,label):
    a.annotate('',(x1,y1),(x2,y2),arrowprops={'arrowstyle':'|-|','color':INK,'lw':.8})
    txt(a,(x1+x2)/2,(y1+y2)/2+.33,label,9,bbox={'facecolor':PAPER,'edgecolor':'none','pad':1})
def arrow(a,pts,c=BLUE):
    for p,q in zip(pts,pts[1:]): a.annotate('',q,p,arrowprops={'arrowstyle':'->','color':c,'lw':1.4})
def table(a,x,y,small=False):
    w=1.1 if small else 2.4
    rect(a,x-w/2,y-.4,w,.8,WOOD)
    for dy in [-.9,.65]: rect(a,x-w/2,y+dy,w,.25,'#cbb28b')
def base(title,sub,code,revision='v2'):
    f=plt.figure(figsize=(17,12),facecolor=PAPER)
    f.text(.04,.947,title,fontsize=23,color=INK,weight='bold')
    f.text(.04,.913,sub,fontsize=10,color=INK)
    f.text(.04,.03,f'RMMO / 2026-10-07 / {revision} / 尺寸与被遮挡部分为设计提案，不是官方测绘',fontsize=9,color=INK)
    f.text(.96,.03,code,fontsize=11,ha='right',color=INK)
    return f
def axes(f,box,xlim,ylim):
    a=f.add_axes(box); a.set_aspect('equal'); a.set_xlim(*xlim); a.set_ylim(*ylim); a.axis('off'); return a
def save(f,name):
    for ext in ['png','svg']: f.savefig(OUT/(name+'.'+ext),dpi=160,facecolor=PAPER)
    plt.close(f)
def outline(a):
    rect(a,0,0,32,14,HALL,lw=4)
    for x in [3.5,7,10.5,21.5,25,28.5]: line(a,[x-.6,x+.6],[0,0],'#77a2ad',3)
    for y in [3.5,6.5,9.5]:
        for x in [0,32]: line(a,[x,x],[y-.6,y+.6],'#77a2ad',3)
def stair(a,upper=False):
    rect(a,2.1,9.7,8.1,1.6,'#e2d0ae')
    for i in range(28): line(a,[2.1+i*.3]*2,[9.7,11.3],lw=.5)
    rect(a,.5,9.7,1.6,1.6,'#e2d0ae')
    arrow(a,[(1.3,10.5),(9.9,10.5)] if upper else [(9.9,10.5),(1.3,10.5)],INK)
    if upper:
        txt(a,9.3,8.95,'楼梯洞口\n下至首层',8)
    else:
        txt(a,4.1,9.05,'楼梯 → 回廊 +4.48 m',9)
def paragraphs(f,box,items,step=.26):
    a=f.add_axes(box); a.axis('off'); y=.98
    for title,body in items:
        a.text(0,y,title,fontsize=14,weight='bold',va='top',color=INK)
        a.text(0,y-.14,body,fontsize=10,va='top',color=INK,linespacing=1.8)
        y-=step

f=base('阿克塞尔冒险者公会 · 首层平面修订','A-01 | 横向长条主楼 32 × 14 m | 招募接待区保持开放 | 告警塔、警卫处见 A-03 独立总平面', 'A-01')
a=axes(f,[.04,.35,.92,.52],(-2,34),(-2.5,16)); outline(a)
rect(a,.7,4.5,.85,4.6,WOOD); txt(a,2.4,6.8,'07 酒吧\n酒桶 / 瓶架',9)
stair(a)
# Board mounted independently near the gallery/stair structure.
rect(a,1.2,13,3.6,.25,'#824f3c',ec='#b69a50',lw=2)
txt(a,3,14.7,'08 独立任务招募板',9)
txt(a,3,12.2,'回廊下 / 板前停留区',8)
for x,y in [(8,9.1),(16,9.5),(30.8,9.0)]: a.add_patch(Circle((x,y),.38,fc=WOOD,ec=INK))
for x in [13.8,18.2]: a.add_patch(Circle((x,1.15),.38,fc=WOOD,ec=INK))
for x,y in [(7,4.2),(11,4.2),(8,7.4),(11.5,7.4)]: table(a,x,y)
for x in [3.6,7,10.5]: table(a,x,1.6,True)
txt(a,9.5,5.8,'03 餐饮 / 组队区',10)
rect(a,14.9,6.4,2.2,2.2,'#bcbca8',lw=1.5); a.add_patch(Circle((16,7.5),.45,fc='#8b8c78',ec=INK))
for x in [13.65,18]: rect(a,x,6.6,.35,1.8,'#b8be89')
txt(a,16,9,'04 雕像＋双屏板',9)
for x,y in [(12.8,2.7),(19.2,2.7),(13.1,7.5),(19.2,7.5),(4.3,5.6),(30,3)]:
    rect(a,x-.16,y-.16,.32,.32,'#89958a'); a.add_patch(Circle((x,y),.12,fc='#faf1ae',ec=INK))
# Arched reception windows and continuous counter.
rect(a,19.5,10.8,12,2.7,EXTRA,ec='none'); wall(a,19.5,10.8,31.5,10.8)
rect(a,20,10.1,9.6,.7,WOOD)
for x in [21,23.3,25.6,27.9]:
    line(a,[x-.65,x+.65],[10.8,10.8],PAPER,6)
    line(a,[x-.65,x+.65],[10.6,10.6],BLUE,1.7)
door(a,30.1,10.8)
txt(a,25,12.4,'登记后台（深度推定）',9)
txt(a,25,9.3,'05 连排石拱窗＋长柜台',10)
a.add_patch(Circle((23.3,10.4),.22,fc='#27c5cf',ec=INK))
a.annotate('09 水晶登记装置（独立道具）',(23.3,10.4),(21.5,15),fontsize=9,color=INK,arrowprops={'arrowstyle':'->','lw':.7})
txt(a,25,5.7,'招募 / 登记开放区\n不摆餐桌',13)
for y in [3.8,6.4]:
    rect(a,30.4,y,.65,1.9,'#bfb79c'); line(a,[31.1,31.1],[y,y+1.9],WOOD,2)
txt(a,33,6,'窗下\n长椅',8)
rect(a,30.1,9.5,1.2,.55,'#6d8e68'); txt(a,32.8,10,'植物箱',8)
for x,y in [(20,8.5),(29.3,8.5)]: rect(a,x,y,.8,.22,'#d5ccb7')
txt(a,21,7.8,'06 告示牌',8)
line(a,[14.4,17.6],[0,0],PAPER,7)
for x,ang in [(14.4,0),(17.6,90)]:
    a.add_patch(Arc((x,0),3.2,3.2,theta1=ang,theta2=ang+90,color=INK,lw=.7)); line(a,[x,x],[0,1.6])
rect(a,12.5,-1.6,7,1.6,'#e3dfd4'); txt(a,16,-.8,'01 双扇主门 3.2 m',9)
arrow(a,[(16,-2),(16,3.7),(20,5),(24,7.5)])
txt(a,16,4.6,'02 地毯主轴',9)
dim(a,0,-2,32,-2,'32.00 m · 临街正面'); dim(a,-1.3,0,-1.3,14,'14.00 m')
paragraphs(f,[.055,.085,.285,.23],[('本版空间依据','长条主楼取自 U00 / U13。\n酒吧、楼梯、局部回廊是一组空间。\n接待端取自 U08 / U12：柜台前留空，\n相邻窗下放长椅，角落放植物箱。')])
paragraphs(f,[.375,.085,.27,.23],[('独立道具与尺寸','招募板、水晶装置与建筑分离。\n主体 448 m²；主通道按 ≥2.4 m 预留。\n楼梯净宽1.6 m，28级×0.16 m；\n实际水平跑长8.1 m，不用短梯替代。')])
paragraphs(f,[.695,.085,.27,.23],[('尚未确定的部分','左右方位与局部距离仍为复原提案。\n蓝色区是不可见后台的设计补全。\n图纸不是正式施工或通行验收。\n三处建筑不以本图新建连廊相接。')])
save(f,'01_ground_floor')

GUEST='#e9dcca'; OFFICE='#dce9eb'; CORRIDOR='#e6dfc8'; VOID='#f7f6f1'
def vdoor(a,x,y,w=1.0,right=True):
    line(a,[x,x],[y,y+w],PAPER,6)
    dx=w if right else -w
    line(a,[x,x+dx],[y,y])
    a.add_patch(Arc((x,y),2*w,2*w,theta1=0 if right else 90,theta2=90 if right else 180,color=INK,lw=.65))
def room(a,x,y,w,h,label,fill=OFFICE,label_y=None):
    rect(a,x,y,w,h,fill,lw=1.2)
    txt(a,x+w/2,label_y if label_y is not None else y+h/2,label,9,
        bbox={'facecolor':fill,'edgecolor':'none','pad':1.5})
def bed(a,x,y):
    rect(a,x,y,.95,2.0,'#f5f1e7',lw=.7); rect(a,x+.07,y+1.58,.81,.32,'#d8dce0',lw=.5)
def shelf(a,x,y,w): rect(a,x,y,w,.35,WOOD,lw=.6)

f=base('阿克塞尔冒险者公会 · 二楼功能规划','A-02 | 用户要求补全二楼，包含客房 | 整层功能与新增楼板均为设计提案，不是动画已确认布局', 'A-02','v3')
a=axes(f,[.04,.34,.92,.52],(-2,34),(-2.5,16)); outline(a)
# Two occupied ends linked only at the back: the central hall remains open.
rect(a,.5,.5,31,13,VOID,ec='none')
rect(a,.5,.5,6.5,13,CORRIDOR,ec='none')
rect(a,7,11.5,15,2,CORRIDOR,ec='none')
rect(a,22,.5,9.5,13,CORRIDOR,ec='none')
rect(a,7,.5,15,11,VOID,ec=INK,lw=1.2)
txt(a,14.5,5.9,'大厅挑空 15 × 11 m\n保留入口、雕像与悬挂骨架上方空间',13)
# First-floor objects projected lightly for orientation.
rect(a,14.9,6.4,2.2,2.2,'none',ec='#c5c8ba',lw=.6,ls='--')
txt(a,16,7.5,'下方雕像',8,c='#a2a793')
txt(a,16,-.9,'临街正面 / 一楼主门在下方中央',10)
# West wing: rooms reached from a 1.6 m corridor along the outside wall.
room(a,2.3,.5,4.5,4.2,'01 小议事室\n约18.9 m²',label_y=1.65)
rect(a,3.4,2.7,2.2,.8,WOOD)
for x in [3.7,4.5,5.3]:
    for y in [2.25,3.75]: rect(a,x-.13,y,.26,.26,'#b8a78a',lw=.5)
room(a,2.3,4.9,4.5,4.3,'02 公会办公室\n约19.4 m²',label_y=6.3)
rect(a,4.1,7.5,1.8,.8,WOOD); shelf(a,2.6,8.6,3.7)
rect(a,6.05,5.2,.5,2.0,WOOD,lw=.7)
vdoor(a,2.3,1.1,right=True); vdoor(a,2.3,5.4,right=True)
txt(a,1.25,4.3,'1.6 m\n通道',8)
stair(a,True)
for y in [9.7,11.3]: line(a,[2.1,7],[y,y],BLUE,1.2)
line(a,[7,7],[.5,9.7],BLUE,1.7); line(a,[7,7],[11.3,11.5],BLUE,1.7)
line(a,[7,22],[11.5,11.5],BLUE,1.7)
txt(a,4.8,12.65,'03 楼梯厅 / 档案柜',8)
shelf(a,2.5,13,3.6)
txt(a,14,12.85,'后侧回廊 / 净宽 2.0 m / +4.48 m',9)
arrow(a,[(1.3,10.6),(1.3,12.05),(21,12.05),(26.4,12.05),(26.4,1.3)])
# East wing guest rooms: clear dimensions, 0.2 m dividing walls and 2 m hall.
for y,num in [(.5,'201'),(4.8,'202')]:
    room(a,22,y,3.2,4.1,f'{num} 单人客房\n约13.1 m²',GUEST,label_y=y+1.0)
    bed(a,22.35,y+1.8); shelf(a,24,y+3.55,.8)
    vdoor(a,25.2,y+.55,right=False)
for y,num in [(.5,'203'),(4.8,'204')]:
    room(a,27.6,y,3.9,4.1,f'{num} 双人客房\n约16.0 m²',GUEST,label_y=y+.95)
    bed(a,28.1,y+1.8); bed(a,30.1,y+1.8)
    vdoor(a,27.6,y+.45,right=True)
room(a,22,9.1,3.2,2.2,'04 布草 / 清洁\n约7.0 m²',label_y=10.2)
vdoor(a,25.2,9.65,right=False)
room(a,27.6,9.1,3.9,4.4,'05 共用盥洗',label_y=11.05)
vdoor(a,27.6,9.5,right=True)
# Fixtures are schematic; the wet-room layout is explicit, not guest furniture.
for x in [27.8,29.7]:
    rect(a,x,11.9,1.6,1.35,'#cadbdc',lw=.65)
txt(a,28.6,12.55,'淋浴',8); txt(a,30.5,12.55,'厕位',8)
rect(a,29.5,9.45,1.7,.55,'#adc9ca',lw=.6); txt(a,30.35,9.73,'洗手台',7)
txt(a,26.4,7.2,'客房走廊\n2.0 m',8,rotation=90)
dim(a,0,-2,32,-2,'32.00 m'); dim(a,-1.3,0,-1.3,14,'14.00 m')
paragraphs(f,[.05,.075,.285,.23],[('客房配置：4间 / 6床位','2间单人房＋2间双床房。\n共用盥洗，单独布草清洁间。\n办公室内设职员休息长凳，\n楼梯厅设带锁档案柜。')])
paragraphs(f,[.37,.075,.285,.23],[('楼板与一楼关系','保留左端回廊，新增后侧通道和右端楼板。\n中央挑空名义范围165 m²。\n右端楼板覆盖部分一楼接待区，\n需要你确认这一取舍。')])
paragraphs(f,[.695,.075,.27,.23],[('尚待建模验证','房间用途和尺寸均为本轮补全。\n楼梯口、门扇、梁柱与坡顶净空待检查。\n给排水优先沿右外墙集中预留。\n客房采光需配合老虎窗再校准。')])
save(f,'02_gallery_section')

# A separate section makes the lower ceiling over reception reviewable.
f=base('公会二楼 · 新增楼板与一楼空间关系','A-04 | 二楼层面 +4.48 m | 沿建筑长轴展开，坡屋面和梁柱为示意投影', 'A-04','v3')
s=axes(f,[.055,.35,.88,.5],(-1.5,35),(-1.5,16.5))
rect(s,0,0,32,.25,'#a2aaa1'); rect(s,0,0,32,6.6,'none',lw=1)
rect(s,.5,4.23,6.5,.25,WOOD); rect(s,22,4.23,9.5,.25,WOOD)
for x in [7,22]: line(s,[x,x],[4.48,5.58],BLUE,1.5)
line(s,[0,32],[14,14],RED,3); line(s,[0,0],[6.6,14],RED,2); line(s,[32,32],[6.6,14],RED,2)
line(s,[2.1,10.2],[4.48,0],WOOD,2)
rect(s,14.9,0,2.2,1.2,'#c1c2af'); rect(s,15.5,1.2,1,3,'#a2ab99')
txt(s,4,7.3,'议事 / 办公',11); txt(s,27,7.3,'客房 / 盥洗',11)
txt(s,15,9,'中央挑空\n悬挂骨架、织物保留',13)
line(s,[11,20],[11.8,11.8],INK,1.2,ls='--')
txt(s,3.8,1.6,'一楼酒吧端',10); txt(s,27,1.6,'一楼接待区\n部分顶面降至约4.23 m',10)
txt(s,33.5,4.48,'+4.48',9); txt(s,33.5,0,'±0.00',9)
txt(s,16,-.9,'主楼长轴 32 m / 构件投影与承重落点待灰盒复核',10)
paragraphs(f,[.06,.10,.39,.21],[('保留的空间','中央挑空和原有楼梯位置保留。\n后侧2m回廊只连接两端，不绕成完整一圈。\n一楼餐饮和接待的平面用途保持。')])
paragraphs(f,[.53,.10,.4,.21],[('本提案新增的代价','右端客房需要新的楼板和承重方案。\n接待区不再全部直接通到屋顶，需联合确认。\n盥洗水路、门窗和坡顶净空尚未进行引擎验证。')])
save(f,'04_upper_floor_section')

f=base('公会 · 告警塔 · 警卫处 / 三者总平面关系','A-03 | 以用户鸟瞰图 U13 为主要依据 | 仅表达分离与相邻关系，建筑间距、塔脚位置和地理朝向不作测绘结论', 'A-03')
a=axes(f,[.04,.16,.54,.69],(-5,40),(-5,51))
rect(a,-3,-3,40,51,'#e7ecda',ec='none')
rect(a,-2,15,37,8,'#eee6d3',ec='none')
rect(a,17,22,8,24,'#eee6d3',ec='none')
rect(a,0,0,32,14,'#d5b190',lw=2); line(a,[0,32],[7,7],RED,2)
txt(a,16,7,'冒险者公会\n独立长条主楼\n拟定32 × 14 m',12)
line(a,[14.4,17.6],[0,0],PAPER,5); txt(a,16,-2,'主入口 / 前场',9)
rect(a,2,25,13,10,'#d2d2bd',lw=1.5); line(a,[2,15],[30,30],RED,2)
txt(a,8.5,30,'警卫处\n独立建筑',11)
a.add_patch(Circle((23,42),3,fc='#bdced0',ec=INK,lw=1.7))
a.add_patch(Circle((23,42),2.2,fill=False,ec=INK,lw=.8))
txt(a,23,48,'告警塔 / 独立塔体',11)
txt(a,16,19,'街巷与开放空地 / 不画连廊',10)
txt(a,32,32,'周边建筑\n位置简化',9)
line(a,[9,9],[35,42],INK,.8,ls=':'); line(a,[9,19.8],[42,42],INK,.8,ls=':')
txt(a,5,40,'后方\n街区',9)
paragraphs(f,[.63,.53,.33,.31],[('取代上一版的判断','公会、警卫处、告警塔分成三处体量。\n告警塔位于后方街区，不落在公会屋顶。\n撤销“公会后墙短通道直连塔”的推定。\n警卫处内部与塔门朝向仍需更多镜头。\n图中位置为关系示意，不据模糊影像量距。')])
paragraphs(f,[.63,.19,.33,.28],[('与首层图的对接','公会建筑坐标只用于本次室内方案。\n外部关系图的上下左右沿鸟瞰阅读方向，\n不等同游戏世界的正北或精确朝向。\n后续部署需要地块、道路与镜头共同校准。\n原图及红色标注已逐字节保存为 U13。')])
save(f,'03_site_relationship')
print(OUT)
