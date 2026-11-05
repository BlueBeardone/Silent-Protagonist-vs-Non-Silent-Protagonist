# Silent-Protagonist-vs-Non-Silent-Protagonist

This repo is about how a silent protagonist game compares to a non-silent
protagonist game. "Silent" here means a blank-slate, self-insert protagonist:
you create the character and you are the character. "Non-silent" means an
authored lead with a fixed name, voice, and story you follow. It has two tabs:
a **Chart** tab showing a bar chart, and a **Numbers** tab showing a table of
the exact figures with a verdict at the bottom. Both cover **current
concurrent players**, **30-day average players**, and **6-month average
players** for fifteen games on each side, so you can see which camp is being
played more — and read the numbers behind it.

The **Numbers** tab lists every game's three values, adds up (and averages)
each camp, then names the side that is more popular overall and the deciding
factor — the metric where the two sides differ most, in relative terms.

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
