# Discipline — Sideloading-Tool Wishlist Research

Helper task for the Discipline build worker (task 6042adfe). Sources: GitHub REST API
(unauthenticated, api.github.com/search/issues, sort=reactions-+1, cached under
tasks/c6dfb45c.../cache/) and the `websearch` module for Reddit sentiment. Reddit's own
`.json` endpoints returned 403 (Blocked) from this box's IP on every attempt (www.reddit.com
and old.reddit.com, two User-Agents tried) — no browser was used per the brief's light-work
rule, so Reddit figures below are search-snippet based (thread titles/snippets only), not
fetched post bodies or real upvote counts, and are marked accordingly.

Capability ground truth used for every feasibility call (per the brief): on a **free** Apple ID,
iOS can't sign **Network Extension / Personal VPN, Push Notifications, Family Controls
(Screen Time), Associated Domains, Siri, Time-Sensitive notifications**. It CAN sign **App
Groups, Background Modes, Keychain Sharing, local (non-push) notifications, WidgetKit
widgets (needs its own extra App ID), and App Intents/Shortcuts in the main app target**.
Source: https://developer.apple.com/help/account/reference/supported-capabilities-ios/
(cited in the brief; not re-fetched here — Apple's docs page, no login needed, treated as
a known reference rather than refetched to save the research window).

Demand signal legend: "👍N" = GitHub `+1` reaction count on that exact issue, read via the
search API's `reactions.+1` field at fetch time. "cN" = comment count on that issue, same
fetch. Reddit items are marked "search-snippet" (no verified upvote count obtained).

---

## 1. Unified expiry tracking + one-tap "Refresh All"
**What people want:** one place that shows every sideloaded app's remaining cert life and
refreshes them all without opening each tool separately; free-account certs expire in ~7
days (SideStore/AltStore/LiveContainer) and DNS/enterprise-signed installs (Scarlet/ESign)
die faster and need manual DNS toggling.
**Sources:** https://github.com/jkcoxson/LocalDevVPN/issues/20 ("shows 'This app is not
available' when installing from AltStore PAL", c5); general pattern across
https://github.com/SideStore/SideStore (7-day refresh cadence is the whole reason the repo
exists); Reddit (search-snippet): "E-sign stop working after 11 days" —
https://www.reddit.com/r/sideloaded/comments/1p2hcet/esign_stop_working_after_11_days/ ;
"How to fix this revocation thing" —
https://www.reddit.com/r/sideloaded/comments/1ghr4ot/how_to_fix_this_revocation_thing/
**Demand signal:** cross-cutting pain, not one issue's reaction count — multiple
independent threads/issues across 3 tools; treat as high but unquantified (unverified
beyond "several separate threads exist").
**Feasibility:** **YES.** Local (non-push) notifications for expiry warnings and
background app refresh are free-account-eligible; Discipline doesn't sign anything itself,
it drives each tool's own URL scheme (`localdevvpn://`, `sidestore://`, `livecontainer://`),
so no blocked entitlement is involved. This is the core of what the build worker is already
making.

## 2. GitHub repo → auto-fetch latest .ipa + update alerts
**What people want:** paste a GitHub repo and have the app watch Releases for a new .ipa
and alert on updates, instead of manually re-downloading from each tool's own source list.
**Sources:** direct ask from Saidie (WhatsApp, Oct 21 10:00 PM, "GitHub to iOS... paste a
repo, it grabs the latest .ipa"); matches the general "source" feature pattern in
https://github.com/LiveContainer/LiveContainer/issues/734 ("Source for LiveContainer+SideStore",
👍16 c7) and https://github.com/LiveContainer/LiveContainer/issues/122 ("Request] Source
support", 👍11 c6).
**Demand signal:** 👍16 / 👍11 on the two closest LiveContainer issues (closed, implemented
upstream as AltStore-style "sources"); Saidie's own ask carries no GitHub number but is the
stated goal.
**Feasibility:** **YES.** GitHub's public Releases API is unauthenticated-readable (same
endpoint style used for this research); downloading and presenting a .ipa for the user to
hand to SideStore/LiveContainer/Plume Impactor needs no special entitlement — it's a
network fetch + local file, same class of work as the build worker's own CI already does.

## 3. AltServer / signing tool for Linux
**What people want:** a native Linux AltServer so refreshing doesn't need a Mac/Windows PC.
**Sources:** https://github.com/altstoreio/AltStore/issues/6 ("Req: AltServer on linux",
👍93 c107, open); https://github.com/altstoreio/AltStore/issues/712 ("AltStore for Linux",
👍37 c3, open).
**Demand signal:** 👍93 (highest single reaction count found in this whole research pass)
+ 👍37 on a duplicate ask.
**Feasibility:** **NOT APPLICABLE to Discipline.** This is a desktop companion tool request,
not an iOS app feature — Discipline is the on-device hub, and with LocalDevVPN wireless
refresh in the stack there's arguably no PC-side tool needed at all for Saidie's own setup.
Worth noting to her as "already solved for you" rather than building anything.

## 4. AltStore PAL EU-region / notarization restriction
**What people want:** AltStore PAL (the DMA-based EU installer) working outside the EU, or
Apple notarizing SideStore the same way so it doesn't need PAL at all.
**Sources:** https://github.com/altstoreio/AltStore/issues/1751 ("Ios 27 'machineID'", 👍82
c55, open — PAL/EU entitlement check failing); https://github.com/SideStore/SideStore/issues/1052
("[FEATURE REQUEST] EU Sidestore PAL", 👍12 c6, open); https://github.com/SideStore/SideStore/issues/986
("feat: notarize SideStore for AltStore PAL", 👍44 c25, open).
**Demand signal:** 👍82 is the single highest reaction count found on any open issue in this
pass (AltStore #1751).
**Feasibility:** **NOT FEASIBLE for Discipline to fix.** This is an Apple regional-policy /
notarization gate inside the upstream tools' own installer, entirely outside an app that
just links out to them. Discipline can surface the error plainly when it happens (it already
plans to, per the build worker's milestone) but cannot route around Apple's EU/non-EU PAL
gate.

## 5. Refresh / login / Apple-ID auth failures
**What people want:** fewer cryptic failures when signing in or refreshing — error -80045
(AltStore), SRP error -27592 and Anisette "error decoding response body" (Plume
Impactor/claration-impactor).
**Sources:** https://github.com/altstoreio/AltStore/issues/1828 ("Cannot refresh or install
apps... error -80045", 👍85 c89, open); https://github.com/claration/impactor/issues/149
("[Help] Error While Logging In Authentication SRP error -27592", 👍3 c2, open);
https://github.com/claration/impactor/issues/211 ("Anisette Error: Request Error error
decoding response body", 👍3 c4, closed).
**Demand signal:** 👍85 c89 on the AltStore issue is very high engagement for a bug report.
**Feasibility:** **PARTLY.** Discipline doesn't do its own Apple-ID signing (it drives
SideStore/Plume Impactor, which do), so it can't fix the SRP/Anisette logic itself. What it
CAN do: catch each tool's known error codes via the URL-scheme callback or a pasted log and
show a plain-English explanation + the fix steps instead of the raw code — genuinely useful,
doesn't touch a blocked entitlement.

## 6. iOS 27 / beta compatibility breakage
**What people want:** tools that keep working across iOS point releases without the app
silently breaking on a new beta.
**Sources:** https://github.com/LiveContainer/LiveContainer/issues/1394 ("[BUG] iOS 27 broke
LiveContainer", 👍18 c64, closed); https://github.com/StikDebug/StikDebug/issues/469 ("DDI
Mount Failed / Connection refused (os error 61) on iOS 27", 👍1 c19, closed);
https://github.com/altstoreio/AltStore/issues/1751 (iOS27 machineID, see item 4, 👍82 c55).
**Demand signal:** 64 comments on the LiveContainer thread is the highest comment count
found on any issue in this pass.
**Feasibility:** **PARTLY.** Discipline's own SwiftUI code targets iOS 26+; whether it runs on
27.2 beta 4 is unverified (it hasn't been compiled or run yet). It cannot patch bugs inside LiveContainer/StikDebug/
AltStore themselves. A "compatibility status" badge per managed tool (pulled from that
repo's latest issues/releases, same API used here) is buildable and genuinely useful,
short of actually fixing anything upstream.

## 7. App ID / certificate "slots remaining" counter
**What people want:** see at a glance how many of the free account's limited App IDs are
used before hitting the wall.
**Source:** https://github.com/claration/impactor/issues/95 ("[Feature] Feature to see how
many App Id's are remaining", 👍1 c0, open).
**Demand signal:** low (👍1) but a clean, narrow, directly-buildable ask with no competing
near-duplicate found.
**Feasibility:** **YES.** Pure local bookkeeping/UI — Discipline already has to track which
apps/App IDs it manages for the 7-day-expiry feature (item 1); surfacing a count is nearly
free given that tracking already exists.

## 8. Export/import and automatic backups of sideloaded app data
**What people want:** back up a sideloaded app's data (saves, settings) so a reinstall or
re-sign doesn't wipe it.
**Sources:** https://github.com/LiveContainer/LiveContainer/issues/1353 ("[Feature Request]
Automatic Daily Backups with ZIP Export & Import Support", 👍10 c1, open);
https://github.com/claration/feather/issues/183 ("[Feature] export/import app data", 👍7 c16,
open).
**Demand signal:** 👍10 + 👍7 c16 — moderate, on open/unimplemented issues in two different
repos, so it's not solved yet upstream.
**Feasibility:** **YES.** App Groups and local file storage are free-account-eligible;
Background Modes (also free-eligible) can drive a scheduled export. No VPN/push/Family
Controls entitlement involved.

## 9. Keychain-group data sharing between managed apps
**What people want:** share login/session data between sideloaded apps the way an official
App Group would.
**Source:** https://github.com/claration/feather/issues/424 ("[Feature] Keychain Group
Modification", 👍5 c1, closed).
**Demand signal:** low (👍5), closed without an upstream fix noted.
**Feasibility:** **PARTLY.** Keychain Sharing is on the free-account-eligible list, so a
keychain group Discipline itself provisions (for apps Discipline manages) is fine. Editing
the keychain-access-group entitlement on an arbitrary already-signed third-party IPA after
the fact is a re-signing operation that belongs to SideStore/Impactor's own flow, not
something Discipline should attempt itself.

## 10. In-app entitlement editor for arbitrary IPAs
**What people want:** a UI to add/remove entitlements (Push, Associated Domains, etc.) on
any IPA before resigning it.
**Source:** https://github.com/claration/feather/issues/271 ("[Feature] Entitlements
Modification", 👍3 c18, closed).
**Demand signal:** low reactions but 18 comments — real discussion, apparently closed as
partially done upstream (Feather added some entitlement editing itself).
**Feasibility:** **NOT FEASIBLE on a free account for most of the useful entitlements.**
Push Notifications, Associated Domains, Family Controls, and a real Personal VPN
entitlement all fail to sign under a free Apple ID regardless of what UI exposes the
toggle — so building this fully would ship a button that errors for Saidie specifically.
Scoped to free-eligible entitlements only (Keychain Sharing, App Groups, Background Modes)
it's buildable, but a general "entitlement editor" oversells what a free ID can actually do.

## 11. Repo/source manager: reorder, multiple sources, show source on app info
**What people want:** manage more than one app "source" (repo list), reorder them, and see
which source an installed app came from.
**Sources:** https://github.com/claration/feather/issues/222 ("Reorder Repos", 👍5 c0,
closed); https://github.com/claration/feather/issues/495 ("[Feature] See the „Source" on the
App's info screen", 👍3 c0, open); https://github.com/LiveContainer/LiveContainer/issues/734
and /122 (source support, see item 2).
**Demand signal:** modest per-issue (👍3–5) but four separate asks across two repos for the
same underlying feature class.
**Feasibility:** **YES.** Pure data-model/UI work (a list of repo URLs + per-app source
metadata); ties directly into item 2 (GitHub-repo ingestion) as the same underlying feature.

## 12. Shortcuts / App Intents automation (start/stop VPN, refresh, install)
**What people want:** trigger LocalDevVPN on/off, app refresh, and install from the iOS
Shortcuts app / Action Button, reliably.
**Sources:** https://github.com/jkcoxson/LocalDevVPN/issues/19 ("support action button
off/on VPN", c1, closed); https://github.com/jkcoxson/LocalDevVPN/issues/15 ("iOS 26.2:
LocalDevVPN does not disconnect when stopped via Shortcuts automation", c2, closed);
https://github.com/jkcoxson/LocalDevVPN/issues/21 ("Stop LocalDevVPN shortcut action doesn't
work", c2, closed).
**Demand signal:** all 0 reactions (LocalDevVPN is a small repo, total 13 issues found) but
3 of its 13 total issues are this exact theme — a large share of its whole feature-request
volume.
**Feasibility:** **YES.** App Intents/Shortcuts integration in the main app target is
explicitly free-account-eligible per the capability table; Discipline can expose intents
that call each managed tool's own URL scheme, same mechanism as its manual buttons.

## 13. Configurable DNS server for LocalDevVPN
**What people want:** pick a custom DNS server instead of whatever LocalDevVPN hard-codes.
**Source:** https://github.com/jkcoxson/LocalDevVPN/issues/25 ("[Feature Suggestion] Add
configurable DNS server", 👍0 c1, closed).
**Demand signal:** low (single issue, 0 reactions, closed) — included because it's a direct,
concrete ask on exactly the VPN tool Discipline is meant to wrap.
**Feasibility:** **PARTLY.** The actual tunneling and DNS resolution happen inside
LocalDevVPN (which already holds whatever entitlement it needs for that, as an App-Store or
sideloaded app in its own right); Discipline can only pass a configuration value through to
it via URL scheme/config file — it can't add Network Extension capability to itself, since
that's on the free-account blocked list.

## 14. UI polish: dark-mode alternate icons + installed app size display
**What people want:** a dark-mode variant of the home-screen icon, and seeing how much disk
space each installed/managed app uses.
**Sources:** https://github.com/LiveContainer/LiveContainer/issues/190 ("[enhancement] Add
to Home Screen support dark mode icons", 👍13 c1, closed); https://github.com/LiveContainer/LiveContainer/issues/827
("[Feature] Show the App Size", 👍13 c0, closed).
**Demand signal:** 👍13 on each of two separate, already-closed (i.e., validated as worth
doing) issues.
**Feasibility:** **YES.** Alternate app icons are a public, non-gated API; reading installed
file/container size is a local filesystem read. Neither needs an entitlement a free account
can't sign.

## 15. Enterprise/DNS-signed distribution (Scarlet/ESign) reliability and revocation
**What people want:** certs that survive longer than ~7–11 days and don't get silently
blacklisted; several threads describe needing to toggle the `ppq.apple.com` DNS block on
and off to "revalidate" a cert, and getting blacklisted if done wrong.
**Sources (search-snippet, Reddit not fetched):** "E-sign stop working after 11 days" —
https://www.reddit.com/r/sideloaded/comments/1p2hcet/esign_stop_working_after_11_days/ ;
"How to fix this revocation thing" —
https://www.reddit.com/r/sideloaded/comments/1ghr4ot/how_to_fix_this_revocation_thing/ ;
"I'm sure I'm missing something here but why isn't Scarlet..." —
https://www.reddit.com/r/sideloaded/comments/11dmi5m/im_sure_im_missing_something_here_but_why_isnt/
**Demand signal:** at least 3 independent Reddit threads surfaced in a single search pass
(search-snippet only — no upvote counts obtained, Reddit JSON blocked 403 from this box).
**Feasibility:** **NOT APPLICABLE to Discipline.** Scarlet/ESign use enterprise or
DNS-profile-based distribution, a different and riskier model than the
LocalDevVPN/SideStore/LiveContainer stack Discipline is built around (free developer-ID
signing, refreshed via AltServer-style pairing rather than an enterprise cert routed through
a DNS block). Worth telling Saidie directly: Discipline's chosen architecture already avoids
this whole failure class.

---

## Top 5 feasible tonight

1. **Unified expiry tracking + one-tap "Refresh All"** (item 1) — the core ask, no blocked
   entitlement, ties every other tracked tool together.
2. **GitHub repo → auto-fetch latest .ipa + update alerts** (item 2) — Saidie's own explicit
   request, plain public-API work.
3. **Shortcuts / App Intents automation** (item 12) — free-account-eligible, reuses the same
   URL-scheme hooks items 1 and 2 already need.
4. **App ID slots-remaining counter** (item 7) — trivial once item 1's tracking exists.
5. **Repo/source manager** (item 11) — same data model as item 2, adds reorder + multi-source
   + "source" shown on each app's info screen.

---

## What I could not reach

- Reddit's `.json` endpoints returned HTTP 403 ("Blocked") on every attempt — www.reddit.com
  and old.reddit.com, two different User-Agent strings — so every Reddit figure above is a
  search-snippet (title + short preview), not a fetched post body or a verified upvote count.
  No browser was used to work around this, per the light-work-only rule in the brief.
- GitHub's unauthenticated search quota (10 requests/60s) meant I used `sort=reactions-+1`
  as the single ranking signal per repo rather than cross-checking `sort=comments` on every
  repo; I did run the comments sort on StikDebug and LocalDevVPN specifically, where reaction
  counts were uniformly near-zero and comments were the only usable signal.
- `khcrysalis/Feather` and `StephenDev0/StikDebug` have both moved (now `claration/feather`
  and `StikDebug/StikDebug`); I detected this from a 422 on the old names and re-queried the
  current ones — URLs above use the current repo paths.
- I did not independently verify Apple's supported-capabilities table beyond citing the URL
  the brief gave; I did not re-fetch it to save search-window time, since it was already
  given as a known reference.


## Built in Discipline v0.1.0 (source written; not yet compiled or UI-tested; see README status)

| Wishlist item | Where | UI test |
|---|---|---|
| 1. Expiry countdowns (from the signing date you enter) + Refresh All (one tap starts it: LocalDevVPN on, SideStore opened; you finish with SideStore's own Refresh All) | Home, Expiry | `HomeUITests`, `ExpiryUITests` |
| 2. GitHub → release lookup, download, install hand-off, manual "Check for updates" with badges (no background fetching or notifications) | GitHub tab | `GitHubUITests` |
| 7. App ID slots counter | Expiry → App IDs | `ExpiryUITests`, `LibraryUITests` |
| 8. Backup / restore of settings, tracked apps, saved repos and the App ID log (not the .ipa files) | More → Settings → Backup | `MoreUITests.testSettingsEveryControl` |
| 12. Shortcuts / App Intents (Refresh All, VPN On) | Shortcuts app | not UI-testable from XCUITest; logic shared with Home buttons |
| 10. Entitlement inspector (read-only; editing would need re-signing) | NCOM Lab | `LabUITests` |
| 11. Show where an app came from | Library → app → From | `LibraryUITests`, `GitHubUITests` |
| 14. Installed app size | Library → app → Size | `LibraryUITests` |

Not built: alternate icons (needs icon variants designed by NCOM), DNS for LocalDevVPN (that lives in LocalDevVPN), and items marked not applicable above.
