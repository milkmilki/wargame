# 河岸供水、连通谷地与密度上下限（2026-10-07）

## 交付状态

已实现两个独立候选地图源，复用原墨卡托高程与高精度矢量河网，无需下载或重建地形。正式 `eurasia.tscn` 仍引用 `eurasia_hydrology_map_source.json`。候选尚未通过全部分布和性能门槛，因此没有切换正式场景；本轮未提交或推送。

- `eurasia_uniform_river_map_source.json`：统一所有可见河段的城市供水，基础半径 0.04，沿用无密度下限。
- `eurasia_valley_river_map_source.json`：在上述近岸供水外，增加连通平原、谷地扩散与弱纬度修正，并采用用户选定的 **5%～100% 选址权重**。

这些数值为游戏抽象，不代表真实灌溉距离、河流流量或历史人口。原人口、产出、道路通行性、主次河分类与航运规则不变。

## 实现约定

`river_settlement_support.gd` 使用到矢量线段的投影距离，全部可见主支流强度一致；近岸支持 1，半径外 0。落点到河床高差约 19 米以内完整支持、约 248 米以上归零；多条河取最大值，避免汇合口重复加分。环境格中心和实际扰动落点共用函数。

`valley_water_support.gd` 从河道经过的分析格出发，用四邻接最小成本传播。预算为地图高度单位 0.12；距离、上坡与起伏消耗预算。原始高程逐像素检查中间山脊和海面，防止两个低端点隔山供水；这也用于本候选的近岸直接供水。分析网格仍为 256×256，没有修改河网走向或汇流。

纬度仅对**外延供水强度**作最多 15% 的弱衰减，中心纬度为绝对值 27°，宽度参数 7°；近岸基础支持不乘此系数。公式是 `1 - 0.15 * exp(-((abs(latitude)-27)/7)^2)`。这是统一的纬度带游戏参数，没有中国、撒哈拉等区域特例。外延和近岸供水取最大值。

城市采样从原始宜居度得到 `clamp(raw_suitability, 0.05, 1.0)`，用于随机排序及局部间距。原始温度、降雨、供水和宜居度不被下限改写。恶劣环境合法陆地仍可入选，但不保证每个地区有城市，也不保证恰好 5% 的城市落在恶劣区。海面、河岸合法性、唯一省份格、渡口净距等限制不因下限失效。间距最多放宽至 80%，不足仍返回失败。

密度配置位于可选 `settlement_density_bounds`，缺省 `{minimum:0, maximum:1}`，仅允许环境选址模型。数值必须有限，满足 `0 ≤ minimum ≤ maximum ≤ 1` 且 maximum 大于零。上下限加入城市布局缓存与复现日志，但不使不变的物理环境缓存失效。

统一与谷地模型都取消整条主河的额外城市间距，改为确定性预留局部渡口。主河屏障连通区域的候选渡口构成图，按地形和稳定位置排序选连接骨架；省份生成后绑定实际两岸。无法合法连通时仍失败，不以非法陆路补接。支流不预留渡口。

## 实测结果

### 扩大圆形半径并不能解决分布

原河网、降雨及五个固定种子不变时，每局区域平均城市数如下。窗口重叠部分按四川、关中、中国中部的先后顺序归类，所有实验采用同一窗口。

| 半径 | 四川 | 关中 | 中国中部 | 撒哈拉 | 阿拉伯 |
|---|---:|---:|---:|---:|---:|
| 0.025 | 3.8 | 3.0 | 23.2 | 14.8 | 9.2 |
| 0.04 | 4.0 | 2.2 | 24.6 | 19.4 | 11.6 |
| 0.06 | 3.4 | 2.4 | 20.2 | 26.0 | 13.0 |
| 0.08 | 5.2 | 2.0 | 18.0 | 27.8 | 11.4 |
| 0.12 | 4.0 | 2.6 | 17.8 | 34.0 | 13.8 |

扩大圆形范围会同时增强干旱区已生成的河网，固定 500 城重新竞争后，中国区域不一定增加。这是改试连通地形扩散的依据。图见 [中国半径对照](images/river-radius-sweep/radius-china.png) 与 [干旱区半径对照](images/river-radius-sweep/radius-sahara-arabia.png)。

### 谷地扩散 + 5% 下限

合成等面积的零宜居区与最佳区，20 个种子、每局 64 城，累计分别 60 和 1,220 城。uniform_v1 与 valley_v1 均通过；默认无下限时零宜居区仍不入选。最高权重 0.5 的单独测试确认实际间距随上限变化。原始环境数组、海陆、河岸与渡口约束均保持。

合成连通平原中，原近岸半径外供水为 0.213975；同距离隔山、隔海均为零。仅纬度改至 27°后为 0.189581。上下游、主支流和经度平移不改变对应供水。

五种子 `2342006650、12345、23456、34567、45678` 全部通过 500 陆地城市、40 国、唯一种子格、省份、主河交通、西欧—中亚—中国连通及模板检查；码头分别为 98、96、94、104、103。中国/旧环境/新模型往返及环境缓存隔离通过；改变密度上下限不污染原始环境。

20 种子固定沿河样本统计（样本格在扩张前冻结，详见 `tests/fixtures/river_settlement_fixed_samples.json`）：

| 固定窗口 | 样本格数 | 原流量加权城市数 | 谷地+5% 城市数 | 平均原始宜居度变化 |
|---|---:|---:|---:|---|
| 四川 | 47 | 9 | 32 | 0.00440 → 0.71182 |
| 关中 | 13 | 19 | 11 | 0.46427 → 0.73825 |
| 中国中部 | 244 | 232 | 211 | 0.87773 → 0.92372 |
| 撒哈拉 | 235 | 2 | 194 | 0.01090 → 0.96980 |
| 阿拉伯 | 136 | 59 | 110 | 0.29421 → 0.98888 |

**关中沿河密度至少翻倍的原验收未通过。** 不以扩大窗口或地域加权隐藏失败。撒哈拉、阿拉伯的固定远河干旱样本累计出现 54、19 城，与用户最新选择的非零下限一致；原先“完全无城”的结果不能再作为本候选目标。沿河窗口城市增加不代表整片荒地的物理宜居度提高。

`river_settlement_regions.gd` 保留原翻倍断言，因此当前候选运行此测试会明确失败。最新选择改变了最低密度要求，并没有取消关中目标或性能目标。

365 天实际模拟（seed 12345）通过：12 次战争、91 次领土易手，领土、财政有效性、军队绑定和逐日继承审计无错误；存在正常的资源短缺，未修改经济公式。

实际 D3D12 场景（seed 12345）通过城市移动、编辑重新生成、失败保留原世界、模板保存读入、历史回看、点击拾取及大陆交通检查。启动至地形就绪为 39.091 秒（单次），包含省份、道路、国家和渲染准备。[中国实际画面](images/valley-rivers/scene/eurasia-china.png)、[全图实际画面](images/valley-rivers/scene/eurasia-full.png)。

五次独立进程、串行测量气候/水文/500城采样，冷运行分别 6812.832、6937.002、6871.103、6982.783、6901.789 ms，中位数 **6901.789 ms**；缓存后换种子分别 2978.246、3226.723、3055.208、2946.956、2988.311 ms，中位数 **2988.311 ms**。仍未满足原定 3 秒/1 秒门槛。主要额外成本是原图精度的连通性检查；已先排除距离、高差不可能改善结果的河段再检查山脊，与优化前逐项比较供水、宜居度、城市坐标及河网完全一致。未为提速取消山脊检查。

同种子前后诊断：[全图](images/valley-rivers/uniform-full.png)、[四川](images/valley-rivers/uniform-sichuan.png)、[关中](images/valley-rivers/uniform-guanzhong.png)、[中国中部](images/valley-rivers/uniform-central-china.png)、[尼罗河](images/valley-rivers/uniform-nile.png)。图中的宜居度是原始物理评分，红点使用带上下限的实际选址权重，不能把两者混为一项。

## 再生成与回归

以下命令从 Godot 项目目录执行，`godot` 指本机 Godot 4.7.1。Windows GUI 版可执行文件请用 `Start-Process -Wait` 或项目本地测试包装脚本等待退出；性能测试需串行独立进程、避免其他重负载。

```powershell
$env:HYDROLOGY_SOURCE = 'res://assets/terrain/eurasia_valley_river_map_source.json'
godot --headless --path . --script res://tests/river_settlement_density_bounds.gd
godot --headless --path . --script res://tests/river_settlement_valley.gd
godot --headless --path . --script res://tests/river_settlement_cache.gd
godot --headless --path . --script res://tests/hydrology_world.gd
$env:REGIONS_OUTPUT = 'res://.dbg/valley-regions.json'
godot --headless --path . --script res://tests/river_settlement_regions.gd # 当前预期报关中未达门槛
$env:ENV_DIAGNOSTICS_FILE = 'res://.dbg/valley-fields.json'
godot --headless --path . --script res://tests/river_settlement_benchmark.gd
Remove-Item Env:ENV_DIAGNOSTICS_FILE
$env:EURASIA_VISUAL_DIR = Join-Path (Get-Location) '.dbg/valley-scene'
godot --path . --script res://tests/eurasia_scene_smoke.gd
Remove-Item Env:HYDROLOGY_SOURCE, Env:REGIONS_OUTPUT, Env:EURASIA_VISUAL_DIR

$env:AI_LONGRUN_MAP_SOURCE = 'res://assets/terrain/eurasia_valley_river_map_source.json'
$env:AI_LONGRUN_DAYS = '365'
$env:AI_LONGRUN_SEED = '12345'
godot --headless --path . --script res://tests/ai_longrun.gd
Remove-Item Env:AI_LONGRUN_MAP_SOURCE, Env:AI_LONGRUN_DAYS, Env:AI_LONGRUN_SEED
```

可在欧亚场景根节点的 `map_source_manifest` 中临时指定候选清单进行试玩；验收前不要保存为正式场景默认。地图模板继续保存实际地图源及最终布局，版本 7；旧模板不自动重撒。
