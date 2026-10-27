# 共享纹理图片回收：独立复现（2026-10-27）

证据目录 `D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/texture_phase_20261025/material_cache_pressure_20261027/`。先前官方 profiler `reload_official15` 的单帧中 `SharedPrefabImages.release` 包含耗时最高10.596ms；该数字不能单独证明图片析构是整帧根因。

`tools/test_shared_pixel_release_cost.gd` 使用真实 Pool.offer、reserve_bundle、commit、publish、producer/follower与最后consumer release；填充/上传不计入释放计时。弱引用验证共享消费者和可选外借者；借用者保留时 pool 的释放不代表实际像素已经销毁。子类逐项计时与原始 Pool 做 ABBA，分项本身有计时开销，不与普通实图帧混用。输出是对象计账/逻辑字节，不代表 RSS 或实际VRAM；16张 RGBA 样本触碰256MiB，不能与实图基准同时运行。

`reclaim20.log` headless 原池在16张 2048² RGBA8、256MiB 条件下最后释放为17.297/16.754ms；分项图片释放16.233/16.770ms。保留一张借用后最后 pool release 14.971/16.730ms，借用者随后释放约0.9ms。GPU关闭；不是实际地图纹理分布。

`reclaim22.log` 使用外部现存完整2048² DXT1 mip DDS的像素，16张共44,739,456字节；headless原池3.213/8.490ms，分项图片3.013/3.557ms。`reclaim23_gpu.log` 私有桌面同输入且启用真实 ImageTexture ticket，原池3.663/3.460ms，分项图片3.662/3.480ms，texture 0.153/0.160ms；包含分项计时开销，未证明整图同等分布，也未证明 GPU 释放总成本。两份检查均0失败；原始逐样本和慢结果保留。`reclaim19.log` 是测试脚本静态类型解析失败，已修正；`reclaim21.log` 使用的旧DDS不含完整mip链，预期检查失败，该次没有DDS测量。不能把失败样本当性能结果。

候选方向：Image/Texture/RID仍在主线程操作，仅转移纯CPU COW字节引用，合批且受统一线程及字节预算限制；同一逻辑binding的新旧代必须各自持有独立租约，旧代任务结束不能释放新代。后台停止持有自己的字节引用并不证明外部借用者已经释放；产品就绪、池内退休状态、账本、quiesce/关闭合同须分别验证。在反例、压测及整图对照完成前不宣称该候选已修复。

此外 `material_publication_scope_20261027/map16_draw20` 使用返回阶段 pre-draw 标记后25ms阈值，正常引擎与GDB退出0、源和地图一致，但没有触发、没有栈；不能作为已复现/已解决的draw长帧或普通性能数据。
