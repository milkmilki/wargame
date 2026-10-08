# 降雨调参记录

## 2026-10-08：中低海拔不消耗水汽

按用户要求只调整降雨中的山地阻挡，环境版本从 `environment_v1.6` 更新为 `environment_v1.7`。

旧容量为 `exp(-海拔km × 0.8)`，低山也会凝结并扣减向下游输送的水汽。新容量为 `exp(-海拔km × smoothstep(2.5, 3.5, 海拔km) × 0.8)`：2500米以下不扣水汽，2500～3500米平滑过渡，约3000米产生明显阻挡。纬度干燥带、风向、传播衰减、海洋补湿、温度、寒冷和土地条件未调整。降雨变化会自然改变产流、河流供水、干旱及城市选址。

测试：`rainfall_high_mountain_threshold` 修改前3项失败，修改后通过，涵盖500／1500／2400米山脊不产生雨影、3000米山脊迎风增雨与背风干燥、确定性。`settlement_environment`、`hydrology_distribution`（20种子）、`hydrology_core`通过。

正式欧亚清单、种子12345、500城／40国生成及环境编号一致性导出通过。对照工具逐项确认高程、海陆、温度、冬温、寒冷系数、平坦度、腹地及内陆性未变化。

产物：

- 基线：`.dbg/heatmaps-current-20261008/diagnostics.json`。
- 新值：`.dbg/settlement-heatmaps-rain-v17.json`。
- 新图册：`.dbg/heatmaps-rain-v17/index.html`。
- 同色标前后对照：`.dbg/heatmaps-rain-v17/rainfall-before-after.png`。
- 对照统计：`.dbg/heatmaps-rain-v17/rainfall-comparison-stats.json`。

重生成仍使用 `scripts/tools/export_settlement_heatmaps.gd` 和 `scripts/tools/render_current_heatmaps.py`。前后对照使用 `scripts/tools/render_rainfall_comparison.py BEFORE_JSON AFTER_JSON OUTPUT_DIR`，Python绘图库路径仍为 `.dbg/plotdeps`。

这次只验证参数试验，不替代未完成的六种子交通、365天与性能验收。没有提交或推送。
