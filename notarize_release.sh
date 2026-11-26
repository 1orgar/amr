#!/bin/bash
set -euo pipefail

# ==============================================================================
# Apple Music Remote (AMR) — One-Command Apple Notarization & Stapling Assistant
# ==============================================================================

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROFILE_NAME="${APPLE_NOTARIZE_KEYCHAIN_PROFILE:-AMR-Notary}"
DEFAULT_APPLE_ID="${APPLE_NOTARIZE_APPLE_ID:-}"
DEFAULT_TEAM_ID="${APPLE_NOTARIZE_TEAM_ID:-886CSW93R8}"
SKIP_BUILD=0
for arg in "$@"; do
    if [ "$arg" = "--skip-build" ]; then
        SKIP_BUILD=1
    fi
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "=========================================================="
echo "🛡️  AMR — Apple Developer ID Signing & Notarization"
echo "=========================================================="

# 1. Verify Developer ID Application certificate is installed in Keychain
DEV_ID_CERT="$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -n 1 | awk -F'"' '{print $2}' || true)"

# Auto-import downloaded developerID_application.cer from ~/Downloads or project root if present
if [ -z "$DEV_ID_CERT" ]; then
    SIGN_KEY_FILE="$HOME/Library/Application Support/AppleMusicRemoteMac/signing/developer_id_rsa.key"
    if [ -f "$SIGN_KEY_FILE" ]; then
        security import "$SIGN_KEY_FILE" -k "$HOME/Library/Keychains/login.keychain-db" -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productsign >/dev/null 2>&1 || true
    fi
    for candidate_cer in "$ROOT_DIR"/developerID_application*.cer "$HOME/Downloads"/developerID_application*.cer "$ROOT_DIR"/*.cer; do
        if [ -f "$candidate_cer" ]; then
            echo "📥 Импортирую скачанный сертификат $(basename "$candidate_cer") в Связку ключей..."
            security import "$candidate_cer" -k "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || true
        fi
    done
    DEV_ID_CERT="$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -n 1 | awk -F'"' '{print $2}' || true)"
fi

if [ -z "$DEV_ID_CERT" ]; then
    echo ""
    echo "❌ В Связке ключей пока нет сертификата 'Developer ID Application'!"
    echo ""
    echo "Сделайте 3 клика в Xcode (займёт ~20 секунд):"
    echo "  1) В окне Xcode → Settings (⌘,) → Apple Accounts нажмите на '$DEFAULT_APPLE_ID'"
    echo "  2) Нажмите кнопку 'Manage Certificates…'"
    echo "  3) Нажмите '+' (внизу слева) → выберите 'Developer ID Application'"
    echo ""
    echo "После этого снова запустите:"
    echo "  ./notarize_release.sh"
    echo ""
    exit 1
fi

echo "✅ Найден сертификат подписи: $DEV_ID_CERT"

# 2. Verify or interactively configure notarytool credentials
HAS_CREDS=0
if [ -n "${APPLE_NOTARIZE_API_KEY_PATH:-}" ] && [ -n "${APPLE_NOTARIZE_API_KEY_ID:-}" ] && [ -n "${APPLE_NOTARIZE_API_ISSUER_ID:-}" ]; then
    HAS_CREDS=1
    echo "✅ Используется App Store Connect API Key: $APPLE_NOTARIZE_API_KEY_ID"
elif [ -n "${APPLE_NOTARIZE_APPLE_ID:-}" ] && [ -n "${APPLE_NOTARIZE_TEAM_ID:-}" ] && [ -n "${APPLE_NOTARIZE_APP_PASSWORD:-}" ]; then
    HAS_CREDS=1
    echo "✅ Используются переменные окружения Apple ID ($APPLE_NOTARIZE_APPLE_ID)"
elif xcrun notarytool history --keychain-profile "$PROFILE_NAME" >/dev/null 2>&1; then
    HAS_CREDS=1
    echo "✅ Найден сохранённый профиль нотаризации в Связке ключей: $PROFILE_NAME"
fi

if [ "$HAS_CREDS" = "0" ]; then
    if [ ! -t 0 ]; then
        echo "❌ Профиль нотаризации '$PROFILE_NAME' ещё не настроен в Связке ключей."
        echo "   Запустите ./notarize_release.sh в обычном окне Терминала для разовой настройки."
        exit 1
    fi

    echo ""
    echo "🔑 Первичная настройка профиля нотаризации '$PROFILE_NAME' (делается 1 раз):"
    echo "   Создайте пароль приложения (App-Specific Password) на:"
    echo "   👉 https://account.apple.com  (Вход и безопасность → Пароли приложений)"
    echo ""

    read -rp "   Apple ID [$DEFAULT_APPLE_ID]: " INPUT_APPLE_ID
    APPLE_ID="${INPUT_APPLE_ID:-$DEFAULT_APPLE_ID}"

    read -rp "   Team ID [$DEFAULT_TEAM_ID]: " INPUT_TEAM_ID
    TEAM_ID="${INPUT_TEAM_ID:-$DEFAULT_TEAM_ID}"

    read -rsp "   Пароль приложения (xxxx-xxxx-xxxx-xxxx): " APP_PASSWORD
    echo ""

    if [ -z "$APP_PASSWORD" ]; then
        echo "❌ Пароль приложения не введён. Отмена."
        exit 1
    fi

    echo "💾 Сохраняю и проверяю учётные данные в Связке ключей..."
    xcrun notarytool store-credentials "$PROFILE_NAME" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD"
    echo "✅ Профиль '$PROFILE_NAME' успешно сохранён!"
fi

if [ "$SKIP_BUILD" = "1" ] && [ -f "$ROOT_DIR/AppleMusicRemoteMac-Universal.dmg" ]; then
    DMG_OUTPUT="$ROOT_DIR/AppleMusicRemoteMac-Universal.dmg"
    echo ""
    echo "🛡️ Отправляю готовый $DMG_OUTPUT в Apple Notary Service (профиль: $PROFILE_NAME)..."
    NOTARY_TXT_OUT="$(mktemp -t amr_notary_result.XXXXXX.txt)"
    trap 'rm -f "$NOTARY_TXT_OUT"' EXIT
    set +e
    xcrun notarytool submit "$DMG_OUTPUT" --keychain-profile "$PROFILE_NAME" --wait 2>&1 | tee "$NOTARY_TXT_OUT"
    SUBMIT_EXIT=${PIPESTATUS[0]}
    set -e
    NOTARY_ID="$(grep -E "^[[:space:]]*id:[[:space:]]*" "$NOTARY_TXT_OUT" | tail -n 1 | awk '{print $2}' || true)"
    NOTARY_STATUS="$(grep -E "^[[:space:]]*status:[[:space:]]*" "$NOTARY_TXT_OUT" | tail -n 1 | awk '{print $2}' || true)"
    if [ "$SUBMIT_EXIT" -ne 0 ] || [ "$NOTARY_STATUS" != "Accepted" ]; then
        echo "❌ Нотаризация отклонена (status: $NOTARY_STATUS, id: $NOTARY_ID)"
        if [ -n "$NOTARY_ID" ]; then
            xcrun notarytool log "$NOTARY_ID" --keychain-profile "$PROFILE_NAME" || true
        fi
        exit 1
    fi
    echo "📎 Приклеиваю тикет нотаризации Apple (stapler)..."
    xcrun stapler staple "$DMG_OUTPUT"
    xcrun stapler validate "$DMG_OUTPUT"
    if [ -d "$ROOT_DIR/AppleMusicRemoteMac/build/AppleMusicRemoteMac.app" ]; then
        xcrun stapler staple "$ROOT_DIR/AppleMusicRemoteMac/build/AppleMusicRemoteMac.app" >/dev/null 2>&1 || true
    fi
    echo "🛡️ Проверяю Gatekeeper (spctl)..."
    spctl -a -t open --context context:primary-signature -v "$DMG_OUTPUT" || true
    echo ""
    echo "✅ Готово! Файл $DMG_OUTPUT полностью подписан, нотаризован Apple и прошёл Gatekeeper!"
    exit 0
fi

echo ""
echo "🚀 Запускаю сборку Universal 2 (.app + .dmg), подпись Developer ID, нотаризацию Apple и приклейку тикета..."
APPLE_SIGN_IDENTITY="$DEV_ID_CERT" \
APPLE_NOTARIZE_KEYCHAIN_PROFILE="$PROFILE_NAME" \
REQUIRE_NOTARIZATION=1 \
"$ROOT_DIR/build_universal_dmg.sh" --notarize
