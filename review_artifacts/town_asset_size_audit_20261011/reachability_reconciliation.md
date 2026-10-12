# 可达图复核补充（2026-10-11）

32项与 `model_texture_code_audit_20261011.json` 完全吻合：366张声明图像中130张从所有mesh材质可达；其余236张=106张仅由未使用材质引用+130张没有材质引用。**全部366张都有texture.source引用**，此前“未引用图片”应准确写作“未从mesh材质图可达的图片”，不能直接删image表而不清理texture/material和索引。

初版inventory以默认场景为根，新复核以全部声明mesh为根；这32项两个集合恰好完全相同。当前无真实extension对象，仅有specular/transmission声明。十件无损候选复核全部通过：源/候选SHA、全部mesh解析图、保留bufferView逐字节、节点/场景/extras一致。transmission声明的路灯不在这十件中，保守helper会拒绝，未静默处理未知扩展。

清理取活跃accessor与image的bufferView并集，重映射两类引用且保留view/accessor布局；当前32项没有图像与几何共用view。12类当前extras已逐类核对，均无需要重映射的GLB表索引。**工具不是通用extras索引解析器**：未来未知扩展或custom extras应先分类/拒绝，不能凭“extras字典没改”就判定可安全清理。

彩旗与植物降分辨率候选有明确像素变化，不纳入无损图像相等结论。未运行GPU、未修改正式资源或地图。

LOD/拾取后续建议：保持LOD组和author UUID，以独立稳定的精确拾取代理避免每个LOD重复建拾取形状。`rmmo_collision:none`只去掉游戏/行走碰撞，**必须仍能在编辑器选择**：保留layer 1，单独排除WALK_MASK。当前visibility range不改变Node.visible，不能据距离自动假定其它LOD无需拾取。代理优化尚未实现，需另外验证隐藏/楼层、重叠物、风场位移、撤销保存。

完整逐项证据：`reachability_reconciliation.json`；复查脚本：`reachability_reconciliation.py`。
