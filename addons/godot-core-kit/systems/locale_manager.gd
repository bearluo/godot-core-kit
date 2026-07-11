extends Node
## LocaleManager —— i18n 本地化托管层。托管 Godot 全局 TranslationServer:
## 运行时切语言 + 持久化(经 bind_settings 注入的 Settings,section "locale")+
## 按 locale 换绑定 Theme 的字体 + 缺翻译 push_warning 告警 + 运行时翻译加载。
## 经 CoreKit.i18n 访问,是第 12 个子系统。
##
## 零门面耦合:不引用 CoreKit / CoreKit.log(缺翻译告警走 push_warning),故可脱离
## 门面独立实例化 headless 单测(同 _settings=null 意图)。字体不改任何全局默认
## (ThemeDB),只换显式 bind_theme 的 Theme.default_font,副作用可控可回退。
##
## Godot 注:切 locale 时引擎向所有节点发 NOTIFICATION_TRANSLATION_CHANGED,tr()
## 文本自动刷新;本层额外提供托管切换 + 持久化 + 字体 + 信号兜底。

## 每次成功切换 locale 后广播(未用 bind_theme 的游戏靠此 + font_for_locale 自换字体)。
signal locale_changed(locale: String)

const SETTINGS_SECTION := "locale"

## bind_settings 注入;untyped:未注入(脱离门面单测/不持久化)时为 null。
var _settings = null
## bind_theme 绑定的托管 Theme;换 locale 时改其 default_font。未绑定为 null。
var _theme: Theme = null
## locale(String)-> Font 注册表。
var _locale_fonts: Dictionary = {}
## 缺翻译告警去重集,键 "locale|key" -> true(每键每语言仅告警一次)。
var _warned: Dictionary = {}


## 注入 Settings:持有引用并恢复上次持久化的 locale(无则保持引擎默认)。**静默恢复**
## ——走内部 _apply_locale,不重放 locale_changed、不回写已持久化值,与 audio/input 的
## bind_settings 范式一致(注入期不应向订阅方广播一次意外的启动事件)。
func bind_settings(settings) -> void:
	_settings = settings
	if _settings == null:
		return
	var stored = _settings.get_value(SETTINGS_SECTION, "current")
	if stored is String and not stored.is_empty():
		_apply_locale(stored)


## 切换 locale。空串 → 警告 no-op;与当前相同 → no-op(不重复落盘/发信号);否则切
## TranslationServer + 应用字体 + 持久化 + 发 locale_changed。
func set_locale(locale: String) -> void:
	if locale.is_empty():
		push_warning("LocaleManager.set_locale: 空 locale,忽略")
		return
	if TranslationServer.get_locale() == locale:
		return
	_apply_locale(locale)
	if _settings != null:
		_settings.set_value(SETTINGS_SECTION, "current", locale)
	locale_changed.emit(locale)


func get_locale() -> String:
	return TranslationServer.get_locale()


## 有已加载翻译的 locale 列表。
func available_locales() -> PackedStringArray:
	return TranslationServer.get_loaded_locales()


## locale 的英文显示名(如 "en" -> "English")。
func locale_display_name(locale: String) -> String:
	return TranslationServer.get_locale_name(locale)


## 托管 tr:取当前 locale 译文;缺失(译文 == key)且 debug 构建时按 "locale|key"
## 去重 push_warning(每键每语言仅一次)。返回译文(缺失则原 key)。
func t(key: StringName, context: String = "") -> String:
	var out := String(TranslationServer.translate(key, context))
	if out == String(key) and OS.is_debug_build():
		var mark := "%s|%s" % [TranslationServer.get_locale(), key]
		if not _warned.has(mark):
			_warned[mark] = true
			push_warning("LocaleManager: 缺翻译 [%s] key '%s'" % [TranslationServer.get_locale(), key])
	return out


## 当前 locale 下是否有该 key 的翻译。
func has_translation(key: StringName, context: String = "") -> bool:
	return String(TranslationServer.translate(key, context)) != String(key)


## 注册某 locale 的字体;null 忽略并告警。
func register_locale_font(locale: String, font: Font) -> void:
	if font == null:
		push_warning("LocaleManager.register_locale_font: font 为 null,忽略(locale=%s)" % locale)
		return
	_locale_fonts[locale] = font


## 取某 locale 注册的字体,无 → null。
func font_for_locale(locale: String) -> Font:
	return _locale_fonts.get(locale)


## 绑定托管 Theme(null 清除);切 locale 时换其 default_font。绑定时若当前 locale
## 已注册字体,立即应用一次。
func bind_theme(theme: Theme) -> void:
	_theme = theme
	if _theme != null:
		_apply_font(TranslationServer.get_locale())


## 注册一个内存 Translation。null 忽略并告警。
func add_translation(translation: Translation) -> void:
	if translation == null:
		push_warning("LocaleManager.add_translation: translation 为 null,忽略")
		return
	TranslationServer.add_translation(translation)


## 从 path 加载一个 .translation/.tres 翻译资源并注册。成功 true;加载不到 / 非
## Translation → 警告 + false。
func load_translation(path: String) -> bool:
	var loaded = ResourceLoader.load(path)
	if loaded == null or not (loaded is Translation):
		push_warning("LocaleManager.load_translation: '%s' 加载失败或非 Translation" % path)
		return false
	TranslationServer.add_translation(loaded)
	return true


## 扫 dir 下 *.translation 与 *.tres 逐个加载注册,返回成功数。目录打不开 → 警告 + 0。
func load_translations(dir: String) -> int:
	var da := DirAccess.open(dir)
	if da == null:
		push_warning("LocaleManager.load_translations: 无法打开目录 '%s'" % dir)
		return 0
	var count := 0
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if not da.current_is_dir() and (entry.ends_with(".translation") or entry.ends_with(".tres")):
			if load_translation(dir.path_join(entry)):
				count += 1
		entry = da.get_next()
	da.list_dir_end()
	return count


## 应用 locale(切 TranslationServer + 换字体),不持久化、不发信号。set_locale 与
## bind_settings 的静默恢复共用——后者据此静默恢复,不重放 locale_changed。
func _apply_locale(locale: String) -> void:
	TranslationServer.set_locale(locale)
	_apply_font(locale)


## 换绑定 Theme 的 default_font 为该 locale 注册的字体(未绑定 Theme 或该 locale
## 未注册字体则不动)。
func _apply_font(locale: String) -> void:
	if _theme != null and _locale_fonts.has(locale):
		_theme.default_font = _locale_fonts[locale]
