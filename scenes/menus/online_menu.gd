extends MenuPage
## Placeholder for online lobbies. The match code path is already
## network-ready (see net/network_session.gd); this page will host/join.


func _build() -> void:
	add_label(tr("ONLINE_COMING_SOON"), 15)
	add_button(tr("MENU_VS_BOTS"), func(): Router.goto(&"lobby", {"preset": "vs_bots"}))
