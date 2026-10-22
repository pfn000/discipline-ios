# Discipline architecture

```
Discipline.app (SwiftUI, iOS 26.0+, Liquid Glass)        DisciplineCore (Swift package, no UIKit)
├─ App/Sources/DisciplineApp.swift   TabView: Home · Library · GitHub · Expiry · More
├─ Model/AppModel.swift              state, persistence, actions  ───────────────►  all logic below
├─ Services/CompanionService.swift   canOpenURL / open / getifaddrs
├─ Services/GitHubService.swift      public REST API (+ test mock)
├─ Services/ReminderService.swift    local notifications
├─ Services/Keychain.swift           optional GitHub token
├─ Services/Intents.swift            App Intents: Refresh All, VPN On
└─ Views/…                           Home, Library + IPA detail, GitHub, Expiry,
                                     More (Setup, Settings, Ouija Guard, Support,
                                     Limits, About, hidden NCOM Lab)
```

**DisciplineCore** holds everything that can be tested without a phone, and runs on Linux:

| File | Job |
|---|---|
| `IPAReader.swift`, `Inflate.swift` | Read .ipa files: ZIP central directory, raw DEFLATE, Info.plist (binary or XML), icon, extension count, entitlements inspection |
| `Entitlements.swift` | Entitlements from the Mach-O code signature (thin and fat binaries), usage-description keys |
| `Guard.swift` | Tracker SDK signatures (20), IPA scan, App Privacy Report (.ndjson) summary |
| `CapabilityCatalog.swift` | Ouija Board capability map, signing preset → entitlements plist + Info.plist keys |
| `GitHubReleases.swift` | Parse GitHub links, decode releases, pick the right .ipa, update detection, rate-limit headers |
| `ExpiryTracker.swift` | 7/365-day expiry, warning window, reminder dates, App ID rolling budget |
| `SigningPolicy.swift` | Free vs paid limits and capabilities (from Apple's table) |
| `DeepLinks.swift` | Exact URLs LocalDevVPN, SideStore and LiveContainer handle |
| `TunnelDetector.swift`, `IPv4.swift`, `PeerAddressPlanner.swift`, `PacketReflector.swift` | Detect LocalDevVPN's tunnel; subnet maths; iOS 26.4 in-subnet peer choice; the packet-reflection technique (for a paid-account tunnel, not shipped) |
| `Compatibility.swift`, `SetupPlan.swift` | iOS-version notes and the setup checklist |
| `AltSource.swift` | AltStore/SideStore source JSON |

## Design decisions

1. **Orchestrate, don't fork.** Discipline contains no code from SideStore, LiveContainer, LocalDevVPN or SideInstaller. It talks to them through the URL schemes and document types they publish. That keeps Discipline NCOM's own code (no AGPL obligations, no conflict with SideInstaller's non-commercial license or LocalDevVPN's no-rebranding clause) and lets each upstream app keep updating itself.
2. **Free Apple ID first.** No extension, no restricted entitlement: one App ID, signable by Plume Impactor with a free account. Features that need a paid account are explained in the app, not faked.
3. **Every control does something observable.** Each action ends in a toast whose accessibility value is the exact URL handed to another app, which the UI tests assert.
4. **Test hooks only behind launch arguments** (`-uiTesting…`): fake companions (the simulator has none of the apps), mock GitHub, seeded fixtures. Normal launches never touch them.

## Data

One JSON file in the app's Documents (`discipline-state.json`): tracked apps, saved repos, library index, App ID log, settings. Imported .ipa files live in `Documents/Library/`. Backup/restore uses the same JSON.
