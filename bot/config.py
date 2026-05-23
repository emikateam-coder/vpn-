import os
from dotenv import load_dotenv

load_dotenv()

BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
MARZBAN_URL = os.getenv("MARZBAN_URL", "http://127.0.0.1:8000")
MARZBAN_USER = os.getenv("MARZBAN_USER", "marzban_admin")
MARZBAN_PASS = os.getenv("MARZBAN_PASS", "SecurePass2026VPN")
ADMIN_IDS = [int(x) for x in os.getenv("ADMIN_IDS", "").split(",") if x.strip()]
SERVER_IP = os.getenv("SERVER_IP", "77.110.108.137")

PLANS = {
    "1m": {"name": "1 месяц", "days": 30, "gb": 0, "devices": "♾", "price": 149, "stars": 75},
    "3m": {"name": "3 месяца", "days": 90, "gb": 0, "devices": "♾", "price": 399, "stars": 200},
    "6m": {"name": "6 месяцев", "days": 180, "gb": 0, "devices": "♾", "price": 699, "stars": 350},
    "1y": {"name": "12 месяцев", "days": 365, "gb": 0, "devices": "♾", "price": 1199, "stars": 600},
}

SERVERS = {
    "de1": {
        "name": "Германия (Hetzner)",
        "flag": "🇩🇪",
        "ip": "77.110.108.137",
        "inbound_tag": "VLESS_REALITY",
    },
}
