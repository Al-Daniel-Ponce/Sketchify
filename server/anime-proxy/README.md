# Sketchify AI proxy

A small authenticated Node service between the Sketchify Android app and two
optional Replicate models:

- `POST /anime` — hosted anime styling, with an on-device fallback in the app.
- `POST /face-transform` — online-only feminize/masculinize face editing.

The proxy exists so the Replicate provider key never ships in the APK. Photos
are forwarded to Replicate and returned; the proxy does not write them to disk.

## Contract

| Item | Anime | Face transform |
|---|---|---|
| Endpoint | `POST /anime` | `POST /face-transform?direction=feminize\|masculinize` |
| Auth | `Authorization: Bearer <APP_TOKEN>` | Same |
| Request | raw `image/jpeg`, max 8 MB | Same |
| Response | `image/jpeg`, exactly the uploaded size | Same |
| Server timeout | 55 seconds | 110 seconds |
| App timeout | 60 seconds | 120 seconds |
| Failure behaviour | App falls back to AnimeGANv2 on device | App shows an error; no local substitute |

`GET /health` returns `{"ok":true}` for both routes. Both endpoints validate
the uploaded JPEG, enforce a per-IP hourly budget, and set `Cache-Control:
no-store`. The face transform route returns `503` when no face model is
configured, `400` for an unknown direction, and `504` when polling runs past
`FACE_TIMEOUT_MS`.

## Anime configuration

- `APP_TOKEN` — a long random token shared with the app build.
- `REPLICATE_API_TOKEN` — your Replicate provider key.
- `REPLICATE_MODEL_VERSION` — the version hash of the hosted anime model.
- `REPLICATE_INPUT_JSON` — optional extra model parameters.
- `REPLICATE_INPUT_JSON` is merged first; the proxy always sets `image` last.
- `ANIME_TIMEOUT_MS` — server polling deadline, default `55000`.
- `RATE_LIMIT_MAX` — anime requests per IP per hour, default `30`.

## Face transform configuration

The route stays disabled unless at least one model or version is set.

- `FACE_MODEL` — Replicate model in `owner/name` form. Uses
  `/v1/models/{owner}/{name}/predictions`, so Replicate selects the model's
  current version.
- `FACE_MODEL_VERSION` — a 64-character version hash instead of a model name.
- `FACE_FEMINIZE_MODEL`, `FACE_FEMINIZE_MODEL_VERSION`,
  `FACE_MASCULINIZE_MODEL`, `FACE_MASCULINIZE_MODEL_VERSION` — optional
  per-direction overrides. These win over the shared settings and let each
  direction use a different model.
- `FACE_IMAGE_FIELD` — model input that receives the uploaded JPEG as a data
  URI. Default `image`.
- `FACE_DIRECTION_FIELD` — optional model input that receives the direction
  value. Leave empty when the model has no target-gender input.
- `FACE_DIRECTION_VALUE_FEMINIZE` / `FACE_DIRECTION_VALUE_MASCULINIZE` —
  defaults `female` / `male`. Change these if your model expects `woman` /
  `man`, `feminine` / `masculine`, or another vocabulary.
- `FACE_INPUT_JSON` — extra inputs for every face prediction.
- `FACE_FEMINIZE_INPUT_JSON` / `FACE_MASCULINIZE_INPUT_JSON` — extra inputs
  for one direction. Merged after `FACE_INPUT_JSON`.
- `FACE_TIMEOUT_MS` — server polling deadline, default `110000`.
- `FACE_RATE_LIMIT_MAX` — face requests per IP per hour, default `10`.

Input merge order is:

```text
FACE_INPUT_JSON → per-direction JSON → FACE_IMAGE_FIELD → FACE_DIRECTION_FIELD
```

For a single model that takes a target gender:

```dotenv
FACE_MODEL=owner/face-model
FACE_DIRECTION_FIELD=target_gender
FACE_DIRECTION_VALUE_FEMINIZE=woman
FACE_DIRECTION_VALUE_MASCULINIZE=man
```

For two direction-specific models:

```dotenv
FACE_FEMINIZE_MODEL=owner/feminize-model
FACE_MASCULINIZE_MODEL=owner/masculinize-model
```

Find version hashes with:

```bash
curl -H "Authorization: Token $REPLICATE_API_TOKEN" \
  https://api.replicate.com/v1/models/OWNER/NAME
```

Use `latest_version.id`. Check the model licence, input schema, cost and
latency before enabling it. Some face models are research-only or prohibit
certain uses.

The proxy downloads the first image URL from the prediction, rotates it by
EXIF, then resizes it with `fit: cover, position: attention` to the uploaded
dimensions. The crop therefore favours faces and detailed regions. The app
rejects replies whose dimensions differ from the upload.

## Local run

```bash
npm install
cp .env.example .env
# edit .env
npm start
curl http://localhost:8080/health
```

Anime and face transform are independent. Set at least one of
`REPLICATE_MODEL_VERSION`, `FACE_MODEL`/`FACE_MODEL_VERSION`, or a
per-direction face model. An unconfigured route returns `503` while the other
keeps working.

## Deploy

The proxy is a stateless Node 20 service. Any container or Node host works.

### Render

1. Create a **Web Service** from this repository.
2. Set **Root Directory** to `server/anime-proxy`.
3. Build command: `npm install`; start command: `npm start`.
4. Add `APP_TOKEN`, `REPLICATE_API_TOKEN` and `REPLICATE_MODEL_VERSION` as
   secret environment variables.
5. Add the face variables you need, for example `FACE_MODEL` (or
   `FACE_MODEL_VERSION`), `FACE_DIRECTION_FIELD` and the direction values.
6. Set the health check path to `/health`.
7. Use the public URL plus `/anime` as `ANIME_PROXY_URL`. The app derives
   `/face-transform` from that URL automatically.

### Railway / Fly.io

- Railway: create a service from `server/anime-proxy`, then add the same
  variables.
- Fly.io: `fly launch --dockerfile server/anime-proxy/Dockerfile`, then
  `fly secrets set APP_TOKEN=... REPLICATE_API_TOKEN=... REPLICATE_MODEL_VERSION=...`
  plus any face variables.

## Build the app with online AI

```bash
flutter build apk --release --split-per-abi \
  --dart-define=ANIME_PROXY_URL=https://your-service.example/anime \
  --dart-define=ANIME_APP_TOKEN=the-same-app-token
```

Face transform reuses `ANIME_APP_TOKEN` unless `FACE_APP_TOKEN` is set, and
derives `FACE_PROXY_URL` from `ANIME_PROXY_URL` unless it is set explicitly:

```bash
flutter build apk --release --split-per-abi \
  --dart-define=ANIME_PROXY_URL=https://your-service.example/anime \
  --dart-define=ANIME_APP_TOKEN=the-same-app-token \
  --dart-define=FACE_PROXY_URL=https://your-service.example/face-transform \
  --dart-define=FACE_APP_TOKEN=the-same-app-token
```

`ANIME_APP_TOKEN` and `FACE_APP_TOKEN` are low-privilege app tokens, not the
Replicate key. The Replicate key exists only in the server environment. Anyone
can extract an app token from an APK, so treat it as a rate-limit identity
rather than a strong secret, rotate it if abused, and keep the rate limits
conservative.

Both online features are opt-in and off by default. The user must accept a
first-use notice before either one runs. Face transform also requires a
permission checkbox in that notice.

## Limitations

- Sketchify does not detect gender. The user explicitly chooses **Feminize
  Face** or **Masculinize Face**, so the app never guesses someone's identity.
- The face transform has no local fallback. Offline, disabled, or proxy errors
  leave the photo unchanged and show an error.
- One photo may contain several people; the model decides whom to edit.
- AI face editing can look unrealistic and may not preserve identity. The app
  shows this warning next to the filters.
- The hosted anime quality still needs a 3–5 photo comparison against the
  on-device model before it is recommended as a default.
- The proxy does not persist photos, but Replicate's own retention and privacy
  policy still applies to its processing.

## Notes

- Replicate output URLs are fetched immediately and never stored by the proxy.
- Requests are logged only as errors. Photos are not written to disk.
- Anime resizes with a centred cover crop; face transform uses an attention
  crop.
- The proxy keeps separate hourly rate buckets for anime and face transform.
