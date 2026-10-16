# DragonUI Enhanced

DragonUI 增强模块（WotLK 3.3.5a）。依赖 **DragonUI**；设置页挂在 DragonUI Options → **增强**。

命令：`/duie` 打开设置；`/duielegacy` 检查仍在加载的冲突旧插件。

## 功能一览

| 分类 | 功能 | 说明 |
|------|------|------|
| 通用 | 移动速度 | 玩家/目标移速百分比，可拖动 |
| 通用 | Buff 关键词屏蔽 | 目标/焦点/队伍垃圾光环 |
| 战斗 | 技能触发提醒 | 大灾变风格 Overlay + DragonUI 动作条发光（替代 ElvUI_VisualProcs） |
| 战斗 | 队伍光环 | 队伍框重要职业 buff + 可驱散/重要 debuff（有才显示；默认可左/右/下） |
| 聊天 | LFG Bot 屏蔽 | bot 公会/角色、Telegram 系统提示、主城 `/who` |
| 聊天 | 聊天增强 | 频道缩写、时间戳、Tab 切频道、`/duieroll` |
| 聊天 | 快捷聊天栏 | 频道按钮 + 表情面板，可拖动 |
| 工具 | 符文动作条 | 换装后回填符文技能 |
| 工具 | 装备列表 | 角色/观察旁列表（宝石/附魔） |
| 工具 | 装备助手 | 天赋/PvP/挑战配装切换 |
| 工具 | 好友同步 | 阵营共享好友库 |
| 工具 | 玩家右键菜单 | 扩展右键菜单（不含职业 buff） |

## 建议禁用的旧插件

功能验收通过后，在**角色选择 → 插件**中禁用（不会删除 SavedVariables）：

| 文件夹 | 原因 |
|--------|------|
| `MotionSpeed` | 已由增强覆盖 |
| `ChatBar` | 已由增强覆盖 |
| `FriendsMenuXP` | 已由增强覆盖 |
| `ElvUI_TinyInspect` | 已由「装备列表」覆盖（装等仍用 DragonUI） |
| `ElvUI_bbTools` | 符文/装备助手/好友同步已覆盖；若仍需 Unitscan 遥控、竞技场截图等可暂时保留 |
| `ElvUI_VisualProcs` | 已由「技能触发提醒」覆盖（Overlay + 按钮发光） |

**不要**为了本插件去禁用整个 `ElvUI_Enhanced`（只迁了 bot 过滤相关逻辑）。

登录约 3 秒后若仍加载上表插件，聊天框会提示；设置 → 增强 → 通用 →「旧插件禁用清单」可复查。

## 数据迁移

首次启用对应功能时，从旧 SavedVariables **只读导入一次**（`DragonUI_EnhancedDB.global.migrated.*` 记标记），**不删除**旧表：

- `bbToolsDB` → 符文条 / 装备助手 / 好友同步
- 旧装备列表相关配置 → 装备列表（若存在）
- LFG 动态屏蔽名单 → `global.lfgBlockedPlayers`

回滚：禁用 Enhanced、重新启用旧插件即可。

## 明确不做（或 P6）

- WhisperInvite、装备出处 tooltip；旧斜杠命令已改由设置页按钮操作
- Unitscan 整功能、ArenaScreenshot、MemoriesData、YssBossLootData、ElvUI 配置导入

## 版本

见 `DragonUI_Enhanced.toc` 与 [CHANGELOG.md](CHANGELOG.md)。
