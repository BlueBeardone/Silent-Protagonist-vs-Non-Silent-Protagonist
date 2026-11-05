# Silent-Protagonist-vs-Non-Silent-Protagonist

This repo is about how a silent protagonist game compares to a non-silent
protagonist game. It shows a bar chart of **current concurrent players** and
**30-day average players** for four games, so you can eyeball which camp is
being played more.

- Silent protagonist: Dark Souls Remastered, Elden Ring
- Non-silent protagonist: GTA V, God of War

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
- A failed lookup stays `null` and the UI shows a dash.

## Run it

Two terminals.

```bash
# 1. the proxy
dart run bin/server.dart          # http://localhost:8080

# 2. the app
flutter run -d chrome
```

If the chart says it can't reach the proxy, start `bin/server.dart` first.

## Test

```bash
flutter test
dart analyze
```
