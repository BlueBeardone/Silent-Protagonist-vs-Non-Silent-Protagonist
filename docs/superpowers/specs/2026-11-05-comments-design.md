# Community Comments — Design

Date: 2026-11-05
Status: draft for approval

## Intent and why

The app compares silent (self-insert) and non-silent (authored-lead)
protagonists using Steam numbers. Numbers tell you what people play; they
don't tell you what people *felt*. The point of this feature is the feeling:
give visitors a place to say, in their own words, how a game landed for them
— "I enjoyed this game because I immersed myself so much in it" — and let
anyone read what everyone else wrote.

The feature has two halves:

1. **Write** — a form: an email (required) and a free-text comment (required).
2. **Read** — a button that opens a list of every comment, newest first, each
   shown next to a masked version of the email that wrote it.

## Goals

- Let any visitor post a free-text comment about their experience with the
  game, identified only by email.
- Persist comments in MongoDB Atlas.
- Let any visitor browse the collected comments.
- Run safely on the public internet: no email harvesting, no injection, no
  abuse free-for-all.

## Non-goals

- No accounts, login, or passwords.
- No email verification (no mail is sent).
- No editing or deleting by the person who wrote a comment.
- No likes, votes, ratings, or "how well received" scoring. "Well received"
  means "read the comments".
- No per-game association. A comment is about the experience in general, not
  tied to one title in the list.
- No moderation queue. Comments appear the moment they are posted.

## Anti-goals (a failure even if it "works")

- A reader ever seeing another user's full email address.
- A crafted request crashing the server or reaching the database as a query.
- The database connection string or admin token ending up in git.

## Constraints

- Front end: existing Flutter web app.
- Back end: existing Dart `shelf` server (`lib/server.dart`, entrypoint
  `bin/server.dart`).
- Database: an existing, empty MongoDB Atlas cluster. Creating the collection
  and document shape is part of this build.
- Deployment target: public internet.
- Match existing patterns: injectable dependencies (`StatsFetcher`), handler
  tests against `shelf` `Request` objects, widget tests.

## Decisions already made (by the human partner)

- A comment is free text about the experience; no fixed questions.
- Email is the only required identifying field.
- The read view shows the comment plus the user who made it.
- Comments post instantly; there is no approval step.
- The app is public.

## Calls I made (check these while reading)

- **Masked email format:** `bar***@gmail.com` — first three characters of the
  local part, then `***`, then the full domain. When the local part is three
  characters or shorter, the whole local part is masked (`***@x.com`) so a
  short address cannot be reconstructed. Full email is stored but never
  leaves the server.
- **Admin delete:** comments post instantly, so a private delete endpoint is
  the safety valve. Guarded by a secret token in a request header.
- **Rate limiting:** in-memory, per-IP, on the public endpoints.
- **Driver:** the pure-Dart `mongo_dart` package.
- **Comment length:** 1–2000 characters after trimming.
- **Read view:** paginated, newest first.
- **Client IP for rate limiting:** use the socket IP by default; when the
  server runs behind a reverse proxy, a `TRUSTED_PROXY_HOPS` env var says how
  many hops to trust before reading `X-Forwarded-For`. Without it the header
  is ignored, so it cannot be spoofed to bypass the limit.
- **CORS on errors:** the allowed-origin header is added to every response,
  including `4xx`/`5xx`, so a browser fetch can read the error instead of
  showing a network failure.
- **Community tab is independent:** comments don't depend on Steam, so the
  Community tab stays reachable even when `/api/stats` fails. `HomePage` is
  restructured so the tab shell no longer lives inside the stats
  `FutureBuilder`; the Chart and Numbers tabs show their own error state.
- **Malformed delete id:** an id that isn't a valid ObjectId returns `404`
  (treated as "no such comment") and driver errors are caught, so no crafted
  id can produce a 500.
- **Mongo down:** a missing `MONGODB_URI` fails fast at startup. If Atlas is
  unreachable at boot or later, `/api/stats` keeps serving; the comments
  endpoints return `503` and the server retries the connection lazily.
- **Full email stored:** the full address is kept (the partner asked to
  capture it) but no response ever contains it.

## How it works

```
Flutter web  --POST /api/comments-->  Dart shelf server  -->  MongoDB Atlas
             <--GET  /api/comments--                    (comments collection)
```

The browser never talks to MongoDB. Only the server holds the connection
string, and only the server decides what a reader is allowed to see.

**Deployment — one service.** The Dart server serves both the API and the
built Flutter web app, so the page and the API share one origin. This removes
the cross-origin problem entirely, means one thing to deploy and keep alive,
and the browser needs no API URL configuration. The server binds `0.0.0.0`
and reads `$PORT`, so it drops into any container host. Since same-origin is
the norm, `ALLOWED_ORIGIN` only matters for local development (where the
Flutter dev server runs on a random port); it defaults to permissive in dev
and is pinned in production.

## Data model

Collection `comments`:

```
{
  _id:       ObjectId,
  email:     string,   // full address, stored server-side only
  comment:   string,   // trimmed free text
  createdAt: Date
}
```

- Index: `{ createdAt: -1 }` so the newest-first read is cheap.
- No unique index on `email`: one person may comment more than once.
- The full `email` is never included in any response body.

## API

All bodies are JSON. The server sets `content-type: application/json`.

### `POST /api/comments`

Request: `{ "email": "...", "comment": "..." }`

Success `201`:
```json
{ "id": "<hex>", "email": "bar***@gmail.com", "comment": "...", "createdAt": "2026-11-05T12:00:00.000Z" }
```

Errors:
- `400` missing/blank fields, bad email format, comment too long, or a field
  that is not a string.
- `413` body larger than the limit.
- `415` content-type is not JSON.
- `429` rate limit exceeded.

### `GET /api/comments?limit=&before=`

Success `200`:
```json
{ "comments": [ { "id": "...", "email": "bar***@gmail.com", "comment": "...", "createdAt": "..." } ], "nextCursor": "..." }
```

- Newest first. `limit` is capped server-side (default 50, max 100).
- `before` is an opaque cursor (`createdAt` of the last item seen); absent
  means start at the newest.
- `nextCursor` is null when there is nothing more.

### `DELETE /api/comments/<id>` (admin)

- Requires header `x-admin-token: <secret>`.
- `204` on success, `401` bad/missing token, `404` unknown or malformed id.
- Not part of the visitor UI.

## Security design

This is the part that matters most, since the endpoint is public.

- **No query injection.** The server never builds a Mongo query from raw
  input. Only the fixed fields `email` and `comment` are accepted, each
  required to be a plain string, and they are passed to the driver as typed
  values. Extra keys (for example a `$where`) are rejected, not forwarded.
- **Validation.** Email checked against a conservative format and a 254-char
  cap. Comment trimmed, required non-empty, capped at 2000 chars, and
  stripped of control characters (newlines kept).
- **Body size limit.** Requests over ~8 KB are rejected with `413` before
  parsing, so a huge body cannot be buffered into memory.
- **XSS.** Comments are rendered as Flutter `Text`, never as HTML, so markup
  in a comment is inert. The server still strips control characters.
- **CORS.** In production the app and API are same-origin, so no CORS header
  is needed and none is granted to other origins. For local development, where
  the Flutter dev server runs on a random port, the server reflects the
  configured dev origin only. The existing read-only `/api/stats` route is
  left as it is.
- **Rate limiting.** Per-IP sliding window on both public endpoints (for
  example 5 writes / 10 min, 60 reads / min) returning `429`. In-memory, so
  it is per-process; note that in the document and in code.
- **Secrets.** `MONGODB_URI`, `ALLOWED_ORIGIN`, and `ADMIN_TOKEN` come from
  the environment, never source. A `.env` file is gitignored.
- **Database least privilege.** The Atlas user used by the server has
  `readWrite` on just this database, nothing else.
- **Transport.** Atlas uses TLS; the deployed server sits behind HTTPS.
- **Logging.** Full emails are never logged.
- **Admin delete** compares the token in constant time.

## Code shape

- `lib/comments.dart`
  - `Comment` model with `toJson()` that emits the masked email.
  - `maskEmail(String)`.
  - `validateEmail(String)` / `validateComment(String)` returning an error
    message or null.
  - `abstract class CommentsStore` with `add`, `recent`, `deleteById`.
  - `InMemoryCommentsStore` for tests, `MongoCommentsStore` for real use.
- `lib/server.dart`
  - Add a comments handler alongside the existing stats route, with the store,
    rate limiter, allowed origin, and admin token injected — same injectable
    style as `statsHandler`.
- `bin/server.dart`
  - Read env vars, connect to Mongo, serve the combined handler.
- Flutter
  - A third tab, **Community**, holding the form (email + comment + submit)
    and a **See what others said** button that loads and shows the list.
  - `HomePage` is restructured so the tab shell is outside the stats
    `FutureBuilder`; Community loads independently of `/api/stats`.
  - A small client wrapper around the two endpoints, injectable for widget
    tests, mirroring `StatsLoader`.

## Testing

- `test/comments_test.dart` — `maskEmail`, the validators, and the in-memory
  store.
- `test/server_comments_test.dart` — handler contract for `POST`, `GET`, and
  `DELETE`: happy path, each validation error, oversized body, bad
  content-type, rate limit, CORS header, and that no response leaks a full
  email.
- Widget tests — form rejects a blank or malformed email, a submitted comment
  appears in the list, and the list shows the masked email.

## Left to the builder

- Exact package versions and Atlas connection details.
- Rate-limiter algorithm and thresholds (a sensible default is given).
- Page size and cursor encoding details.
- Whether the list shows absolute or relative timestamps.
- Visual styling of the Community tab.
