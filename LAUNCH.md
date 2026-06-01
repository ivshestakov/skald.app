# Skald — Launch & Monetization Plan

**Цель:** запустить бесплатно, набрать аудиторию, потом ввести Skald
Cloud (платный proxy к Claude без BYOK) если будет спрос. На первом
горизонте — окупить кофе и Developer ID, не более.

**Этот файл — план для будущих сессий.** Каждый раздел самодостаточен:
открываешь репо в новом чате с Claude, говоришь «делаем Phase 0, шаг 3»
— по нему видно, что именно сделать.

Текущий статус приложения: **Skald 0.3.0** опубликован,
<https://github.com/ivshestakov/skald.app/releases/tag/v0.3.0>.
**Signed + notarized**, никаких Gatekeeper warning'ов. Продуктовый
лендинг на <https://panic-kit.com/skald>. Sparkle auto-update
настроен, фид на panic-kit.com/skald/appcast.xml — будущие версии
устанавливаются сами.

**Phase 0 закрыт ✅.** Дальше — Phase 1 (лонч).

---

## Phase 0 — Инфраструктура (1 неделя, ~$200)

Цель: убрать все технические трения перед лончем. Без этого нет смысла
куда-то постить — конверсия будет нулевая.

### 0.1. Apple Developer ID — $99/год  *(оплачен, нужен только cert)*

Сам аккаунт уже есть. Осталось сгенерировать сертификат
**Developer ID Application** (это НЕ то же самое, что «Apple
Development» — последний только для локального Xcode).

- <https://developer.apple.com/account/resources/certificates/list>
  → **+** → **Developer ID Application** → Continue.
- Apple просит CSR (Certificate Signing Request):
  - **Keychain Access** → меню **Certificate Assistant** →
    **Request a Certificate from a Certificate Authority…**
  - Email: ivshestakov@gmail.com, Common Name: `Ivan Shestakov`,
    Request is: **Saved to disk**.
- Загрузить CSR назад на сайт Apple → скачать `developerID_application.cer`
  → дабл-кликом установить в login keychain.
- Проверить:
  ```
  security find-identity -v -p codesigning | grep "Developer ID"
  ```
  Должно вывести `Developer ID Application: Ivan Shestakov (975ZZPJQNB)`.

### 0.2. Notarization keychain profile

Нужен **app-specific password** (не основной пароль Apple ID).

- <https://appleid.apple.com/account/manage> → **App-Specific Passwords**
  → **+** → имя `skald-notarize` → Generate. Пароль показывают **один раз** —
  скопировать.
- В терминале:
  ```
  xcrun notarytool store-credentials skald-notarize \
    --apple-id ivshestakov@gmail.com \
    --team-id 975ZZPJQNB \
    --password <app-specific-password>
  ```
  Это кэширует креды в keychain под профилем `skald-notarize`.
  `release.sh` сам ищет этот профиль.

### 0.3. Sparkle EdDSA-ключи — ✅ сделано

- Public key уже в `Info.plist`: `jxJctZXd7IIRthQEe2DyTHYZvNZ4gVv0/kbh4C94pgo=`
- Private key в login keychain под `https://sparkle-project.org`.
- **Забэкапить приватный ключ:**
  ```
  TranslatorApp/Frameworks/Sparkle-bin/generate_keys -x ~/skald-sparkle-private.key
  ```
  Положить в 1Password / на флешку. Потерять — навсегда отрезать
  существующих юзеров от автообновлений.

### 0.4. panic-kit лендинг — ✅ сделано

`panic-kit.com/skald` уже есть (продуктовая страница в стиле parent-сайта)
и `panic-kit.com/skald/appcast.xml` — это Sparkle feed. Всё в репо
[ivshestakov/panic-kit](https://github.com/ivshestakov/panic-kit), раздаётся
через Vercel автоматически на каждый push в main.

`SUFeedURL` в Info.plist уже указывает на новый URL.

Проверить после push'а panic-kit:
```
curl -fsSI https://panic-kit.com/skald/appcast.xml
```
Должен вернуть `HTTP/2 200`.

### 0.5. Домен skald.app *(опционально, в будущем)*

Если захочется отдельный бренд `skald.app` (например для маркетинга),
докинуть как alias на Vercel-проект panic-kit — Vercel поддерживает
несколько доменов на один деплой. Тогда `skald.app` будет
проксировать на текущий `/skald/` контент. Не блокер для лонча.

### 0.6. Релиз 0.3.0 — первая чистая сборка

Когда 0.1, 0.2, и panic-kit запушен в main:

- Версия `0.3.0` и build `5` уже в Info.plist (SUFeedURL уже на
  panic-kit.com).
- ```
  cd TranslatorApp
  SKALD_SIGN_IDENTITY="Developer ID Application: Ivan Shestakov (975ZZPJQNB)" \
    ./release.sh
  ```
  Скрипт выплюнет `dist/Skald-0.3.0.dmg` и `<item>` блок для appcast'а.
- ```
  gh release create v0.3.0 TranslatorApp/dist/Skald-0.3.0.dmg \
    --title "Skald 0.3.0" --notes "..."
  ```
- Вставить `<item>` в `skald/appcast.xml` **в репо panic-kit** (через
  UI: github.com/ivshestakov/panic-kit/edit/main/skald/appcast.xml — или
  клонировать локально). Закоммитить + push, Vercel задеплоит за ~30с.
- Описание в release notes: «**No more Gatekeeper warnings** — Skald is now
  signed and notarized. Auto-updates enabled — future versions install
  themselves.»

**Критерий выхода из Phase 0:** друг скачивает DMG с GitHub, открывает,
тащит Skald.app в Applications, дабл-кликает — открывается без правого
клика и без warning'а. И: на твоём 0.3.0 install в меню «Check for
Updates…» работает (надо сначала кому-то поставить 0.3.0, чтобы было
с чего тестировать обновление до 0.3.1).

---

## Phase 1 — Лонч (1–2 недели после Phase 0)

Цель: 500–2000 юзеров за месяц. Это «есть ли pull» сигнал.

### 1.1. Демо-видео (вечер работы)

Самый важный артефакт лонча. 30 секунд, без слов.

Сценарий:
1. **0–3 сек**: курсор в Slack/Telegram, кто-то пишет «как ты ваще»
2. **3–5 сек**: ⌥/ — выезжает glass-панель, видно «RU ↔ EN» как placeholder
3. **5–9 сек**: набираешь «как ты ваще» → Enter → вставляется «how are you»
4. **9–14 сек**: Settings → Style → ставишь Vulgar 🔥
5. **14–18 сек**: то же самое «как ты ваще» → Enter → вставляется
   «how the f\* are you»
6. **18–25 сек**: показываешь tone slider бегунком на красную сторону
   панели тонируется
7. **25–30 сек**: логотип + текст «free, open source, github.com/ivshestakov/skald.app»

Записать через QuickTime → Screen Recording. Обработать в iMovie или
просто оставить как есть. Экспорт в .mp4 720p ≤ 10MB (для X/HN).

### 1.2. Подготовить артефакты

- **README.md полировка**: убедиться что в начале есть видео или хотя
  бы скриншот, скриншот настроек, скриншот панели в активном Vulgar
  тоне (тонирована красным, видна иконка огня)
- **3 скриншота** для лонча: панель в default тоне, панель в Vulgar
  тоне, окно Settings → Style
- **Один tweet/HN-параграф** написать заранее (см. ниже)

### 1.3. Show HN — самый сильный канал для технарей

- Заголовок: `Show HN: Skald — a macOS menu-bar translator with a tone slider (Corporate → Vulgar)`
- Body (комментом сразу после поста):
  ```
  Hi HN! I built this because every translator I tried produced
  Wikipedia-grade English when I needed to sound like a pissed-off
  human in a Slack message.

  Skald is a small (1.6 MB) menu-bar app for macOS. Press a hotkey,
  type a phrase in any language, hit Enter — translation lands at
  your cursor. Five engines: Apple (on-device, offline), Google,
  DeepL, Claude. The novel bit is the tone slider for Claude:
  Corporate → Simple → Original → Youth → Vulgar. The vulgar end
  swears properly. The corporate end is dry as a brief.

  Auto-falls back to Apple's on-device model when offline. BYOK for
  DeepL/Claude (keys live in the Keychain). Hotkey is configurable.
  There's also a quick-translate hotkey that translates your
  selection or clipboard in place without showing the panel.

  No analytics, no telemetry. Open source under MIT.

  https://github.com/ivshestakov/skald.app

  Happy to answer questions / take feedback.
  ```
- Время поста: будний день 9–11 утра по PST (8–10 вечера по
  Киеву/Москве). Вторник-четверг лучше всего.
- Не ботить и не «рассылать друзьям заплюсовать» — за это банят
  навечно. Пусть всплывает органически или не всплывает совсем.

### 1.4. r/macapps — органичная аудитория

- Заголовок: `[Free, Open Source] Skald — translator with a tone slider, Apple/Google/DeepL/Claude in one place`
- Body похожий на HN, но более casual
- Прикрепить демо-видео через Reddit video uploader (важно — иначе
  гонят на «no external links»)

### 1.5. X/Twitter

Тред:
1. **Tweet 1** (видео + текст): `I built a macOS translator with a "Vulgar" tone slider. It just shipped. ⌥/, type, Enter — translation at your cursor.`
2. **Tweet 2**: список движков и почему мульти-движковость
3. **Tweet 3**: tone slider — что это
4. **Tweet 4**: ссылка на github.com/ivshestakov/skald.app

Дальше отвечать на каждый замёт-комент персонально первые 24 часа —
это поднимает шанс что Twitter покажет тред шире.

### 1.6. Product Hunt (опционально)

PH — отдельная игра. Подготовка занимает 1–2 недели:
- Зарегиться, наполнить профиль
- Найти hunter'а с большой аудиторией если можешь — но не критично
- Запостить во вторник или среду в 12:01 PT
- Иметь готовый набор скриншотов, GIF, FAQ
- Самому отвечать на каждый коммент в день лонча

Если не хочется заморачиваться — пропусти. PH != HN, аудитория
другая, эффект на indie-маков спорный.

### 1.7. Что трекать

После каждого канала смотреть:
- **GitHub Release downloads** — единственный реальный сигнал.
  Открой `https://github.com/ivshestakov/skald.app/releases/latest`,
  под каждым ассетом есть счётчик. Хорошая динамика для индии-app:
  100+ загрузок в первые 24 часа после Show HN front-page.
- **GitHub repo stars** — proxy для широкой узнаваемости
- **GitHub issues + discussions** — что юзеры реально просят. Это
  будущий backlog для Pro/Cloud версии.

**Критерий выхода из Phase 1:** через 1 месяц после публикации есть
хотя бы 500 уникальных загрузок 0.3.0 + 50 stars + 10 GitHub issues
с фидбэком. Если нет — рынка нет, не парьтесь со Skald Cloud,
оставьте бесплатным навсегда.

---

## Phase 2 — Слушать и итерировать (месяц 2–3)

Цель: понять, **за что** люди готовы платить.

### 2.1. Каждую неделю отвечать на issues + DMs

- Не игнорить ни одно сообщение в первые 24 часа
- Багфиксы — релизить в течение недели (через Sparkle юзеры
  получат автоматом)
- Феча-реквесты — складывать в `IDEAS.md` (создать в репо)
- Раз в неделю смотреть что повторяется чаще всего

### 2.2. Признаки того, что есть pull

- Несколько разных людей просят **одну и ту же фичу**
- Кто-то пишет «куда задонатить» / «есть ли Pro»
- Repository получает >5 stars/неделю стабильно после первого хайпа
- Юзеры приводят друзей (смотрим: разные User-Agent на download,
  если есть какая-то аналитика; или просто чувство по issues)

### 2.3. Признаки того, что pull нет

- Spike → silence через неделю
- Issues только багрепорты, ноль feature requests
- Stars стагнируют

В этом случае — оставляем как есть. Open-source side project, окупает
ничего, но и не требует ничего. **Это нормальный исход для большинства
indie проектов.** Не надо насиловать монетизацию там, где её нет.

---

## Phase 3 — Skald Cloud (если pull есть, месяц 4–6+)

**Запускаем только если:**
- Есть >5 разных людей, которые жалуются на BYOK-frictoin
- Или просто >10% downloads → активные юзеры
- Или кто-то прямым текстом сказал «возьми с меня деньги»

### 3.1. Архитектура

```
[Skald.app] -- HTTPS --> [skald-cloud.fly.dev] -- HTTPS --> [api.anthropic.com]
                              |
                              +-- Postgres (usage tracking)
                              +-- Stripe / Lemon Squeezy webhooks
```

**Backend (Fly.io / Railway, ~$5/мес)**:
- Простой HTTP-сервер, Go или Node
- Endpoints:
  - `POST /translate` — auth header → forwards to Anthropic, возвращает результат + декремент квоты
  - `POST /auth/magic-link` — выдаёт login-link на email
  - `POST /webhook/stripe` — обрабатывает subscription events
- DB: Postgres (Supabase free tier до 500 MB)
  - Tables: users, subscriptions, usage_log
- Anthropic key — env variable, никогда не в репо

**Биллинг**: **Lemon Squeezy** — берёт на себя VAT, возвраты, споры.
5% transaction fee. Stripe мощнее, но больше код.

**Pricing model (для прикидки)**:
- Haiku 4.5: $1/M input + $5/M output. Средняя короткая фраза ~50 in
  + 50 out tokens → ~$0.0003 за перевод
- 10 000 переводов в месяц = $3 себестоимость
- $5/мес юзеру = 40% маржи + обслуживание серверов
- Вариант: $5/мес «unlimited fair use» (rate limit 1000/день)

**Skald.app (изменения)**:
- Новое поле в Settings → Account: `Sign in with Skald`
- При логине email → magic-link → app получает JWT
- В `Settings.shared` добавить `cloudToken`
- В `Translator.swift` добавить `.skaldCloud` engine, который вместо
  api.anthropic.com шлёт запрос на skald-cloud.fly.dev
- UI: переключатель «Use Skald Cloud» в Model tab, hides BYOK поле

### 3.2. Что НЕ делать

- ❌ Не пилить «Pro» с локальными фичами (история, presets) — они
  не оправдывают подписку. Cloud-доступ к Claude без ключей — оправдывает.
- ❌ Не делать сложный pricing с тиерами в первой версии. **Один план,
  одна цена.**
- ❌ Не блокировать BYOK навсегда. Юзер может выбрать: Cloud (платная
  подписка) ИЛИ свой ключ (как было).
- ❌ Не пилить сразу iOS-версию ради синхронизации. Сначала проверить,
  что macOS-only Cloud работает.

### 3.3. Запуск Cloud

- Beta-тест: пригласить 10 самых активных юзеров (тех кто открывал
  GitHub issues), бесплатные 30 дней
- Корректировки на основе реальной usage
- Публичный лонч: "Skald 0.5.0 — meet Skald Cloud"
- Пост на HN с фокусом на цену+простоту

---

## Расходы первого года

| Что | Сколько |
|---|---|
| Apple Developer Program | $99 |
| Домен skald.app | ~$15 |
| GitHub Pages (Sparkle appcast) | $0 |
| Lemon Squeezy (когда дойдём до Phase 3) | $0 setup, 5% transaction |
| Fly.io / Railway (Phase 3) | ~$5/мес = $60/год |
| Postgres / Supabase free tier | $0 |
| **Итого до запуска Cloud** | **~$115/год** |
| **Итого с Cloud-инфрой** | **~$175/год** |

Окупиться кофе можно с ~$3/мес донатов или 2 платящих юзера на $5/мес.

---

## Что есть прямо сейчас (Phase 0 закрыт ✅)

- [x] **Skald 0.3.0 опубликован** — signed + notarized DMG на GitHub,
      auto-update через panic-kit.com/skald/appcast.xml работает
- [x] Developer ID Application cert установлен (Team ID `975ZZPJQNB`)
- [x] notarytool keychain profile `skald-notarize` создан
- [x] Sparkle EdDSA пара — public в Info.plist, private в keychain +
      backup на диске (надо переложить в 1Password!)
- [x] Продуктовая страница `panic-kit.com/skald` с direct DMG download
      кнопкой (stable URL `releases/latest/download/Skald.dmg`)
- [x] `release.sh` end-to-end: build → sign → notarize → DMG → notarize
      DMG → Sparkle sign → stable alias copy. Печатает `<item>`.
- [x] Universal binary (arm64 + x86_64), Sparkle 2.9.1 встроен
- [x] Tone slider, оффлайн-фоллбек, два хоткея, dictation, gear icon

## Хвосты с релиза (быстро добить в начале следующей сессии)

1. **Merge PR `claude/nifty-babbage-5f8949` → main** в skald.app
   (или локально `git checkout main && git merge --ff-only … && git push`).
   На ветке tag `v0.3.0` уже есть и release уже опубликован.
2. **Переложить `~/skald-sparkle-private.key` в 1Password** и удалить
   с диска. Это единственная страховка от потери авто-обновлений.
3. **Smoke test на чистой машине / другом аккаунте**: скачать DMG с
   panic-kit.com/skald → перетащить в Applications → запустить → не
   должно быть Gatekeeper warning'а. В меню «Check for Updates…» —
   «Up to date».

## Известные грабли pipeline (для будущих релизов)

- **Intune MDM** периодически зачищает notarytool keychain profile.
  Если `release.sh` упадёт с "No Keychain password item found for
  profile: skald-notarize" — пере-создать профилем
  `xcrun notarytool store-credentials skald-notarize ...` и дозапустить
  оставшиеся шаги вручную (см. memory `skald_release_pipeline.md`,
  раздел "If release.sh dies mid-flight").
- **Первая нотаризация от нового Team ID** заняла 50 минут. Последующие
  ~25 секунд. Не паниковать раньше 90 минут.
- **0.2.x юзеры** не получат 0.3.0 через Sparkle — у них appcast был
  отключён. Им нужно установить 0.3.0 вручную, дальше уже автомат.
