# Atlas 原生详情框

2026-10-10，正式入口 `atlas_military.tscn`。保留此前未提交的前线与缓存绘制实现；本轮不提交、不推送。

## 来源与范围

以 civ-atlas `103afd3d998eac6750692a6813bf5aea03521448` 的
[panelParts.tsx](https://github.com/guaner-334/civ-atlas/blob/103afd3d998eac6750692a6813bf5aea03521448/src/ui/panelParts.tsx)、
[countryPanel.css](https://github.com/guaner-334/civ-atlas/blob/103afd3d998eac6750692a6813bf5aea03521448/src/ui/countryPanel.css)、
[theme.css](https://github.com/guaner-334/civ-atlas/blob/103afd3d998eac6750692a6813bf5aea03521448/src/ui/theme.css)
和 desktop.css 为依据，移植左侧卡片、色标、22像素标题、54像素快捷按钮、分组行及滚动布局。
使用其浅色主题颜色与系统无衬线字体，移植四个SVG线条图标；行军和战争图标为同套笔触的新图标。

全部使用原生Godot Control / Theme / ScrollContainer。半透明面板没有加入全视口毛玻璃采样，
保留原生圆角和阴影；不声称与浏览器CSS逐像素相同。无React、Canvas或浏览器运行时。
许可与字体说明见 `assets/atlas/NOTICE.md`。

只改变信息展示与现有操作入口。生成、气候、州府、交通、军事、贸易和君主规则没有改变。
贸易数据按当前系统状态显示“未启用”或真实缓存值；没有因此启动贸易结算或动态君主事件。

## 信息与操作

| 页面 | 内容 |
|---|---|
| 城市／州府 | 实控、法理、所属州治、首都身份、资源产出、粮仓、忠诚与动荡、守军、驻军、贸易、宜居度与气候、选中道路链接 |
| 国家 | 首都、治所及州府数量、君主与特质、国库、可用人口库、真实粮仓库存、最近月度费用与粮食估计、外交、军队与贸易 |
| 军队 | 人数、士气、供给、攻防、军费倍率、部署、道路进度、目标与战役绑定 |
| 道路 | 两端、控制辖区、长度、容量、通行军队、危险度、行军与补给倍率 |

左键点击辖区打开城市框；点“所属国家”或国家蓝字打开国家框，点首都／州治蓝字切换城市。
军队可从国家、驻军链接或“选本国军队”打开；行军中的地图军队也可直接选中。
“设为中心”只更新地图变换；原有下令、宣战入口复用现有模拟方法。
Esc／右上角×关闭。右上“地图工具”保留生成、种子、推进一天、操控国、军队、交通调试、模板、历史和截图功能。
截图导出隐藏整个界面；界面内滚轮不会穿透到地图，跨面板松开中键不会留下拖动状态。

界面每0.5秒更新已打开页面的数值；相同结构复用控件，只在信息类别或行结构变化时重新布局。
不在相机操作中排序、重建控件或调用贸易／军事预测。

## 历史数据边界

现有 PoliticalHistory 主要记录政治归属、君主、外交、布局，未完整记录库存、忠诚、产出与军队。
历史面板只展示可还原的政治与地理数据，明确写出“此政治快照未记录”经济和兵力，
不显示复制到视图状态中的当前数值。历史模式禁用军事操作及推进时间；本轮没有扩展存档或历史格式。

## 验证

- `atlas_information_model`：真实产出、固定隶属、交通节点排除、库存真源、稳定军队ID、占领实控／法理、历史记录范围、无RNG／库存副作用。
- `atlas_information_panel`：增量更新保留控件、链接与按钮使用最新目标、滚轮边界、面板裁剪、Esc关闭。
- 编译、场景释放、静态绘制失效、前线、政治历史回归通过；共享模拟套件505断言通过。
- `atlas_information_visual` 在 Godot4.7.1 / D3D12 / RX7600 / 1280×720、原生地球种子1／40国执行，PID12600，退出0、stderr为空。
  实机检查城市、国家、军队、道路、历史、返回当前、900×600窗口、工具框、真实滚轮与历史操作防护。
  120次暖缓存拖动时，控件没有重建，P95 9.818ms、P99 10.762ms；模拟暂停、基准关闭垂直同步。
  这是信息框的交互烟测，不能替代上一轮五进程性能基准，也不表示AI长帧已经修复。

截图、逐帧样本、实际参数、输出与源码哈希见 `information_evidence/`。

复现：

```powershell
python run_tests.py --godot D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe --tests project_compile atlas_information_model atlas_information_panel atlas_preview_lifecycle test_suite --timeout 90
```

实机入口为 `--script res://tests/atlas_information_visual.gd`。
可用 `-- --atlas-cache=res://.dbg/atlas-military-earth.bin` 只跳过生成；没有缓存时从正式场景原生生成。
Windows后台启动使用 `Start-Process -WindowStyle Hidden`。
