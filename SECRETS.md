# Секреты — как вписать (мобилка)

`google-services.json` не коммитится (в `.gitignore`). В CI он подставляется из GitHub-секрета.

## GitHub Actions

Repo → Settings → Secrets and variables → Actions → **New repository secret**:

| Secret | Значение |
|---|---|
| `GOOGLE_SERVICES_JSON` | всё содержимое файла `android/app/google-services.json` (целиком, как есть) |

Workflow (`.github/workflows/release.yml`) при сборке пишет этот секрет обратно в `android/app/google-services.json`, собирает **debug** APK и публикует его как GitHub Release с версией из `pubspec.yaml`.

## Локальная сборка

Положи реальный `android/app/google-services.json` из Firebase Console (проект → Android app → скачать). Он останется локально, в git не попадёт.

## Адрес сервера

Сейчас адрес API захардкожен в `lib/services/api.dart` (`kApiBase`). Когда бэкенд переедет в кластер за стабильный домен — поменять на этот домен один раз. До тех пор при смене сети адрес правится там же вручную.
