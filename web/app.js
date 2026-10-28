// Ouija ring sign-in page. Holds this computer's Ed25519 key, gets a session from the phone
// (Wi-Fi helper or Web Bluetooth), signs it, and shows the signed login as spinning rings.
(() => {
  'use strict';
  const NR = window.NCOMRing;
  const $ = (id) => document.getElementById(id);
  const params = new URLSearchParams(location.search);
  const DEMO = params.has('demo');            // ?demo: a made-up session, for previews only
  const FIXTURE = params.get('fixture');      // ?fixture=<seed>: deterministic key + session, still rings (tests)
  const BLE = { service: '4e434f4d-4f55-494a-4100-000000000001', session: '4e434f4d-4f55-494a-4100-000000000002', hello: '4e434f4d-4f55-494a-4100-000000000003' };
  const FRAME_MS = 450, RESIGN_S = 90, MAX_AGE_S = 120;
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

  const state = { key: null, pub: null, session: null, sessionSource: null, frames: [], iat: 0, spin: [0, 0, 0, 0], paused: false, helper: false, t0: performance.now() };
  const canvas = $('rings'), ctx = canvas.getContext('2d');

  // ---------- key ----------
  function idb() {
    return new Promise((res, rej) => {
      const r = indexedDB.open('ouija-ring', 1);
      r.onupgradeneeded = () => r.result.createObjectStore('kv');
      r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
    });
  }
  async function kv(op, k, v) {
    const db = await idb();
    return new Promise((res, rej) => {
      const tx = db.transaction('kv', op === 'get' ? 'readonly' : 'readwrite'), st = tx.objectStore('kv');
      const r = op === 'get' ? st.get(k) : op === 'del' ? st.delete(k) : st.put(v, k);
      r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
    });
  }
  async function loadKey(fresh) {
    if (FIXTURE) {   // fixed test key from a 32-byte seed (PKCS#8 wrapper for Ed25519)
      const seed = new Uint8Array(32).map((_, i) => (Number(FIXTURE) * 31 + i * 7) & 0xFF);
      const pk8 = new Uint8Array([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20, ...seed]);
      const priv = await crypto.subtle.importKey('pkcs8', pk8, { name: 'Ed25519' }, true, ['sign']);
      const jwk = await crypto.subtle.exportKey('jwk', priv);
      const pub = Uint8Array.from(atob(jwk.x.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
      return { privateKey: priv, pub: Array.from(pub) };
    }
    if (!fresh) { const saved = await kv('get', 'key').catch(() => null); if (saved && saved.privateKey) return saved; }
    const pair = await crypto.subtle.generateKey({ name: 'Ed25519' }, false, ['sign', 'verify']);
    const pub = Array.from(new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey)));
    const rec = { privateKey: pair.privateKey, pub, made: Date.now() };
    await kv('put', 'key', rec).catch(() => {});
    return rec;
  }
  function showKey() {
    $('fp').textContent = NR.fingerprint(state.pub);
    $('keyText').textContent = NR.keyText(state.pub);
    $('copyKey').disabled = false;
    state.spin = NR.choreography(state.pub);
  }

  // ---------- signing + rings ----------
  async function sign() {
    if (!state.key || !state.session) return;
    const iat = FIXTURE ? 1800000000 : Math.floor(Date.now() / 1000);
    const msg = await NR.signLogin(crypto.subtle, state.key, state.pub, state.session, iat);
    state.iat = iat; state.msg = msg; state.frames = NR.frames(msg); state.t0 = performance.now();
    $('canvasWrap').dataset.live = 'true';
    $('resign').disabled = false; $('pause').disabled = false;
    $('sessionMeta').textContent = NR.hex(state.session).slice(0, 8) + '…';
    canvas.setAttribute('aria-label', 'Ring code for this sign-in, ' + state.frames.length + ' frames. Point Ouija on your iPhone at it.');
    $('stageLede').textContent = DEMO ? 'Demo session: these rings are real, but no phone asked for them.' : 'Point Ouija at the rings. Hold steady until the phone buzzes.';
    window.__ouija = { msg: NR.hex(msg), frames: state.frames.length, key: NR.keyText(state.pub), session: NR.hex(state.session), iat };
  }
  function setSession(bytes, source) {
    if (!bytes || bytes.length !== 16) return;
    if (state.session && NR.hex(state.session) === NR.hex(bytes)) return;
    state.session = bytes; state.sessionSource = source;
    link('live', source === 'demo' ? 'Demo session' : 'Phone · ' + source);
    sign();
  }
  function fit() {
    const r = canvas.getBoundingClientRect(), dpr = Math.min(window.devicePixelRatio || 1, 3);
    const px = Math.max(64, Math.round(r.width * dpr));
    if (canvas.width !== px) { canvas.width = px; canvas.height = px; }
  }
  function frameAt(now) {
    if (FIXTURE) {   // ?fixture=seed&frame=i&angles=a,b,c,d : one still frame for the decoder tests
      const i = Number(params.get('frame') || 0), a = (params.get('angles') || '0,0,0,0').split(',').map(Number);
      return { f: state.frames[i % state.frames.length], angles: a, i };
    }
    const t = Math.max(0, (now - state.t0) / 1000);
    const i = Math.floor(t * 1000 / FRAME_MS) % state.frames.length;
    const angles = state.spin.map((s) => (reduceMotion ? 0 : s * t * 2 * Math.PI));
    return { f: state.frames[i], angles, i };
  }
  const idleFrame = NR.frames([0x4E, 0x43, 0x4F, 0x4D])[0];
  function tick(now) {
    fit();
    const size = canvas.width;
    if (state.frames.length && !state.paused) {
      const { f, angles, i } = frameAt(now);
      NR.draw(ctx, f, size, angles, { scale: 0.92 });
      $('frameMeta').textContent = (i + 1) + ' / ' + state.frames.length;
      const left = Math.max(0, MAX_AGE_S - (Math.floor(Date.now() / 1000) - state.iat));
      $('ttlMeta').textContent = FIXTURE ? 'fixed' : Math.floor(left / 60) + ':' + String(left % 60).padStart(2, '0');
      if (!FIXTURE && left <= MAX_AGE_S - RESIGN_S) sign();   // keep the code fresh while the phone looks
    } else if (!state.frames.length) {
      NR.draw(ctx, idleFrame, size, [0.4, -1.2, 2.1, 0.7], { scale: 0.92, ink: '#2a2d2f' });   // still: nothing to read yet
    }
    window.__drawn = true;
    requestAnimationFrame(tick);
  }

  // ---------- link: chip + routes ----------
  function link(s, text) { $('linkChip').dataset.state = s; $('linkText').textContent = text; }
  function pill(id, s, text) { const p = $(id); p.dataset.state = s; p.textContent = text; }

  async function helperLoop() {
    try {
      const h = await fetch('/health', { cache: 'no-store' });
      const j = h.ok ? await h.json() : null;
      if (!j || j.service !== 'ouija-host') throw new Error('no helper');
      state.helper = true;
      pill('wifiState', 'ok', 'Running');
      $('wifiHelp').textContent = 'Advertising as “' + (j.name || 'this computer') + '” on your Wi-Fi. Ouija finds it on the Sign in tab.';
      await fetch('/pubkey', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ key: NR.keyText(state.pub) }) }).catch(() => {});
      if (!state.session) link('wait', 'Waiting for your phone');
      for (;;) {
        const r = await fetch('/session', { cache: 'no-store' });
        if (r.ok) { const s = await r.json(); if (s.session) setSession(NR.unhex(s.session), 'Wi-Fi'); }
        await new Promise((ok) => setTimeout(ok, 1000));
      }
    } catch (e) {
      if (state.helper) { pill('wifiState', 'no', 'Lost'); state.helper = false; setTimeout(helperLoop, 3000); return; }
      pill('wifiState', 'wait', 'Not running');
    }
  }

  function setupBluetooth() {
    const btn = $('bleBtn');
    if (!('bluetooth' in navigator)) {
      const ua = navigator.userAgent, safariOrFirefox = /Firefox\//.test(ua) || (/Safari\//.test(ua) && !/Chrom(e|ium)\/|Edg\//.test(ua));
      pill('bleState', 'no', 'Not in this browser');
      $('bleHelp').textContent = safariOrFirefox
        ? 'Safari and Firefox don’t support Web Bluetooth, so this route isn’t possible here. Use Chrome or Edge, or the Wi-Fi helper.'
        : 'Web Bluetooth isn’t available in this browser window. Use desktop Chrome or Edge, or the Wi-Fi helper.';
      btn.disabled = true; return;
    }
    pill('bleState', '', 'Ready');
    btn.addEventListener('click', async () => {
      try {
        pill('bleState', 'wait', 'Pick “Ouija”…');
        const dev = await navigator.bluetooth.requestDevice({ filters: [{ services: [BLE.service] }, { name: 'Ouija' }], optionalServices: [BLE.service] });
        const gatt = await dev.gatt.connect();
        const svc = await gatt.getPrimaryService(BLE.service);
        const sess = await (await svc.getCharacteristic(BLE.session)).readValue();
        const text = new TextDecoder().decode(sess.buffer);
        await (await svc.getCharacteristic(BLE.hello)).writeValue(new TextEncoder().encode('NCOM-HELLO ' + NR.fingerprint(state.pub)));
        pill('bleState', 'ok', 'Connected');
        dev.addEventListener('gattserverdisconnected', () => pill('bleState', '', 'Disconnected'));
        setSession(NR.unhex(text), 'Bluetooth');
      } catch (e) {
        pill('bleState', 'no', e && e.name === 'NotFoundError' ? 'Cancelled' : 'Failed');
        $('bleHelp').textContent = 'Couldn’t connect: ' + (e && e.message ? e.message : e) + '. Keep Ouija open on the Sign in tab and try again.';
      }
    });
  }

  // ---------- buttons ----------
  $('copyKey').addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(NR.keyText(state.pub)); $('keyHint').className = 'hint'; $('keyHint').textContent = 'Copied. Paste it in Ouija → Keys → Add key.'; }
    catch { const r = document.createRange(); r.selectNodeContents($('keyText')); getSelection().removeAllRanges(); getSelection().addRange(r); $('keyHint').textContent = 'Selected. Copy it with ⌘C / Ctrl+C.'; }
  });
  $('resign').addEventListener('click', () => sign());
  $('pause').addEventListener('click', () => {
    state.paused = !state.paused; $('pause').setAttribute('aria-pressed', String(state.paused)); $('pause').textContent = state.paused ? 'Resume' : 'Pause';  // motion > 5 s gets a stop control
  });
  $('resetKey').addEventListener('click', async () => {
    if (!confirm('Make a new key? Ouija will need the new one enrolled before it accepts this computer.')) return;
    const k = await loadKey(true); state.key = k.privateKey; state.pub = k.pub; showKey(); sign();
    $('keyHint').className = 'hint'; $('keyHint').textContent = 'New key made. Enroll it in Ouija again.';
    if (state.helper) fetch('/pubkey', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ key: NR.keyText(state.pub) }) }).catch(() => {});
  });

  // ---------- start ----------
  (async () => {
    requestAnimationFrame(tick);
    if (!window.isSecureContext || !crypto.subtle) {
      $('keyText').textContent = 'This page needs a secure address (https:// or http://localhost) to make a key.';
      $('keyHint').className = 'hint err'; link('error', 'Insecure page'); return;
    }
    try { const k = await loadKey(false); state.key = k.privateKey; state.pub = k.pub; showKey(); }
    catch (e) {
      $('keyText').textContent = 'This browser can’t make Ed25519 keys yet (needs Chrome 137+, Edge 137+, Safari 17+ or Firefox 129+).';
      $('keyHint').className = 'hint err'; $('keyHint').textContent = String(e && e.message || e); link('error', 'No Ed25519'); return;
    }
    setupBluetooth();
    if (FIXTURE) { setSession(Array.from({ length: 16 }, (_, i) => (Number(FIXTURE) * 13 + i * 11) & 0xFF), 'fixture'); pill('wifiState', '', 'Test'); return; }
    if (DEMO) { setSession(Array.from(crypto.getRandomValues(new Uint8Array(16))), 'demo'); }
    $('envNote').textContent = location.host;
    helperLoop();
  })();
})();
