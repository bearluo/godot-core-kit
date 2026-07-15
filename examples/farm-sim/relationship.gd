extends RefCounted
## 好感度纯逻辑(P3,零依赖,可 headless 单测)。送礼 delta 按 NPC 偏好判定,好感等级按点数分档,
## 反应分类供选台词/i18n。供 Farm(运行时)+ test_relationship(离线)共用。占位数值,后续平衡可调。

const GIFT_LOVED := 50
const GIFT_LIKED := 20
const GIFT_NEUTRAL := 5
const GIFT_DISLIKED := -30
const POINTS_PER_LEVEL := 100


## 送某物品给 npc_def 的好感增量:爱 +50 / 喜欢 +20 / 讨厌 -30 / 其余 +5;def 为 null → 中性。
static func gift_delta(npc_def, item_id: StringName) -> int:
	if npc_def == null:
		return GIFT_NEUTRAL
	if (npc_def.gift_loved as Array).has(item_id):
		return GIFT_LOVED
	if (npc_def.gift_liked as Array).has(item_id):
		return GIFT_LIKED
	if (npc_def.gift_disliked as Array).has(item_id):
		return GIFT_DISLIKED
	return GIFT_NEUTRAL


## 好感等级 = 点数 / 100(下取整);负点数记 0 级。
static func level_of(points: int) -> int:
	return maxi(0, points) / POINTS_PER_LEVEL


## 送礼反应分类(loved/liked/neutral/disliked),供选反应台词 / i18n key。
static func reaction_of(delta: int) -> String:
	if delta >= GIFT_LOVED:
		return "loved"
	if delta >= GIFT_LIKED:
		return "liked"
	if delta < 0:
		return "disliked"
	return "neutral"
