# WorldWar · Atlas 2D

Godot 4.7 原生2D全球地图与州府军事模拟。正式入口为 `atlas_military.tscn`，默认真实地球、种子1。支持随机星球、四种地图模式、州府、共享道路、行军、补给、野战、攻城和军事AI。贸易结算、动态统治者与海运当前关闭。

打开 `project.godot` 后运行项目即可。运行时不依赖 Node、浏览器或 `.dbg` 缓存。`atlas_preview.tscn` 与 `atlas_earth_preview.tscn` 是同一新地图模块的开发预览。

```powershell
& 'D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe' --path .
python run_tests.py --godot 'D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe'
```

测试分为 `--group core` 和 `--group atlas`，默认全部。军事烟测默认35天；完整365天使用 `--days 365 --timeout 1800`。日志写入 `.dbg/regression/`。实机截图可用 `-- --atlas-capture=绝对路径.png --atlas-labels`，必须使用图形渲染器。

旧欧亚、中国高度图场景、3D地图、河流交通生成器和专用测试已移除。旧地图模板3～8不再支持，版本9仅接受Atlas地图；地图模板用于重新开局，不是战役存档。测试目录的合成网格只用于共享模拟回归。

详见 [军事接入](docs/atlas/MILITARY_INTEGRATION.md)、[地图算法与绘制](docs/atlas/README.md)、[本次迁移记录](docs/atlas/LEGACY_REMOVAL.md)。上游移植代码与资源的许可和来源见 [NOTICE](assets/atlas/NOTICE.md)。
