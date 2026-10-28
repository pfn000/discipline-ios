# Ouija ring page

Sign in to a computer with your iPhone: this page shows a signed, one-time code as four spinning
rings, and Ouija reads them with the camera.

1. On the computer, in this folder: `python3 ouija_host.py` (Python 3.8+, standard library only;
   `pip install zeroconf` if you're not on a Mac and Bonjour doesn't start), then open
   http://localhost:8737.
2. The page makes an Ed25519 key that stays in this browser (IndexedDB, not exportable). Copy the
   `NCOMKEY1.…` text into Ouija → Keys → Add key and check the fingerprint matches.
3. In Ouija tap Sign in. The phone finds the computer over Wi-Fi (Bonjour `_ncom-ouija._tcp`) or,
   in Chrome/Edge, over Bluetooth ("Connect over Bluetooth"), hands it a fresh session, and the
   page shows the rings. Point the camera at them.

What the phone checks: the key is enrolled, the Ed25519 signature over `"NCOM-RING-1"` + version,
session, time and key id, that the session is the one it just made, and that the code is under two
minutes old.

Safari and Firefox have no Web Bluetooth; use the Wi-Fi helper there.

Files: `ring.js` is the ring code (a port of `DisciplineCore/RingCode.swift` and `RingLogin.swift`);
`app.js` runs the page; `ouija_host.py` serves the page, advertises it and relays the session.
`?demo` shows rings for a made-up session; `?fixture=1&frame=i&angles=a,b,c,d` draws one still frame
with a fixed test key (used to make `DisciplineCore/Tests/.../Fixtures/web-ring-*`, which the Swift
reader tests read back and verify).
