# Discipline: research notes

Written 2026-10-22 for Saidie (NCOM). Every claim below links to the source it was read from on that date. Anything not verified is marked **unverified**.

## 1. What "Discipline" is

Saidie's ask (WhatsApp, Oct 21 2026, 6:53 PM): "You can work on that tonight when I sleep. You'd be best doing full deep dive research and build 'Discipline iOS app'".

Her reference screenshot is a Windows Notepad window. Its text, transcribed exactly:

> Build an ios app using Reverse engineer anything tools you have and combine the following apps into ONE side load app
> - LocalDevVPN
> - LiveContainer
> -SideInstaller & SideLoader

Status bar: `Ln 4, Col 28 | 175 characters | Plain text | 100% | Windows (CRLF) | UTF-8`. Tabs: `…anife`, `script.ahk`. Behind it, a browser error page: "This site can't be re…", "The connection was reset.", "ERR_CONNECTION_RESET", "Reload".

Her later goals (Oct 21, 9:54 PM to 10:12 PM, relayed): she signs apps with **Plume Impactor** from a PC, Developer Mode is on, iPhone 17 Pro on **iOS 27.2 beta 4**; she wants apps to never expire, .ipa files to open straight into the app, "GitHub to iOS", Liquid Glass, a tip button, a hidden NCOM Lab for her Ouija Board app, and its own GitHub repo and release.

So **Discipline = one hub app that ties LocalDevVPN, SideStore/SideInstaller and LiveContainer together**, not a Screen Time app. Section 8 covers the Screen Time reading anyway, because the name suggests it.

## 2. The upstream projects

| Project | Repo | License (read from the repo) | What it does |
|---|---|---|---|
| LocalDevVPN | https://github.com/jkcoxson/LocalDevVPN (App Store id6755608044) | "StosVPN License": MIT text plus attribution, "based on" statement, and **no rebranding or republishing of the whole project without written permission** | A packet-tunnel VPN that reflects packets back to the phone so the phone can reach its own lockdown service |
| SideStore | https://github.com/SideStore/SideStore | AGPL-3.0 | On-device AltStore fork: signs apps with your Apple ID and installs/refreshes them through LocalDevVPN |
| LiveContainer | https://github.com/LiveContainer/LiveContainer | AGPL-3.0 | Runs many apps inside one installed app; ships a "LiveContainer+SideStore" build |
| SideInstaller | https://github.com/FrizzleM/SideInstaller | Custom: source use and modification allowed for **non-commercial** purposes with attribution; **no redistribution of official IPAs, no monetization** without permission | Installs SideStore + LiveContainer from the phone itself (iOS 27.0.1+), using a Rust core over jkcoxson/idevice |
| Plume Impactor | https://github.com/claration/impactor | MIT | Desktop (Windows/macOS/Linux) signer/installer; makes pairing files; "almost proper entitlement handling" |
| iloader | https://github.com/nab138/iloader | MIT | Desktop installer SideStore's docs now recommend |

**How the pieces work** (sources: LocalDevVPN `TunnelProv/PacketTunnelProvider.swift`; https://jkcoxson.com/blog/i-made-apple-mad):
- lockdownd refuses connections from the phone's own addresses. LocalDevVPN brings up a `utun` interface (default interface 10.7.1.1, peer 10.7.0.1) and swaps the source and destination of every IPv4 packet it reads. Traffic to 10.7.0.1 comes back looking like it came from another machine, so SideStore can talk to lockdown and `installation_proxy` on the phone itself.
- In **iOS 26.4** Apple added a check: a connection arriving on a `utun` interface is rejected unless its address could be on the Wi-Fi subnet. The fix is a peer address inside the Wi-Fi subnet, routed as /32 (LocalDevVPN builds and forks like SiamSadik/LocalDevVPN carry it).
- LocalDevVPN accepts `localdevvpn://enable?scheme=<app>` / `disable`, then opens `<app>://` (read in `LocalDevVPNApp.swift`). SideStore accepts `sidestore://install?url=` and `sidestore://source?url=` (https://docs.sidestore.io/docs/advanced/url-schema). LiveContainer accepts `livecontainer://install?url=`, `livecontainer://source?url=` and `livecontainer://livecontainer-launch?bundle-name=` (read in `LCAppListView.swift`, `LCAltStoreSourcesView.swift`). SideStore declares the `com.apple.itunes.ipa` document type and LiveContainer declares `public.item`, so both appear in the share sheet for an .ipa (their Info.plist files).
- SideStore has **no URL that starts a refresh** (its `URLHandler.swift` handles install, source, pairing, certificate, backup).

## 3. Free vs paid Apple account (verified)

From Apple's capability table, https://developer.apple.com/help/account/reference/supported-capabilities-ios/ (column "Apple Developer" = free account):

| Capability | Free Apple ID | Paid ($99/yr) |
|---|---|---|
| App Groups, Background Modes, Keychain sharing, Data Protection, HealthKit, HomeKit, Maps, Inter-App Audio, Wireless Accessory Configuration | yes | yes |
| Network Extensions, Personal VPN | **no** | yes |
| Push notifications, Time Sensitive notifications | **no** | yes |
| Family Controls (development only) | **no** | yes (distribution needs Apple's approval) |
| NFC Tag Reading, Access WiFi information, Siri, iCloud, Associated Domains, Increased Memory Limit | **no** | yes |

Limits (SideStore FAQ, https://docs.sidestore.io/docs/faq): a free account signs for **7 days**, allows **3 apps** at once (including SideStore) and **10 App IDs per 7 days**; paid gives **365 days**. Every app extension needs its own App ID.

**Consequences for Discipline**
- A free account **cannot sign a VPN**, so Discipline cannot contain LocalDevVPN. It drives the App Store LocalDevVPN instead. (A paid account could embed a packet tunnel; `DisciplineCore/PacketReflector.swift` and `PeerAddressPlanner.swift` are the tested logic for that, but no tunnel target ships.)
- Discipline ships **no extensions** (one App ID). App Intents (Shortcuts) live in the main app.
- Local notifications need no entitlement, so expiry reminders work on a free account. Remote push does not.

## 4. "Never expires": what's honestly possible

- No legitimate way makes a signature permanent. Free = 7 days, paid = 365 days.
- Enterprise certificates sold as "permanent" get revoked by Apple; using one breaks Apple's terms and puts your Apple ID and data at risk. Not recommended.
- **TrollStore** (permanent signing through a CoreTrust bug) supports iOS 14.0 to 16.6.1, 16.7 RC and 17.0 only (https://theapplewiki.com/wiki/TrollStore). It does not work on iOS 27.
- The closest real thing: **LiveContainer + SideStore**. Apps inside LiveContainer are not signed one by one; only LiveContainer (and SideStore) need refreshing, and SideStore refreshes in the background while LocalDevVPN is on. Discipline adds countdowns from the signing date you enter, reminders 48/24/2 hours ahead, a one-tap start to the refresh (LocalDevVPN on, SideStore opened; you finish with SideStore's Refresh All), and an App ID counter.

## 5. iOS 27.2 beta, Plume Impactor, Developer Mode

- SideInstaller lists iOS 27.0.1+ as fully on-device; 17.4 to 26.7 need a pairing file made on a computer (its README).
- Known iOS 27 issues reported by users: SideStore UDID/pairing-file errors, fixed by updating, re-generating the pairing file (Plume Impactor can) and re-importing it (https://github.com/SideStore/SideStore/issues/1217; https://www.reddit.com/r/SideStore/comments/1v3tsox/sidestore_broken_since_update/). **Unverified on her device.**
- JIT on iOS 26+/27 works only for a short list of apps (https://docs.sidestore.io/docs/advanced/jit). Most apps run in LiveContainer without JIT.
- Betas can change lockdown or signing behaviour between builds (iOS 26.4 did). Re-test after each beta.

## 6. Jailbreak question (Saidie, 10:07 PM)

Apple does not make jailbreaks. Findings on 2026-10-22:
- No publicly documented jailbreak that I could verify supports iOS 27.x on A19/A19 Pro. Apple's Memory Integrity Enforcement is always on in iPhone 17 models (https://security.apple.com/blog/memory-integrity-enforcement/); Cellebrite writes that iOS 27 cannot be jailbroken on current devices (https://cellebrite.com/en/blog/ios-risk-for-mobile-app-developers-and-security-teams/).
- MacRumors reports Dopamine reached iOS 26 in August 2026 (https://www.macrumors.com/2026/08/07/ios-26-dopamine-jailbreak/); which devices it covers is **unverified** here.
- Videos claiming iOS 27 jailbreaks ("vPhone" and similar) are not verified and look like the usual scams. Don't install profiles or "jailbreak" apps from them.
- Discipline ships no exploit and recommends none.

## 7. NCOM Ouija Board capability map (NCOM Lab)

| Feature | Framework | Restricted entitlement | Free Apple ID? | Source |
|---|---|---|---|---|
| UWB / Nearby Interaction (phone and accessory) | NearbyInteraction | none (usage string; `nearby-interaction` background mode) | ✅ | https://developer.apple.com/documentation/nearbyinteraction |
| Bluetooth LE | CoreBluetooth | none | ✅ | https://developer.apple.com/documentation/corebluetooth |
| NFC tag reading | CoreNFC | `com.apple.developer.nfc.readersession.formats` | ⚠️ paid | Apple capability table |
| Wi-Fi Aware | WiFiAware | `com.apple.developer.wifi-aware` | ⚠️ treat as paid (not in the free column; **unverified on device**) | https://developer.apple.com/documentation/wifiaware/adopting-wi-fi-aware |
| Local network / Bonjour | Network | none (usage string + Bonjour types) | ✅ | Apple docs |
| Multicast / broadcast | Network | `com.apple.developer.networking.multicast` | ❌ Apple approval only | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast |
| Wi-Fi name (SSID) | NetworkExtension | `com.apple.developer.networking.wifi-info` | ⚠️ paid | Apple capability table |
| Proximity sensor | UIKit | none | ✅ | https://developer.apple.com/documentation/uikit/uidevice/isproximitymonitoringenabled |
| Motion | CoreMotion | none (usage string) | ✅ | https://developer.apple.com/documentation/coremotion |
| External Accessory | ExternalAccessory | none, but hardware must be MFi-certified | ✅ app side | https://developer.apple.com/documentation/externalaccessory |
| Multipeer Connectivity | MultipeerConnectivity | none (local network usage string) | ✅ | https://developer.apple.com/documentation/multipeerconnectivity |

A signer can only request what Apple's portal provisions for the account. Discipline's Lab shows this per feature and writes the `.entitlements` + Info.plist keys; it cannot grant anything.

## 8. If "Discipline" meant a focus / Screen Time app

Apps like Opal, one sec and Jomo are built on Apple's Screen Time API (FamilyControls, ManagedSettings, DeviceActivity) (https://developer.apple.com/documentation/familycontrols; which exact APIs each app uses is **unverified**). Family Controls is **not available to a free Apple ID** (capability table above), and distributing it needs Apple's approval (https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement). A sideloaded app on a free account can't block other apps. If that's what she wants, it needs the paid program.

## 9. Security

- Discipline never asks for an Apple ID password. Signing happens in Plume Impactor or SideStore.
- Apps inside LiveContainer share one sandbox: one guest app can read another's data (LiveContainer README, "Limitations").
- Only install SideStore, LiveContainer, SideInstaller and LocalDevVPN from their official sources. SideInstaller's README warns about credential-stealing forks and the fake "sideinstaller.com".
- The GitHub token is optional and stays in the iPhone's Keychain.
- Ouija Guard reads .ipa files and App Privacy Report exports on the phone; nothing is uploaded.

## 10. What works today / what needs a Mac + Apple ID

**Verified tonight (Linux box):** the shared logic in `DisciplineCore`: IPA reading (ZIP + DEFLATE + binary Info.plist + icon), entitlement extraction from Mach-O, tracker scan, App Privacy Report parsing, GitHub link/release logic, expiry and App ID maths, deep links matching upstream handlers, VPN detection, capability map and signing preset. `swift test`: **30 tests, 0 failures** (Swift 6.2, Linux).

**Needs a Mac (Xcode 27):** compiling the SwiftUI app and running the UI tests. The workflow in `.github/workflows/ios.yml` does it on GitHub's `xcode-27` runner. **Status on 2026-10-22: blocked.** GitHub refused to start the job because of the account's billing ("recent account payments have failed or your spending limit needs to be increased"). Until a run passes, the SwiftUI code is **uncompiled and untested**, and **no IPA exists**.

**Needs her Apple ID (on her PC):** signing and installing the IPA with Plume Impactor (see PLUME-INSTALL.md). Discipline can't be signed without her Apple account, and nothing here was signed.

## Sources

- Apple capability table: https://developer.apple.com/help/account/reference/supported-capabilities-ios/
- SideStore docs: https://docs.sidestore.io/docs/faq, https://docs.sidestore.io/docs/advanced/url-schema, https://docs.sidestore.io/docs/advanced/jit, https://docs.sidestore.io/docs/installation/prerequisites
- LocalDevVPN source: https://github.com/jkcoxson/LocalDevVPN
- Jackson Coxson, "I Made Apple Mad": https://jkcoxson.com/blog/i-made-apple-mad
- LiveContainer: https://github.com/LiveContainer/LiveContainer
- SideInstaller: https://github.com/FrizzleM/SideInstaller
- Plume Impactor: https://github.com/claration/impactor
- iloader: https://github.com/nab138/iloader
- SiamSadik/LocalDevVPN (iOS 26.4 /32 fix): https://github.com/SiamSadik/LocalDevVPN
- TrollStore support range: https://theapplewiki.com/wiki/TrollStore
- Apple MIE: https://security.apple.com/blog/memory-integrity-enforcement/
- GitHub runner images (xcode-27 label): https://github.com/actions/runner-images/issues/14404
- Wishlist research: WISHLIST.md
