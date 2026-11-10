# Silent-Protagonist-vs-Non-Silent-Protagonist

This repo is about how a silent protagonist game compares to a non-silent
protagonist game. "Silent" here means a blank-slate, self-insert protagonist:
you create the character and you are the character. "Non-silent" means an
authored lead with a fixed name, voice, and story you follow. It has two tabs:
a **Chart** tab showing a bar chart, and a **Numbers** tab showing a table of
the exact figures with a verdict at the bottom. Both cover **current
concurrent players**, **30-day average players**, **6-month average players**,
and each game's **all-time peak** for fifteen games on each side, so you can
see which camp is being played more — and read the numbers behind it.

Both the Chart and Numbers tabs can be filtered to **All**, **Silent**, or
**Non-silent** games. The Numbers tab no longer shows a per-row camp column;
the filter tells you which camp is in view, and the table still groups games
by camp with subtotal rows.

The **Numbers** tab lists every game's four values, adds up (and averages)
each camp, then names the side that is more popular overall and the deciding
factor — the metric where the two sides differ most, in relative terms. The
verdict is shown on the All view; selecting a single camp hides it because
there is no comparison to make.

- Silent protagonists (self-insert): Dark Souls Remastered, Elden Ring, Dark
  Souls III, Monster Hunter: World, Skyrim Special Edition, Fallout: New Vegas,
  Stardew Valley, Terraria, Valheim, ARK: Survival Evolved, Rust, Path of Exile,
  Warframe, No Man's Sky, Divinity: Original Sin 2
- Non-silent protagonists (authored leads): GTA V, God of War, The Witcher 3:
  Wild Hunt, Red Dead Redemption 2, Assassin's Creed Odyssey, Assassin's Creed
  Origins, Halo: The Master Chief Collection, Resident Evil 2, NieR: Automata,
  Horizon Zero Dawn Complete Edition, Marvel's Spider-Man Remastered, The Last
  of Us Part I, Star Wars Jedi: Fallen Order, Rise of the Tomb Raider, Ghost of
  Tsushima Director's Cut

## How it works

```
Flutter web app  --HTTP-->  local proxy  --HTTP-->  Steam Web API (current players)
  (browser)                 (port 8080)     \----->  SteamCharts (30-day average)
```

Steam and SteamCharts send no CORS headers, so a browser can't call them
directly. The small Dart proxy in `lib/server.dart` (entrypoint
`bin/server.dart`) fetches both sources, merges them, and serves JSON from
`GET /api/stats`.

- Live players: Steam `ISteamUserStats/GetNumberOfCurrentPlayers`
- 30-day average: the "Last 30 Days" row scraped from `steamcharts.com`
- 6-month average: the last six monthly rows on `steamcharts.com`, averaged
- All-time peak: the "all-time peak" figure in the `steamcharts.com` header
- A failed lookup stays `null` and the UI shows a dash.

## Run it

Two terminals.

```bash
# 1. the proxy
dart run bin/server.dart          # http://localhost:8080

# 2. the app
flutter run -d chrome --web-port=4200 \
  --dart-define=API_BASE_URL=http://localhost:8080
```

If the chart says it can't reach the proxy, start `bin/server.dart` first.

The app's web port is pinned to `4200` so it matches `ALLOWED_ORIGIN` in
`.env`, and `API_BASE_URL` points the comments API at the proxy (`:8080`)
instead of the Flutter dev server. In production the app and API share one
origin, so `API_BASE_URL` is left unset and `ALLOWED_ORIGIN` empty.

## Test

```bash
flutter test
dart analyze
```

## Public launch hardening

The server now includes:

- **Shared rate limiting** — a MongoDB-backed `rate_limits` collection with a
  TTL index, so limits survive restarts and are shared across instances. If
  Mongo is unreachable, the limiter falls back to in-memory.
- **Stats cache** — `/api/stats` is cached for 60 seconds and rate-limited
  (60/min per IP), with 5-second timeouts on the upstream calls.
- **Spam protection** — a `website` honeypot field on every comment, plus
  optional Cloudflare Turnstile when `TURNSTILE_SECRET_KEY` is set.
- **Security headers** — CSP, HSTS, `nosniff`, `frame-ancestors`, and
  `Referrer-Policy`.
- **Privacy policy** — `web/privacy.html`, served at `/privacy.html` and linked
  from the Community tab.
- **Email encryption at rest** — when `EMAIL_ENCRYPTION_KEY` is set, the full
  email is encrypted with AES-GCM before it is stored. The API still returns
  only the masked form.

### Environment variables

| Variable | Purpose |
| --- | --- |
| `MONGODB_URI` | Atlas connection string. Required. |
| `ADMIN_TOKEN` | Secret for `DELETE /api/comments/<id>`. Empty disables DELETE. |
| `ALLOWED_ORIGIN` | Dev-only CORS origin. Empty in production. |
| `TRUSTED_PROXY_HOPS` | Set to `1` on Render (one reverse proxy). |
| `PORT` | Port to listen on. Render provides this. |
| `TURNSTILE_SECRET_KEY` | Optional. Enables Turnstile verification. |
| `EMAIL_ENCRYPTION_KEY` | Optional. Base64 32-byte AES key for email encryption at rest. |
| `CSP` | Optional. Overrides the default Content-Security-Policy. |
| `API_ORIGIN` | Optional. The API origin for the app's CSP when split. |
| `RETENTION_DAYS` | Documented retention period. |

### Render (recommended)

Render runs the Dart server and the built Flutter app in one service. The
`Dockerfile` builds both. Use `render.yaml` or set the variables manually.
Set `TRUSTED_PROXY_HOPS=1`; otherwise every user shares Render's proxy IP and
the global rate limit applies to the whole site.

### Netlify + Render

Netlify can only host the static Flutter app. Build it with
`--dart-define=API_BASE_URL=https://your-api.onrender.com`, deploy
`build/web`, and set `ALLOWED_ORIGIN=https://your-site.netlify.app` on Render.
`netlify.toml` includes the headers and SPA redirect.

### Retention

The server does not delete comments automatically. To delete comments older
than the retention period, run this in the Mongo shell:

```js
db.comments.deleteMany({
  createdAt: { $lt: new Date(Date.now() - 365 * 24 * 60 * 60 * 1000) }
});
```

