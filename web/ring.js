// NCOM ring code, the page side. A byte-for-byte port of DisciplineCore/RingCode.swift + RingLogin.swift.
// Works in the browser (window.NCOMRing) and in Node (module.exports) so the tests can check it.
(function (root) {
  'use strict';
  const RINGS = 4, CELLS = 32, FRAME_BYTES = 16, DATA_BYTES = 14, MAX_FRAMES = 16;
  const HUB = 0.12, FINDER_IN = 0.92, FINDER_OUT = 0.98;
  const DATA_R = [0.28, 0.45, 0.62, 0.79], DATA_HALF = 0.04, TICK_OFF = 0.08, TICK_HALF = 0.025;
  const DOMAIN = new TextEncoder().encode('NCOM-RING-1');
  const KEY_PREFIX = 'NCOMKEY1.';

  // xorshift32 from "NCOM" (0x4E434F4D), 15 bytes; same table as the phone.
  const WHITENING = (() => {
    let x = 0x4E434F4D >>> 0; const out = [];
    for (let i = 0; i < 15; i++) {
      x ^= (x << 13) >>> 0; x >>>= 0; x ^= x >>> 17; x ^= (x << 5) >>> 0; x >>>= 0;
      out.push(x & 0xFF);
    }
    return out;
  })();

  function crc8(bytes) {
    let c = 0;
    for (const b of bytes) {
      c ^= b;
      for (let i = 0; i < 8; i++) c = (c & 0x80) ? ((c << 1) ^ 0x07) & 0xFF : (c << 1) & 0xFF;
    }
    return c;
  }

  function fnv1a(bytes) {
    let h = 0x811C9DC5 >>> 0;
    for (const b of bytes) { h ^= b; h = Math.imul(h, 0x01000193) >>> 0; }
    return h >>> 0;
  }

  function frames(message) {
    const n = Math.max(1, Math.ceil(message.length / DATA_BYTES));
    if (n > MAX_FRAMES) throw new Error('message too long for a ring code');
    const out = [];
    for (let i = 0; i < n; i++) {
      const data = new Array(DATA_BYTES).fill(0);
      for (let j = 0; j < DATA_BYTES && i * DATA_BYTES + j < message.length; j++) data[j] = message[i * DATA_BYTES + j];
      out.push({ index: i, count: n, data });
    }
    return out;
  }

  // The 16 on-air bytes: whitened header + data, then CRC-8 of those 15.
  function frameBytes(f) {
    const raw = [((f.index << 4) | (f.count - 1)) & 0xFF, ...f.data].map((b, i) => b ^ WHITENING[i]);
    return raw.concat([crc8(raw)]);
  }

  // bits[ring][cell]; ring r cell c is bit r*32+c, MSB first.
  function bits(f) {
    const b = frameBytes(f), out = [];
    for (let r = 0; r < RINGS; r++) {
      const row = [];
      for (let c = 0; c < CELLS; c++) { const bit = r * CELLS + c; row.push(((b[bit >> 3] >> (7 - (bit & 7))) & 1) === 1); }
      out.push(row);
    }
    return out;
  }

  // Each key gives the rings their own spin (turns per second), from FNV-1a of the key.
  function choreography(key) {
    const h = fnv1a(key), out = [];
    for (let i = 0; i < RINGS; i++) {
      const nib = ((h >>> (i * 8)) & 0xFF) / 255;
      const dir = ((h >>> (i + 28)) & 1) === 1 ? 1 : -1;
      out.push(dir * (0.04 + 0.10 * nib));
    }
    return out;
  }

  // Draws one frame onto a 2D context. angles[i] = ring i's rotation in radians, clockwise on screen.
  function draw(ctx, f, size, angles, opts) {
    const o = Object.assign({ scale: 0.9, ink: '#f4f4f6', paper: '#07080a', guide: null }, opts || {});
    const R = size / 2 * o.scale, cx = size / 2, cy = size / 2, cell = 2 * Math.PI / CELLS;
    const b = bits(f);
    ctx.save();
    ctx.fillStyle = o.paper; ctx.fillRect(0, 0, size, size);
    const annulus = (r0, r1, a0, a1) => {
      ctx.beginPath(); ctx.arc(cx, cy, r1 * R, a0, a1, false); ctx.arc(cx, cy, r0 * R, a1, a0, true); ctx.closePath(); ctx.fill();
    };
    if (o.guide) {
      ctx.fillStyle = o.guide;
      for (let i = 0; i < RINGS; i++) annulus(DATA_R[i] - DATA_HALF, DATA_R[i] + DATA_HALF, 0, 2 * Math.PI);
    }
    ctx.fillStyle = o.ink;
    ctx.beginPath(); ctx.arc(cx, cy, HUB * R, 0, 2 * Math.PI); ctx.fill();
    annulus(FINDER_IN, FINDER_OUT, 0, 2 * Math.PI);
    for (let i = 0; i < RINGS; i++) {
      const a = (angles && angles[i]) || 0;
      for (let c = 0; c < CELLS; c++) {
        if (!b[i][c]) continue;
        const mid = a + c * cell;
        annulus(DATA_R[i] - DATA_HALF, DATA_R[i] + DATA_HALF, mid - 0.40 * cell, mid + 0.40 * cell);
      }
      annulus(DATA_R[i] + TICK_OFF - TICK_HALF, DATA_R[i] + TICK_OFF + TICK_HALF, a - 0.45 * cell, a + 0.45 * cell);
    }
    ctx.restore();
  }

  // RingLogin: 0x01 | session(16) | iat u32 BE | keyID u32 BE | Ed25519 sig(64) of "NCOM-RING-1" + first 25 bytes.
  function signedPart(session, iat, keyID) {
    const be = (v) => [(v >>> 24) & 0xFF, (v >>> 16) & 0xFF, (v >>> 8) & 0xFF, v & 0xFF];
    return [1, ...session, ...be(iat >>> 0), ...be(keyID >>> 0)];
  }

  async function signLogin(subtle, privateKey, publicKeyRaw, session, iat) {
    if (session.length !== 16) throw new Error('session must be 16 bytes');
    const part = signedPart(session, iat, fnv1a(publicKeyRaw));
    const data = new Uint8Array(DOMAIN.length + part.length);
    data.set(DOMAIN, 0); data.set(part, DOMAIN.length);
    const sig = new Uint8Array(await subtle.sign({ name: 'Ed25519' }, privateKey, data));
    return part.concat(Array.from(sig));
  }

  const b64url = (bytes) => {
    let s = ''; for (const b of bytes) s += String.fromCharCode(b);
    return (typeof btoa === 'function' ? btoa(s) : Buffer.from(s, 'binary').toString('base64'))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  };
  const keyText = (pk) => KEY_PREFIX + b64url(pk);
  const fingerprint = (pk) => {
    const h = fnv1a(pk), hex = (v) => v.toString(16).toUpperCase().padStart(4, '0');
    return hex(h >>> 16) + '-' + hex(h & 0xFFFF);
  };
  const hex = (b) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
  const unhex = (s) => {
    s = (s || '').trim();
    if (!/^([0-9a-fA-F]{2})+$/.test(s)) return null;
    const out = []; for (let i = 0; i < s.length; i += 2) out.push(parseInt(s.slice(i, i + 2), 16));
    return out;
  };

  const api = { RINGS, CELLS, FRAME_BYTES, DATA_BYTES, WHITENING, crc8, fnv1a, frames, frameBytes, bits,
    choreography, draw, signedPart, signLogin, keyText, fingerprint, hex, unhex };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.NCOMRing = api;
})(typeof self !== 'undefined' ? self : this);
