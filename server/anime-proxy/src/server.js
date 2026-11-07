import crypto from 'node:crypto';
import 'dotenv/config';
import express from 'express';
import sharp from 'sharp';

const PORT = Number.parseInt(process.env.PORT ?? '8080', 10);
const APP_TOKEN = process.env.APP_TOKEN ?? '';
const REPLICATE_API_TOKEN = process.env.REPLICATE_API_TOKEN ?? '';
const REPLICATE_MODEL_VERSION = process.env.REPLICATE_MODEL_VERSION ?? '';
const ANIME_TIMEOUT_MS = Number.parseInt(
  process.env.ANIME_TIMEOUT_MS ?? '55000',
  10,
);
const RATE_LIMIT_MAX = Number.parseInt(
  process.env.RATE_LIMIT_MAX ?? '30',
  10,
);
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;
const MAX_UPLOAD_BYTES = 8 * 1024 * 1024;
const REPLICATE_API = 'https://api.replicate.com/v1';

const extraInput = parseExtraInput(process.env.REPLICATE_INPUT_JSON);

const FACE_TIMEOUT_MS = positiveInt(process.env.FACE_TIMEOUT_MS, 110000);
const FACE_RATE_LIMIT_MAX = positiveInt(process.env.FACE_RATE_LIMIT_MAX, 10);
const FACE_IMAGE_FIELD = process.env.FACE_IMAGE_FIELD?.trim() || 'image';
const FACE_DIRECTION_FIELD = process.env.FACE_DIRECTION_FIELD?.trim() ?? '';
const FACE_EXTRA_INPUT = parseExtraInput(
  process.env.FACE_INPUT_JSON,
  'FACE_INPUT_JSON',
);
const FACE_BASE_MODEL = (process.env.FACE_MODEL ?? '').trim();
const FACE_BASE_VERSION = (process.env.FACE_MODEL_VERSION ?? '').trim();
const FACE_DIRECTIONS = {
  feminize: {
    model: (process.env.FACE_FEMINIZE_MODEL ?? '').trim(),
    version: (process.env.FACE_FEMINIZE_MODEL_VERSION ?? '').trim(),
    extraInput: parseExtraInput(
      process.env.FACE_FEMINIZE_INPUT_JSON,
      'FACE_FEMINIZE_INPUT_JSON',
    ),
    directionValue:
      process.env.FACE_DIRECTION_VALUE_FEMINIZE?.trim() || 'female',
  },
  masculinize: {
    model: (process.env.FACE_MASCULINIZE_MODEL ?? '').trim(),
    version: (process.env.FACE_MASCULINIZE_MODEL_VERSION ?? '').trim(),
    extraInput: parseExtraInput(
      process.env.FACE_MASCULINIZE_INPUT_JSON,
      'FACE_MASCULINIZE_INPUT_JSON',
    ),
    directionValue:
      process.env.FACE_DIRECTION_VALUE_MASCULINIZE?.trim() || 'male',
  },
};

if (!hasFaceConfiguration()) {
  console.warn(
    'Face transform route disabled. Set FACE_MODEL or FACE_MODEL_VERSION ' +
      '(or a per-direction override) to enable it.',
  );
}

if (!APP_TOKEN || !REPLICATE_API_TOKEN) {
  console.error(
    'Missing configuration. Set APP_TOKEN and REPLICATE_API_TOKEN.',
  );
  process.exit(1);
}
if (APP_TOKEN.length < 16) {
  console.error('APP_TOKEN must be at least 16 characters long.');
  process.exit(1);
}
if (!REPLICATE_MODEL_VERSION && !hasFaceConfiguration()) {
  console.error(
    'Nothing to serve. Set REPLICATE_MODEL_VERSION for /anime and/or ' +
      'FACE_MODEL or FACE_MODEL_VERSION for /face-transform.',
  );
  process.exit(1);
}
if (!REPLICATE_MODEL_VERSION) {
  console.warn(
    'Anime route disabled. Set REPLICATE_MODEL_VERSION to enable it.',
  );
}

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', 1);

const rateBuckets = new Map();

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

app.post(
  '/anime',
  express.raw({ type: ['image/jpeg'], limit: MAX_UPLOAD_BYTES }),
  async (req, res) => {
    if (!isAuthorized(req)) {
      return res.status(401).json({ error: 'Unauthorized.' });
    }
    if (!REPLICATE_MODEL_VERSION) {
      return res
        .status(503)
        .json({ error: 'Online anime is not configured.' });
    }
    if (!req.is('image/jpeg')) {
      return res.status(415).json({ error: 'Send a JPEG body.' });
    }
    if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
      return res.status(400).json({ error: 'A JPEG body is required.' });
    }
    if (!takeRateLimit(req.ip)) {
      return res
        .status(429)
        .json({ error: 'Too many requests. Try again later.' });
    }

    let inputWidth;
    let inputHeight;
    try {
      const metadata = await sharp(req.body).metadata();
      inputWidth = metadata.width;
      inputHeight = metadata.height;
      if (!inputWidth || !inputHeight) {
        throw new Error('Missing image dimensions.');
      }
    } catch {
      return res.status(415).json({ error: 'The upload is not a valid JPEG.' });
    }

    try {
      const output = await renderAnime(req.body, inputWidth, inputHeight);
      res.set('Cache-Control', 'no-store');
      res.type('image/jpeg').send(output);
    } catch (error) {
      console.error('Anime render failed:', error);
      const timedOut = error?.code === 'ANIME_TIMEOUT';
      res.status(timedOut ? 504 : 502).json({
        error: timedOut
          ? 'The anime render took too long.'
          : 'The anime render failed.',
      });
    }
  },
);

app.post(
  '/face-transform',
  express.raw({ type: ['image/jpeg'], limit: MAX_UPLOAD_BYTES }),
  async (req, res) => {
    if (!isAuthorized(req)) {
      return res.status(401).json({ error: 'Unauthorized.' });
    }
    if (!req.is('image/jpeg')) {
      return res.status(415).json({ error: 'Send a JPEG body.' });
    }

    const directionName = String(req.query.direction ?? '').toLowerCase();
    if (!Object.hasOwn(FACE_DIRECTIONS, directionName)) {
      return res.status(400).json({
        error: 'Use ?direction=feminize or ?direction=masculinize.',
      });
    }

    let target;
    try {
      target = faceTarget(directionName);
    } catch (error) {
      console.error('Face transform configuration error:', error.message);
      return res
        .status(503)
        .json({ error: 'Online face transform is not configured.' });
    }
    if (!target) {
      return res
        .status(503)
        .json({ error: 'Online face transform is not configured.' });
    }

    if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
      return res.status(400).json({ error: 'A JPEG body is required.' });
    }
    if (!takeRateLimit(req.ip, FACE_RATE_LIMIT_MAX, 'face')) {
      return res
        .status(429)
        .json({ error: 'Too many face transform requests. Try again later.' });
    }

    let inputWidth;
    let inputHeight;
    try {
      const metadata = await sharp(req.body).metadata();
      inputWidth = metadata.width;
      inputHeight = metadata.height;
      if (!inputWidth || !inputHeight) {
        throw new Error('Missing image dimensions.');
      }
    } catch {
      return res.status(415).json({ error: 'The upload is not a valid JPEG.' });
    }

    try {
      const output = await renderFaceTransform(
        req.body,
        inputWidth,
        inputHeight,
        directionName,
        target,
      );
      res.set('Cache-Control', 'no-store');
      res.type('image/jpeg').send(output);
    } catch (error) {
      console.error('Face transform failed:', error);
      const timedOut = error?.code === 'FACE_TIMEOUT';
      res.status(timedOut ? 504 : 502).json({
        error: timedOut
          ? 'The face transform took too long.'
          : 'The face transform failed.',
      });
    }
  },
);

app.use((error, _req, res, next) => {
  if (error?.type === 'entity.too.large') {
    return res.status(413).json({ error: 'The upload is too large.' });
  }
  return next(error);
});

app.use((_req, res) => {
  res.status(404).json({ error: 'Not found.' });
});

function isAuthorized(req) {
  const header = req.get('authorization') ?? '';
  if (!header.startsWith('Bearer ')) return false;
  const supplied = Buffer.from(header.slice(7));
  const expected = Buffer.from(APP_TOKEN);
  return (
    supplied.length === expected.length &&
    crypto.timingSafeEqual(supplied, expected)
  );
}

function takeRateLimit(ip, max = RATE_LIMIT_MAX, scope = 'anime') {
  const key = `${scope}:${ip || 'unknown'}`;
  const now = Date.now();
  const bucket = rateBuckets.get(key);
  if (!bucket || now - bucket.startedAt > RATE_LIMIT_WINDOW_MS) {
    rateBuckets.set(key, { startedAt: now, count: 1 });
    return true;
  }
  bucket.count += 1;
  return bucket.count <= max;
}

async function renderAnime(jpeg, width, height) {
  const output = await runPrediction({
    version: REPLICATE_MODEL_VERSION,
    input: { ...extraInput, image: dataUri(jpeg) },
    timeoutMs: ANIME_TIMEOUT_MS,
    timeoutCode: 'ANIME_TIMEOUT',
    label: 'Anime render',
  });

  return sharp(output)
    .rotate()
    .resize(width, height, { fit: 'cover', position: 'centre' })
    .jpeg({ quality: 92, chromaSubsampling: '4:4:4' })
    .toBuffer();
}

async function renderFaceTransform(jpeg, width, height, directionName, target) {
  const direction = FACE_DIRECTIONS[directionName];
  const input = {
    ...FACE_EXTRA_INPUT,
    ...direction.extraInput,
  };
  input[FACE_IMAGE_FIELD] = dataUri(jpeg);
  if (FACE_DIRECTION_FIELD) {
    input[FACE_DIRECTION_FIELD] = direction.directionValue;
  }

  const output = await runPrediction({
    ...target,
    input,
    timeoutMs: FACE_TIMEOUT_MS,
    timeoutCode: 'FACE_TIMEOUT',
    label: 'Face transform',
  });

  return sharp(output)
    .rotate()
    // Cover keeps the uploaded size while attention biases the crop toward
    // faces and other detailed regions instead of the exact centre.
    .resize(width, height, { fit: 'cover', position: 'attention' })
    .jpeg({ quality: 92, chromaSubsampling: '4:4:4' })
    .toBuffer();
}

/// Resolves the model or version for one direction. Per-direction values win
/// over the shared FACE_MODEL/FACE_MODEL_VERSION settings.
function faceTarget(directionName) {
  const direction = FACE_DIRECTIONS[directionName];
  let model = '';
  let version = '';
  if (direction.model) {
    model = direction.model;
  } else if (direction.version) {
    version = direction.version;
  } else if (FACE_BASE_MODEL) {
    model = FACE_BASE_MODEL;
  } else if (FACE_BASE_VERSION) {
    version = FACE_BASE_VERSION;
  }

  if (model) {
    if (!/^[\w.-]+\/[\w.-]+$/.test(model)) {
      const error = new Error('FACE_MODEL must use the owner/name format.');
      error.code = 'FACE_CONFIG';
      throw error;
    }
    return { model };
  }
  if (version) return { version };
  return null;
}

function hasFaceConfiguration() {
  return Boolean(
    FACE_BASE_MODEL ||
      FACE_BASE_VERSION ||
      Object.values(FACE_DIRECTIONS).some(
        (direction) => direction.model || direction.version,
      ),
  );
}

async function runPrediction({
  model,
  version,
  input,
  timeoutMs,
  timeoutCode,
  label,
}) {
  const deadline = Date.now() + timeoutMs;
  const path = model ? `/models/${model}/predictions` : '/predictions';
  const payload = model ? { input } : { version, input };

  let current = await replicateRequest(path, {
    method: 'POST',
    body: JSON.stringify(payload),
  });

  while (current.status !== 'succeeded') {
    if (current.status === 'failed' || current.status === 'canceled') {
      throw new Error(current.error ?? `${label} stopped without a result.`);
    }
    if (!current.id) {
      throw new Error(`${label} did not return a prediction id.`);
    }
    if (Date.now() > deadline) {
      if (current.urls?.cancel) {
        fetch(current.urls.cancel, {
          method: 'POST',
          headers: authHeaders(),
        }).catch(() => {});
      }
      const error = new Error(`${label} timed out.`);
      error.code = timeoutCode;
      throw error;
    }
    await sleep(1000);
    current = await replicateRequest(`/predictions/${current.id}`);
  }

  const outputUrl = pickOutputUrl(current.output);
  if (!outputUrl) {
    throw new Error('The model returned no image URL.');
  }
  const outputResponse = await fetch(outputUrl);
  if (!outputResponse.ok) {
    throw new Error(
      `Could not download the model output (${outputResponse.status}).`,
    );
  }
  return Buffer.from(await outputResponse.arrayBuffer());
}

function dataUri(jpeg) {
  return `data:image/jpeg;base64,${jpeg.toString('base64')}`;
}

function replicateRequest(path, options = {}) {
  return fetchJson(`${REPLICATE_API}${path}`, {
    ...options,
    headers: { ...authHeaders(), ...(options.headers ?? {}) },
  });
}

async function fetchJson(url, options) {
  const response = await fetch(url, options);
  const text = await response.text();
  let body;
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    body = {};
  }
  if (!response.ok) {
    const message =
      body?.detail ?? body?.error ?? `Replicate returned ${response.status}.`;
    throw new Error(message);
  }
  return body;
}

function authHeaders() {
  return {
    Authorization: `Token ${REPLICATE_API_TOKEN}`,
    'Content-Type': 'application/json',
  };
}

function pickOutputUrl(output) {
  if (typeof output === 'string') return output;
  if (Array.isArray(output)) {
    return output.find((item) => typeof item === 'string') ?? null;
  }
  if (output && typeof output.url === 'string') return output.url;
  return null;
}

function parseExtraInput(raw, name = 'REPLICATE_INPUT_JSON') {
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    console.warn(`Ignoring ${name}: not valid JSON.`);
    return {};
  }
}

function positiveInt(raw, fallback) {
  const value = Number.parseInt(raw ?? '', 10);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

const server = app.listen(PORT, () => {
  console.log(`Sketchify anime proxy listening on :${PORT}`);
});

setInterval(() => {
  const now = Date.now();
  for (const [key, bucket] of rateBuckets) {
    if (now - bucket.startedAt > RATE_LIMIT_WINDOW_MS) {
      rateBuckets.delete(key);
    }
  }
}, 10 * 60 * 1000).unref();

function shutdown() {
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 5000).unref();
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
