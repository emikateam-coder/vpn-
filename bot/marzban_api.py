import aiohttp
import time
from config import MARZBAN_URL, MARZBAN_USER, MARZBAN_PASS


class MarzbanAPI:
    def __init__(self):
        self._token = None
        self._token_expires = 0

    async def _get_token(self) -> str:
        if self._token and time.time() < self._token_expires:
            return self._token

        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{MARZBAN_URL}/api/admin/token",
                data={"username": MARZBAN_USER, "password": MARZBAN_PASS},
            ) as resp:
                data = await resp.json()
                self._token = data["access_token"]
                self._token_expires = time.time() + 3500
                return self._token

    async def _headers(self) -> dict:
        token = await self._get_token()
        return {"Authorization": f"Bearer {token}"}

    async def get_system_stats(self) -> dict:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                f"{MARZBAN_URL}/api/system", headers=await self._headers()
            ) as resp:
                return await resp.json()

    async def get_users(self, offset=0, limit=50) -> dict:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                f"{MARZBAN_URL}/api/users",
                headers=await self._headers(),
                params={"offset": offset, "limit": limit},
            ) as resp:
                return await resp.json()

    async def get_user(self, username: str) -> dict | None:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                f"{MARZBAN_URL}/api/user/{username}",
                headers=await self._headers(),
            ) as resp:
                if resp.status == 200:
                    return await resp.json()
                return None

    async def create_user(
        self,
        username: str,
        data_limit_gb: int = 0,
        expire_days: int = 0,
        promo_code: str | None = None,
        inbound_tag: str = "VLESS_REALITY",
    ) -> dict | None:
        import uuid as uuid_mod

        expire_ts = 0
        if expire_days > 0:
            expire_ts = int(time.time()) + expire_days * 86400

        user_data = {
            "username": username,
            "proxies": {
                "vless": {
                    "id": str(uuid_mod.uuid4()),
                    "flow": "xtls-rprx-vision",
                }
            },
            "inbounds": {"vless": [inbound_tag]},
            "data_limit": data_limit_gb * 1024 * 1024 * 1024 if data_limit_gb else 0,
            "expire": expire_ts,
            "status": "active",
            "note": promo_code or "",
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{MARZBAN_URL}/api/user",
                headers={**(await self._headers()), "Content-Type": "application/json"},
                json=user_data,
            ) as resp:
                if resp.status == 200:
                    return await resp.json()
                return None

    async def delete_user(self, username: str) -> bool:
        async with aiohttp.ClientSession() as session:
            async with session.delete(
                f"{MARZBAN_URL}/api/user/{username}",
                headers=await self._headers(),
            ) as resp:
                return resp.status == 200

    async def toggle_user(self, username: str, enable: bool) -> dict | None:
        status = "active" if enable else "disabled"
        async with aiohttp.ClientSession() as session:
            async with session.put(
                f"{MARZBAN_URL}/api/user/{username}",
                headers={**(await self._headers()), "Content-Type": "application/json"},
                json={"status": status},
            ) as resp:
                if resp.status == 200:
                    return await resp.json()
                return None

    async def reset_traffic(self, username: str) -> bool:
        async with aiohttp.ClientSession() as session:
            async with session.post(
                f"{MARZBAN_URL}/api/user/{username}/reset",
                headers=await self._headers(),
            ) as resp:
                return resp.status == 200


marzban = MarzbanAPI()
