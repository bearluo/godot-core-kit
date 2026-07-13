class_name KitUiScreen
extends Node
## 可选 UI 屏组件。屏幕想要生命周期回调 / 公共操作就挂它做子节点;宿主 KitUiStack
## 在 push 时注入 stack 回指并驱动其信号。零依赖,可脱离框架单独用。
## 生命周期信号由 KitUiStack 驱动;prev/next 为对手屏节点名,无则 ""。

signal entered(prev_name: String)   ## 本屏成为栈顶、激活
signal exited(next_name: String)    ## 本屏被 pop、即将移除
signal covered()                    ## 被上层 push 盖住、被 process_mode 停用
signal revealed()                   ## 上层 pop 后重新成为栈顶、恢复活动

## 宿主回指;push 时由 KitUiStack 注入。不标注 KitUiStack 类型(破 class_name 循环引用)。
var stack


func pop() -> void:
	if stack != null:
		stack.pop()


func push(scene_or_node, opts := {}) -> Control:
	if stack != null:
		return stack.push(scene_or_node, opts)
	return null


func replace(scene_or_node, opts := {}) -> Control:
	if stack != null:
		return stack.replace(scene_or_node, opts)
	return null


## 从任意(深层)子节点往上找到所属屏的 KitUiScreen 组件;无则 null。
static func of(node: Node) -> KitUiScreen:
	var n: Node = node
	while n != null:
		for c in n.get_children():
			if c is KitUiScreen:
				return c
		n = n.get_parent()
	return null
