extends Node
## CoreKit.layers —— 具名 CanvasLayer 管理器(第 13 子系统)。在本节点下懒建一组
## 具名 CanvasLayer,z 序由常量表定义;因本节点是 CoreKit autoload 子节点,这些层
## 及挂在其上的内容独立于当前场景渲染、跨 change_scene 存活。零跨系统依赖。
##
## 保留带(本管理器不创建,仅登记常量供引用):
##   CONSOLE=128   —— DevConsole 自建自持(console/dev_console.gd)
##   TRANSITION=4096 —— SceneManager 淡入淡出遮罩自建自持(systems/scene_manager.gd)
## 新增自定义层的 z 应落在 SYSTEM(60)与 CONSOLE(128)之间以免盖过控制台/转场。

## --- z 序常量(权威单一数据源;游戏引用而非猜数字)---
const BACKGROUND := -10   ## 世界底下(视差/天幕)
const HUD := 10           ## 常驻血条/小地图
const WINDOW := 20        ## 游戏内面板
const POPUP := 30         ## 弹窗
const MODAL := 40         ## 模态
const NOTIFY := 50        ## Toast/成就弹
const SYSTEM := 60        ## Loading/暂停幕
const CONSOLE := 128      ## 保留带:DevConsole 现值(不创建)
const TRANSITION := 4096  ## 保留带:SceneManager 转场遮罩现值(不创建)

## 内置具名层 → z。register_layer 往这里加自定义项;console/transition 故意不在内。
var _z_map: Dictionary = {
	&"background": BACKGROUND, &"hud": HUD, &"window": WINDOW, &"popup": POPUP,
	&"modal": MODAL, &"notify": NOTIFY, &"system": SYSTEM,
}
var _layers: Dictionary = {}   # StringName -> CanvasLayer(已懒建缓存)


## 取(懒建)具名层。未知名(未内置且未 register)→ push_error + null。
func layer(name: StringName) -> CanvasLayer:
	if _layers.has(name):
		return _layers[name]
	if not _z_map.has(name):
		push_error("CoreKit.layers: 未知层名 '%s'(需内置名或先 register_layer)" % name)
		return null
	var cl := CanvasLayer.new()
	cl.name = "Layer_%s" % name
	cl.layer = _z_map[name]
	add_child(cl)
	_layers[name] = cl
	return cl


## 把节点搬进具名层(从原父摘下再挂)。未知层名 → push_error + no-op。
func mount(node: Node, name: StringName) -> void:
	var cl := layer(name)
	if cl == null:
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	cl.add_child(node)


## 清空某层(queue_free 全部子节点)。未建的层 → no-op。
func clear(name: StringName) -> void:
	if not _layers.has(name):
		return
	for c in (_layers[name] as CanvasLayer).get_children():
		c.queue_free()


## 登记自定义层名→z(懒建在下次 layer() 时)。重名 → push_warning + 拒;
## z 落入保留带(>= CONSOLE)→ push_warning 但仍登记(进阶用途)。
func register_layer(name: StringName, z: int) -> void:
	if _z_map.has(name):
		push_warning("CoreKit.layers: 层名 '%s' 已存在,拒绝重复登记" % name)
		return
	if z >= CONSOLE:
		push_warning("CoreKit.layers: 自定义层 '%s' z=%d 落入保留带(>=%d),可能盖过控制台/转场" % [name, z, CONSOLE])
	_z_map[name] = z


## 是否已登记该层名(内置或 register 过);不创建。
func has_layer(name: StringName) -> bool:
	return _z_map.has(name)
