# 当前项目交接

正式入口：`res://atlas_military.tscn`，Godot 4.7原生2D，默认真实地球、种子1；开发分支 `feature/civ-atlas-godot`。

旧欧亚/中国高度图入口、地图绘制器、3D资源及旧地形/水运生成管线已删除。`GameState` 只接受Atlas世界或Atlas版本9新局模板；共享军事、经济、外交和君主数据模型仍保留。合成网格生成位于 `tests/support/grid_world.gd`，不能作为游戏入口。

真实地球使用降雨v5、宜居度v6（两季封顶），原城市成为州治，州内最多三个府。行政划分固定，控制权和法理归属由现有领土事务维护。交通节点不计入城市/资源/占领目标；共享物理道路供行军、补给和野战共同使用。

当前关闭贸易结算、动态统治者事件与海运。地图模板不是战役存档。运行日志写入 `user://debug_runs/`；改变入口或生成流程必须保留实际PID、种子、配置、来源与world_index，并保持模拟随机流不变。

验证：`python run_tests.py --godot <Godot路径>`，默认共享回归+Atlas军事35天烟测。完整烟测添加 `--days 365 --timeout 1800`。真实图形验证另运行项目或截图测试。

详细模块、验证证据和遗留限制见 `docs/atlas/MILITARY_INTEGRATION.md` 与 `docs/atlas/LEGACY_REMOVAL.md`。旧实现和历史性能资料可在Git历史查询。
