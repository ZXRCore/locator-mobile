# locator-mobile

0xMap — приложение шеринга геолокации (тип Zenly). Flutter, Android.
Package: `sh.zxr.locator`.

## Сборка локально
```bash
# положить android/app/google-services.json из Firebase (см. SECRETS.md)
flutter pub get
flutter build apk --debug
```
Собираем **debug** APK — в нём плагин трекинга (`flutter_background_geolocation`) бесплатен. Раздаётся друзьям напрямую.

## CI/CD
`.github/workflows/release.yml`: пуш в `master` → сборка debug APK → GitHub Release с версией из `pubspec.yaml` и приложенным `app-debug.apk`. `google-services.json` подставляется из секрета `GOOGLE_SERVICES_JSON`.

## Адрес сервера
`lib/services/api.dart` → `kApiBase`. Указывает на locator-backend. Правится вручную до переезда бэкенда на стабильный домен.

Секреты — см. [SECRETS.md](SECRETS.md).
