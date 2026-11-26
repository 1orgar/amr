#!/bin/bash
set -euo pipefail

# ==============================================================================
# AMR — Automated GitHub Actions Notarization Secrets Uploader (gh CLI)
# ==============================================================================
# Packages local Developer ID certificate + private key into an ephemeral PKCS#12
# bundle, verifies it in an isolated keychain, and uploads encrypted secrets
# directly to GitHub Actions for `.github/workflows/release.yml`.
# ==============================================================================

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
CER_FILE="$ROOT_DIR/developerID_application.cer"
KEY_FILE="$HOME/Library/Application Support/AppleMusicRemoteMac/signing/developer_id_rsa.key"
DEFAULT_APPLE_ID="${APPLE_NOTARIZE_APPLE_ID:-}"
DEFAULT_TEAM_ID="${APPLE_NOTARIZE_TEAM_ID:-886CSW93R8}"
SIGN_IDENTITY="${APPLE_SIGN_IDENTITY:-Developer ID Application}"

echo "=========================================================="
echo "🔐 AMR — Настройка GitHub Actions Secrets для нотаризации"
echo "=========================================================="

if ! command -v gh >/dev/null 2>&1; then
    echo "❌ Утилита GitHub CLI (gh) не найдена. Установите: brew install gh"
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "❌ Вы не авторизованы в gh CLI. Выполните: gh auth login"
    exit 1
fi

if [ ! -f "$CER_FILE" ]; then
    echo "❌ Не найден сертификат: $CER_FILE"
    exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
    echo "❌ Не найден приватный ключ: $KEY_FILE"
    exit 1
fi

REPO_URL="$(git -C "$ROOT_DIR" remote get-url origin)"
echo "📦 Репозиторий: $REPO_URL"
echo ""

read -rp "1) Apple ID для нотаризации [$DEFAULT_APPLE_ID]: " INPUT_APPLE_ID
APPLE_ID="${INPUT_APPLE_ID:-$DEFAULT_APPLE_ID}"

read -rp "2) Team ID [$DEFAULT_TEAM_ID]: " INPUT_TEAM_ID
TEAM_ID="${INPUT_TEAM_ID:-$DEFAULT_TEAM_ID}"

read -rsp "3) App-Specific Password (тот же, что для AMR-Notary): " APP_PASSWORD
echo ""
if [ -z "$APP_PASSWORD" ]; then
    echo "❌ Пароль приложения не введён. Отмена."
    exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'security delete-keychain "$TMP_DIR/verify.keychain-db" >/dev/null 2>&1 || true; rm -rf "$TMP_DIR"' EXIT

echo ""
echo "🔄 Собираю зашифрованный контейнер PKCS#12 (.p12) во временной памяти..."
P12_PASSWORD="$(uuidgen)-$(uuidgen)"
KC_PASS="$(uuidgen)"

/usr/bin/openssl x509 -inform DER -in "$CER_FILE" -out "$TMP_DIR/cert.pem" 2>/dev/null || cp "$CER_FILE" "$TMP_DIR/cert.pem"
/usr/bin/openssl pkcs12 -export \
    -out "$TMP_DIR/cert.p12" \
    -inkey "$KEY_FILE" \
    -in "$TMP_DIR/cert.pem" \
    -passout "pass:$P12_PASSWORD"

echo "🔍 Проверяю импорт .p12 в изолированный временный Keychain (как в GitHub Actions)..."
security create-keychain -p "$KC_PASS" "$TMP_DIR/verify.keychain-db"
security unlock-keychain -p "$KC_PASS" "$TMP_DIR/verify.keychain-db"
security import "$TMP_DIR/cert.p12" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$TMP_DIR/verify.keychain-db" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$TMP_DIR/verify.keychain-db" >/dev/null
FOUND_ID="$(security find-identity -v -p codesigning "$TMP_DIR/verify.keychain-db" | grep "Developer ID Application" | head -n 1 | awk -F'"' '{print $2}' || true)"

if [ -z "$FOUND_ID" ]; then
    echo "❌ Проверка .p12 не прошла: Developer ID Application не найден после импорта."
    exit 1
fi
SIGN_IDENTITY="$FOUND_ID"
echo "✅ Проверка пройдена: $SIGN_IDENTITY"

P12_BASE64="$(base64 < "$TMP_DIR/cert.p12" | tr -d '\n')"

echo "☁️  Загружаю зашифрованные секреты в GitHub Actions ($REPO_URL)..."
printf "%s" "$P12_BASE64"    | gh secret set APPLE_CERTIFICATE_P12_BASE64 -R "$REPO_URL"
printf "%s" "$P12_PASSWORD"  | gh secret set APPLE_CERTIFICATE_PASSWORD   -R "$REPO_URL"
printf "%s" "$SIGN_IDENTITY" | gh secret set APPLE_SIGN_IDENTITY          -R "$REPO_URL"
printf "%s" "$APPLE_ID"      | gh secret set APPLE_NOTARIZE_APPLE_ID      -R "$REPO_URL"
printf "%s" "$TEAM_ID"       | gh secret set APPLE_NOTARIZE_TEAM_ID       -R "$REPO_URL"
printf "%s" "$APP_PASSWORD"  | gh secret set APPLE_NOTARIZE_APP_PASSWORD  -R "$REPO_URL"

echo ""
echo "📋 Текущий список секретов в репозитории:"
gh secret list -R "$REPO_URL"

echo ""
echo "✅ Готово! Теперь при каждом пуше тега (например: git tag v3.0.1 && git push origin v3.0.1)"
echo "   GitHub Actions автоматически прогонит тесты, соберёт Universal .dmg, подпишет Developer ID,"
echo "   нотаризует в Apple, приклеит тикет и опубликует релиз в GitHub Releases!"
