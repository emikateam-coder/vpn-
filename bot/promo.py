import json
import os

PROMO_FILE = os.getenv("PROMO_FILE", "/var/lib/marzban/promo_codes.json")

def _load() -> dict:
    if os.path.exists(PROMO_FILE):
        with open(PROMO_FILE) as f:
            return json.load(f)
    return {}

def _save(data: dict):
    with open(PROMO_FILE, "w") as f:
        json.dump(data, f, indent=2)

def validate_promo(code: str) -> dict | None:
    """Returns promo config if valid, None otherwise."""
    promos = _load()
    promo = promos.get(code.upper())
    if not promo:
        return None
    if promo.get("uses", 0) >= promo.get("max_uses", 1):
        return None
    return promo

def use_promo(code: str) -> bool:
    promos = _load()
    key = code.upper()
    if key not in promos:
        return False
    promos[key]["uses"] = promos[key].get("uses", 0) + 1
    _save(promos)
    return True

def add_promo(code: str, days: int = 30, gb: int = 0, max_uses: int = 1) -> bool:
    promos = _load()
    promos[code.upper()] = {
        "days": days,
        "gb": gb,
        "max_uses": max_uses,
        "uses": 0,
    }
    _save(promos)
    return True

def list_promos() -> dict:
    return _load()

def delete_promo(code: str) -> bool:
    promos = _load()
    if code.upper() in promos:
        del promos[code.upper()]
        _save(promos)
        return True
    return False
