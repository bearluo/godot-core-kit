extends Control
## HUD(P0 占位):左上角显示 日期 / 金币 / 体力。挂在 CoreKit.layers 的 "hud" 具名层(跨场景常驻)。
## 体力 P0 固定占位不消耗(P1 接体力系统)。日期读 CoreKit.clock,金币读注入的钱包(shop)。

var _clock
var _wallet
var _world        ## 提供 energy()/energy_max()/selected_crop_name()
var _date_label: Label
var _weather_label: Label
var _gold_label: Label
var _energy_label: Label
var _seed_label: Label


func bind(clock, wallet, world) -> void:
	_clock = clock
	_wallet = wallet
	_world = world


func _ready() -> void:
	var vb := VBoxContainer.new()
	vb.position = Vector2(12, 8)
	add_child(vb)
	_date_label = Label.new()
	_weather_label = Label.new()
	_gold_label = Label.new()
	_energy_label = Label.new()
	_seed_label = Label.new()
	vb.add_child(_date_label)
	vb.add_child(_weather_label)
	vb.add_child(_gold_label)
	vb.add_child(_energy_label)
	vb.add_child(_seed_label)


func _process(_delta: float) -> void:
	var i18n = CoreKit.i18n
	if _clock != null:
		_date_label.text = "y%d %s d%d  %02d:%02d" % [
			_clock.year(), i18n.t("SEASON_" + _clock.season_name()),
			_clock.day(), _clock.hour(), _clock.minute()]
	if _wallet != null:
		_gold_label.text = "%s: %d" % [i18n.t("HUD_GOLD"), _wallet.gold]
	if _world != null:
		_weather_label.text = "%s: %s" % [i18n.t("HUD_WEATHER"), _world.weather_name()]
		_energy_label.text = "%s: %d/%d" % [i18n.t("HUD_ENERGY"), _world.energy(), _world.energy_max()]
		var ok_season: bool = _world.selected_crop_plantable()
		_seed_label.text = "%s: %s%s %s" % [
			i18n.t("HUD_SEED"), _world.selected_crop_name(),
			"" if ok_season else " " + i18n.t("HUD_OFFSEASON"), i18n.t("HUD_SEED_HINT")]
