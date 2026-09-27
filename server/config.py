import os
import json

CONFIG_FILE = os.path.expanduser("~/.apple_music_remote_config.json")

DEFAULT_CONFIG = {
    "port": 8080,
    "country": "ru",
    "musickit_developer_token": "",
    "musickit_user_token": ""
}

def load_config():
    config = DEFAULT_CONFIG.copy()
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                config.update(data)
        except Exception as e:
            print(f"[Config] Error loading config: {e}")
    return config

def save_config(new_config):
    config = load_config()
    config.update(new_config)
    try:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        return True, config
    except Exception as e:
        print(f"[Config] Error saving config: {e}")
        return False, str(e)
