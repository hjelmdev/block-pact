class_name PauseMenu
extends Control

signal resume_requested()
signal restart_requested()
signal quit_requested()

@onready var _resume: Button = %ResumeButton
@onready var _restart: Button = %RestartButton
@onready var _quit: Button = %QuitButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_resume.pressed.connect(func(): AudioManager.play(Sfx.UI_CLICK); resume_requested.emit())
	_restart.pressed.connect(func(): AudioManager.play(Sfx.UI_CLICK); restart_requested.emit())
	_quit.pressed.connect(func(): quit_requested.emit())


func open() -> void:
	show()
	_resume.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(ControlSchemes.PAUSE_ACTION):
		resume_requested.emit()
		get_viewport().set_input_as_handled()
