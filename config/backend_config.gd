class_name BackendConfig
extends Resource
## Online backend settings (Supabase). Empty = offline/guest-only, and the
## game runs fine without it.
##
## Put real values in res://config/backend_config.local.tres (git-ignored)
## or directly in backend_config.tres. The anon key is a public key – Row
## Level Security in the database is what protects data.

const LOCAL_PATH := "res://config/backend_config.local.tres"
const DEFAULT_PATH := "res://config/backend_config.tres"

@export var supabase_url: String = ""
@export var supabase_anon_key: String = ""
## OAuth providers enabled in Supabase Auth.
@export var oauth_providers: PackedStringArray = PackedStringArray(["google", "discord"])
## Where Supabase sends the browser after login. Empty = the current page.
## Must also be listed under Auth > URL Configuration > Redirect URLs.
@export var web_redirect_url: String = ""
## Port for the desktop/editor login callback (http://localhost:PORT/).
@export var desktop_callback_port: int = 43117


func is_configured() -> bool:
	return supabase_url.strip_edges() != "" and supabase_anon_key.strip_edges() != ""


func base_url() -> String:
	return supabase_url.strip_edges().trim_suffix("/")


static func load_active() -> BackendConfig:
	for path in [LOCAL_PATH, DEFAULT_PATH]:
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is BackendConfig:
				return res
	return BackendConfig.new()
