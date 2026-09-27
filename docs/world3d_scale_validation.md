# 三维米制与 VRChat SDK 核验

核验日期：2026-09-27。项目世界坐标 1 单位 = 1 米，与 VRChat 的 Unity 默认立方体边长一致。角色导入的 0.8 倍缩放是素材身高调整，不是世界米制换算。

## 官方依据与下载

- [VRChat 创建头像说明](https://creators.vrchat.com/avatars/creating-your-first-avatar/)用边长 1 米的 Unity Cube 检查尺寸。
- [Unity 基础物体说明](https://docs.unity.com/en-us/engine/6000.5/manual/working-with-gameobjects/gameobject-fundamentals/primitive-objects)说明默认 Cube 边长为 1 单位。
- [VRChat VPM 仓库](https://vcc.docs.vrchat.com/vpm/repos/)中的官方索引用于查找包版本。
- 本次下载 [Worlds SDK 3.10.5](https://github.com/vrchat/packages/releases/download/3.10.5/com.vrchat.worlds-3.10.5.zip)，Unity 2022.3；zip SHA-256 与索引匹配：`51fbd4812ca9216b91d4a242319f8a29058222f2819ecebc3bce086093ffda7c`。

下载、解包和测量报告留在工程外 `D:/code/rmmo_runtime/review_artifacts/vrchat_scale/`。

## SDK 实测

检查 Samples/UdonExampleScene/SampleAssetsSet 的 FBX、importer meta 和 Prefabs 中的立方体；tools/inspect_vrchat_scale.py 用 Blender 读取实际网格包围盒，并断言导入缩放后的尺寸与 prefab collider 一致。

| 样例 | Prefab scale | BoxCollider 尺寸 | 含义 |
| --- | --- | --- | --- |
| VRC_cube_B_matte | 1,1,1 | 1,0.99999994,1 | 标准一米参照 |
| VRC_cube_A_matte | 1,1,1 | 1.0213454,1.0213451,1.0213455 | 外形略大，不宜用外包围盒直接当一米 |

FBX 在 Blender 的 B 方块包围盒约 0.01 米；Unity importer 的 globalScale=100、useFileScale=1 将它补偿到一米。不能将这个原始 FBX 测量值当作 Unity 世界尺寸。sdk-measurements.json 保存逐轴实测。

## 本地运行时

tools/test_world3d_scale.gd 创建 1×1×1 的 WorldDocument 方块，导出 GLB 后经正式地图 glTF 路径重载。实际 Vulkan 运行验证包围盒 1×1×1、底面 0、顶面 1，trimesh 碰撞体从上方射线命中 y=1。one_meter.glb、rmmo-measurements.json 和 scale-comparison.png 保存结果。

同场共享角色模型在站立姿势的 Body+Hair 蒙皮顶点高度约为女 1.830774 米、男 1.896425 米，包含发顶，不含鞋和额外头饰。这个测量不是裸足医学身高，也不意味着用户已经确认最终角色身高设计。

本次完成 SDK 文件与本地运行时交叉核验，没有安装启动 Unity 编辑器或 VRChat 客户端；不声称已进行两客户端联机或视觉视角标定。
