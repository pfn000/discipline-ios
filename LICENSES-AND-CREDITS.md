# Licenses and credits

Discipline's code is NCOM's own (© NCOM, all rights reserved; the source is public to read since 2026-10-22, with no open-source license granted). It includes **no source code** from the projects below. It works with them through their published URL schemes, document types and file formats.

| Project | License | How Discipline relates |
|---|---|---|
| LocalDevVPN (jkcoxson, SideStore team) | StosVPN License (MIT text + attribution + no rebranding) | Opens it via `localdevvpn://`; `PacketReflector.swift` is an independent re-implementation of the publicly described packet-reflection technique (em_proxy / LocalDevVPN), credited here and in the code |
| SideStore | AGPL-3.0 | Opens it via `sidestore://`, hands it .ipa files through the share sheet |
| LiveContainer | AGPL-3.0 | Opens it via `livecontainer://`, hands it .ipa files |
| SideInstaller (FrizzleM) | Custom non-commercial | Recommended as an official install route only; no code used |
| Plume Impactor (claration) | MIT | The signer Saidie uses; no code used |
| AltStore source format | (format) | Parsed in `AltSource.swift` |

If NCOM ever wants a true single binary (e.g. a fork of LiveContainer+SideStore with Discipline's UI), that fork must be released under AGPL-3.0 with its full source, and it could not include SideInstaller code in a commercial product.

The tracker list in `Guard.swift` is NCOM's own, built from vendors' public framework and class names.
