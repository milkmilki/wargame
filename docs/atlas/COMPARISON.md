# 原版／Godot 实机对照

这些是原始渲染器截图，没有后处理。左列为固定 civ-atlas `103afd3d998eac6750692a6813bf5aea03521448` 的 Chromium Canvas，右列为 Godot 4.7.1／AMD RX 7600／OpenGL Compatibility。两边均为等距圆柱、2048×1024、城市阈值严格大于 1、水文仅用于环境、静态 40 国；没有河流绘制、人口成长或历史推演。

Godot 默认入口完整原生生成。大地图参考 JSON 和开发缓存不属于运行时依赖。比较工具对原版施加同样的城市筛选、静态分国和河流关闭规则；因此这里比较的是这组已确认规则下的原版生成及画风，而非原版历史演化某一年。

算法证据见 [VALIDATION.md](VALIDATION.md)，文件 SHA256、截图参数和运行记录见 [evidence/manifest.json](evidence/manifest.json)。**这些图用于用户视觉验收，尚未标记为逐像素相同或视觉达标。**

## 政治全图：省份生成、静态国界与道路

全图比较先隐藏城市和文字，使填色、边界及道路差别更容易辨认。道路使用相同候选城市、主城等级、禁水成本和原版生成顺序，立即显示全部已生成陆路。

| 种子 | 原版 | Godot |
| --- | --- | --- |
| 1 | ![原版种子 1](evidence/original-political-1.png) | ![Godot 种子 1](evidence/godot-political-1.png) |
| 7 | ![原版种子 7](evidence/original-political-7.png) | ![Godot 种子 7](evidence/godot-political-7.png) |
| 2024 | ![原版种子 2024](evidence/original-political-2024.png) | ![Godot 种子 2024](evidence/godot-political-2024.png) |

## 种子 1 的其他模式

| 模式 | 原版 | Godot |
| --- | --- | --- |
| 地形 | ![原版地形](evidence/original-terrain-1.png) | ![Godot 地形](evidence/godot-terrain-1.png) |
| 省份 | ![原版省份](evidence/original-province-1.png) | ![Godot 省份](evidence/godot-province-1.png) |
| 宜居度 | ![原版宜居度](evidence/original-habitat-1.png) | ![Godot 宜居度](evidence/godot-habitat-1.png) |

省份参考图使用每省独立归属的原版政治绘制，以便比较省份填色与边界。宜居度显示环境场；城市资格在省份生成之后按治所数值筛选，因此改变阈值不会改变省份形状。

## 海岸、山林、国界交汇与道路近景

种子 1，镜头中心世界坐标 `(500,420)`；表中倍数相对完整 2048×1024 地图。点击和放大政治填色查询相同平滑边段，逻辑划省数据仍只生成一次。

| 缩放 | 原版 | Godot |
| --- | --- | --- |
| 2× | ![原版 2 倍](evidence/original-zoom-2.png) | ![Godot 2 倍](evidence/godot-zoom-2.png) |
| 4× | ![原版 4 倍](evidence/original-zoom-4.png) | ![Godot 4 倍](evidence/godot-zoom-4.png) |
| 8× | ![原版 8 倍](evidence/original-zoom-8.png) | ![Godot 8 倍](evidence/godot-zoom-8.png) |

## 城市符号与文字

两边使用相同名称输入、原版地理实体与国家拟合路径、同源霞鹜文楷 Medium。参考工具固定国号为静态国家名，并固定城市等级为城市／主要城市／首都，保留原版文字避让与符号绘制；不将人口或历史逻辑引入预览。

| 视图 | 原版 | Godot |
| --- | --- | --- |
| 全图 1× | ![原版文字全图](evidence/original-labels-1.png) | ![Godot 文字全图](evidence/godot-labels-1.png) |
| 近景 4× | ![原版文字近景](evidence/original-labels-4.png) | ![Godot 文字近景](evidence/godot-labels-4.png) |

原生绘制已修正误用粗体、偏细光晕和留白不足；最终避让位置、字形基线及抗锯齿仍有差别，不能由名称／拟合路径测试替代看图。国家和城市名称始终使用清晰上层绘制，不随罩染模糊。

## 经线和极地

| 视图 | 原版 | Godot |
| --- | --- | --- |
| 跨 180°，4×，中心 `(2048,440)` | ![原版经线](evidence/original-seam.png) | ![Godot 经线](evidence/godot-seam.png) |
| 极地，8×，中心 `(880,160)`，纵向限制 | ![原版极地](evidence/original-polar-8.png) | ![Godot 极地](evidence/godot-polar-8.png) |

海冰边链已逐点对照，但 Shader 的背光及排线实现与 Canvas 裁剪阴影不同。罩染透明度、海岸断头附近回退取样和极锐线角也保留差异说明，详见验证文档。

## 打开原型

在 Godot 编辑器打开 `res://atlas_preview.tscn` 后按 F6。首次冷生成加显示准备约一分钟上下，本轮只记录耗时。建议先看默认种子 1 的政治全图，再放大山林、三国交汇和海岸；切换省份模式、改变单省归属，并测试经线平移。

用户确认画风达到目标之前，不接入军事、贸易、补给、战斗；本轮未提交、未推送。
