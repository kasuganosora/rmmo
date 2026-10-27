# axel_town 缺失 DDS 的隔离地图对照（2026-10-27）

正式包不写入。`isolated_axel_dds_20261027_01` 是全新外部测试根，约801,952,310字节，复制受影响地图及显式依赖，2,369记录/1,065个重写rmres/49个实际使用native模型/85纹理变体/11候选；prefab paint通过 retarget 同步嵌入数据并更新内容身份。原生产品在临时root按新逻辑路径重键，49产品共193,396,086字节、只读预检无声明的ResourceLoader外部依赖；无运行时GLB。38类编辑器快照/资料路径只保留且不属于此 mesh-only 测试的确认消费者；未做全进程IO跟踪，manifest明确 `full_map_closure_verified=false`。地图、资源、各source/native/候选SHA及分类见 `isolated_axel_dds_20261027_01_control/verification.json`、`freeze_after_texture_profile.json` 和根内manifest。

临时地图retarget/保存重开20/20，native重键29/29，完整小fixture builder22/22，真实profile初始化链8/8，子进程 APPDATA/LOCALAPPDATA/TEMP 私有化与autoload/root override已按已检查路径验证。小样本四次新进程ABBA校验12变体仅11个候选选择变化。runner默认正式路径不变；隔离fixture使用独占协作锁、前后核对同一私有root的源/候选/原生/地图/设置。路径安全依赖独占私有目录，未证明抵御恶意链接并发替换。

先在同一副本做origin-only诊断：A 50次DDS读取、11次源图解码、85次纹理上传逻辑360,666,036字节；B 61次DDS、0次源图解码、85次上传272,676,352字节。A/B初始63次prepared terrain命中一致；A先运行，私有root和OS缓存先后状态不同，诊断启用profile，不能将15.544→12.828秒差归因于侧车或当正常游戏FPS。

随后无纹理profiling的新进程ABBA，同一私有map/root/user目录，A移除11个候选、B安装11个，A2最终恢复A。每次检测85变体、1,378个stable文件、地图及设置；四组797个被测源码SHA相同、engine SHA `40554844d964cb0e6d9d15ebf85f989ce5cb1c77f82efe81acaafca79275cc73`，功能/资源检查均通过。四组初始工作均229 groups/2564 source/361 surfaces、231 rebuild、3923 prepare和2724 pack；GPU审计均3943 surfaces/3202非白/1502带纹理/145 unique，不证明完整画质。

| 样本 | 入口秒 | 完整就绪秒 | 返回 / 重载 1% low FPS | 卸载 / 返回 / 重载最大帧 ms | >50ms 帧数 |
| --- | ---: | ---: | --- | --- | --- |
| A1 | 5.962 | 12.647 | 30.476 / 29.481 | 44.977 / 161.019 / 44.344 | 0 / 4 / 0 |
| B1 | 5.111 | 11.298 | 48.808 / 26.492 | 128.276 / 121.311 / 111.080 | 2 / 1 / 1 |
| B2 | 5.276 | 11.795 | 39.098 / 29.167 | 30.565 / 101.199 / 80.204 | 0 / 2 / 3 |
| A2 | 5.353 | 11.607 | 46.548 / 29.091 | 69.144 / 112.582 / 51.862 | 1 / 1 / 1 |

四条样本均保留；没有稳定低于10秒或稳定1% low改善，也不能把差值单独归因于侧车。严格散列预检会预热系统缓存，user目录也已被诊断预热；不是冷盘或无缓存，不含1Hz宿主负载观察，不能宣称排除了其他程序/OS/GPU干扰。四条不足以得p95。ABBA使用高速几何焦点穿行，非真实玩家；地图/预制件paint开启，但进口模型材质、HUD及外围仍未覆盖。与此前正式地图 map24 的控制参数及内容地址不同，不能跨实验直接相减。原始 `isolated_axel_dds_samples_01/` 包含诊断、每轮资源核对、逐帧JSON、切换日志和 `abba_analysis02.json`。这些结果不构成候选正式发布或整体画面验收。
