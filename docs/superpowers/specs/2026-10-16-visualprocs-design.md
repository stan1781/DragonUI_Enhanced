# VisualProcs → DragonUI_Enhanced 设计规格

日期：2026-10-16  
状态：已批准并实现（v0.6.0）

## 目标

在 `DragonUI_Enhanced` 内完整替代 `ElvUI_VisualProcs`：

- 屏幕 Overlay（大灾变风格技能触发特效）
- 动作条 Button Glow（蚂蚁边发光）

视觉与 proc 数据与原版一致；启用后可禁用 `ElvUI_VisualProcs`。

## 架构

| 层 | 路径 | 职责 |
|----|------|------|
| LibBlizzardProcs | `Libs/LibBlizzardProcs/` | Buff 监听、proc 数据、Overlay/Glow 动画（自 VisualProcs 迁入） |
| 适配层 | `features/visualprocs.lua` | 锚点 Frame、DragonUI 按钮扫描、启停、选项 |

不修改 DragonUI 核心动作条；不依赖 ElvUI / LibActionButton。

## 数据流

### Overlay

`UNIT_AURA` → LBP → `SPELL_ACTIVATION_OVERLAY_SHOW/HIDE` → 锚点 Frame `DragonUI_Enhanced_VisualProcsOverlay`

### Button Glow

动作槽变化 → 适配层解析 spellID → `LBP:ChangeAction` → Buff 触发 → Glow SHOW/HIDE → 匹配按钮发光

覆盖按钮：`ActionButton*`、`MultiBar*`、`BonusActionButton*`、`DragonUI_ExtraBarButton*`。

## 配置

`features.visualprocs`：

- `enabled` / `overlay` / `buttonGlow`
- `overlayScale`（默认 0.8）
- `disableSound`

Overlay 锚点固定屏幕中央（与原版一致，不可拖动，不拦截鼠标）。

选项：DragonUI Options → 增强 → 战斗。

## 旧插件

`ElvUI_VisualProcs` 列入 `core/legacy.lua` 硬冲突清单；登录提示建议禁用。

## 验收

1. 支持职业 Overlay 正常；缩放/静音生效  
2. 主条 / MultiBar / ExtraBar Glow；换技能/翻页刷新  
3. 宏指向技能可 Glow  
4. 总开关/子开关关闭后无残留  
5. 与旧 VisualProcs 同开时有 legacy 提示、不崩溃  
6. 不支持职业无报错、选项提示  
