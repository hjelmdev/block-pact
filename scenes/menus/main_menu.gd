extends Control

@onready var _solo: Button = %SoloButton
@onready var _bots: Button = %BotsButton
@onready var _party: Button = %PartyButton
@onready var _online: Button = %OnlineButton
@onready var _leaderboard: Button = %LeaderboardButton
@onready var _account: Button = %AccountButton
@onready var _settings: Button = %SettingsButton
@onready var _quit: Button = %QuitButton
@onready var _status: Label = %AccountStatus


func _ready() -> void:
	_solo.pressed.connect(_go.bind(&"match", {"setup": MatchFactory.quick_solo()}))
	_bots.pressed.connect(_go.bind(&"lobby", {"preset": "vs_bots"}))
	_party.pressed.connect(_go.bind(&"lobby", {"preset": "local"}))
	_online.pressed.connect(_go.bind(&"online", {}))
	_leaderboard.pressed.connect(_go.bind(&"leaderboard", {}))
	_account.pressed.connect(_go.bind(&"account", {}))
	_settings.pressed.connect(_go.bind(&"settings", {}))
	_quit.pressed.connect(func(): get_tree().quit())
	_quit.visible = not Platform.is_web() and not Platform.is_mobile()
	_party.visible = Platform.has_keyboard() or Input.get_connected_joypads().size() > 0
	Auth.session_changed.connect(func(_l): _refresh_status())
	Progress.profile_changed.connect(_refresh_status)
	_refresh_status()
	AudioManager.play_music()
	_solo.grab_focus()


func _refresh_status() -> void:
	if Progress.is_tracking():
		_status.text = tr("MENU_SIGNED_IN") % Progress.display_name()
	else:
		_status.text = tr("MENU_GUEST")


func _go(key: StringName, params: Dictionary) -> void:
	AudioManager.play(Sfx.UI_CLICK)
	if key == &"match":
		# fresh setup each time (seed, nickname)
		params = {"setup": MatchFactory.quick_solo()}
	Router.goto(key, params)
