# 从已购 Unreal 素材导出 PBR

网页只有“在启动器中查看”的素材，可先在 Epic 已购库下载到专用空工程，再用本机 Unreal 导出。当前实现已用 Wood Material Pack3 实测：40 张 4K PNG，11 个材质参数清单，无导出错误。

## 导出

```powershell
python tools/export_unreal_materials.py --engine 'F:/Program Files/Epic Games/UE_5.6' --content 'D:/path/to/StagingProject/Content' --asset-root '/Game/WoodMaterial3' --output 'D:/code/rmmo_runtime/cache/wood_export_new' --source-url 'https://www.fab.com/listings/ff8612c9-a38f-4d8c-95d8-5d97282e7fe4'
```

`--output` 必须是新的外部目录。工具复制 Content 资产到隔离工程，启用引擎自带 Python 插件，用 NullRHI commandlet 在不激活的独立桌面执行；不加载源工程脚本、插件或地图，不保存源资产。`--asset` 可以重复指定只需检查的材质／贴图路径。输出保留 Unreal 文件夹身份，避免同名贴图互相覆盖。

输出包括：

- `textures/`：原生 PNG，保留源分辨率和通道。
- `manifest.json`：来源、源文件及输出 SHA-256、材质父链、纹理／标量／颜色／开关参数、贴图 sRGB、压缩和绿通道翻转设置。
- `export.log`：引擎结果；`errors` 非空、无贴图或进程失败时返回非零状态。
- `staging/`：独立副本，供复查，不是发布内容。

材质依赖也通过 Asset Registry 遍历，避免 NullRHI 下已编译 `GetUsedTextures` 为空时漏图。图像导出不会烘焙任意材质图、分层混合、世界坐标投影、纹理调整或置换；全局参数解析到最终值，分层覆盖仅保留文本供复查。不能把参数清单等同于完整着色器转换。

## 筛选并安装

先检查实际导出的颜色图与配套法线，再在清单里显式选定 Unreal 材质、通道参数、法线约定、建议米制尺寸和用途：

```powershell
python tools/import_unreal_materials.py --export 'D:/code/rmmo_runtime/cache/wood_export_new' --manifest tools/fab_unreal_wood_materials.json --pack 'D:/code/rmmo_runtime/packs/default'
```

安装器验证导出 SHA-256，分类写入默认包，归档源 `.uasset`、导出参数及筛选清单。运行图最大 2K，缩小法线后重新归一化，保留原始高分辨率来源。已有材质目录会拒绝覆盖；共享 Fab 目录清单合并新增项，不清空旧条目。建议尺寸与材质适配选择明确记录，不把数值自动猜成实测物理尺寸。

此工具是离线内容加工器，没有暴露通过 MCP 启动 Unreal 或任意文件导出的接口。安装后的资产与其他默认材质完全相同，可经当前 3D MCP 的分类发现、刷面、撤销重做、保存重开和预制件依赖复制使用；旧二维 MCP 保持停用。

实现依据 Epic 官方 [Python commandlet](https://dev.epicgames.com/documentation/en-us/unreal-engine/scripting-the-unreal-editor-using-python)、[AssetExportTask](https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/AssetExportTask?application_version=5.6) 和 [MaterialEditingLibrary](https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/MaterialEditingLibrary?application_version=5.6)。
