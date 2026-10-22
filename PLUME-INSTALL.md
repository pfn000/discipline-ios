# Install Discipline with Plume Impactor (PC → iPhone)

You need: a Windows PC (with iTunes from Apple installed, or the Apple Devices app) or a Mac/Linux PC, Plume Impactor (https://github.com/claration/impactor/releases), a USB cable, your Apple ID, and the unsigned `Discipline-v0.1.0-unsigned.ipa` (inside the CI run's artifact zip; you must be signed in to GitHub to download it, before 2026-11-05).

> Status 2026-10-22: the unsigned IPA was built by [CI run #8](https://github.com/pfn000/discipline-ios/actions/runs/39819722184) and is attached to that run as the artifact `discipline-39819722184` (until 2026-11-05). SHA-256: `c7062a1fd25af8becf39cda2d45daa11642507b030d263cd9b1373e007b46a36`. It hasn't been installed on a real iPhone or run on iOS 27.2 yet, so these steps are untested with this build. There is no GitHub Release.

1. **Check the file.** Compare its SHA-256 with the `.sha256` file that came with it (it's in the same artifact zip) (PowerShell: `Get-FileHash .\Discipline-v0.1.0-unsigned.ipa`).
2. **Plug in the iPhone** and unlock it. Tap **Trust** and enter your passcode if asked.
3. **Open Plume Impactor** and sign in with your Apple ID, following Plume Impactor's own instructions. Discipline does not ask for your Apple ID password. We have not audited how Plume Impactor handles your credentials.
4. **Drag the .ipa** into Plume Impactor (or choose it), then install. Plume is expected to register the app with Apple, sign it (7 days on a free account, 365 on a paid one) and install it, subject to your Apple account, your device and what Plume currently supports. This IPA has not been installed this way yet.
5. **Developer Mode:** if it is off, turn it on: Settings → Privacy & Security → Developer Mode → On, then restart.
6. **Trust the developer profile:** Settings → General → VPN & Device Management → your Apple ID → Trust.
7. **Open Discipline.** Then do More → Setup: get LocalDevVPN from the App Store and install SideStore + LiveContainer (Plume Impactor offers to install both and generate their pairing file; that companion setup has not been verified with this build).

## Keeping it alive
- Free Apple ID: every app you sign (Discipline included) runs for 7 days. If installing works on your phone, you can re-sign with Plume, or try adding Discipline to SideStore and refreshing it there with LocalDevVPN on. Neither route has been tested with this IPA.
- Putting other apps inside **LiveContainer** means only LiveContainer and SideStore need refreshing, which is how LiveContainer works around the free account's 3-app limit (per LiveContainer's docs; not tested here).

## iOS 27.2 beta notes (reported, not tested on your phone)
- If SideStore shows a UDID or pairing error after an update: update SideStore, generate a new pairing file in Plume Impactor, and import it again (https://github.com/SideStore/SideStore/issues/1217).
- Apple changed the VPN check in iOS 26.4; keep LocalDevVPN updated.
- JIT works only for a short list of apps on iOS 26+ (https://docs.sidestore.io/docs/advanced/jit). Discipline doesn't need JIT.
- Each beta can change this again. After a beta update, More → Setup is a suggested place to re-check; that has not been verified on a beta either.
