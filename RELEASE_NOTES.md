Discipline v0.4.0 (unsigned build)

- Final app icon Discipline-v64C (Icon Composer .icon, Liquid Glass layers) is the app icon.
- 37.6 pt corners on every rounded card and container.
- More visual screens: tinted mesh backdrop under Liquid Glass, stat tiles (Home, Library, GitHub), a signature ring on Home, a days-left chart (Home, Expiry), a sideloading-kit gauge. All earlier features kept.
- Self-update UI test fixture is now v99.0.0, so it stays newer than any real version (CI #26 was red because the app caught up with the old fixture).
- Version 0.4.0 (build 5).

Discipline v0.1.0 (unsigned build; not published as a Release)

What's in it (implemented flows; tested only on an iOS 27.0 simulator with fixtures; the hand-offs to other apps, real downloads and installation are not yet device-tested)
- Home: signature countdown (from the signing date you enter), one-tap start to a refresh (sends LocalDevVPN a link asking it to turn on and open SideStore; finish in SideStore), VPN on/off, status of LocalDevVPN, SideStore and LiveContainer.
- Library: open any .ipa from Files or Safari ("Open in Discipline"), see its name, bundle ID, version, icon and extensions, and hand it to LiveContainer or SideStore.
- GitHub to iOS: paste a repo or release link, list its .ipa files, download, hand off to install, save repos, and tap Check for updates to get badges.
- Expiry: tracked apps, 48/24/2-hour reminders, App ID counter (counted when you confirm an install).
- Backup: settings, tracked apps, saved repos and the App ID log (not the .ipa files). Restoring a backup has not been tested.
- Ouija Guard: tracker SDK scan, App Privacy Report reader.
- NCOM Lab (hidden): entitlements inspector, Ouija Board capability map and signing preset.
- Support page with a tip link. Liquid Glass throughout.

Honest limits
- Unsigned, not installed on a real device yet, not run on iOS 27.2: sign and install it with Plume Impactor and your Apple ID (PLUME-INSTALL.md). Free Apple ID = 7 days, paid = 1 year. Nothing makes it permanent.
- A free account can't sign VPNs, push, Screen Time, NFC. Discipline uses the App Store LocalDevVPN for the tunnel.
- SideStore has no "refresh now" link; Refresh All opens it and you tap Refresh All there.
