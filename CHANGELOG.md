# Changelog

## 0.6.1

- 队伍光环：在 PartyMemberFrame 上显示重要职业 buff（坚韧/野性/王者/力量/智力/精神/荆棘）与可驱散、重要 debuff
- 有才显示；默认挂左侧，设置可选左/右/下；图标大小与数量可调
- 设置：增强 → 战斗 → 队伍光环
- 修复：旧配置缺字段时误判开关关闭导致图标不显示；图标改挂 UIParent 避免被队伍框裁切
- 队伍光环：图标中央显示剩余时间（5m / 12s），可在设置中关闭

## 0.6.0

- 技能触发提醒：迁入 LibBlizzardProcs，在 DragonUI 动作条上复现 ElvUI_VisualProcs 的 Overlay + 按钮发光
- 设置：增强 → 战斗；可开关 Overlay/Glow、缩放、静音、预览、重置位置
- 旧插件清单增加 `ElvUI_VisualProcs`

## 0.5.0

- P4：嵌入 FriendsMenuXP 玩家右键菜单（不含职业 buff / RaidGroupButton 安全属性写入）
- FriendSync 挂钩增强版菜单的加/删好友
- P5：旧插件禁用清单（设置页 + 登录提示 + `/duielegacy`）
- README / CHANGELOG

## 0.1.0 – 0.4.x（阶段摘要）

- P0：框架、`RegisterFeature`、MotionSpeed、Enhanced 设置页
- P0.5：Buff 关键词屏蔽、LFG Bot 屏蔽
- P1–P2：聊天增强、快捷栏、表情、符文条
- P3：装备列表面板、装备助手、好友同步（舍弃出处与 WhisperInvite）
