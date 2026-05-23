import asyncio
import logging
import uuid as uuid_mod
from datetime import datetime

from aiogram import Bot, Dispatcher, F, Router
from aiogram.types import (
    Message,
    CallbackQuery,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    LabeledPrice,
    PreCheckoutQuery,
)
from aiogram.filters import Command, CommandStart
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.enums import ParseMode

from config import BOT_TOKEN, ADMIN_IDS, SERVER_IP, PLANS, SERVERS
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


class AdminAddServer(StatesGroup):
    waiting_name = State()
    waiting_tag = State()


def is_admin(user_id: int) -> bool:
    return user_id in ADMIN_IDS


def fmt_bytes(b: int) -> str:
    if b <= 0:
        return "0 B"
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if abs(b) < 1024:
            return f"{b:.1f} {unit}"
        b /= 1024
    return f"{b:.1f} PB"


def fmt_ts(ts: int) -> str:
    if not ts:
        return "Безлимит"
    return datetime.fromtimestamp(ts).strftime("%d.%m.%Y %H:%M")


# ==================== KEYBOARDS ====================

def kb_main(user_id: int) -> InlineKeyboardMarkup:
    buttons = [
        [InlineKeyboardButton(text="🖥 Мои VPN", callback_data="my_vpn")],
        [InlineKeyboardButton(text="🛒 Купить подписку", callback_data="buy_menu")],
        [InlineKeyboardButton(text="🎁 Активировать промокод", callback_data="enter_promo")],
        [InlineKeyboardButton(text="📖 Инструкция", callback_data="instruction")],
        [InlineKeyboardButton(text="ℹ️ Информация", callback_data="info")],
    ]
    if is_admin(user_id):
        buttons.append(
            [InlineKeyboardButton(text="⚙️ Админ-панель", callback_data="admin_menu")]
        )
    return InlineKeyboardMarkup(inline_keyboard=buttons)


def kb_back(target: str = "back_main") -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        inline_keyboard=[[InlineKeyboardButton(text="⬅️ Назад", callback_data=target)]]
    )


def kb_buy_plans() -> InlineKeyboardMarkup:
    buttons = []
    for plan_id, plan in PLANS.items():
        label = f"📦 {plan['name']} — {plan['price']}₽"
        buttons.append([InlineKeyboardButton(text=label, callback_data=f"plan_{plan_id}")])
    buttons.append([InlineKeyboardButton(text="⬅️ Назад", callback_data="back_main")])
    return InlineKeyboardMarkup(inline_keyboard=buttons)


def kb_select_server(plan_id: str) -> InlineKeyboardMarkup:
    buttons = []
    for srv_id, srv in SERVERS.items():
        flag = srv.get("flag", "🌐")
        buttons.append([InlineKeyboardButton(
            text=f"{flag} {srv['name']}",
            callback_data=f"srv_{plan_id}_{srv_id}"
        )])
    buttons.append([InlineKeyboardButton(text="⬅️ Назад", callback_data="buy_menu")])
    return InlineKeyboardMarkup(inline_keyboard=buttons)


def kb_payment(plan_id: str, srv_id: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="⭐ Telegram Stars", callback_data=f"pay_stars_{plan_id}_{srv_id}")],
        [InlineKeyboardButton(text="🎟 Ввести промокод", callback_data="enter_promo")],
        [InlineKeyboardButton(text="⬅️ Назад", callback_data=f"plan_{plan_id}")],
    ])


def kb_admin() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="👥 Пользователи", callback_data="admin_users")],
        [InlineKeyboardButton(text="📊 Статистика", callback_data="admin_stats")],
        [InlineKeyboardButton(text="🎟 Промокоды", callback_data="admin_promos")],
        [InlineKeyboardButton(text="➕ Добавить промокод", callback_data="admin_add_promo")],
        [InlineKeyboardButton(text="🌐 Серверы", callback_data="admin_servers")],
        [InlineKeyboardButton(text="⬅️ Назад", callback_data="back_main")],
    ])


def kb_instruction() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="🤖 Android", callback_data="instr_android")],
        [InlineKeyboardButton(text="🍎 iOS", callback_data="instr_ios")],
        [InlineKeyboardButton(text="💻 Windows / Mac / Linux", callback_data="instr_pc")],
        [InlineKeyboardButton(text="⬅️ Назад", callback_data="back_main")],
    ])


# ==================== HANDLERS ====================

@router.message(CommandStart())
async def cmd_start(message: Message, state: FSMContext):
    await state.clear()
    user = message.from_user
    text = (
        f"🔐 <b>VPN Service</b>\n"
        f"━━━━━━━━━━━━━━━━━━\n\n"
        f"👋 Привет, <b>{user.first_name}</b>!\n\n"
        f"Быстрый и безопасный VPN\n"
        f"на базе протокола VLESS-Reality\n\n"
        f"Выберите действие:"
    )
    await message.answer(text, reply_markup=kb_main(user.id), parse_mode=ParseMode.HTML)


@router.callback_query(F.data == "back_main")
async def go_main(cb: CallbackQuery, state: FSMContext):
    await state.clear()
    text = (
        f"🔐 <b>VPN Service</b>\n"
        f"━━━━━━━━━━━━━━━━━━\n\n"
        f"Выберите действие:"
    )
    await cb.message.edit_text(text, reply_markup=kb_main(cb.from_user.id), parse_mode=ParseMode.HTML)


# ===== MY VPN =====

@router.callback_query(F.data == "my_vpn")
async def my_vpn(cb: CallbackQuery):
    tg_id = cb.from_user.id
    username = f"tg_{tg_id}"
    user_data = await marzban.get_user(username)

    if not user_data:
        text = (
            "🔒 <b>У вас нет активной подписки</b>\n\n"
            "Купите подписку или используйте промокод."
        )
        kb = InlineKeyboardMarkup(inline_keyboard=[
            [InlineKeyboardButton(text="🛒 Купить подписку", callback_data="buy_menu")],
            [InlineKeyboardButton(text="🎁 Промокод", callback_data="enter_promo")],
            [InlineKeyboardButton(text="⬅️ Назад", callback_data="back_main")],
        ])
        await cb.message.edit_text(text, reply_markup=kb, parse_mode=ParseMode.HTML)
        return

    status = user_data.get("status", "unknown")
    status_icon = "✅" if status == "active" else "❌"
    used = user_data.get("used_traffic", 0)
    limit = user_data.get("data_limit", 0)
    expire = user_data.get("expire", 0)

    if expire:
        days_left = max(0, (expire - int(datetime.now().timestamp())) // 86400)
        expire_str = f"{fmt_ts(expire)} (осталось {days_left} дн.)"
    else:
        expire_str = "♾ Безлимит"

    traffic_str = fmt_bytes(used)
    traffic_str += f" / {fmt_bytes(limit)}" if limit else " / ♾"

    links = user_data.get("links", [])
    sub_url = user_data.get("subscription_url", "")

    text = (
        f"🖥 <b>Ваш профиль</b>\n"
        f"━━━━━━━━━━━━━━━━━━\n\n"
        f"👤 Имя: <code>{username}</code>\n"
        f"📊 Статус: {status_icon} {status.title()}\n"
        f"📅 Истекает: {expire_str}\n"
        f"📈 Трафик: {traffic_str}\n"
        f"━━━━━━━━━━━━━━━━━━\n\n"
    )

    if links:
        text += f"🔗 <b>Ссылка для подключения:</b>\n<code>{links[0]}</code>\n\n"

    if sub_url:
        full_sub = f"http://{SERVER_IP}:8000{sub_url}"
        text += f"🔄 <b>Подписка (авто-обновление):</b>\n<code>{full_sub}</code>\n"

    kb = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📖 Как подключиться", callback_data="instruction")],
        [InlineKeyboardButton(text="⬅️ Назад", callback_data="back_main")],
    ])
    await cb.message.edit_text(text, reply_markup=kb, parse_mode=ParseMode.HTML)


# ===== BUY =====

@router.callback_query(F.data == "buy_menu")
async def buy_menu(cb: CallbackQuery):
    text = (
        "🛒 <b>Выберите тариф</b>\n"
        "━━━━━━━━━━━━━━━━━━\n\n"
    )
    for plan_id, plan in PLANS.items():
        text += (
            f"📦 <b>{plan['name']}</b>\n"
            f"   Срок: {plan['days']} дн. | "
            f"Трафик: {plan.get('gb', 0) or '♾'} ГБ | "
            f"Устройства: {plan.get('devices', '♾')}\n"
            f"   💰 Цена: <b>{plan['price']}₽</b>\n\n"
        )
    await cb.message.edit_text(text, reply_markup=kb_buy_plans(), parse_mode=ParseMode.HTML)


@router.callback_query(F.data.startswith("plan_"))
async def select_plan(cb: CallbackQuery):
    plan_id = cb.data.replace("plan_", "")
    plan = PLANS.get(plan_id)
    if not plan:
        await cb.answer("Тариф не найден", show_alert=True)
        return

    text = (
        f"🌍 <b>Выберите сервер</b>\n"
        f"━━━━━━━━━━━━━━━━━━\n\n"
        f"Тариф: <b>{plan['name']}</b> — {plan['price']}₽\n\n"
        f"Доступные серверы:"
    )
    await cb.message.edit_text(text, reply_markup=kb_select_server(plan_id), parse_mode=ParseMode.HTML)


@router.callback_query(F.data.startswith("srv_"))
async def select_server(cb: CallbackQuery):
    parts = cb.data.split("_", 2)
    plan_id = parts[1]
    srv_id = parts[2]
    plan = PLANS.get(plan_id)
    srv = SERVERS.get(srv_id)
    if not plan or not srv:
        await cb.answer("Ошибка", show_alert=True)
        return

    text = (
        f"💳 <b>Оплата тарифа</b>\n"
        f"━━━━━━━━━━━━━━━━━━\n\n"
        f"📦 Тариф: {plan['name']}\n"
        f"🌍 Сервер: {srv.get('flag','')} {srv['name']}\n"
        f"📅 Срок: {plan['days']} дн.\n"
        f"📈 Трафик: {plan.get('gb', 0) or '♾'} ГБ\n\n"
        f"💰 <b>Сумма к оплате: {plan['price']}₽</b>\n\n"
        f"Выберите способ оплаты:"
    )
    await cb.message.edit_text(text, reply_markup=kb_payment(plan_id, srv_id), parse_mode=ParseMode.HTML)


# ===== TELEGRAM STARS PAYMENT =====

@router.callback_query(F.data.startswith("pay_stars_"))
async def pay_stars(cb: CallbackQuery):
    parts = cb.data.split("_")
    plan_id = parts[2]
    srv_id = parts[3]
    plan = PLANS.get(plan_id)
    if not plan:
        await cb.answer("Ошибка", show_alert=True)
        return

    stars_amount = plan.get("stars", 1)

    await bot.send_invoice(
        chat_id=cb.from_user.id,
        title=f"VPN — {plan['name']}",
        description=f"Подписка VPN на {plan['days']} дней. Сервер: {SERVERS.get(srv_id, {}).get('name', 'Auto')}",
        payload=f"{plan_id}|{srv_id}",
        currency="XTR",
        prices=[LabeledPrice(label=plan["name"], amount=stars_amount)],
    )
    await cb.answer()


@router.pre_checkout_query()
async def pre_checkout(query: PreCheckoutQuery):
    await query.answer(ok=True)


@router.message(F.successful_payment)
async def successful_payment(message: Message):
    payload = message.successful_payment.invoice_payload
    plan_id, srv_id = payload.split("|")
    plan = PLANS.get(plan_id, {})

    tg_id = message.from_user.id
    username = f"tg_{tg_id}"

    existing = await marzban.get_user(username)
    if existing:
        text = "✅ Оплата прошла! Ваша подписка уже активна.\n\nНажмите 🖥 Мои VPN для ссылки."
        await message.answer(text, reply_markup=kb_back())
        return

    srv = SERVERS.get(srv_id, {})
    inbound_tag = srv.get("inbound_tag", "VLESS_REALITY")

    user_data = await marzban.create_user(
        username=username,
        data_limit_gb=plan.get("gb", 0),
        expire_days=plan.get("days", 30),
        inbound_tag=inbound_tag,
    )

    if user_data:
        links = user_data.get("links", [])
        text = f"✅ <b>Оплата успешна!</b>\n\n"
        if links:
            text += f"🔗 Ваша ссылка:\n<code>{links[0]}</code>\n\n"
        text += "Нажмите 📖 Инструкция для подключения."
        await message.answer(text, reply_markup=kb_back(), parse_mode=ParseMode.HTML)
    else:
        await message.answer(
            "❌ Ошибка создания подписки. Обратитесь в поддержку.",
            reply_markup=kb_back(),
        )


# ===== PROMO =====

@router.callback_query(F.data == "enter_promo")
async def enter_promo(cb: CallbackQuery, state: FSMContext):
    await cb.message.edit_text(
        "🎟 <b>Введите промокод:</b>",
        reply_markup=kb_back(),
        parse_mode=ParseMode.HTML,
    )
    await state.set_state(PromoState.waiting_code)


@router.message(PromoState.waiting_code)
async def process_promo(message: Message, state: FSMContext):
    code = message.text.strip()
    promo = validate_promo(code)

    if not promo:
        await message.answer("❌ Промокод неверен или уже использован.", reply_markup=kb_back())
        await state.clear()
        return

    tg_id = message.from_user.id
    username = f"tg_{tg_id}"

    existing = await marzban.get_user(username)
    if existing:
        await message.answer(
            "ℹ️ У вас уже есть подписка!\nНажмите 🖥 Мои VPN.",
            reply_markup=kb_back(),
        )
        await state.clear()
        return

    user_data = await marzban.create_user(
        username=username,
        data_limit_gb=promo.get("gb", 0),
        expire_days=promo.get("days", 30),
    )

    if user_data:
        use_promo(code)
        links = user_data.get("links", [])
        text = f"✅ <b>Подписка активирована!</b>\n\n"
        if links:
            text += f"🔗 Ваша ссылка:\n<code>{links[0]}</code>\n\n"
        text += "Нажмите 📖 Инструкция для подключения."
        await message.answer(text, reply_markup=kb_back(), parse_mode=ParseMode.HTML)
    else:
        await message.answer("❌ Ошибка создания подписки.", reply_markup=kb_back())

    await state.clear()


# ===== INSTRUCTION =====

@router.callback_query(F.data == "instruction")
async def instruction(cb: CallbackQuery):
    text = (
        "📖 <b>Как подключиться к VPN</b>\n"
        "━━━━━━━━━━━━━━━━━━\n\n"
        "Выберите вашу платформу:"
    )
    await cb.message.edit_text(text, reply_markup=kb_instruction(), parse_mode=ParseMode.HTML)


@router.callback_query(F.data == "instr_android")
async def instr_android(cb: CallbackQuery):
    text = (
        "🤖 <b>Android</b>\n"
        "━━━━━━━━━━━━━━━━━━\n\n"
        "<b>Рекомендуемые приложения:</b>\n"
        "• V2RayNG — Google Play\n"
        "• Hiddify — Google Play\n"
        "• NekoBox — GitHub\n\n"
        "<b>Подключение:</b>\n"
        "1. Установите приложение\n"
        "2. Перейдите в 🖥 Мои VPN\n"
        "3. Скопируйте ссылку (vless://...)\n"
        "4. В приложении нажмите ➕\n"
        "5. Выберите «Добавить из буфера»\n"
        "6. Нажмите кнопку подключения ▶️\n\n"
        "<b>Проверка:</b>\n"
        "• ipinfo.io — должен показать IP сервера\n"
        "• 2ip.ru — должен показать ваш IP (РФ)\n\n"
        "⚠️ Убедитесь что <b>Flow = xtls-rprx-vision</b>"
    )
    await cb.message.edit_text(text, reply_markup=kb_back("instruction"), parse_mode=ParseMode.HTML)


@router.callback_query(F.data == "instr_ios")
async def instr_ios(cb: CallbackQuery):
    text = (
        "🍎 <b>iOS (iPhone / iPad)</b>\n"
        "━━━━━━━━━━━━━━━━━━\n\n"
        "<b>Рекомендуемые приложения:</b>\n"
        "• Streisand — App Store (бесплатно)\n"
        "• FoXray — App Store (бесплатно)\n"
        "• Shadowrocket — App Store (платно)\n"
        "• Happ — App Store\n\n"
        "<b>Подключение:</b>\n"
        "1. Установите приложение\n"
        "2. Перейдите в 🖥 Мои VPN\n"
        "3. Скопируйте ссылку (vless://...)\n"
        "4. Откройте приложение\n"
        "5. Ссылка добавится автоматически\n"
        "6. Разрешите VPN-конфигурацию\n"
        "7. Подключитесь ▶️\n\n"
        "⚠️ Проверьте что <b>Flow = xtls-rprx-vision</b>"
    )
    await cb.message.edit_text(text, reply_markup=kb_back("instruction"), parse_mode=ParseMode.HTML)


@router.callback_query(F.data == "instr_pc")
async def instr_pc(cb: CallbackQuery):
    text = (
        "💻 <b>Windows / Mac / Linux</b>\n"
        "━━━━━━━━━━━━━━━━━━\n\n"
        "<b>Рекомендуемые приложения:</b>\n"
        "• Nekoray — github.com/MatsuriDayo/nekoray\n"
        "• Hiddify — github.com/hiddify/hiddify-app\n"
        "• V2RayN (Windows) — github.com/2dust/v2rayN\n\n"
        "<b>Подключение:</b>\n"
        "1. Скачайте и установите приложение\n"
        "2. Перейдите в 🖥 Мои VPN\n"
        "3. Скопируйте ссылку (vless://...)\n"
        "4. В приложении: Сервер → Добавить из буфера\n"
        "5. Включите System Proxy или TUN режим\n\n"
        "<b>Настройка маршрутизации:</b>\n"
        "В настройках маршрутов добавьте в Direct:\n"
        "<code>geoip:ru, geosite:category-ru, domain:.ru, domain:.su</code>\n\n"
        "Это позволит российским сайтам (Госуслуги, Сбер, ВК)\n"
        "работать напрямую без VPN."
    )
    await cb.message.edit_text(text, reply_markup=kb_back("instruction"), parse_mode=ParseMode.HTML)


# ===== INFO =====

@router.callback_query(F.data == "info")
async def info(cb: CallbackQuery):
    text = (
        "ℹ️ <b>О сервисе</b>\n"
        "━━━━━━━━━━━━━━━━━━\n\n"
        "🔐 Протокол: VLESS-Reality\n"
        "🛡 Защита: XTLS-Vision + uTLS\n"
        "🌍 Серверы: Германия (DE)\n\n"
        "📌 <b>Преимущества:</b>\n"
        "• Не обнаруживается РКН и DPI\n"
        "• Маскировка под обычный HTTPS\n"
        "• Нет логирования трафика\n"
        "• Поддержка всех платформ\n\n"
        "📞 Поддержка: @your_support"
    )
    await cb.message.edit_text(text, reply_markup=kb_back(), parse_mode=ParseMode.HTML)


# ===== ADMIN =====

@router.callback_query(F.data == "admin_menu")
async def admin_menu(cb: CallbackQuery):
    if not is_admin(cb.from_user.id):
        await cb.answer("Нет доступа", show_alert=True)
        return
    await cb.message.edit_text("⚙️ <b>Админ-панель</b>", reply_markup=kb_admin(), parse_mode=ParseMode.HTML)


@router.callback_query(F.data == "admin_users")
async def admin_users(cb: CallbackQuery):
    if not is_admin(cb.from_user.id):
        return
    data = await marzban.get_users()
    users = data.get("users", [])

    text = f"👥 <b>Пользователи ({len(users)})</b>\n━━━━━━━━━━━━━━━━━━\n\n"
    for u in users[:20]:
        icon = "✅" if u["status"] == "active" else "❌"
        traffic = fmt_bytes(u.get("used_traffic", 0))
        text += f"{icon} <code>{u['username']}</code> — {traffic}\n"

    if not users:
        text += "Пусто"
    await cb.message.edit_text(text, reply_markup=kb_admin(), parse_mode=ParseMode.HTML)


@router.callback_query(F.data == "admin_stats")
async def admin_stats(cb: CallbackQuery):
    if not is_admin(cb.from_user.id):
        return
    stats = await marzban.get_system_stats()
    users_data = await marzban.get_users()

    text = (
        f"📊 <b>Статистика сервера</b>\n"
        f"━━━━━━━━━━━━━━━━━━\n\n"
        f"🖥 CPU: {stats.get('cpu_usage', 0):.0f}%\n"
        f"💾 RAM: {fmt_bytes(stats.get('mem_used', 0))} / {fmt_bytes(stats.get('mem_total', 0))}\n"
        f"👥 Пользователей: {users_data.get('total', 0)}\n"
        f"🌐 IP: {SERVER_IP}\n"
    )
    await cb.message.edit_text(text, reply_markup=kb_admin(), parse_mode=ParseMode.HTML)


@router.callback_query(F.data == "admin_promos")
async def admin_promos_list(cb: CallbackQuery):
    if not is_admin(cb.from_user.id):
        return
    promos = list_promos()

    if not promos:
        text = "🎟 <b>Промокоды</b>\n\nПусто. Добавьте через ➕"
    else:
        text = f"🎟 <b>Промокоды ({len(promos)})</b>\n━━━━━━━━━━━━━━━━━━\n\n"
        for code, p in promos.items():
            text += (
                f"<code>{code}</code>\n"
                f"  📅 {p['days']} дн. | 📊 {p.get('gb', 0) or '♾'} ГБ | "
                f"🔢 {p.get('uses', 0)}/{p['max_uses']}\n\n"
            )
    await cb.message.edit_text(text, reply_markup=kb_admin(), parse_mode=ParseMode.HTML)


@router.callback_query(F.data == "admin_add_promo")
async def admin_add_promo(cb: CallbackQuery, state: FSMContext):
    if not is_admin(cb.from_user.id):
        return
    await cb.message.edit_text("➕ Введите промокод (например: FREE30):", reply_markup=kb_back("admin_menu"))
    await state.set_state(AdminAddPromo.waiting_code)


@router.message(AdminAddPromo.waiting_code)
async def ap_code(message: Message, state: FSMContext):
    await state.update_data(code=message.text.strip().upper())
    await message.answer("📅 Сколько дней действия? (например: 30)")
    await state.set_state(AdminAddPromo.waiting_days)


@router.message(AdminAddPromo.waiting_days)
async def ap_days(message: Message, state: FSMContext):
    try:
        days = int(message.text.strip())
    except ValueError:
        await message.answer("Введите число.")
        return
    await state.update_data(days=days)
    await message.answer("🔢 Максимум использований? (например: 10)")
    await state.set_state(AdminAddPromo.waiting_max_uses)


@router.message(AdminAddPromo.waiting_max_uses)
async def ap_max(message: Message, state: FSMContext):
    try:
        max_uses = int(message.text.strip())
    except ValueError:
        await message.answer("Введите число.")
        return
    data = await state.get_data()
    add_promo(data["code"], days=data["days"], gb=0, max_uses=max_uses)
    await message.answer(
        f"✅ Промокод создан!\n\n"
        f"🎟 Код: <code>{data['code']}</code>\n"
        f"📅 Дней: {data['days']}\n"
        f"🔢 Макс: {max_uses}",
        reply_markup=kb_admin(),
        parse_mode=ParseMode.HTML,
    )
    await state.clear()


@router.callback_query(F.data == "admin_servers")
async def admin_servers(cb: CallbackQuery):
    if not is_admin(cb.from_user.id):
        return
    text = f"🌐 <b>Серверы ({len(SERVERS)})</b>\n━━━━━━━━━━━━━━━━━━\n\n"
    for srv_id, srv in SERVERS.items():
        text += f"{srv.get('flag', '🌐')} <b>{srv['name']}</b>\n  ID: <code>{srv_id}</code> | Tag: <code>{srv.get('inbound_tag', 'VLESS_REALITY')}</code>\n\n"
    text += "ℹ️ Серверы настраиваются в config.py"
    await cb.message.edit_text(text, reply_markup=kb_admin(), parse_mode=ParseMode.HTML)


async def main():
    logger.info("Starting VPN bot...")
    await dp.start_polling(bot)


if __name__ == "__main__":
    asyncio.run(main())
