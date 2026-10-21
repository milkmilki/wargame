## 调试运行复现约定

所有 Debug 场景运行自动通过 `DebugRunLog` 记录复现信息到项目目录 `res://.dbg/debug_runs/`，不得再写到 C 盘用户目录。预览生成与军事运行共用同一会话。只保留最新一次运行及其最新一张初始地图；并行活动会话暂时保留，正常关闭、日志对象释放或下次启动时清理已结束／已退出的旧会话。清理只匹配本模块生成的文件，不递归删除其他目录。需要读取当前会话产物时，应在 `close()` 或释放日志对象之前读取。

排查正在运行的随机局时，先读取对应 PID 的运行日志，核对实际 `seed`、场景、代码版本、生成参数及最近 `day`，不要把场景里的固定回退种子当作随机局种子。日志的战争 ID 从0开始，界面的“战争N”对应 `N-1`。重新生成和读入地图均需保留独立 world_index 元数据，旧地图模板会被最新成功写入的模板替换；初始地图模板用于重建地图，不能当成运行中存档。日志不得消耗模拟随机流或修改游戏状态；改动启动入口时保持此记录机制。提交和推送仍交给用户指定的“代码推送者”对话。

## 战争回归约定

修改战争、占领、议和、兼并、灭国清理或编年史时，必须评估并覆盖“被宣战方反攻并灭掉宣战方”的反向路径，不能默认主动方就是胜者。根据改动范围检查双方视角、领土与资源归属、战争关系与军队绑定释放、联盟部分成员灭国，以及最终事件只结算一次。测试应走相关真实事务和生命周期入口，不能仅修改存亡标记后断言文案；同时保留正向胜利回归。

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**This project has a knowledge graph. Start with the code-review-graph
MCP tools to narrow scope, then read the source.** The graph is cheaper than scanning files and
gives you structural context (callers, dependents, test coverage) that file search cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes_tool` or `query_graph_tool` instead of Grep
- **Understanding impact**: `get_impact_radius_tool` instead of manually tracing imports
- **Code review**: `detect_changes_tool` + `get_review_context_tool` instead of reading entire files
- **Finding relationships**: `query_graph_tool` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview_tool` + `list_communities_tool`

### Verify in the source

- Narrow scope with the graph, then read the source. Do not change code from graph output alone.
- For any non-trivial change, read the implementation and the relevant tests before concluding.
- Verify the exact source when touching behavior, database logic, migrations, retries, fallbacks,
  recovery, or compatibility code.
- When the graph and the source disagree, the source wins. The graph may be stale or may not
  model that relationship.
- An empty graph result can mean "not indexed" or "not statically visible", not "does not exist".

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes_tool` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context_tool` | Need source snippets for review — token-efficient |
| `get_impact_radius_tool` | Understanding blast radius of a change |
| `get_affected_flows_tool` | Finding which execution paths are impacted |
| `query_graph_tool` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes_tool` | Finding functions/classes by name or keyword |
| `get_architecture_overview_tool` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. Explicitly update the graph before review; do not assume hooks have succeeded.
2. Use `detect_changes_tool` for code review.
3. Use `get_affected_flows_tool` to understand impact.
4. Use `query_graph_tool` pattern="tests_for" to check coverage.
<!-- /code-review-graph MCP tools -->

## 代码图谱提交约定

每次提交都必须更新代码图谱，文档和配置提交也不例外。提交前对当前工作区调用 `build_or_update_graph_tool`（明确传入本仓库 `repo_root`），再进行图谱审查和源码核对；不要仅依赖 Git 钩子。
提交成功后再次增量更新，并用 `list_graph_stats_tool` 核对 `_graph.built_at_sha` 等于当前 `HEAD`、`head_matches_build=true`。图谱更新失败时先修复或明确报告失败，不得宣称已同步或直接继续推送。
交给用户指定的“代码推送者”对话时，必须一并传达这项要求；提交方执行更新，交接方复核最终提交的图谱状态。图谱只维护当前索引，不额外保存历史图谱、版本副本或性能证据归档。

## 性能优化场景约定

用户已确认：默认启动、后续性能基线和优化验证统一使用欧亚遮罩，北纬20°～55°、西经15°～东经145°，真实地球种子1、40国。
必须核对实际生成参数中 `settlement_mask.enabled=true` 及四个边界；不要拿全球缓存或全球战争快照替代欧亚性能基线。
全球地图只用于兼容回归。比较性能时使用相同的欧亚运行中状态、天数、CPU条件和模拟配置，分开记录计算耗时与GUI帧耗时。
