# Atlas 拖动与缩放优化

2026-10-09；`feature/civ-atlas-godot` 工作树，基线 `f2396b6` 加前线实现。
输入固定为原生地球种子 1、40 国、1796 治所、4321 交通节点。
真实 Godot 4.7.1 / D3D12 Forward+ / AMD RX 7600，1280×720，模拟暂停。
开发缓存仅跳过生成阶段，绘制、相机、输入和军事层均走正常实现。

## 定位与改动

分层测量发现，军事层在每帧重新提交静态州界和府界：完整绘制约
57173 次调用，`_draw` 单次实测约 12 秒。隐藏该层后，道路、海岸与文字
仍在相机移动时重建。依据
[Godot 绘制缓存机制](https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html)
调整失效范围，保留动态军队、战斗标记刷新。

- 州界、府界合并为少量网格；静态绘制不再每帧重新提交。
- 道路、国界和海岸只构建可见范围加192屏幕像素余量的网格；小幅拖动
  复用缓存。选择完整边链，不截断虚线相位，不改实际交通路径。
- 地形符号纹理增加192像素余量；同缩放下的小幅拖动复用现有纹理。
- 输入期间立即对已有符号、文字作相机变换，停止输入140毫秒后再生成
  精确细节、字号和避让。重排时重置临时变换，避免累计坐标误差。
- 把政治填色的当前缩放与符号纹理的缓存缩放分开，保持曲线填色、海岸
  抗锯齿及符号让色位置一致。使用实际时间防止旧长帧提前触发重排。

## 测量

| 项目 | 实测 |
|---|---:|
| 原同步拖动，2×／4× | 26460／18747 ms |
| 原同步缩放至2×／4× | 6679／12869 ms |
| 缓存和合批后的同步完整拖动，2×／4× | 439／470 ms |
| 最终真实拖动输入：8帧的画面响应中位数 | 13.90 ms |
| 最终真实滚轮输入：6帧的画面响应中位数 | 16.26 ms |
| 输入停止至精细排版完成，拖动／滚轮 | 618／615 ms |
| 最终府辖区近景绘制调用 | 2652 |

前两组同步测量含完整细节重绘；最后两组输入响应先复用已有画面，完整
重绘在停止输入后发生，因此不把即时响应视为所有重建工作的耗时。
拖动响应样本范围9～53毫秒，滚轮10～27毫秒。仍有约0.6秒的停止后精细
更新成本；长距离连续移动期间，新进入视野的符号和文字会在停止后补齐。
这轮没有修改首次世界生成、军事AI或模拟日结算法，不声称运行期所有
负载都达到相同帧率。

## 验证与复现

新增静态绘制失效、可见边链缓存、相机即时反馈和长帧计时回归。
相关9项自动测试通过；综合套件505项通过。
真实GPU输入测试0失败、stderr为空，14次输入都未同步重建文字或符号；
检查地块与交通数据不变、停止后的精确变换恢复、前线及模式切换。
全图、4×／8×中国、经线及府辖区截图已经实际查看。

```powershell
python run_tests.py --godot D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe --tests atlas_camera_feedback atlas_render_invalidation atlas_view_caches atlas_native_strokes atlas_preview_lifecycle atlas_war_fronts project_compile test_suite political_history_test --timeout 120
$navProbe = Start-Process D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe -ArgumentList @('--path','D:/ProjectICreate/Wargame/wargame','--script','res://tests/atlas_navigation_visual.gd','--','--atlas-cache=res://.dbg/atlas-military-earth.bin') -WindowStyle Hidden -PassThru
```

无开发缓存时，GPU测试仍会从正式入口原生生成。
实际PID、种子、参数、源文件与截图SHA256、阶段测量和输出记录均在
`navigation_evidence/`。基线测量进程26296，最终验证进程32796。
重新运行测试会更新该目录的实际结果。
