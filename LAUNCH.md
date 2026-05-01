# Skald — Launch & Monetization Plan

**Цель:** запустить бесплатно, набрать аудиторию, потом ввести Skald
Cloud (платный proxy к Claude без BYOK) если будет спрос. На первом
горизонте — окупить кофе и Developer ID, не более.

**Этот файл — план для будущих сессий.** Каждый раздел самодостаточен:
открываешь репо в новом чате с Claude, говоришь «делаем Phase 0, шаг 3»
— по нему видно, что именно сделать.

Текущий статус приложения: **Skald 0.2.2** опубликован,
<https://github.com/ivshestakov/skald.app>. Подписан self-signed
сертификатом, юзеры видят Gatekeeper warning при первом запуске.

---

## Phase 0 — Инфраструктура (1 неделя, ~$200)

Цель: убрать все технические трения перед лончем. Без этого нет смысла
куда-то постить — конверсия будет нулевая.

### 0.1. Apple Developer ID — $99/год

Без этого никакая монетизация не имеет смысла, потому что Gatekeeper
warning при первом запуске отпугивает 70%+ людей.

- Зарегистрироваться: <https://developer.apple.com/programs/enroll/>
- Заплатить $99, ждать 24–48 часов на одобрение Apple
- В личном кабинете → Certificates → создать **Developer ID Application**
  certificate, скачать, установить в login keychain (двойным кликом
  на `.cer` файл)
- Проверить: `security find-identity -v -p codesigning` должен
  показать `Developer ID Application: Ivan Shestakov (XXXXXXXXXX)`

### 0.2. Notarization

После того, как cert установлен, нужно настроить notarization, чтобы
Apple подтверждала каждую сборку как «безопасную».

- Сгенерировать **app-specific password** для notarization:
  <https://appleid.apple.com/account/manage> → App-Specific Passwords →
  Generate. Назвать `skald-notarize`. Сохранить в keychain под этим именем.
- В терминале залогинить notarytool:
  ```
  xcrun notarytool store-credentials skald-notarize \
    --apple-id you@example.com \
    --team-id XXXXXXXXXX \
    --password <app-specific-password>
  ```
- Обновить `TranslatorApp/release.sh`: после `ditto` добавить
  ```
  xcrun notarytool submit "$DIST_DIR/$ZIP_NAME" \
    --keychain-profile skald-notarize \
    --wait

  # Re-zip with stapled ticket
  ditto -x -k "$DIST_DIR/$ZIP_NAME" /tmp/skald-staple/
  xcrun stapler staple /tmp/skald-staple/Skald.app
  rm "$DIST_DIR/$ZIP_NAME"
  ditto -c -k --keepParent /tmp/skald-staple/Skald.app "$DIST_DIR/$ZIP_NAME"
  rm -rf /tmp/skald-staple
  ```
- Билд теперь требует:
  ```
  SKALD_SIGN_IDENTITY="Developer ID Application: Ivan Shestakov (XXXXXXXXXX)" ./release.sh
  ```

### 0.3. Sparkle EdDSA-ключи и appcast

Сейчас `SUFeedURL` указывает на `https://ivshestakov.github.io/skald.app/appcast.xml`,
но appcast'а там нет, и `SUPublicEDKey` пустой. Auto-update не работает.

- Сгенерировать ключи:
  ```
  cd TranslatorApp
  ./Frameworks/Sparkle.framework/Versions/Current/Resources/../../../bin/generate_keys
  ```
- Public key вставить в `Info.plist` → `SUPublicEDKey`. Private key —
  система сохранила в keychain под `https://sparkle-project.org`.
- Включить автопроверки: `SUEnableAutomaticChecks` → `true`.
- Создать `gh-pages` ветку (или папку `docs/` на main + Pages из docs):
  ```
  git checkout --orphan gh-pages
  git rm -rf .
  echo "Skald appcast" > index.html
  git add index.html
  git commit -m "Initial gh-pages"
  git push -u origin gh-pages
  ```
- Настроить GitHub Pages: Settings → Pages → Source = `gh-pages`,
  branch root.
- Дальше для каждого релиза `bin/sign_update Skald-0.X.Y.zip` даёт
  подпись, которая идёт в `<enclosure>` элемент в `appcast.xml`.
  Подробности в `RELEASE.md`.

### 0.4. Домен skald.app

Опционально, но усиливает «легитимность» при лонче.

- Купить на Porkbun (~$15/год для `.app`) или Cloudflare Registrar
- Настроить DNS: CNAME на `ivshestakov.github.io`, custom domain в
  GitHub Pages settings
- Появится `https://skald.app` — лендинг = README, релизы тут же

### 0.5. Релиз 0.3.0 — первая чистая сборка

Когда 0.1–0.4 сделаны:
- Поднять версию до `0.3.0` в `Info.plist`
- `SKALD_SIGN_IDENTITY="Developer ID Application: …" ./release.sh`
- Залить .zip как GitHub Release `v0.3.0`
- Сгенерить appcast item, закоммитить в gh-pages
- Описание в release: «**No more Gatekeeper warnings** — Skald is now
  signed and notarized. Auto-updates enabled.»

**Критерий выхода из Phase 0:** друг скачивает .zip с GitHub, дабл-кликает
`Skald.app` — открывается без правого клика и без warning'а.

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

## Что есть прямо сейчас

- [x] App работает (0.2.2)
- [x] GitHub repo public, README + INSTALL + LICENSE + RELEASE.md
- [x] Universal binary (arm64 + x86_64)
- [x] Sparkle framework встроен (но appcast/keys не настроены)
- [x] Self-signed signed (юзеры видят Gatekeeper warning)
- [x] Tone slider, оффлайн-фоллбек, два хоткея, dictation, gear icon

## Что делаем следующим

Открыть `LAUNCH.md` в свежем чате с Claude и сказать «делаем Phase 0,
шаг 0.1 — Apple Developer ID». Дальше по плану.
