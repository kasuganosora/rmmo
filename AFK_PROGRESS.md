# AFK 交接备忘（box `/workspace/rmmo`）


## Review-fix pass (2026-09-18)

- **Loot roll client**: `world.gd` handles `loot_roll_start`/`choice`/`resolve`; HUD 需求/贪婪/放弃 → `request_loot_roll` → `MockServer.try_loot_roll` (playable in-game).
- **Ally corpse**: `_damage_npc` keeps ally (kind/faction/`ally`) at hp=0 + `awaiting_respawn`; hostiles still removed. Kill→revive covered in `test_revive`.
- **skills.json**: `data/combat` ↔ `scripts/net/combat/data` synced (anims from scripts copy).
- **AoE weapon wear**: once per cast (`wear_first`); smoke in `test_weapon_durability`.
- **Missing/dead target**: Chinese fail msgs (not empty actions).
- **Mount while dead**:「你已经倒下了。」
- **Interrupt cast cancel**: one interrupt toast (silence still applied, no double spam).
- **Execute/charge**: success toast only on hit; charge re-checks landing occupancy at apply.
- **Status refresh**: preserves `tick_acc`; `tick_hp × stacks` on tick.
- **Buyback**: keep on shop close; clear on map transfer / ring overwrite only.
- **NPC cast aim**: cast aim freezes for the cast duration (existing); documented.
- Skip HUD perf rewrite (P2).


## 热键（完整默认表）

| 键 | 功能 | 键 | 功能 |
|----|------|----|------|
| C | 角色 | I | 背包 |
| K | 技能 | L | 任务日志 |
| M | 地图 | X | 系统 |
| P | 队伍 | U | 仓库 |
| O | 好友 | N | 邮件 |
| J | 制作（含烹饪） | E | 表情 |
| T | 称号 | G | 公会 |
| V | 成就 | | |
| Shift | 跑步 | | |
| H | 拍卖 | B | 战斗日志 |
| Y | 任务追踪 | Tab | 切换目标 |
| F | 拾取 | Z | 自动攻击 |
| R | 坐下 | Esc | 关闭/取消 |
| F1–F12 | 热键栏行0 | `` ` `` / 1–0 / -/= | 热键栏行1 |

无独立热键（菜单/怎么试）：采集、钓鱼、宠物、签到、日常任务、试炼洞窟、回城卷、净化药水、绷带、旅店、铁匠修理/强化、修理工具包、强化石、出售垃圾、商店回购、拾取过滤、低血自动喝药、雷达 POI、个人地图标记、世界首领。

## 系统清单（本 stretch）

| 系统 | 要点 |
|------|------|
| 技能学习 / SP | skill book、升级发 SP、学习门槛 |
| 技能重置 | 技能窗「重置技能」；返还 SP；平坦 50 金；保留 `basic_attack`；清热键遗忘技能 |
| 属性点升级 | 升级 +5 属性点；力量/敏捷/体质/智力；派生 atk/def/hp_max/mp_max；C 窗「+」分配；重置 30 金 |
| 升级 Toast | `level_up`→「升级！Lv.N」顶栏约 2s；SP↑附「获得技能点」；不挡输入 |
| 任务可交付/完成 Toast | `quest_update` 状态→ready/completed 时顶栏「任务可交付/完成：{title}」约 2s；仅过渡触发；不挡输入 |
| 经验飘字 | `exp_gain`→「经验 +N」~1.2s；同帧合并；设置 `show_exp_floats` |
| 金币飘字 | `inventory_update` 金增→「金币 +N」~1.2s；同帧合并；忽略减少；设置 `show_gold_floats` |
| 物品飘字 | `inventory_update` 数量增→「获得：{名} ×N」~1.2s；同 id 合并；并发≤3；忽略首包/减少；设置 `show_item_floats` |
| 物品稀有度 | `common/uncommon/rare/epic`→`[普通/优秀/精良/史诗]` 前缀；catalog 默认 common；tips/飘字 |
| 仓库 U | 存取物品/金币 |
| 好友 O | 添加/删除/在线 |
| 死亡掉落 | softcore 死丢部分背包 |
| 制作 J | `recipes.json` + `try_craft`；**制作等级** `craft_level`/`craft_xp`（与战斗等级分离）；配方 `craft_level` 门槛；成功 +5×qty XP；升级推送 `craft_update` +
「制作等级提升至 N！」；窗底「制作 Lv.N (xp/next)」 |
| 烹饪 | `cook_*` 走 J（烤鱼/药汤/鱼宴） |
| 食物增益 | 烹饪食物 heal 后嵌套 `status`（吃饱了/草药暖身/盛宴）；药水无 status |
| move_route | 事件移动路线 |
| 表情 E | 文字气泡 |
| 邮件 N | 收发/领取/删除 |
| 城镇安全区 | `safe_zones.json` AABB；安全区内禁决斗/打远程；敌对不追；HUD「安全区」 |
| 休息经验 | 安全区坐下每秒 +5；上限 `min(500, exp_to_next)`；击杀 EXP 消耗池至多 2×；HUD「休息 N」/ `rested_update` |
| 坐下回血回蓝 | 脱战坐下每 ~3s +3 HP / +2 MP（安全区 2×）；满则停；站立/战斗/移动打断；静默 `set_stat`；烟雾 `tools/test_sit_regen.gd` |
| 决斗 | 壳远程玩家决斗薄壳 |
| 怪物 leash | 回家/脱战整理 |
| 成就 V | 击杀/采集/等级/组队计数解锁；日志窗已解锁/锁定；解锁系统「成就解锁：{名}」+可选金/经验碎屑；权威 MockServer；烟雾 `tools/test_achievements.gd` |
| 称号 T | 击杀/制作/死亡计数解锁；日志窗已解锁/锁定（锁定灰+catalog 解锁提示）；点击装备/再点卸下；名牌下薄 Label；`try_title_equip` 权威；烟雾 `tools/test_title_ui.gd` / `tools/test_titles.gd` |
| 公会 G | 创建/邀请/踢人/离开 |
| 采集 | `gather_nodes.json`、`try_gather`；可选 `tool`（背包持有；见「工具耐久」）；demo 药草无工具、`ore_*` 需 `tool_pickaxe`→`iron_ore`；`ore_b` 需采集 Lv.2；枯竭重生；见「采集等级」 |
| 采集等级 | 与战斗/制作分离；默认 Lv.1；`try_gather`/`try_fish` 共用；成功 +5 XP（`20+level*10`）；升级「采集等级提升至 N！」；`gather_update` 含 level/xp；`ore_b`/`fish_pond_b` 需 Lv.2；系统→游戏设置「采集 Lv.N」；烟雾 `tools/test_gather_skill.gd` |
| 拍卖 H | 上架/浏览/购买/下架 |
| 宠物 | `try_pet_summon`/`try_pet_dismiss`；滞后跟随；助战 `pet_assist` 默认开（邻敌每~1.5s 小伤，恨归玩家）；系统「宠物助战」；烟雾 `tools/test_pet_assist.gd` / `tools/test_pet.gd` |
| 钓鱼 | `fish_spots.json`、`try_fish`；忙锁+枯竭重生；可选鱼饵 `bait_worm`/`bait_shiny`（闪光优先，成功消耗）；与采集共用 `gather_level`；`fish_pond_b` 需 Lv.2 |
| 天气采集加成 | 雨/雪：`try_gather` 药草节点成功时 30% +1 qty +「雨天收获更好！」；`try_fish` 闪光鱼权重 +0.1；晴/其它不变；`weather_gather_util`；烟雾 `tools/test_weather_gather.gd` |
| 任务 gather/fish | 推进；demo：`herb_gather`、`pond_fishing` |
| 每日签到 | `enter_world` 邮箱发金+小药；同日不重复 |
| 日常任务板 | `category:daily`：`daily_slime`/`daily_herb`；系统「日常任务」；同日接取一次；交付后记 `daily_log[date][id]`；次日可再接；`try_daily_board_list` → available|accepted|done_today；snapshot 含 `daily_date`+`daily` |
| 回城卷 | `scroll_town`→`recall`；安全点/倒地失败 |
| 旅店 | `try_inn_rest(25)` / `inn_rest`；满血满蓝+清有害 |
| 装备耐久 | 死亡磨损 10%；铁匠 `blacksmith` / `try_repair`；消耗品 `repair_kit`「修理工具包」→`repair_equip`（各槽 +30% max 向上取整，无金币；满耐久不消耗） |
| 装备强化 +N | 实例 `enhance` 0–5（背包栈元数据+装备槽）；`enhance_stone`「强化石」商店有售；铁匠对话「强化：…」/`try_enhance(slot)`：耗 1 石+`10*(等级+1)`G；v1 必成；武器 +1 p_atk/级、防具 +1 p_def/级；tooltip 显示 +N，对比/绑定仍可用 |
| 制作等级 | 与战斗等级分离；默认 Lv.1；成功制作 +5×qty XP（`20+level*10`）；皮帽/铜戒需 Lv.2；J 窗「制作 Lv.N」；烟雾 `tools/test_craft_skill.gd` |
| 队伍击杀 EXP | 同图 +5%/人（含自己，封顶 +25%） |
| 队伍拾取模式 | `ffa`/`leader`/`round_robin`/`need_greed`；掉落 `owner_id`；需求贪婪 15s 掷骰；60s 后自由；队长切模式 |
| 队伍任务进度分享 | 同图组队（N>1）：`note_party_kill`/`note_party_gather`/`note_party_fish` 模拟队友击杀/采集/钓鱼推进**本地**任务目标；本人击杀仍走原 `note_kill` 路径不双计；进度时系统「队伍协作：任务进度 +1」；壳端远程无日志；**不**代接日常 |
| 队伍干粮 | 消耗品 `food_party_ration`「队伍干粮」heal 20 + `well_fed` 45s；同图组队 N>1 时本地延长至 90s + `party_buff` +「队伍干粮：全员士气提升。」（壳端仅本地）；商店廉价；烟雾 `tools/test_party_food.gd` |
| 出售垃圾 | `try_shop_sell_junk`（misc/material、未锁、单价≤10） |
| 战斗飘字 | damage/heal/miss；crit `!`；每目标最多 8 |
| 战斗日志 B | HUD 环缓冲 50 |
| 命中/暴击 | hit≈90%±等级差；crit≈8%×1.5 |
| 拾取过滤 | 全部 / 不拾装备 / 金币与消耗品；手动仍全拿 |
| 低血/低蓝自动喝药 | 设置 `auto_potion_hp/mp` 默认关；阈值% 默认 40/30（1–90）；MockServer 0.5s 限速；`potion_*` 优先；无药静默（10s 一条）；施法/倒地不喝 |
| 任务追踪 Y | 迷你地图下最多 5 条；左键前往/右键详情 |
| 雷达 POI | 黄任务/青旅店/橙铁匠/绿采集/蓝钓鱼/紫首领；枯竭/死亡隐藏 |
| 小地图缩放 | `GameSettings.radar_view_radius` 允许 8/11(默认)/16/22；更小=放大；雷达滚轮或角 +/-；系统→游戏设置「小地图缩放」；烟雾 `tools/test_radar_zoom.gd` |
| 大地图 POI 寻路 | 点标记→`request_map_move`；阻挡邻近落脚 |
| NPC/玩家受伤红闪 | `hurt_flash.gd`；未命中不闪 |
| 暴击震屏 | Camera2D ~0.2s/3px；设置 `screen_shake` 默认开 |
| 战斗镜头偏移 | 选中敌对时 Camera2D soft bias 向玩家↔目标中点（`(t-p)*0.25` clamp 64px，逐帧 lerp）；清除/非敌对/关设置回零；shake 叠加；不走 `start_follow`；`GameSettings.combat_camera_frame` 默认开；系统→游戏设置「战斗镜头偏移」；烟雾 `tools/test_combat_camera.gd` |
| 名牌距离 | Chebyshev 格距外隐藏 NPC/远程名牌；`GameSettings.nameplate_distance` 默认 12（4–32）；选中目标始终显示；物件/事件仍无名牌；系统→游戏设置「名牌距离」；烟雾 `tools/test_nameplate_distance.gd` |
| 挂机提醒 | 无输入 N 分钟后非阻塞 Toast「你已离开一段时间」+ 软建议坐下（R）；`GameSettings.afk_warn_minutes` 默认 10（0=关，否则 5–60）；不踢线/不断 MockServer；系统→游戏设置「挂机提醒(分钟)」；烟雾 `tools/test_afk_warn.gd` |
| 装备对比 | 悬停背包装备看与已装备差值（物攻/物防等 `5 → 8 (+3)`）；空槽显示「当前：空」+绝对值 |
| 灵魂绑定（装备后绑定） | 物品 `bind:"equip"`；背包装备 `{id,qty,bound?}`；首次装备绑定；禁交易/拍卖/邮寄；商店可卖；提示「已绑定」/「装备后绑定」 |
| 拾取绑定（拾取后绑定） | 物品 `bind:"pickup"` / `bind_on_pickup:true`；地上拾取/掷骰获胜入包/任务奖励入包即 `bound`；禁交易/拍卖/邮寄；商店卖出挡「已绑定，无法出售。」；提示「已绑定」/「拾取绑定」；样例 `bone_necklace`；烟雾 `tools/test_bind_pickup.gd` |
| 个人地图标记 | 大地图 Shift+左键/右键设/清个人 pin（最多 3）；雷达+大地图品红点；点标记走 `request_map_move`；「清除标记」；会话内跨图保留（按 map_id 过滤显示） |
| 仇恨/坦克指示 | 选中敌对目标时目标栏小芯片：「仇恨」金/红=你是 victim；「无仇恨」灰=有目标但 victim 空/他人；非敌对/无目标隐藏。`threat_you`/`threat_rank`/`threat_pct` 来自 `hate_list`+`victim_id`；`threat_update` 或 set_stat 捎带；`snapshot_threat` |
| 个人 DPS 计量 | 当前战斗个人伤害；`_dps_fight` 累计；无伤 6s 结束；`dps_update`→HUD「DPS N」；设置 `show_dps_meter` 默认开 |
| 聊天时间戳 | 聊天行可选 `[HH:MM:SS]` 前缀；`GameSettings.show_chat_timestamps` 默认开；系统→游戏设置「聊天时间戳」；历史行存 `ts`，重建稳定；经 `_push_chat` 的附近/私聊/队伍/系统/战斗均生效 |
| 世界首领 | demo `world_boss_king`「森林霸主」@(24,17)；高HP/攻防、大leash、`respawn_sec` 120；击杀宣布「击败了森林霸主！」+额外金/经验；掉落强化石/铁矿×3；雷达/大地图紫色 `boss` POI，死亡隐藏 |
| 商店声望 | `vendor_rep`/`_rep_by_vendor` 0–1000（demo `starter_goods`）；购+1/次、售+1（开店时）；折扣 ≥100→5% / ≥300→10% / ≥600→15%（金≥1）；`snapshot_shop`/`try_shop_buy` 打折；跨阈「声望提升」；商店标题/页脚「声望 N」 |
| 商店回购 | 卖出进环缓冲（N=8）；商店「回购」页；`try_shop_buyback(index)` 按卖价买回；BoP 禁售不进列表；换图清空（关店保留）；「已回购：{名}」「金币不足。」「没有可回购的物品。」；烟雾 `tools/test_shop_buyback.gd` |
| 试炼洞窟（薄壳） | 系统「进入试炼洞窟」→`try_dungeon_enter` 传送 `street_map`；生成 2×`dungeon_guard_*`（meta `dungeon`）；击杀计数 HUD「试炼 N/2」；满杀「试炼完成！」+金/经验/强化石；「离开试炼」/`try_dungeon_exit` 回 demo；中途普通传送放弃无奖；snapshot 含 `dungeon`；烟雾 `tools/test_dungeon.gd` |
| 疾风靴油 / 移速 | 消耗品 `boots_swift`「疾风靴油」→`apply_status`/`swift_oil` 60s `move_speed_mul` 1.35；`try_move` 回传 mul；客户端步进 tween `dur/mul`；商店有售；烟雾 `tools/test_move_speed.gd` |
| 双手/副手装备 | 物品 `hand`:`main`/`off`/`both`（双手）；双手装主手强制卸副手回包；双手占用时不可装副手「双手武器占用副手。」；副手-only 不可进主手；`great_club`「大木棒」+ `wood_shield`「木盾」（双份 items.json，商店可选）；`total_bonuses()` 双手仅计主手；烟雾 `tools/test_weapon_hands.gd` |
| 法力护盾 | 技能 `mana_shield`「法力护盾」自施 buff 30s；受伤时吸收至多 50%（或 `absorb_max`）伤害，按 1 MP / 2 HP 扣蓝直至蓝空或到期；`combat_engine._damage_player`；可 SP 学习；烟雾 `tools/test_mana_shield.gd` |
| 潜行 | 技能 `stealth`「潜行」自施 buff ~8s；敌对 AI 视作不可见（不进视野/不追）；已追则 `clear_chase` 回家；普攻/伤害技/受伤/成功采集取消；可 SP 学习；烟雾 `tools/test_stealth.gd` |
| 嘲讽 | 坦克技能 `taunt`「嘲讽」瞬发短 CD/小 MP；需敌对目标在射程；`add_hate` 大仇恨尖刺强制 `victim_id`/追击到玩家；系统「嘲讽了{名}」；可 SP 学习（skills.json + catalog fallback）；烟雾 `tools/test_taunt.gd` |
| 打断 | 技能 `interrupt`「打断」瞬发短 CD/小 MP；敌对目标；微量伤害 + `silence`「沉默」debuff 3s；`try_npc_skill` 被沉默阻挡；系统「打断：沉默了{名}！」；可 SP 学习（skills.json + catalog fallback）；烟雾 `tools/test_interrupt.gd` |
| NPC 施法/打断 | 敌对技能 `cast_time`>0 进入施法（`cast_start`/`tick_npc_casts`）；样例 demo 史莱姆 `flame_burst`；玩家 `interrupt` 取消施法「打断了{名}的施法！」+仍沉默；无打断则到期结算；烟雾 `tools/test_npc_cast.gd` |
| 净化药水 | 消耗品 `potion_cleanse`「净化药水」→`use_effect`/`cleanse`；`clear_harmful` 清 poison/silence 等 debuff/dot，保留 buff；CD 3s；商店 `starter_goods` 有售；烟雾 `tools/test_cleanse_potion.gd` |
| 标记 | 技能 `mark`「标记」敌对 debuff 12s `def_mul` 0.85（受伤↑）；CD 10s / MP 8 / 射程 5；可 SP 学习；系统「标记了{名}！」；烟雾 `tools/test_mark.gd` |
| 复活 | 技能 `revive`「复活」瞬发；MP 25 / CD 30s / 射程 4；目标=同图死亡队友（party stub / 假玩家 ally / `ally` NPC）；成功 ~30% 最大 HP、清 `awaiting_respawn`、保留死亡格；系统「复活了{名}！」；失败：未死亡/太远/非队友/MP不足/无法自我复活；可 SP 学习（双 skills.json + catalog fallback）；烟雾 `tools/test_revive.gd` |
| 冲锋 | 技能 `charge`「冲锋」瞬发；MP 12 / CD 12s / 射程 2–6（`min_range` 2）；敌对目标；成功移至邻格、约 1.2×物攻、`root`「定身」0.75s；失败：无目标/太远/太近/路径阻挡/非敌对；可 SP 学习（双 skills.json + catalog fallback）；`player_move` 动作；烟雾 `tools/test_charge.gd` |
| 战吼 | 技能 `battle_shout`「战吼」自施 buff 15s `atk_add` +3；MP 10 / CD 20s / 射程 0；同图组队 N>1 时 `party_buff` +「战吼：全队攻击提升！」（壳端仅本地）；系统「战吼响起！」；可 SP 学习（双 skills.json + catalog fallback）；烟雾 `tools/test_battle_shout.gd` |
| 斩杀 | 技能 `execute`「斩杀」瞬发物理终结技；MP 15 / CD 15s / 射程 1–2；敌对且目标 HP≤30% 最大生命；约 2.0×物攻；系统「斩杀了{名}！」；失败「目标生命过高」/非敌对/太远；可 SP 学习（双 skills.json + catalog fallback）；烟雾 `tools/test_execute.gd` |
| 骑乘（薄壳） | 技能 `mount`「骑乘」自施 toggle；挂 `mounted` buff `move_speed_mul` 1.45（复用移速路径）；战斗中/死亡无法上马；普攻/受伤/伤害技下马；系统「已骑乘。」「已下马。」「战斗中无法骑乘。」；无新美术；可 SP 学习；`MockServer.player_is_mounted`/`try_mount`；烟雾 `tools/test_mount.gd` |
| 绷带 | 消耗品 `bandage`「绷带」→`heal_hp` **固定 +40 HP**（非%）；`out_of_combat_only` 战斗中失败「战斗中无法包扎。」且不消耗；CD 8s；商店 `starter_goods` 买价 5；复用 `icon_index` 32（生命药水）；双份 items.json；烟雾 `tools/test_bandage.gd` |
| 魔力药水 | 消耗品 `mana_potion`「魔力药水」→`heal_mp` **固定 +50 MP**（钳至 max）；战斗内外可用；满蓝失败「魔力已满。」且不消耗；CD 6s；商店 `starter_goods` 买价 8；复用 `icon_index` 33（小型魔法药水）；双份 items.json + shops.json；烟雾 `tools/test_mana_potion.gd` |
| 工具耐久 | 采集工具（如 `tool_pickaxe`）背包栈 `durability`/`durability_max`（镐默认 40）；工具门控成功采集/钓鱼各 −1；归零消耗并「工具已损坏。」；悬停「耐久：x/y」；`repair_kit` 亦修背包工具（+30% max 向上取整）；铁匠 `try_repair("tools"|"all")` 按点扣金；双份 items.json；烟雾 `tools/test_tool_durability.gd` |
| 武器耐久 | 主手（可选副手）装备槽 `durability`/`durability_max`（木剑 `durability_max` 100）；玩家成功造成伤害的普攻/技能命中主手 −1；归零卸下销毁并「武器已损坏。」；悬停「耐久：x/y」（复用工具提示）；`repair_kit`/铁匠修已装备武器；双份 items.json；烟雾 `tools/test_weapon_durability.gd` |
| 集结石（队伍召唤） | 消耗品 `party_summon`「集结石」；组队同图 N>1 使用→「发出了集结。」并开 pending；成员 `try_party_summon_accept` / `try_party_summon_accept_all` / `party_summon_auto_accept` 传到施法者邻格空位；独行「需要队伍。」；无空位「没有空余位置。」；CD 60s 消耗 1；复用卷轴 `icon_index` 186；双份 items.json + shops；烟雾 `tools/test_party_summon.gd` |
| 增益刷新/叠加 | 同 id 再施加：**刷新** duration 至 max（默认不叠层）；status 可选 `stack_max`（>1 可叠至 N，如 debug）；`well_fed`/`battle_shout`/`mark` 为 `stack_max` 1；权威 `status_effects.apply_status` / `_apply_status_to`；烟雾 `tools/test_buff_refresh.gd` |

## 怎么试（短）

- **灵魂绑定**：木剑/皮帽/皮背心为装备后绑定；装备一次后背包保留已绑定，不可交易/拍卖/邮寄，仍可卖店；手套等非绑定装不受影响。
- **拾取绑定**：地上拾取 / 掷骰获胜入包 / 任务奖励若带 BoP 物品则入包即绑定；不可交易/拍卖/邮寄；商店出售提示「已绑定，无法出售。」；悬停显示「拾取绑定」或已绑「已绑定」。样例史诗 `bone_necklace`「骨项链」（史莱姆稀有掉落）。烟雾：`tools/test_bind_pickup.gd`。

- **属性点**：升级获得 5 点；C 开角色窗点「+」分配力量/敏捷/体质/智力（攻/防/HP/MP）；「重置属性」花 30 金全退回。
- **采集**：靠近节点 `try_gather`；枯竭等重生。药草无需工具；铁矿脉 `ore_a`@(20,24)/`ore_b`@(22,22) 需背包持有「矿工镐」（商店可买；耐久 40，每次成功 −1，归零损坏「工具已损坏。」）；无镐提示「需要工具：矿工镐」。
- **钓鱼**：demo 鱼塘 @(16,11)@(18,11)；`try_fish`；忙锁+枯竭重生；可选饵（蚯蚓/闪光，商店可买，开局×10蚯蚓）；成功消耗最佳饵并提高闪光鱼权重。
- **天气采集加成**：雨/雪时药草 `try_gather` 成功有 30% 额外 +1 数量并系统「雨天收获更好！」；钓鱼闪光鱼权重 +0.1；晴天/风暴/雾无加成；用 `set_weather`/`get_weather`。烟雾：`tools/test_weather_gather.gd`（另 `test_weather` / `test_gather_tool`）。
- **宠物**：系统「召唤/收回」或「宠物哨」；Chebyshev 滞后 1–2 格；有敌对目标且宠物在 1–2 格内时周期性助战小伤（`3+等级`，恨/掉落/经验归玩家）；系统→游戏设置「宠物助战」默认开（关则仅跟随）。烟雾：`tools/test_pet.gd` / `tools/test_pet_assist.gd`。
- **旅店**：`inn_rest` 或 `try_inn_rest(25)`；金不足/已全满失败。
- **铁匠**：`blacksmith`@(14,12) 或 `try_repair("all")`/`try_repair("tools")`；死亡磨损 10%；背包工具可按点修；对话另有「强化：装备名 +N（强化石+XG）」。
- **修理工具包**：背包/热键使用 `repair_kit`；修复所有未满耐久已装备槽各 +30% max（向上取整），并同样修复背包内耐久工具；无需金币；无可修时「没有需要修理的装备。」且不消耗；商店 `starter_goods` 有售。
- **装备强化**：铁匠选「强化」或 `try_enhance("weapon_main")`；耗 1×强化石 + `10*(当前+1)` 金；必成至 +5；武器物攻/防具物防各 +1/级；卸下保留强化；商店卖 `enhance_stone`。烟雾：`tools/test_enhance.gd`。
- **拍卖**：H 开面板；上架/浏览/购买/下架。
- **邮件每日**：当日首次 `enter_world` 邮箱「每日签到奖励」（金+小药）。
- **日常任务**：系统→「日常任务」看板；接取 `daily_slime`（杀5史莱姆）/`daily_herb`（采3药草）；交付后当日「已完成」，换日可再接。烟雾：`tools/test_daily_quests.gd`。
- **世界首领**：demo 地图 @(24,17)「森林霸主」；高血敌对；击杀有全图式系统宣布、额外金币/经验、强化石+铁矿掉落；约 120s 重生；雷达/大地图紫色首领点（死后消失）。烟雾：`tools/test_world_boss.gd`。
- **商店声望**：找杂货商人开店；标题/页脚「声望 N」；每次购买 +1（封顶 1000），出售开店时 +1；声望≥100/300/600 买价 5%/10%/15% 折（至少 1 金）；刚跨阈聊天「声望提升」。烟雾：`tools/test_vendor_rep.gd`。
- **商店回购**：开店卖出后切「回购」页；点条目按卖价买回（金不足「金币不足。」）；换图清空列表（关店保留）（否则环缓冲最多 8 条）；BoP 绑定不可卖故不进回购。烟雾：`tools/test_shop_buyback.gd`。
- **任务追踪寻路**：Y 开追踪；标题/目标左键或「去」→ `resolve_quest_nav`（交付 NPC / 抵达 / 采集·钓鱼 POI）→「前往：…」；右键开日志。

- **背包搜索**：I 开背包；网格上方「搜索物品…」；按显示名/物品 id 子串过滤（不区分大小写）；空查询显示全部；过滤时隐藏空槽与不匹配格；仅客户端，不改服务端背包。烟雾：`tools/test_inv_search.gd`。
- **装备对比**：打开背包悬停装备，tooltip 显示与已装备同槽差值（`物攻 5 → 8 (+3)`）；空槽为「当前：空」+绝对值；商店/掉落/热键栏同样。
- **双手/副手**：`great_club` 双手装主手会卸副手回包；双手占用时再装 `wood_shield` 失败并提示「双手武器占用副手。」；副手盾不可装主手。烟雾：`tools/test_weapon_hands.gd`。
- **物品稀有度**：物品 `rarity`（common/uncommon/rare/epic）；tooltip / 获得飘字名行「[优秀] 名称」；catalog 缺省 common；皮甲/木剑 uncommon，强化石/闪光鱼/鱼宴 rare，骨项链 epic。烟雾：`tools/test_item_rarity.gd`。
- **城镇安全区**：`demo_map` 城镇 AABB（旅店/铁匠/出生点一带）；进/出推送 `safe_zone`；区内决斗与打壳远程失败「安全区内无法决斗。」；敌对不新仇恨且进区脱战；采集/钓鱼/NPC 仍可用。
- **仇恨指示**：选中史莱姆等敌对 → 攻击后目标栏「仇恨」；脱战/leash 后「无仇恨」或隐藏。烟雾：`tools/test_threat_hud.gd`。
- **战斗日志筛选**：B 面板顶部勾选 伤害/治疗/未命中/击杀；缓冲仍最多 50 条，筛选只影响显示；设置 `combat_log_show_*`（默认全开）可持久化。烟雾：`tools/test_combat_log_filter.gd` / `tools/test_combat_log.gd`。
- **个人 DPS 计量**：攻击怪物后左下角（战斗日志旁）出现「DPS N」；6 秒无输出结束本场并隐藏；系统→游戏设置可关 `显示 DPS 计量`。烟雾：`tools/test_dps_meter.gd`。
- **战斗镜头偏移**：选中敌对目标时镜头轻微偏向玩家与目标之间；清除目标或关「战斗镜头偏移」恢复居中；暴击震屏仍叠加。烟雾：`tools/test_combat_camera.gd`。
- **聊天时间戳**：系统→游戏设置「聊天时间戳」（默认开）；聊天行前缀 `[HH:MM:SS]`；关后重建不带时间但仍保留历史 `ts`。烟雾：`tools/test_chat_timestamps.gd`。
- **名牌距离**：系统→游戏设置「名牌距离」（默认 12，钳制 4–32）；超出 Chebyshev 格距隐藏 NPC/远程名牌，选中仍显示；物件/事件永不显示。烟雾：`tools/test_nameplate_distance.gd`。
- **挂机提醒**：系统→游戏设置「挂机提醒(分钟)」（默认 10；0=关闭；5–60）；无键鼠输入达阈值后顶栏 Toast「你已离开一段时间」+「建议坐下休息（R）」约 3s，并系统一条；再输入重置；不自动下线。烟雾：`tools/test_afk_warn.gd`。
- **试炼洞窟**：系统→「进入试炼洞窟」（demo）传送中央市街并刷 2 守卫；HUD「试炼 N/2」；杀满「试炼完成！」发金+经验+强化石；系统「离开试炼」回原格；中途踩传送点放弃无奖。烟雾：`tools/test_dungeon.gd`。

- **小地图缩放**：系统→游戏设置「小地图缩放」（8/11/16/22，默认 11）；雷达上滚轮或角 +/- 切换；半径越小越放大；滚轮不滚动父控件。烟雾：`tools/test_radar_zoom.gd`。
- **安全区坐下攒休息经验**：R 坐下且在安全区内，每 1s +5 休息经验（上限 `min(500, exp_to_next)`）；空池→有值提示「开始积攒休息经验。」、满仓提示「休息经验已满。」各一次；出安全区或站立不攒；击杀怪物时 `bonus=min(池, 本次基础EXP)` 至多 2×，聊天「休息加成 +N」；XP 条 tooltip / 小字「休息 N」；`snapshot`/`combat` 含 `rested_exp`/`rested_exp_max`。烟雾：`tools/test_rested_exp.gd`。
- **坐下回血回蓝**：R 坐下且脱战、存活时，每约 3 秒恢复 **+3 HP / +2 MP**（钳至上限）；安全区内 **2×**（+6/+4）；站立 / 进战 / 移动会打断坐下；无系统刷屏（静默 `set_stat`）。与安全区休息经验并存（休息经验仍为 1s 节奏）。烟雾：`tools/test_sit_regen.gd`。
- **个人地图标记**：M 开大地图；Shift+左键（或右键）空地设标记（最多 3，默认「标记1/2/3」）；再点同格清除；左键标记寻路；地图窗/系统菜单「清除标记」。

- **低血/低蓝自动喝药**：系统→游戏设置 勾选「低血/低蓝自动喝药」并设阈值%；进战后 HP%/MP%≤阈值时自动用最佳 `potion_*`（尊重物品 CD，约 0.5s 最多一次）；无药不刷屏。烟雾：`tools/test_auto_potion.gd`。
- **制作等级**：与战斗等级分离；默认制作 Lv.1；J 窗底「制作 Lv.N (xp/next)」；成功制作 +5×数量 XP（`20+level*10` 升级）；皮帽/铜戒需制作 Lv.2，基础药水 Lv.1。烟雾：`tools/test_craft_skill.gd`。
- **工具耐久**：矿工镐等带 `durability_max` 的工具入包为满耐久；悬停「耐久：x/y」；工具门控节点每次成功采集 −1，归零移除并「工具已损坏。」；修理工具包或铁匠「修理工具」/`try_repair("tools")` 可修。烟雾：`tools/test_tool_durability.gd`。
- **武器耐久**：木剑等武器装备后主手满耐久（默认/`durability_max` 100）；悬停「耐久：x/y」；普攻/伤害技能每次成功命中 −1，归零销毁并「武器已损坏。」；修理工具包或铁匠可修。烟雾：`tools/test_weapon_durability.gd`。
- **采集等级**：与战斗/制作分离；默认采集 Lv.1；系统→游戏设置只读「采集 Lv.N」；成功采集/钓鱼 +5 XP；升级「采集等级提升至 N！」；`ore_b`/`fish_pond_b` 需 Lv.2，药草/`ore_a`/`fish_pond_a` 为 Lv.1。烟雾：`tools/test_gather_skill.gd`（另 `test_gather_tool` / `test_fish`）。
- **食物增益**：J 烹饪烤鱼/药汤/鱼宴后，从背包或热键栏使用；回血并挂增益/HoT（同 id 刷新）。
- **技能重置**：K 开技能窗 →「重置技能」点两次确认；花 50 金，返还已学技能 SP，仅留普通攻击；热键栏遗忘技能清空。
- **队伍拾取**：P 开队伍；队长用「拾取」下拉切 自由/队长/轮流/需求贪婪；组队击杀掉落按模式写 `owner_id`；非所有者打开/拾取失败「该掉落属于队友。」；60s 后自由；自动拾取跳过他人袋。
- **队伍需求/贪婪**：拾取模式 `need_greed`（别名 `roll`）；同图 N>1 击杀掉落开 ~15s 掷骰（「开始掷骰：{物品}」）；成员 `try_loot_roll(need|greed|pass)`（壳 stub 用 `try_loot_roll_for`）；需求最高＞贪婪最高；全过/超时自动放弃→自由或唯一投票者得；独行跳过；系统「{名} 需求 87」「{名} 获得了 {物品}」。烟雾：`tools/test_loot_roll.gd`。
- **队伍任务进度分享**：同图有队友时，队友击杀/采集/钓鱼可推进你已接的同目标（壳：`MockServer.note_party_kill`/`note_party_gather`/`note_party_fish`）；本人击杀不双计；有推进时「队伍协作：任务进度 +1」。不代接日常。烟雾：`tools/test_party_quest_share.gd`。
- **队伍干粮**：商店买 `food_party_ration`「队伍干粮」或背包使用；独行 heal+吃饱 45s；同图有队友时吃饱 90s 并系统「队伍干粮：全员士气提升。」（壳仅本地 buff）。烟雾：`tools/test_party_food.gd`。
- **疾风靴油 / 移速**：商店买 `boots_swift`「疾风靴油」使用；挂 `swift_oil` 60s（`move_speed_mul` 1.35）；走路/跑步步进更快；状态到期恢复。烟雾：`tools/test_move_speed.gd`。
- **法力护盾**：K 学 `mana_shield`「法力护盾」（SP）；施放挂 30s buff；受伤时护盾吸收约一半伤害并扣蓝（2 HP≈1 MP），蓝空则不再吸收。烟雾：`tools/test_mana_shield.gd`。
- **潜行**：K 学 `stealth`「潜行」（SP）；施放挂 ~8s buff；敌对不追/已追回家；攻击或受伤取消。烟雾：`tools/test_stealth.gd`。
- **嘲讽**：K 学 `taunt`「嘲讽」（SP）；选中敌对施放；大仇恨尖刺抢 `victim_id`；系统「嘲讽了{名}」。烟雾：`tools/test_taunt.gd`。
- **打断**：K 学 `interrupt`「打断」（SP）；选中敌对施放；微量伤害并沉默 3 秒（挡 NPC 技能）；系统「打断：沉默了{名}！」。烟雾：`tools/test_interrupt.gd`。
- **NPC 施法/打断**：敌对技能带 `cast_time`（样例：demo 史莱姆 `flame_burst`）会先读条；读条中对目标施放「打断」取消施法（「打断了{名}的施法！」）并仍挂沉默；不打断则到期按原效果结算。烟雾：`tools/test_npc_cast.gd`。
- **净化药水**：商店买或背包用 `potion_cleanse`「净化药水」；清除中毒/沉默等有害状态，保留增益；CD 3s。烟雾：`tools/test_cleanse_potion.gd`。
- **绷带**：背包/热键使用 `bandage`；脱战恢复 **40 点生命**；战斗中提示「战斗中无法包扎。」且不消耗；物品 CD 约 8s；商店廉价有售（买价 5）。烟雾：`tools/test_bandage.gd`。
- **魔力药水**：背包/热键使用 `mana_potion`；恢复 **50 点魔力**（战斗内外均可）；已满提示「魔力已满。」且不消耗；物品 CD 约 6s；商店廉价有售（买价 8）。烟雾：`tools/test_mana_potion.gd`。
- **标记**：K 学 `mark`「标记」（SP）；选中敌对施放；挂 12s debuff（`def_mul` 0.85，受伤↑）；CD 10s / MP 8 / 射程 5；系统「标记了{名}！」。烟雾：`tools/test_mark.gd`。
- **复活**：K 学 `revive`「复活」（SP）；选中同图死亡队友施放；回 ~30% 血并就地起身；系统「复活了{名}！」。烟雾：`tools/test_revive.gd`。
- **冲锋**：K 学 `charge`「冲锋」（SP）；选中 2–6 格敌对施放；冲到邻格并轻伤+定身；太近/太远/挡路失败。烟雾：`tools/test_charge.gd`。
- **增益刷新/叠加**：同 buff/debuff id 再挂只刷新剩余时间（不叠层）；`stack_max`>1 才叠层（封顶 N）。烤鱼/战吼/标记再施均为刷新。烟雾：`tools/test_buff_refresh.gd`。
- **战吼**：K 学 `battle_shout`「战吼」（SP）；施放自挂 15s 物攻+3；同图有队友时分享并系统「战吼：全队攻击提升！」；独行仅「战吼响起！」。烟雾：`tools/test_battle_shout.gd`。
- **斩杀**：K 学 `execute`「斩杀」（SP）；选中 1–2 格且血量≤30% 的敌对施放；约 2.0×物攻；生命过高失败「目标生命过高」。烟雾：`tools/test_execute.gd`。
- **骑乘**：K 学 `mount`「骑乘」（SP）；施放切换骑乘（无新外观）；移速 ×1.45；战斗中无法上马；普攻/受伤自动下马。烟雾：`tools/test_mount.gd`。
- **集结石**：商店买或背包用 `party_summon`「集结石」；同图有队友时发出集结；队友 `try_party_summon_accept`（壳 stub / 头测可用 `try_party_summon_accept_all` 或 `party_summon_auto_accept`）传送至身边邻格；独行「需要队伍。」；四周无空位「没有空余位置。」；CD 60s。烟雾：`tools/test_party_summon.gd`。
- **成就日志**：V 开成就窗（系统菜单「成就」也可）；列出已解锁/锁定（锁定灰+catalog `desc`/`require`）；解锁时系统「成就解锁：{名}」，可选金币/经验碎屑；权威 MockServer 计数；无 Steam 同步。烟雾：`tools/test_achievements.gd`。
- **称号日志**：T 开称号窗；已解锁可点装备，装备中再点卸下；锁定灰显+解锁提示（catalog `desc`/`require`）；装备称号显示在左上名牌下方薄 Label「称号」；权威 `MockServer.try_title_equip`。烟雾：`tools/test_title_ui.gd`、`tools/test_titles.gd`。

其它：烹饪开 J 选 `cook_*`；回城卷用 `scroll_town`；修理用 `repair_kit`；出售垃圾商店按钮或 `try_shop_sell_junk()`；雷达/大地图点色点寻路。

## 回归

- **Phase A 再确认（本轮）**：`test_tool_durability` / `test_sit_regen` / `test_mana_potion` / `test_bandage` / `test_mount` / `test_loot_roll` / `test_bind_pickup` / `test_shell_systems` 均 PASS。
- **game_hud 解析**：地牢本地结果勿直接调用不存在的 `apply_inventory_update`/`apply_exp_gain`（改 `apply_inventory_snapshot` / `show_exp_gain_float`）；否则 HUD 脚本加载失败，壳/背包/称号 UI 冒烟会挂。已修。

- **game_hud BoE tip**：勿对 `preload` 的 `Equipment` 脚本调用 `.has_method`（RefCounted 脚本类会破坏 HUD 解析）；直接用静态 `Equipment.is_bind_on_equip(def)`。已修；`test_bind_equip` / `test_auto_potion` / `test_shell_systems` HUD 段应过。
- **标记**：`tools/test_mark.gd` PASS（def_mul 0.85 / 12s / CD10 / MP8 / range5）。
- **复活**：`tools/test_revive.gd` PASS（MP25 / CD30 / range4 / ~30% HP / party stub + ally NPC）。
- **冲锋**：`tools/test_charge.gd` PASS（MP12 / CD12 / range2–6 / 1.2×atk / root 0.75s / player_move）。
- **增益刷新/叠加**：`tools/test_buff_refresh.gd` PASS（同 id 刷新 duration；`stack_max`>1 叠层封顶；food/shout/mark）。
- **战吼**：`tools/test_battle_shout.gd` PASS（MP10 / CD20 / range0 / atk_add+3 / 15s / party_buff）。
- **斩杀**：`tools/test_execute.gd` PASS（MP15 / CD15 / range1–2 / 2.0×atk / HP≤30% /「斩杀了{名}！」）。
- **骑乘**：`tools/test_mount.gd` PASS（mul 1.45 / 战斗中挡上马 / 受伤·普攻下马）。
- **集结石**：`tools/test_party_summon.gd` PASS（同图 N>1 / 邻格落地 / 需要队伍 / 无空位 / CD / auto_accept）。
- **商店回购**：`tools/test_shop_buyback.gd` PASS（环缓冲 8 / 卖价买回 / BoP 不进 / 关店·换图清空 / 中文提示）。
- **NPC 施法/打断**：`tools/test_npc_cast.gd` PASS（`flame_burst` 开读条 → interrupt 取消；无打断则结算伤害）。
- **Phase A（本轮）**：`test_achievements` / `test_weapon_durability` / `test_party_summon` / `test_tool_durability` / `test_shell_systems` 均 PASS。
- **最近全量约 73/81 PASS**（SceneTree 头测）。本 stretch 强化壳：`test_enhance` PASS；耐久/绑定冒烟仍过。
- **RTP 8 FAIL**（环境缺 Generator/RTP，**非逻辑回归**）：`test_autotile_paint`、`test_create_preview`、`test_editor_paint`、`test_map_minimap`、`test_map_perf`、`test_paperdoll_look`、`test_tile_anim`、`test_tile_palette`。
- 全量入口：`tools/run_all_tests.sh`（`GODOT` 可覆盖；日志默认 `/tmp/rmmo_test_logs`）。

```bash
# 代表冒烟（示例）— 含 Toast：升级 / 任务可交付·完成 / 经验飘字 / 金币飘字 / 物品飘字
godot --path /workspace/rmmo --headless -s res://tools/test_level_up_toast.gd
godot --path /workspace/rmmo --headless -s res://tools/test_quest_toast.gd
godot --path /workspace/rmmo --headless -s res://tools/test_exp_float.gd
godot --path /workspace/rmmo --headless -s res://tools/test_gold_float.gd
godot --path /workspace/rmmo --headless -s res://tools/test_item_float.gd
godot --path /workspace/rmmo --headless -s res://tools/test_daily_quests.gd
godot --path /workspace/rmmo --headless -s res://tools/test_quest_tracker.gd
godot --path /workspace/rmmo --headless -s res://tools/test_hurt_flash.gd
godot --path /workspace/rmmo --headless -s res://tools/test_skill_learn.gd
godot --path /workspace/rmmo --headless -s res://tools/test_attr_points.gd
godot --path /workspace/rmmo --headless -s res://tools/test_skill_respec.gd
godot --path /workspace/rmmo --headless -s res://tools/test_quest_tracker_nav.gd
godot --path /workspace/rmmo --headless -s res://tools/test_radar_poi.gd
godot --path /workspace/rmmo --headless -s res://tools/test_radar_zoom.gd
godot --path /workspace/rmmo --headless -s res://tools/test_map_poi_path.gd
godot --path /workspace/rmmo --headless -s res://tools/test_camera_shake.gd
godot --path /workspace/rmmo --headless -s res://tools/test_food_buff.gd
godot --path /workspace/rmmo --headless -s res://tools/test_safe_zone.gd
godot --path /workspace/rmmo --headless -s res://tools/test_threat_hud.gd
godot --path /workspace/rmmo --headless -s res://tools/test_dps_meter.gd
godot --path /workspace/rmmo --headless -s res://tools/test_chat_timestamps.gd
godot --path /workspace/rmmo --headless -s res://tools/test_nameplate_distance.gd
godot --path /workspace/rmmo --headless -s res://tools/test_equip_compare.gd
godot --path /workspace/rmmo --headless -s res://tools/test_item_rarity.gd
godot --path /workspace/rmmo --headless -s res://tools/test_map_pins.gd
godot --path /workspace/rmmo --headless -s res://tools/test_party_loot.gd
godot --path /workspace/rmmo --headless -s res://tools/test_loot_roll.gd
godot --path /workspace/rmmo --headless -s res://tools/test_party_exp.gd
godot --path /workspace/rmmo --headless -s res://tools/test_party_stub.gd
godot --path /workspace/rmmo --headless -s res://tools/test_party_quest_share.gd
godot --path /workspace/rmmo --headless -s res://tools/test_party_food.gd
godot --path /workspace/rmmo --headless -s res://tools/test_gather_tool.gd
godot --path /workspace/rmmo --headless -s res://tools/test_tool_durability.gd
godot --path /workspace/rmmo --headless -s res://tools/test_weapon_durability.gd
godot --path /workspace/rmmo --headless -s res://tools/test_weather_gather.gd
godot --path /workspace/rmmo --headless -s res://tools/test_weather.gd
godot --path /workspace/rmmo --headless -s res://tools/test_fish_bait.gd
godot --path /workspace/rmmo --headless -s res://tools/test_repair_kit.gd
godot --path /workspace/rmmo --headless -s res://tools/test_durability.gd
godot --path /workspace/rmmo --headless -s res://tools/test_bind_equip.gd
godot --path /workspace/rmmo --headless -s res://tools/test_bind_pickup.gd
godot --path /workspace/rmmo --headless -s res://tools/test_rested_exp.gd
godot --path /workspace/rmmo --headless -s res://tools/test_auto_potion.gd
godot --path /workspace/rmmo --headless -s res://tools/test_enhance.gd
godot --path /workspace/rmmo --headless -s res://tools/test_craft_skill.gd
godot --path /workspace/rmmo --headless -s res://tools/test_craft.gd
godot --path /workspace/rmmo --headless -s res://tools/test_cook.gd
godot --path /workspace/rmmo --headless -s res://tools/test_world_boss.gd
godot --path /workspace/rmmo --headless -s res://tools/test_combat_camera.gd
godot --path /workspace/rmmo --headless -s res://tools/test_vendor_rep.gd
godot --path /workspace/rmmo --headless -s res://tools/test_shop_buyback.gd
godot --path /workspace/rmmo --headless -s res://tools/test_gather_skill.gd
godot --path /workspace/rmmo --headless -s res://tools/test_titles.gd
godot --path /workspace/rmmo --headless -s res://tools/test_title_ui.gd
godot --path /workspace/rmmo --headless -s res://tools/test_combat_log_filter.gd
godot --path /workspace/rmmo --headless -s res://tools/test_afk_warn.gd
godot --path /workspace/rmmo --headless -s res://tools/test_dungeon.gd
godot --path /workspace/rmmo --headless -s res://tools/test_inv_search.gd
godot --path /workspace/rmmo --headless -s res://tools/test_pet_assist.gd
godot --path /workspace/rmmo --headless -s res://tools/test_shell_systems.gd
godot --path /workspace/rmmo --headless -s res://tools/test_move_speed.gd
godot --path /workspace/rmmo --headless -s res://tools/test_weapon_hands.gd
godot --path /workspace/rmmo --headless -s res://tools/test_mark.gd
godot --path /workspace/rmmo --headless -s res://tools/test_revive.gd
godot --path /workspace/rmmo --headless -s res://tools/test_charge.gd
godot --path /workspace/rmmo --headless -s res://tools/test_battle_shout.gd
godot --path /workspace/rmmo --headless -s res://tools/test_buff_refresh.gd
godot --path /workspace/rmmo --headless -s res://tools/test_execute.gd
godot --path /workspace/rmmo --headless -s res://tools/test_mount.gd
godot --path /workspace/rmmo --headless -s res://tools/test_party_summon.gd
godot --path /workspace/rmmo --headless -s res://tools/test_mana_shield.gd
godot --path /workspace/rmmo --headless -s res://tools/test_stealth.gd
godot --path /workspace/rmmo --headless -s res://tools/test_taunt.gd
godot --path /workspace/rmmo --headless -s res://tools/test_interrupt.gd
godot --path /workspace/rmmo --headless -s res://tools/test_npc_cast.gd
godot --path /workspace/rmmo --headless -s res://tools/test_cleanse_potion.gd
godot --path /workspace/rmmo --headless -s res://tools/test_bandage.gd
godot --path /workspace/rmmo --headless -s res://tools/test_mana_potion.gd
```

## 约束（回来时）

- box only；**勿默认 Luna/git/art**。
- 无新功能除非明确要求；只修真实回归。
