# Discipline UI element inventory (for the Liquid Glass markup)

Made Nov 3 2026 for Saidie on branch `discipline-glass-inventory`. Every distinct visual element in the Discipline app
(`App/` + `Shared/DisciplineShape.swift`; the Ouija app is separate and not listed). The numbers match the debug-only
Element Gallery screen (`App/Sources/Views/ElementGallery.swift`, launch argument `-elementGallery`) and its screenshots.

How to read the gallery: **A** = the element as the app draws it today. **B** = the same element with Apple's official
iOS 26 Liquid Glass (`.glassEffect` / `GlassEffectContainer` / `.buttonStyle(.glass)`) added, or, for the elements that
already use official glass, with the glass **removed** (opaque system fill), so either way B shows the other choice.
System UI (tab bar, nav bars, search, sheets, dialogs) is drawn by iOS 26 as Liquid Glass automatically; it is shown once, as it is.

Ember palette pass (Nov 3 2026, branch `discipline-ember-glass`): every colour now comes from `App/Sources/Theme/EmberTheme.swift`,
Saidie's own nine values (orange #E85002; gradient #000000 → #C10801 → #F16001 → #D9C3AB; #333333, #646464, #A7A7A7, #F9F9F9).
No purple, blue, green or gold remains in Discipline's screens. Status colours stay inside the palette: fine = sand (dark) / steel (light),
soon = orange, expired = red.

Status key: glass = official Liquid Glass today · none = no glass today · system = Apple system UI/control · background = the colour glass refracts.

| # | Element | Status today | Source |
|---|---|---|---|
| 1 | Tab bar (Home · Library · Store · Expiry · More) | Apple system UI | App/Sources/DisciplineApp.swift (RootView) |
| 2 | Navigation bar, large title | Apple system UI | HomeView.swift, LibraryView.swift, ExpiryView.swift, MoreView.swift |
| 3 | Navigation bar, inline title + ‹ More back button | Apple system UI | MoreView.swift (MoreNavigationBack), StoreViews.swift (StoreAppDetail) |
| 4 | Toolbar icon buttons (↻ Check status, Sources list) | Apple system UI | HomeView.swift, StoreViews.swift, GitHubView.swift |
| 5 | Segmented picker (Apps | GitHub) | Apple system UI | StoreViews.swift (StoreModePicker) |
| 6 | Search field (“Search apps”) | Apple system UI | StoreViews.swift (StoreBrowseView .searchable) |
| 7 | Sheet with Cancel / Done bar (Track an app, Sources, From link, Scan) | Apple system UI | ExpiryView.swift, StoreViews.swift, LibraryView.swift, OuijaViews.swift |
| 8 | Confirmation dialog (“Delete … from the library?”) | Apple system UI | LibraryView.swift (IPADetailView) |
| 9 | Share sheet, Files picker, Photos picker | Apple system UI | LibraryView.swift, MoreView.swift, LabView.swift, GuardView.swift, OuijaViews.swift |
| 10 | Swipe action (Stop tracking / Delete) | Apple system UI | ExpiryView.swift, LibraryView.swift |
| 11 | Toast banner | official Liquid Glass now | Components.swift (ToastBanner) |
| 12 | Tinted mesh backdrop (behind every screen) | background (not glassable) | Visuals.swift (DisciplineBackdrop) |
| 13 | Magic Ring overlay (reading an NCOM code) | no glass now | OuijaViews.swift (MagicRingView) |
| 14 | Glass card | official Liquid Glass now | Components.swift (GlassCard): Home, IPA detail |
| 15 | Tinted glass card | official Liquid Glass now | Components.swift (GlassCard tinted): Home hero, IPA header, Support |
| 16 | Stat tile | official Liquid Glass now | Visuals.swift (StatTile) |
| 17 | Stat strip (3 tiles that merge) | official Liquid Glass now | Visuals.swift (StatStrip): Home, Library, GitHub |
| 18 | Stat tile icon disc | no glass now (flat Ember disc: it sits inside a glass tile, no glass on glass) | Visuals.swift (StatTile) |
| 19 | Ring gauge (signature time left, glowing gradient ring) | no glass now in the Home hero (inside a glass card); the component keeps an official glass disc option | Visuals.swift (RingGauge): Home hero |
| 20 | Big countdown (“2d 4h left on Delta”) | no glass now | HomeView.swift (expiryHero) |
| 21 | Signatures bar chart | no glass now | Visuals.swift (ExpiryChart): Home, Expiry |
| 22 | Kit gauge (circular 2/3) | no glass now | HomeView.swift (companionsCard) |
| 23 | Companion status disc (✓ / ↓) | no glass now (flat Ember disc inside a glass card) | HomeView.swift (companionsCard) |
| 24 | Companion row (disc, name, role, Open) | no glass now | HomeView.swift (companionsCard) |
| 25 | VPN status line (Loopback VPN ● On + interface) | no glass now | HomeView.swift (vpnCard) |
| 26 | Status dots (green / orange) | no glass now | Components.swift (StatusDot) |
| 27 | App facts strip (Version | Released | Size | iOS) | official Liquid Glass now | StoreViews.swift (StoreAppDetail.facts) |
| 28 | Prominent glass button (Refresh All, Turn on, Import .ipa, Check now) | official Liquid Glass now | HomeView, LibraryView, GitHubView, UpdatesView, MoreView |
| 29 | Glass button (Mark done, Turn off, From link) | official Liquid Glass now | HomeView, LibraryView, ExpiryView, LabView, MoreView |
| 30 | Button pair (orange glass + clear glass, side by side; no longer in a GlassEffectContainer, which drew the glass over the orange button's label) | official Liquid Glass now | HomeView.swift (hero, VPN), LibraryView.swift |
| 31 | Small inline glass buttons (Open, Refreshed, Scan) | official Liquid Glass now | HomeView, ExpiryView, GuardView, MoreView (SetupView) |
| 32 | Sign in with Ouija / NCOM button | official Liquid Glass now | OuijaSignInViews.swift (SignInWithOuijaSection) |
| 33 | Store detail Get button | official Liquid Glass now | StoreViews.swift (StoreAppDetail) |
| 34 | List text button (+ Add app, Check for updates, Edit sources) | no glass now | ExpiryView, GitHubView, StoreViews, LabView |
| 35 | Destructive text button (Sign out, Clear App ID log) | no glass now | OuijaSignInViews.swift, ExpiryView.swift, LibraryView.swift |
| 36 | Version footer (“Discipline 0.5.0”, hidden tap target) | no glass now | MoreView.swift |
| 37 | Category chip | official Liquid Glass now | StoreViews.swift (categoryChips) |
| 38 | Category chip, selected | official Liquid Glass now | StoreViews.swift (categoryChips) |
| 39 | Get pill (store rows) | official Liquid Glass now | StoreViews.swift (StoreRow) |
| 40 | PRE badge (pre-release) | official Liquid Glass now | GitHubView.swift |
| 41 | Update badge | official Liquid Glass now | GitHubView.swift |
| 42 | FEATURED badge (on trending card) | no glass now | StoreViews.swift (TrendingCard) |
| 43 | Capability verdict text (✅ / ⚠️ / ❌) | no glass now | LabView.swift (Capability map) |
| 44 | Trending card (official glass over her black → red → flame → sand gradient) | official Liquid Glass now | StoreViews.swift (TrendingCard) |
| 45 | Store app row | no glass now | StoreViews.swift (StoreRow) |
| 46 | Store app icon (with hairline) | no glass now | StoreViews.swift (StoreIcon) |
| 47 | Library app icon | no glass now | Components.swift (AppIconView) |
| 48 | “Why it's here” lines | no glass now | StoreViews.swift (StoreAppDetail) |
| 49 | Screenshot thumbnail | no glass now | StoreViews.swift (StoreAppDetail) |
| 50 | Source row with verified seal | no glass now | StoreViews.swift (StoreSourcesSheet) |
| 51 | Loading spinners (large / small) | no glass now | StoreViews.swift, GitHubView.swift, UpdatesView.swift |
| 52 | Offline / empty state | no glass now | StoreViews.swift (StoreBrowseView) |
| 53 | Grouped list section (header, rows, footer) | no glass now | every List screen: Library, Expiry, More, Settings, Lab, Guard, Updates |
| 54 | Navigation row with icon (Setup checklist, Settings …) | no glass now | MoreView.swift |
| 55 | Library app row | no glass now | LibraryView.swift |
| 56 | Labeled value row (Size  12.4 MB) | no glass now | LibraryView, MoreView, LabView, UpdatesView |
| 57 | Tracked app row (countdown + Refreshed) | no glass now | ExpiryView.swift |
| 58 | Release asset row (.ipa + Get) | no glass now | GitHubView.swift |
| 59 | Saved repo row (+ Update badge) | no glass now | GitHubView.swift |
| 60 | Setup checklist step row | no glass now | MoreView.swift (SetupView) |
| 61 | Capability map row | no glass now | LabView.swift |
| 62 | Ouija Guard scan row | no glass now | GuardView.swift |
| 63 | Guard result line (✓ No known trackers) | no glass now | GuardView.swift |
| 64 | Signed-in account row | no glass now | OuijaSignInViews.swift (SignInWithOuijaSection) |
| 65 | “Install Ouija to pair” block | no glass now | OuijaSignInViews.swift (SignInWithOuijaSection) |
| 66 | Toggle row (Auto refresh, Check automatically) | Apple system UI | ExpiryView, UpdatesView, MoreView (Settings), LabView |
| 67 | Glowing gradient progress bar (App IDs 3/10; also the Home hero) | official Liquid Glass now (capsule) | Theme/EmberTheme.swift (EmberProgressBar): ExpiryView.swift, HomeView.swift |
| 68 | Menu picker (Appearance, Glass tint, Apple account, Send to) | Apple system UI | MoreView.swift (Settings), LibraryView.swift, LabView.swift |
| 69 | Text field (App name, repo, source URL) | Apple system UI | ExpiryView, GitHubView, StoreViews, LibraryView, LabView, MoreView |
| 70 | Secure field (GitHub token) | Apple system UI | MoreView.swift (Settings) |
| 71 | Date picker (Signed / refreshed) | Apple system UI | ExpiryView.swift (AddTrackedAppSheet) |
| 72 | QR camera frame (Scan NCOM code sheet) | no glass now | OuijaViews.swift (OuijaScannerSheet) |

Totals: 72 elements: 20 already official glass, 36 without glass, 15 Apple system UI/controls, 1 background.

## Not in this list, and why

- **ID / smart card**: Discipline has none. The ID card (and its reveal) lives in the Ouija app (`Ouija/`), which this pass leaves alone.
- **Widgets and Dynamic Island / Live Activity**: Discipline ships no widget extension or Live Activity; the Island screens belong to Ouija (`OuijaWidgets/`, `Shared/OuijaSignInActivity.swift`).
- **Home-screen app icon**: already a layered Liquid Glass icon made in Icon Composer (`App/Resources/AppIcon.icon`); it is drawn by iOS, not by the app's views.
- **Plain body text and section titles**: text is not a surface; it can sit on glass (see the B tiles) but can't be glass itself.
- **App Intents / Shortcuts** (`Services/Intents.swift`): no UI of their own.

## Notes on the gallery copies

- Shared components are the real ones (GlassCard, StatTile, StatStrip, RingGauge, ToastBanner, StatusDot, StoreModePicker, DisciplineBackdrop, MagicRingView).
- Elements that live inline inside a screen (chips, pills, rows, the facts strip, the trending card) are copied with the same modifiers and sample data, because they are private to their screen or need live data (store sources, tracked apps).
- Rows that sit in a grouped List are shown on the List cell colour (A) and on glass in the app's 37.6 pt corner (B).
- The Magic Ring is drawn as one still frame (it animates in the app) and is scaled to 42 % to fit beside its B.
- Everything sits on neutral grey stripes, the same under A and B, so the glass has something to bend; on a flat colour, glass is nearly invisible.
