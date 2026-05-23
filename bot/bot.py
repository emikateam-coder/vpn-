import asyncio
import logging
from datetime import datetime

from aiogram import Bot, Dispatcher, F, Router
from aiogram.types import (
    Message,
    CallbackQuery,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
)
from aiogram.filters import Command, CommandStart
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.enums import ParseMode

from config import BOT_TOKEN, ADMIN_IDS, SERVER_IP
from marzban_api import marzban
from promo import validate_promo, use_promo, add_promo, list_promos, delete_promo

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()
router = Router()
dp.include_router(router)


class PromoState(StatesGroup):
    waiting_code = State()


class AdminAddPromo(StatesGroup):
    waiting_code = State()
    waiting_days = State()
    waiting_max_uses = State()


def is_admin(user_id: int) -> bool:
    return user_id in ADMIN_IDS


def format_bytes(b: int) -> str:
    if b <= 0:
        return "0 B"
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if abs(b) < 1024:
            return f"{b:.1f} {unit}"
        b /= 1024
    return f"{b:.1f} PB"


def format_timestamp(ts: int) -> str:
    if not ts:
        return "Unlimited"
    return datetime.fromtimestamp(ts).strftime("%d.%m.%Y %H:%M")


def main_menu_kb(user_id: int) -> InlineKeyboardMarkup:
    buttons = [
        [InlineKeyboardButton(text="[LINK] Podklyuchitsya", callback_data="my_config")],
        [InlineKeyboardButton(text="[STATUS] Moya podpiska", callback_data="my_status")],
        [InlineKeyboardButton(text="[KEY] Promokod", callback_data="enter_promo")],
        [InlineKeyboardButton(text="[INFO] Info", callback_data="info")],
    ]
    if is_admin(user_id):
        buttons.append(
            [InlineKeyboardButton(text="[ADMIN] Admin panel", callback_data="admin_menu")]
        )
    return InlineKeyboardMarkup(inline_keyboard=buttons)


def admin_menu_kb() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [InlineKeyboardButton(text="[USERS] Polzovateli", callback_data="admin_users")],
            [InlineKeyboardButton(text="[STATS] Statistika servera", callback_data="admin_stats")],
            [InlineKeyboardButton(text="[PROMO] Promokody", callback_data="admin_promos")],
            [InlineKeyboardButton(text="[ADD] Dobavit promokod", callback_data="admin_add_promo")],
            [InlineKeyboardButton(text="[BACK] Nazad", callback_data="back_main")],
        ]
    )


def back_kb() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [InlineKeyboardButton(text="[BACK] Glavnoe menu", callback_data="back_main")]
        ]
    )


@router.message(CommandStart())
async def cmd_start(message: Message):
    user = message.from_user
    text = (
        f"[VPN] VPN Service\n\n"
        f"Privet, {user.first_name}!\n\n"
        f"Vyberi deystvie:"
    )
    await message.answer(text, reply_markup=main_menu_kb(user.id))


@router.callback_query(F.data == "back_main")
async def back_main(callback: CallbackQuery, state: FSMContext):
    await state.clear()
    text = f"[VPN] VPN Service\n\nVyberi deystvie:"
    await callback.message.edit_text(text, reply_markup=main_menu_kb(callback.from_user.id))


@router.callback_query(F.data == "my_config")
async def my_config(callback: CallbackQuery):
    tg_id = callback.from_user.id
    username = f"tg_{tg_id}"

    user_data = await marzban.get_user(username)

    if not user_data:
        text = (
            "[LOCK] U vas net aktivnoy podpiski.\n\n"
            "Ispolzuyte promokod dlya aktivatsii:"
        )
        kb = InlineKeyboardMarkup(
            inline_keyboard=[
                [InlineKeyboardButton(text="[KEY] Vvesti promokod", callback_data="enter_promo")],
                [InlineKeyboardButton(text="[BACK] Nazad", callback_data="back_main")],
            ]
        )
        await callback.message.edit_text(text, reply_markup=kb)
        return

    links = user_data.get("links", [])
    sub_url = user_data.get("subscription_url", "")

    text = f"[OK] Vasha ssylka dlya podklyucheniya:\n\n"

    if links:
        text += f"<code>{links[0]}</code>\n\n"

    if sub_url:
        full_sub = f"http://{SERVER_IP}:8000{sub_url}"
        text += f"[LINK] Ssylka podpiski:\n<code>{full_sub}</code>\n\n"

    text += (
        "[SETUP] Kak podklyuchitsya:\n"
        "1. Skopiruyte ssylku vyshe\n"
        "2. Otkroyte V2RayNG / Hiddify / NekoBox\n"
        "3. Nazhmite + -> Add from Clipboard\n"
        "4. Podklyuchites!"
    )

    await callback.message.edit_text(
        text, reply_markup=back_kb(), parse_mode=ParseMode.HTML
    )


@router.callback_query(F.data == "my_status")
async def my_status(callback: CallbackQuery):
    tg_id = callback.from_user.id
    username = f"tg_{tg_id}"

    user_data = await marzban.get_user(username)

    if not user_data:
        text = "[LOCK] Podpiska ne naydena.\nIspolzuyte promokod dlya aktivatsii."
        await callback.message.edit_text(text, reply_markup=back_kb())
        return

    status = user_data.get("status", "unknown")
    status_icon = "[OK]" if status == "active" else "[X]"

    used_traffic = user_data.get("used_traffic", 0)
    data_limit = user_data.get("data_limit", 0)
    expire = user_data.get("expire", 0)

    if expire:
        days_left = max(0, (expire - int(datetime.now().timestamp())) // 86400)
        expire_str = f"{format_timestamp(expire)} (ostalos {days_left} dn.)"
    else:
        expire_str = "Unlimited"

    traffic_str = format_bytes(used_traffic)
    if data_limit:
        traffic_str += f" / {format_bytes(data_limit)}"
    else:
        traffic_str += " / Unlimited"

    text = (
        f"[USER] Podpiska\n\n"
        f"  Imya: {username}\n"
        f"  Status: {status_icon} {status.title()}\n"
        f"  Istekast: {expire_str}\n"
        f"  Trafik: {traffic_str}\n"
    )

    await callback.message.edit_text(text, reply_markup=back_kb())


@router.callback_query(F.data == "enter_promo")
async def enter_promo(callback: CallbackQuery, state: FSMContext):
    text = "[KEY] Vvedite promokod:"
    kb = InlineKeyboardMarkup(
        inline_keyboard=[
            [InlineKeyboardButton(text="[BACK] Otmena", callback_data="back_main")]
        ]
    )
    await callback.message.edit_text(text, reply_markup=kb)
    await state.set_state(PromoState.waiting_code)


@router.message(PromoState.waiting_code)
async def process_promo(message: Message, state: FSMContext):
    code = message.text.strip()
    promo = validate_promo(code)

    if not promo:
        await message.answer(
            "[X] Promokod neveren ili uzhe ispolzovan.",
            reply_markup=back_kb(),
        )
        await state.clear()
        return

    tg_id = message.from_user.id
    username = f"tg_{tg_id}"

    existing = await marzban.get_user(username)
    if existing:
        await message.answer(
            "[INFO] U vas uzhe est podpiska! Ispolzuyte [LINK] Podklyuchitsya.",
            reply_markup=back_kb(),
        )
        await state.clear()
        return

    user_data = await marzban.create_user(
        username=username,
        data_limit_gb=promo.get("gb", 0),
        expire_days=promo.get("days", 30),
        promo_code=code,
    )

    if user_data:
        use_promo(code)
        links = user_data.get("links", [])
        text = f"[OK] Podpiska aktivirovana!\n\n"

        if links:
            text += f"Vasha ssylka:\n<code>{links[0]}</code>\n\n"

        text += "Nazhmite [LINK] Podklyuchitsya dlya instruktsiy."

        await message.answer(text, reply_markup=back_kb(), parse_mode=ParseMode.HTML)
    else:
        await message.answer(
            "[X] Oshibka sozdaniya podpiski. Poprobuyto pozzhe.",
            reply_markup=back_kb(),
        )

    await state.clear()


@router.callback_query(F.data == "info")
async def info(callback: CallbackQuery):
    text = (
        "[INFO] VPN Service\n\n"
        "Protokol: VLESS-Reality\n"
        "Zashchita: XTLS-Vision + uTLS\n"
        "Server: Germaniya (DE)\n\n"
        "Rekomenduemye prilozheniya:\n"
        "  Android: V2RayNG, Hiddify, NekoBox\n"
        "  iOS: Streisand, FoXray\n"
        "  PC: Nekoray, Hiddify, V2RayN\n\n"
        "Posle podklyucheniya:\n"
        "  ipinfo.io -> IP servera (DE)\n"
        "  2ip.ru -> vash IP (RU)\n"
    )
    await callback.message.edit_text(text, reply_markup=back_kb())


# ===== ADMIN HANDLERS =====

@router.callback_query(F.data == "admin_menu")
async def admin_menu(callback: CallbackQuery):
    if not is_admin(callback.from_user.id):
        await callback.answer("Net dostupa", show_alert=True)
        return
    await callback.message.edit_text(
        "[ADMIN] Admin panel", reply_markup=admin_menu_kb()
    )


@router.callback_query(F.data == "admin_users")
async def admin_users(callback: CallbackQuery):
    if not is_admin(callback.from_user.id):
        return

    data = await marzban.get_users()
    users = data.get("users", [])

    if not users:
        await callback.message.edit_text(
            "[USERS] Net polzovateley.", reply_markup=admin_menu_kb()
        )
        return

    text = f"[USERS] Polzovateli ({len(users)}):\n\n"
    for u in users[:20]:
        status = "[OK]" if u["status"] == "active" else "[X]"
        traffic = format_bytes(u.get("used_traffic", 0))
        text += f"  {status} {u['username']} - {traffic}\n"

    await callback.message.edit_text(text, reply_markup=admin_menu_kb())


@router.callback_query(F.data == "admin_stats")
async def admin_stats(callback: CallbackQuery):
    if not is_admin(callback.from_user.id):
        return

    stats = await marzban.get_system_stats()
    users_data = await marzban.get_users()
    total_users = users_data.get("total", 0)

    mem = stats.get("mem_used", 0)
    mem_total = stats.get("mem_total", 0)
    cpu = stats.get("cpu_usage", 0)

    text = (
        f"[STATS] Statistika servera\n\n"
        f"  CPU: {cpu:.0f}%\n"
        f"  RAM: {format_bytes(mem)} / {format_bytes(mem_total)}\n"
        f"  Polzovateley: {total_users}\n"
        f"  Server: {SERVER_IP}\n"
    )

    await callback.message.edit_text(text, reply_markup=admin_menu_kb())


@router.callback_query(F.data == "admin_promos")
async def admin_promos_list(callback: CallbackQuery):
    if not is_admin(callback.from_user.id):
        return

    promos = list_promos()
    if not promos:
        text = "[PROMO] Net promokodov.\nDobavte cherez [ADD]."
    else:
        text = f"[PROMO] Promokody ({len(promos)}):\n\n"
        for code, p in promos.items():
            text += (
                f"  {code}\n"
                f"    Dney: {p['days']} | GB: {p.get('gb', 0) or 'Unlim'}\n"
                f"    Ispolzovan: {p.get('uses', 0)}/{p['max_uses']}\n\n"
            )

    await callback.message.edit_text(text, reply_markup=admin_menu_kb())


@router.callback_query(F.data == "admin_add_promo")
async def admin_add_promo(callback: CallbackQuery, state: FSMContext):
    if not is_admin(callback.from_user.id):
        return

    await callback.message.edit_text(
        "[ADD] Vvedite promokod (naprimer: FREE30):",
        reply_markup=InlineKeyboardMarkup(
            inline_keyboard=[
                [InlineKeyboardButton(text="[BACK] Otmena", callback_data="admin_menu")]
            ]
        ),
    )
    await state.set_state(AdminAddPromo.waiting_code)


@router.message(AdminAddPromo.waiting_code)
async def admin_promo_code(message: Message, state: FSMContext):
    if not is_admin(message.from_user.id):
        return

    await state.update_data(code=message.text.strip().upper())
    await message.answer("Skolko dney deystviya? (naprimer: 30)")
    await state.set_state(AdminAddPromo.waiting_days)


@router.message(AdminAddPromo.waiting_days)
async def admin_promo_days(message: Message, state: FSMContext):
    if not is_admin(message.from_user.id):
        return

    try:
        days = int(message.text.strip())
    except ValueError:
        await message.answer("Vvedite chislo. Naprimer: 30")
        return

    await state.update_data(days=days)
    await message.answer("Maksimum ispolzovaniy? (naprimer: 10)")
    await state.set_state(AdminAddPromo.waiting_max_uses)


@router.message(AdminAddPromo.waiting_max_uses)
async def admin_promo_max_uses(message: Message, state: FSMContext):
    if not is_admin(message.from_user.id):
        return

    try:
        max_uses = int(message.text.strip())
    except ValueError:
        await message.answer("Vvedite chislo. Naprimer: 10")
        return

    data = await state.get_data()
    code = data["code"]
    days = data["days"]

    add_promo(code, days=days, gb=0, max_uses=max_uses)

    await message.answer(
        f"[OK] Promokod sozdan!\n\n"
        f"  Kod: {code}\n"
        f"  Dney: {days}\n"
        f"  Max ispolzovaniy: {max_uses}",
        reply_markup=admin_menu_kb(),
    )
    await state.clear()


async def main():
    logger.info("Starting VPN bot...")
    await dp.start_polling(bot)


if __name__ == "__main__":
    asyncio.run(main())
