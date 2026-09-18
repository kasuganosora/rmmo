extends RefCounted
## 编辑器会话态聚合（应用层）：当前包 / 地图文档 / 当前地图 id / 绘制工具。
## 组合根 ContentEditor 通过委托属性把这些字段暴露出去，使 session 成为单一数据源，
## 便于整体重置/替换，以及后续用例服务直接操作会话态。

var pack: RefCounted
var doc: RefCounted
var current_map_id: String = ""
var paint: RefCounted
