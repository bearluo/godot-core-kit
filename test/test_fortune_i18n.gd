extends SceneTree
## LocaleCatalog + kit LocaleManager 中英双语 headless 断言。
## 运行:godot --headless --path . -s res://test/test_fortune_i18n.gd
## 直接实例化 LocaleManager(不经 autoload);LocaleCatalog.apply 注册 en/zh 两表。
## 重点:① apply 注册两语言 ② 运行时切语言同 key 文案不同 ③ 缺翻译回退原 key
##       ④ has_translation ⑤ 字体回退:register_locale_font + bind_theme → 切 locale 换 default_font。
## 加载注:LocaleManager 延迟到 _initialize 内 load()(kit 门测试约定,避开顶层 preload 编译期坑);
## LocaleCatalog 为 example 本地类、不引用门面,可顶层 preload。
const LocaleCatalog := preload("res://examples/fortune-mill/systems/locale_catalog.gd")


func _initialize() -> void:
	var LocaleManager = load("res://addons/godot-core-kit/systems/locale_manager.gd")
	var failures := 0
	var i18n = LocaleManager.new()

	# 1. apply 注册 en/zh 两语言
	var n = LocaleCatalog.apply(i18n)
	if n != 2:
		print("FAIL 1: apply 应注册 2 语言,得到 %d" % n); failures += 1

	# 2. 运行时切语言:en/zh 同 key 文案不同
	i18n.set_locale("en")
	var en = i18n.t(&"fortune.throw")
	i18n.set_locale("zh")
	var zh = i18n.t(&"fortune.throw")
	if en != "Throw" or zh != "投镖":
		print("FAIL 2: en 应 'Throw' zh 应 '投镖',得到 '%s'/'%s'" % [en, zh]); failures += 1

	# 3. 缺翻译 → 回退原 key(缺翻译告警由 t() push_warning;此处验回退值)
	if i18n.t(&"fortune.__nope__") != "fortune.__nope__":
		print("FAIL 3: 缺翻译应回退原 key"); failures += 1

	# 4. has_translation:已注册 key 为 true、缺失为 false
	if not i18n.has_translation(&"fortune.title") or i18n.has_translation(&"fortune.__nope__"):
		print("FAIL 4: has_translation 判定错"); failures += 1

	# 5. 字体回退:注册 zh 字体 + bind_theme → 切到 zh 换 theme.default_font,切到无字体的 en 不动
	var theme := Theme.new()
	var zh_font := SystemFont.new()
	i18n.register_locale_font("zh", zh_font)
	i18n.bind_theme(theme)
	i18n.set_locale("en")   # en 未注册字体 → 不改 default_font
	i18n.set_locale("zh")   # zh 已注册 → theme.default_font = zh_font
	if theme.default_font != zh_font:
		print("FAIL 5: 切到 zh 后 theme.default_font 应为注册的 zh 字体"); failures += 1

	i18n.free()
	if failures == 0:
		print("test_fortune_i18n: ALL PASS")
		quit(0)
	else:
		print("test_fortune_i18n: %d FAILURE(S)" % failures)
		quit(1)
