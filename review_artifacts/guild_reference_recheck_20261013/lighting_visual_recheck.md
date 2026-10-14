# 菱石灯自投影与入口阴影复验

通过：受控闭合发光石体自遮挡修复的 CPU 合同及整楼 GPU 实图；冻结 GLB 未修改。

整楼源 SHA256：`ff905eb6f9f47ec19b64b8b85ae200d28cbbc0bef5ae40bc77f28899dbdd1f8b`。运行实现 SHA 见同名 JSON。

整楼实际是 6 枚大厅菱石 + 2 枚门口菱石，共 8 枚；另 8 个为蜡烛 socket。只改变全材质发光、严格包含有效 socket 的闭合实体投影，金属框与玻璃保持原状态。共享资源、流式重建及派生合批语义不变；缺材质、边界、开壳、空心和混合材质保守保留。20 项 headless 回归通过。

- [entry_closed_still.png](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_lighting/entry_closed_still.png)：入口石墙、木门及浅石门框的阴影边界都有相同交叉采样纹，跨材质出现。 SHA256 `b4e398c5a8eef819118a10413de9b430d9afb263333b5bb22c734b6cdcb81f3e`
- [entry_closed_no_ssao_still.png](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_lighting/entry_closed_no_ssao_still.png)：关闭 SSAO 后上述网纹仍然存在。 SHA256 `395f02c6e26f8f0fc641d5ea6a7d6b2c3ce65076527f4461c22d3f681984bfb7`
- [entry_closed_no_sun_shadow_still.png](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_lighting/entry_closed_no_sun_shadow_still.png)：仅关闭太阳阴影后网纹消失；证明问题位于方向光阴影，不据此改坏源 PBR 纹理。 SHA256 `d70f2a6e14f91906bc3279bae21adc29383ebbd126fce21b6b0dcc1b3d874273`
- [lantern_detail_night_still.png](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_lighting/lantern_detail_night_still.png)：墙体现在得到连续暖光；内部顶盖、底座受光合理，原菱石自身遮挡导致的三角亮斑消失。保留框架、顶盖遮挡。 SHA256 `dc0cf7b56040221be05d938029d69173ad328cb3ef054544e78f85c61911b8b4`
- [hall_night_still.png](D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_lighting/hall_night_still.png)：大厅近灯桌边、地面出现暖光；夜间整体仍较暗，但自发光石体不再堵住真实点光。 SHA256 `600b2b7c2b63a692e1457fc3c61053ca5b539d6ddf4095afefea5e38a275c868`

- 昼夜灯池预算及完整活动柜门运行证明仍由当前源运行专项汇总。
- 入口日光终图需改进测试方向光阴影采样后重拍；关阴影图仅作定位，不作为有完整投影的最终验收图。
- 此记录不代表正式内容库或地图部署。
