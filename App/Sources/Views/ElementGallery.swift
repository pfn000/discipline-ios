// Element Gallery (debug builds only; launch argument -elementGallery).
// Saidie, Nov 3 2026: every UI element numbered so she can mark which ones get Apple's official Liquid Glass.
// Generated together with ELEMENT-INVENTORY.md; the numbers match.
#if DEBUG
import SwiftUI
import Charts
import DisciplineCore

// MARK: - Gallery scaffolding

enum GKey { case tabBar, navLargeTitle, navInline, toolbarIcons, segmented, searchField, sheetChrome, confirmDialog, systemSheets, swipeAction, toast, backdrop, magicRing, glassCard, glassCardTinted, statTile, statStrip, statIconDisc, ringGauge, countdown, expiryChart, kitGauge, companionDisc, companionRow, vpnHeader, statusDot, factsStrip, btnProminent, btnGlass, btnPair, btnSmallGlass, btnSignInOuija, btnGetLarge, btnListAction, btnDestructive, versionFooter, chip, chipSelected, getPill, badgePre, badgeUpdate, badgeFeatured, capabilityBadge, trendingCard, storeRow, storeIcon, appIcon, reasonRow, screenshotThumb, sourceRow, spinner, emptyState, listSection, navRow, libraryRow, labeledRow, trackedRow, releaseAssetRow, savedRepoRow, setupStepRow, capabilityRow, guardRow, findingLabel, accountRow, installOuijaBlock, toggle, budgetGauge, menuPicker, textField, secureField, datePicker, cameraFrame }
enum GalleryStatus { case glass, none, system, na }
enum GalleryLayout { case pair, stack, solo, scaled }
enum Variant { case a, b }

struct GalleryItem: Identifiable {
    let id: Int
    let key: GKey
    let name: String
    let file: String
    let status: GalleryStatus
    let layout: GalleryLayout
    var hasB: Bool { layout != .solo }
    var bTitle: String { status == .glass ? "B \u{00B7} GLASS REMOVED" : "B \u{00B7} OFFICIAL GLASS" }
    var statusText: String {
        switch status {
        case .glass: return "NOW: OFFICIAL LIQUID GLASS"
        case .none: return "NOW: NO GLASS"
        case .system: return layout == .solo ? "APPLE SYSTEM UI: GLASS AUTOMATICALLY" : "APPLE SYSTEM CONTROL"
        case .na: return "BACKGROUND: GLASS NEEDS THIS BEHIND IT"
        }
    }
    var statusColor: Color {
        switch status {
        case .glass: return Ember.accentText
        case .none: return Ember.muted
        case .system: return Ember.ok
        case .na: return Ember.muted
        }
    }
}

let galleryItems: [GalleryItem] = [
    GalleryItem(id: 1, key: .tabBar, name: "Tab bar (Home · Library · Store · Expiry · More)", file: "App/Sources/DisciplineApp.swift (RootView)", status: .system, layout: .solo),
    GalleryItem(id: 2, key: .navLargeTitle, name: "Navigation bar, large title", file: "HomeView.swift, LibraryView.swift, ExpiryView.swift, MoreView.swift", status: .system, layout: .solo),
    GalleryItem(id: 3, key: .navInline, name: "Navigation bar, inline title + ‹ More back button", file: "MoreView.swift (MoreNavigationBack), StoreViews.swift (StoreAppDetail)", status: .system, layout: .solo),
    GalleryItem(id: 4, key: .toolbarIcons, name: "Toolbar icon buttons (↻ Check status, Sources list)", file: "HomeView.swift, StoreViews.swift, GitHubView.swift", status: .system, layout: .solo),
    GalleryItem(id: 5, key: .segmented, name: "Segmented picker (Apps | GitHub)", file: "StoreViews.swift (StoreModePicker)", status: .system, layout: .stack),
    GalleryItem(id: 6, key: .searchField, name: "Search field (“Search apps”)", file: "StoreViews.swift (StoreBrowseView .searchable)", status: .system, layout: .solo),
    GalleryItem(id: 7, key: .sheetChrome, name: "Sheet with Cancel / Done bar (Track an app, Sources, From link, Scan)", file: "ExpiryView.swift, StoreViews.swift, LibraryView.swift, OuijaViews.swift", status: .system, layout: .solo),
    GalleryItem(id: 8, key: .confirmDialog, name: "Confirmation dialog (“Delete … from the library?”)", file: "LibraryView.swift (IPADetailView)", status: .system, layout: .solo),
    GalleryItem(id: 9, key: .systemSheets, name: "Share sheet, Files picker, Photos picker", file: "LibraryView.swift, MoreView.swift, LabView.swift, GuardView.swift, OuijaViews.swift", status: .system, layout: .solo),
    GalleryItem(id: 10, key: .swipeAction, name: "Swipe action (Stop tracking / Delete)", file: "ExpiryView.swift, LibraryView.swift", status: .system, layout: .solo),
    GalleryItem(id: 11, key: .toast, name: "Toast banner", file: "Components.swift (ToastBanner)", status: .glass, layout: .stack),
    GalleryItem(id: 12, key: .backdrop, name: "Tinted mesh backdrop (behind every screen)", file: "Visuals.swift (DisciplineBackdrop)", status: .na, layout: .solo),
    GalleryItem(id: 13, key: .magicRing, name: "Magic Ring overlay (reading an NCOM code)", file: "OuijaViews.swift (MagicRingView)", status: .none, layout: .scaled),
    GalleryItem(id: 14, key: .glassCard, name: "Glass card", file: "Components.swift (GlassCard): Home, IPA detail", status: .glass, layout: .stack),
    GalleryItem(id: 15, key: .glassCardTinted, name: "Tinted glass card", file: "Components.swift (GlassCard tinted): Home hero, IPA header, Support", status: .glass, layout: .stack),
    GalleryItem(id: 16, key: .statTile, name: "Stat tile", file: "Visuals.swift (StatTile)", status: .glass, layout: .pair),
    GalleryItem(id: 17, key: .statStrip, name: "Stat strip (3 tiles that merge)", file: "Visuals.swift (StatStrip): Home, Library, GitHub", status: .glass, layout: .stack),
    GalleryItem(id: 18, key: .statIconDisc, name: "Stat tile icon disc", file: "Visuals.swift (StatTile)", status: .none, layout: .pair),
    GalleryItem(id: 19, key: .ringGauge, name: "Ring gauge (signature time left)", file: "Visuals.swift (RingGauge): Home hero", status: .none, layout: .pair),
    GalleryItem(id: 20, key: .countdown, name: "Big countdown (“2d 4h left on Delta”)", file: "HomeView.swift (expiryHero)", status: .none, layout: .pair),
    GalleryItem(id: 21, key: .expiryChart, name: "Signatures bar chart", file: "Visuals.swift (ExpiryChart): Home, Expiry", status: .none, layout: .stack),
    GalleryItem(id: 22, key: .kitGauge, name: "Kit gauge (circular 2/3)", file: "HomeView.swift (companionsCard)", status: .none, layout: .pair),
    GalleryItem(id: 23, key: .companionDisc, name: "Companion status disc (✓ / ↓)", file: "HomeView.swift (companionsCard)", status: .none, layout: .pair),
    GalleryItem(id: 24, key: .companionRow, name: "Companion row (disc, name, role, Open)", file: "HomeView.swift (companionsCard)", status: .none, layout: .stack),
    GalleryItem(id: 25, key: .vpnHeader, name: "VPN status line (Loopback VPN ● On + interface)", file: "HomeView.swift (vpnCard)", status: .none, layout: .stack),
    GalleryItem(id: 26, key: .statusDot, name: "Status dots (green / orange)", file: "Components.swift (StatusDot)", status: .none, layout: .pair),
    GalleryItem(id: 27, key: .factsStrip, name: "App facts strip (Version | Released | Size | iOS)", file: "StoreViews.swift (StoreAppDetail.facts)", status: .glass, layout: .stack),
    GalleryItem(id: 28, key: .btnProminent, name: "Prominent glass button (Refresh All, Turn on, Import .ipa, Check now)", file: "HomeView, LibraryView, GitHubView, UpdatesView, MoreView", status: .glass, layout: .stack),
    GalleryItem(id: 29, key: .btnGlass, name: "Glass button (Mark done, Turn off, From link)", file: "HomeView, LibraryView, ExpiryView, LabView, MoreView", status: .glass, layout: .stack),
    GalleryItem(id: 30, key: .btnPair, name: "Button pair that merges (GlassEffectContainer)", file: "HomeView.swift (hero, VPN), LibraryView.swift", status: .glass, layout: .stack),
    GalleryItem(id: 31, key: .btnSmallGlass, name: "Small inline glass buttons (Open, Refreshed, Scan)", file: "HomeView, ExpiryView, GuardView, MoreView (SetupView)", status: .glass, layout: .stack),
    GalleryItem(id: 32, key: .btnSignInOuija, name: "Sign in with Ouija / NCOM button", file: "OuijaSignInViews.swift (SignInWithOuijaSection)", status: .glass, layout: .stack),
    GalleryItem(id: 33, key: .btnGetLarge, name: "Store detail Get button", file: "StoreViews.swift (StoreAppDetail)", status: .glass, layout: .pair),
    GalleryItem(id: 34, key: .btnListAction, name: "List text button (+ Add app, Check for updates, Edit sources)", file: "ExpiryView, GitHubView, StoreViews, LabView", status: .none, layout: .pair),
    GalleryItem(id: 35, key: .btnDestructive, name: "Destructive text button (Sign out, Clear App ID log)", file: "OuijaSignInViews.swift, ExpiryView.swift, LibraryView.swift", status: .none, layout: .pair),
    GalleryItem(id: 36, key: .versionFooter, name: "Version footer (“Discipline 0.5.0”, hidden tap target)", file: "MoreView.swift", status: .none, layout: .pair),
    GalleryItem(id: 37, key: .chip, name: "Category chip", file: "StoreViews.swift (categoryChips)", status: .glass, layout: .pair),
    GalleryItem(id: 38, key: .chipSelected, name: "Category chip, selected", file: "StoreViews.swift (categoryChips)", status: .glass, layout: .pair),
    GalleryItem(id: 39, key: .getPill, name: "Get pill (store rows)", file: "StoreViews.swift (StoreRow)", status: .glass, layout: .pair),
    GalleryItem(id: 40, key: .badgePre, name: "PRE badge (pre-release)", file: "GitHubView.swift", status: .glass, layout: .pair),
    GalleryItem(id: 41, key: .badgeUpdate, name: "Update badge", file: "GitHubView.swift", status: .glass, layout: .pair),
    GalleryItem(id: 42, key: .badgeFeatured, name: "FEATURED badge (on trending card)", file: "StoreViews.swift (TrendingCard)", status: .none, layout: .pair),
    GalleryItem(id: 43, key: .capabilityBadge, name: "Capability verdict text (✅ / ⚠️ / ❌)", file: "LabView.swift (Capability map)", status: .none, layout: .stack),
    GalleryItem(id: 44, key: .trendingCard, name: "Trending card (glass over her gradient)", file: "StoreViews.swift (TrendingCard)", status: .glass, layout: .stack),
    GalleryItem(id: 45, key: .storeRow, name: "Store app row", file: "StoreViews.swift (StoreRow)", status: .none, layout: .stack),
    GalleryItem(id: 46, key: .storeIcon, name: "Store app icon (with hairline)", file: "StoreViews.swift (StoreIcon)", status: .none, layout: .pair),
    GalleryItem(id: 47, key: .appIcon, name: "Library app icon", file: "Components.swift (AppIconView)", status: .none, layout: .pair),
    GalleryItem(id: 48, key: .reasonRow, name: "“Why it's here” lines", file: "StoreViews.swift (StoreAppDetail)", status: .none, layout: .stack),
    GalleryItem(id: 49, key: .screenshotThumb, name: "Screenshot thumbnail", file: "StoreViews.swift (StoreAppDetail)", status: .none, layout: .pair),
    GalleryItem(id: 50, key: .sourceRow, name: "Source row with verified seal", file: "StoreViews.swift (StoreSourcesSheet)", status: .none, layout: .stack),
    GalleryItem(id: 51, key: .spinner, name: "Loading spinners (large / small)", file: "StoreViews.swift, GitHubView.swift, UpdatesView.swift", status: .none, layout: .pair),
    GalleryItem(id: 52, key: .emptyState, name: "Offline / empty state", file: "StoreViews.swift (StoreBrowseView)", status: .none, layout: .stack),
    GalleryItem(id: 53, key: .listSection, name: "Grouped list section (header, rows, footer)", file: "every List screen: Library, Expiry, More, Settings, Lab, Guard, Updates", status: .none, layout: .stack),
    GalleryItem(id: 54, key: .navRow, name: "Navigation row with icon (Setup checklist, Settings …)", file: "MoreView.swift", status: .none, layout: .stack),
    GalleryItem(id: 55, key: .libraryRow, name: "Library app row", file: "LibraryView.swift", status: .none, layout: .stack),
    GalleryItem(id: 56, key: .labeledRow, name: "Labeled value row (Size  12.4 MB)", file: "LibraryView, MoreView, LabView, UpdatesView", status: .none, layout: .stack),
    GalleryItem(id: 57, key: .trackedRow, name: "Tracked app row (countdown + Refreshed)", file: "ExpiryView.swift", status: .none, layout: .stack),
    GalleryItem(id: 58, key: .releaseAssetRow, name: "Release asset row (.ipa + Get)", file: "GitHubView.swift", status: .none, layout: .stack),
    GalleryItem(id: 59, key: .savedRepoRow, name: "Saved repo row (+ Update badge)", file: "GitHubView.swift", status: .none, layout: .stack),
    GalleryItem(id: 60, key: .setupStepRow, name: "Setup checklist step row", file: "MoreView.swift (SetupView)", status: .none, layout: .stack),
    GalleryItem(id: 61, key: .capabilityRow, name: "Capability map row", file: "LabView.swift", status: .none, layout: .stack),
    GalleryItem(id: 62, key: .guardRow, name: "Ouija Guard scan row", file: "GuardView.swift", status: .none, layout: .stack),
    GalleryItem(id: 63, key: .findingLabel, name: "Guard result line (✓ No known trackers)", file: "GuardView.swift", status: .none, layout: .stack),
    GalleryItem(id: 64, key: .accountRow, name: "Signed-in account row", file: "OuijaSignInViews.swift (SignInWithOuijaSection)", status: .none, layout: .stack),
    GalleryItem(id: 65, key: .installOuijaBlock, name: "“Install Ouija to pair” block", file: "OuijaSignInViews.swift (SignInWithOuijaSection)", status: .none, layout: .stack),
    GalleryItem(id: 66, key: .toggle, name: "Toggle row (Auto refresh, Check automatically)", file: "ExpiryView, UpdatesView, MoreView (Settings), LabView", status: .system, layout: .stack),
    GalleryItem(id: 67, key: .budgetGauge, name: "Glowing gradient progress bar (App IDs 3/10, Home hero)", file: "Theme/EmberTheme.swift (EmberProgressBar): ExpiryView, HomeView", status: .glass, layout: .stack),
    GalleryItem(id: 68, key: .menuPicker, name: "Menu picker (Appearance, Glass tint, Apple account, Send to)", file: "MoreView.swift (Settings), LibraryView.swift, LabView.swift", status: .system, layout: .stack),
    GalleryItem(id: 69, key: .textField, name: "Text field (App name, repo, source URL)", file: "ExpiryView, GitHubView, StoreViews, LibraryView, LabView, MoreView", status: .system, layout: .stack),
    GalleryItem(id: 70, key: .secureField, name: "Secure field (GitHub token)", file: "MoreView.swift (Settings)", status: .system, layout: .stack),
    GalleryItem(id: 71, key: .datePicker, name: "Date picker (Signed / refreshed)", file: "ExpiryView.swift (AddTrackedAppSheet)", status: .system, layout: .stack),
    GalleryItem(id: 72, key: .cameraFrame, name: "QR camera frame (Scan NCOM code sheet)", file: "OuijaViews.swift (OuijaScannerSheet)", status: .none, layout: .pair)
]

enum GalleryColors {
    static func page(_ s: ColorScheme) -> Color { s == .dark ? Ember.black : Ember.studio }
    static func stripeA(_ s: ColorScheme) -> Color { s == .dark ? Ember.charcoal.opacity(0.45) : Ember.silver.opacity(0.22) }
    static func stripeB(_ s: ColorScheme) -> Color { s == .dark ? Ember.charcoal.opacity(0.75) : Ember.silver.opacity(0.38) }
    /// The non-glass surface used for "glass removed" (an opaque system fill, not a blur).
    static let flat = Ember.surface
}

/// Neutral grey diagonal stripes behind each specimen, the same under A and B, so glass has something to bend.
struct GalleryPad: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(GalleryColors.stripeA(scheme)))
            let step: CGFloat = 18
            var x: CGFloat = -size.height
            while x < size.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                p.addLine(to: CGPoint(x: x + size.height + step / 2, y: 0))
                p.addLine(to: CGPoint(x: x + step / 2, y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(GalleryColors.stripeB(scheme)))
                x += step
            }
        }
        .accessibilityHidden(true)
    }
}

struct SystemNote: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Ember.accentText)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GalleryColors.flat, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

/// GlassCard's exact layout with an opaque fill instead of glassEffect.
struct FlatCard<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    GalleryColors.flat
                    if let tint { tint.opacity(0.25) }
                }
                .clipShape(.rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
            }
    }
}

/// StatTile's exact layout with opaque fills instead of glassEffect.
struct FlatStatTile: View {
    let value: String
    let label: String
    let systemImage: String
    var tint: Color = Ember.accentText
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage).font(.headline).foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.22), in: .circle)
            Text(value).font(.title2.weight(.bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GalleryColors.flat, in: .rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
    }
}

/// RingGauge's exact drawing on an opaque disc instead of a glass disc.
struct FlatRingGauge: View {
    let progress: Double
    let tint: Color
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: 11)
            Circle().trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: [tint.opacity(0.55), tint], center: .center),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "timer").font(.title.weight(.semibold)).foregroundStyle(tint)
        }
        .frame(width: 96, height: 96)
        .padding(10)
        .background { Circle().fill(GalleryColors.flat).overlay(Circle().fill(tint.opacity(0.14))) }
    }
}

/// ExpiryChart's exact marks with three sample apps (the real chart reads the tracked apps).
struct GalleryChart: View {
    private struct Row: Identifiable { let id: String; let days: Double; let color: Color; let text: String }
    private let rows = [Row(id: "Delta", days: 5.1, color: Ember.ok, text: "5d 3h"),
                        Row(id: "Provenance", days: 1.1, color: Ember.warn, text: "1d 2h"),
                        Row(id: "uYou", days: 0, color: Ember.bad, text: "Expired")]
    var body: some View {
        Chart(rows) { r in
            BarMark(x: .value("Days left", r.days), y: .value("App", r.id))
                .foregroundStyle(r.color.gradient)
                .cornerRadius(8)
                .annotation(position: .trailing) { Text(r.text).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .chartXScale(domain: 0...7)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .padding(.trailing, 36)
        .frame(height: 3 * 36 + 30)
    }
}

/// StoreAppDetail.facts with sample values.
struct GalleryFacts: View {
    let glass: Bool
    var body: some View {
        let strip = HStack(spacing: 0) {
            fact("Version", "1.6.3"); Divider().frame(height: 34)
            fact("Released", "Oct 28"); Divider().frame(height: 34)
            fact("Size", "38 MB"); Divider().frame(height: 34)
            fact("iOS", "15.0")
        }
        .padding(.vertical, 12)
        if glass { strip.glassEffect(.regular, in: RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous)) }
        else { strip.background(GalleryColors.flat, in: RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous)) }
    }
    private func fact(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The Store's category chip (its modifiers copied from StoreBrowseView.chip).
struct GalleryChip: View {
    let title: String
    let selected: Bool
    let glass: Bool
    var body: some View {
        let label = Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(selected ? Ember.onAccent : Color.primary)
            .background(selected ? AnyShapeStyle(Ember.accent) : AnyShapeStyle(Color.clear), in: Capsule())
        if glass { label.glassEffect(selected ? .regular.tint(Ember.accent) : .regular, in: Capsule()) }
        else { label.background(GalleryColors.flat, in: Capsule()) }
    }
}

/// TrendingCard's exact layout with sample values; B swaps the artwork gradient for tinted glass.
struct GalleryTrendingCard: View {
    let glass: Bool
    var body: some View {
        let content = VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                GalleryIcon(size: 64, colors: [Ember.flame, Ember.red], symbol: "gamecontroller.fill", hairline: true)
                Spacer()
                Text("FEATURED").font(.caption2.weight(.bold)).tracking(0.8)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Ember.black.opacity(0.45), in: Capsule())
            }
            Spacer(minLength: 0)
            Text("Delta").font(.title3.bold()).lineLimit(1)
            Text("The all-in-one game emulator").font(.subheadline).lineLimit(2).opacity(0.85)
            Text("Featured \u{00B7} Updated this week").font(.caption.weight(.medium)).lineLimit(1).opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(width: 290, height: 220, alignment: .topLeading)
        let shape = RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous)
        if glass {
            content.glassEffect(.regular.tint(Ember.black.opacity(0.18)), in: shape)
                .background(Ember.heroGradient, in: shape)
                .environment(\.colorScheme, .dark)
                .clipShape(shape)
        } else {
            content
                .background(Ember.heroGradient, in: shape)
                .clipShape(shape)
        }
    }
}

/// A sample app icon drawn with the app's icon shape (0.225 corner, continuous) and optional hairline (StoreIcon).
struct GalleryIcon: View {
    let size: CGFloat
    let colors: [Color]
    let symbol: String
    var hairline = false
    var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay {
                if hairline { RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(.primary.opacity(0.08)) }
            }
    }
}

extension View {
    /// The same label on an opaque capsule: what a glass button looks like without glass.
    func flatButton(prominent: Bool, tint: Color) -> some View {
        self.font(.body.weight(.medium))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(prominent ? Ember.onAccent : Color.primary)
            .background(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(GalleryColors.flat), in: .capsule)
    }
}

/// Debug-only screen (launch argument -elementGallery): every Discipline UI element, numbered, A as now and B with
/// official Liquid Glass added (or, for elements that already use it, removed). Pages advance with the top-right
/// button so the UI test can photograph each screenful without cutting an element in half.
struct ElementGalleryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var frames: [Int: CGRect] = [:]
    @State private var viewport: CGFloat = 0
    @State private var topIndex = 0
    @State private var page = 1

    private var nextIndex: Int {
        guard let top = frames[galleryItems[topIndex].id] else { return topIndex + 1 }
        var j = topIndex
        while j < galleryItems.count, let f = frames[galleryItems[j].id], f.maxY - top.minY <= viewport - 6 { j += 1 }
        return max(j, topIndex + 1)
    }
    private var isLastPage: Bool { nextIndex >= galleryItems.count }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header(proxy)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(galleryItems) { item in
                            GalleryRow(item: item, a: element(item.key, .a), b: item.hasB ? element(item.key, .b) : nil)
                                .containerRelativeFrame(.horizontal)   // never wider than the screen (a wide control would shift every row)
                                .id(item.id)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("galleryContent")) } action: { frames[item.id] = $0 }
                        }
                        Color.clear.frame(height: max(viewport, 400))
                    }
                    .coordinateSpace(.named("galleryContent"))
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
            }
            .background(GalleryColors.page(scheme).ignoresSafeArea())
        }
    }

    private func header(_ proxy: ScrollViewProxy) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DISCIPLINE \u{00B7} EVERY UI ELEMENT \u{00B7} \(scheme == .dark ? "DARK" : "LIGHT")")
                    .font(.caption.weight(.heavy))
                Text("A = as it is now   B = official Liquid Glass (or glass removed)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if isLastPage { Text("END").font(.caption.weight(.heavy)).accessibilityIdentifier("gallery.done") }
            Text("p\(page)").font(.caption.weight(.heavy).monospacedDigit()).accessibilityIdentifier("gallery.page")
            Button {
                let n = nextIndex
                guard n < galleryItems.count else { return }
                topIndex = n
                page += 1
                proxy.scrollTo(galleryItems[n].id, anchor: .top)
            } label: { Image(systemName: "chevron.right").font(.caption.weight(.bold)).padding(6) }
            .buttonStyle(.glass)
            .accessibilityIdentifier("gallery.next")
            .accessibilityValue(isLastPage ? "end" : "more")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(GalleryColors.page(scheme))
    }

    private func companionDisc(ok: Bool, glass: Bool) -> some View {
        let c: Color = ok ? Ember.ok : Ember.warn
        let icon = Image(systemName: ok ? "checkmark" : "arrow.down").font(.subheadline.weight(.bold)).foregroundStyle(c)
            .frame(width: 34, height: 34)
        return Group {
            if glass { icon.glassEffect(.regular.tint(c.opacity(0.22)), in: .circle) }
            else { icon.background(c.opacity(0.22), in: .circle) }
        }
    }

    /// A list row as it sits in its grouped List (on the system cell colour).
    private func cellRow(_ row: some View) -> some View {
        row.padding(.horizontal, 16).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GalleryColors.flat, in: .rect(cornerRadius: 26, style: .continuous))
    }
    /// The same row on official glass, in the app's 37.6 pt corner.
    private func glassRow(_ row: some View) -> some View {
        row.padding(.horizontal, 16).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
    }

    func element(_ key: GKey, _ v: Variant) -> AnyView {
        let b = (v == .b), t = model.settings.tint.color
        switch key {
        case .tabBar: return AnyView(e_tabBar(b, t))
        case .navLargeTitle: return AnyView(e_navLargeTitle(b, t))
        case .navInline: return AnyView(e_navInline(b, t))
        case .toolbarIcons: return AnyView(e_toolbarIcons(b, t))
        case .segmented: return AnyView(e_segmented(b, t))
        case .searchField: return AnyView(e_searchField(b, t))
        case .sheetChrome: return AnyView(e_sheetChrome(b, t))
        case .confirmDialog: return AnyView(e_confirmDialog(b, t))
        case .systemSheets: return AnyView(e_systemSheets(b, t))
        case .swipeAction: return AnyView(e_swipeAction(b, t))
        case .toast: return AnyView(e_toast(b, t))
        case .backdrop: return AnyView(e_backdrop(b, t))
        case .magicRing: return AnyView(e_magicRing(b, t))
        case .glassCard: return AnyView(e_glassCard(b, t))
        case .glassCardTinted: return AnyView(e_glassCardTinted(b, t))
        case .statTile: return AnyView(e_statTile(b, t))
        case .statStrip: return AnyView(e_statStrip(b, t))
        case .statIconDisc: return AnyView(e_statIconDisc(b, t))
        case .ringGauge: return AnyView(e_ringGauge(b, t))
        case .countdown: return AnyView(e_countdown(b, t))
        case .expiryChart: return AnyView(e_expiryChart(b, t))
        case .kitGauge: return AnyView(e_kitGauge(b, t))
        case .companionDisc: return AnyView(e_companionDisc(b, t))
        case .companionRow: return AnyView(e_companionRow(b, t))
        case .vpnHeader: return AnyView(e_vpnHeader(b, t))
        case .statusDot: return AnyView(e_statusDot(b, t))
        case .factsStrip: return AnyView(e_factsStrip(b, t))
        case .btnProminent: return AnyView(e_btnProminent(b, t))
        case .btnGlass: return AnyView(e_btnGlass(b, t))
        case .btnPair: return AnyView(e_btnPair(b, t))
        case .btnSmallGlass: return AnyView(e_btnSmallGlass(b, t))
        case .btnSignInOuija: return AnyView(e_btnSignInOuija(b, t))
        case .btnGetLarge: return AnyView(e_btnGetLarge(b, t))
        case .btnListAction: return AnyView(e_btnListAction(b, t))
        case .btnDestructive: return AnyView(e_btnDestructive(b, t))
        case .versionFooter: return AnyView(e_versionFooter(b, t))
        case .chip: return AnyView(e_chip(b, t))
        case .chipSelected: return AnyView(e_chipSelected(b, t))
        case .getPill: return AnyView(e_getPill(b, t))
        case .badgePre: return AnyView(e_badgePre(b, t))
        case .badgeUpdate: return AnyView(e_badgeUpdate(b, t))
        case .badgeFeatured: return AnyView(e_badgeFeatured(b, t))
        case .capabilityBadge: return AnyView(e_capabilityBadge(b, t))
        case .trendingCard: return AnyView(e_trendingCard(b, t))
        case .storeRow: return AnyView(e_storeRow(b, t))
        case .storeIcon: return AnyView(e_storeIcon(b, t))
        case .appIcon: return AnyView(e_appIcon(b, t))
        case .reasonRow: return AnyView(e_reasonRow(b, t))
        case .screenshotThumb: return AnyView(e_screenshotThumb(b, t))
        case .sourceRow: return AnyView(e_sourceRow(b, t))
        case .spinner: return AnyView(e_spinner(b, t))
        case .emptyState: return AnyView(e_emptyState(b, t))
        case .listSection: return AnyView(e_listSection(b, t))
        case .navRow: return AnyView(e_navRow(b, t))
        case .libraryRow: return AnyView(e_libraryRow(b, t))
        case .labeledRow: return AnyView(e_labeledRow(b, t))
        case .trackedRow: return AnyView(e_trackedRow(b, t))
        case .releaseAssetRow: return AnyView(e_releaseAssetRow(b, t))
        case .savedRepoRow: return AnyView(e_savedRepoRow(b, t))
        case .setupStepRow: return AnyView(e_setupStepRow(b, t))
        case .capabilityRow: return AnyView(e_capabilityRow(b, t))
        case .guardRow: return AnyView(e_guardRow(b, t))
        case .findingLabel: return AnyView(e_findingLabel(b, t))
        case .accountRow: return AnyView(e_accountRow(b, t))
        case .installOuijaBlock: return AnyView(e_installOuijaBlock(b, t))
        case .toggle: return AnyView(e_toggle(b, t))
        case .budgetGauge: return AnyView(e_budgetGauge(b, t))
        case .menuPicker: return AnyView(e_menuPicker(b, t))
        case .textField: return AnyView(e_textField(b, t))
        case .secureField: return AnyView(e_secureField(b, t))
        case .datePicker: return AnyView(e_datePicker(b, t))
        case .cameraFrame: return AnyView(e_cameraFrame(b, t))
        }
    }

    @ViewBuilder private func e_tabBar(_ b: Bool, _ t: Color) -> some View {
        TabView {
            Tab("Home", systemImage: "shield.lefthalf.filled") { GalleryPad() }
            Tab("Library", systemImage: "shippingbox") { GalleryPad() }
            Tab("Store", systemImage: "bag.fill") { GalleryPad() }
            Tab("Expiry", systemImage: "timer") { GalleryPad() }
            Tab("More", systemImage: "ellipsis.circle") { GalleryPad() }
        }
        .tint(t)
        .frame(height: 150)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder private func e_navLargeTitle(_ b: Bool, _ t: Color) -> some View {
        NavigationStack {
            GalleryPad()
                .navigationTitle("Discipline")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {} label: { Label("Check status", systemImage: "arrow.clockwise") }
                    }
                }
        }
        .frame(height: 170)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder private func e_navInline(_ b: Bool, _ t: Color) -> some View {
        NavigationStack {
            GalleryPad()
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {} label: { Label("More", systemImage: "chevron.left") }
                    }
                }
        }
        .frame(height: 120)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder private func e_toolbarIcons(_ b: Bool, _ t: Color) -> some View {
        NavigationStack {
            GalleryPad()
                .navigationTitle("Store")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {} label: { Label("Check status", systemImage: "arrow.clockwise") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {} label: { Image(systemName: "list.bullet.rectangle") }
                    }
                }
        }
        .frame(height: 120)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder private func e_segmented(_ b: Bool, _ t: Color) -> some View {
        if b { StoreModePicker().padding(8).glassEffect(.regular, in: .capsule) } else { StoreModePicker() }
    }

    @ViewBuilder private func e_searchField(_ b: Bool, _ t: Color) -> some View {
        NavigationStack {
            GalleryPad()
                .navigationTitle("Store")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: .constant(""), prompt: "Search apps")
        }
        .frame(height: 200)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder private func e_sheetChrome(_ b: Bool, _ t: Color) -> some View {
        NavigationStack {
            Form {
                TextField("App name", text: .constant(""))
                TextField("Bundle ID (optional)", text: .constant(""))
            }
            .navigationTitle("Track an app")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") {} }
                ToolbarItem(placement: .confirmationAction) { Button("Add") {} }
            }
        }
        .frame(height: 230)
        .clipShape(.rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
    }

    @ViewBuilder private func e_confirmDialog(_ b: Bool, _ t: Color) -> some View {
        SystemNote(symbol: "rectangle.bottomthird.inset.filled",
                   text: "Apple's own action sheet (\u{201C}Delete Delta from the library?\u{201D} \u{00B7} Delete \u{00B7} Cancel). iOS 26 draws it as Liquid Glass; apps can't restyle it.")
    }

    @ViewBuilder private func e_systemSheets(_ b: Bool, _ t: Color) -> some View {
        SystemNote(symbol: "square.and.arrow.up",
                   text: "Share sheet, Files picker and Photos picker belong to iOS. They are already Liquid Glass and can't be restyled by Discipline.")
    }

    @ViewBuilder private func e_swipeAction(_ b: Bool, _ t: Color) -> some View {
        SystemNote(symbol: "hand.draw",
                   text: "Swiping a row left shows Apple's red \u{201C}Stop tracking\u{201D} / \u{201C}Delete\u{201D} button. Apple draws it; it can be recoloured but not made glass.")
    }

    @ViewBuilder private func e_toast(_ b: Bool, _ t: Color) -> some View {
        if b {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Ember.ok)
                Text("Status updated").font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(GalleryColors.flat, in: .capsule)
        } else {
            ToastBanner(toast: AppModel.Toast(text: "Status updated", detail: "", isError: false))
        }
    }

    @ViewBuilder private func e_backdrop(_ b: Bool, _ t: Color) -> some View {
        DisciplineBackdrop()
            .frame(height: 170)
            .clipShape(.rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
    }

    @ViewBuilder private func e_magicRing(_ b: Bool, _ t: Color) -> some View {
        MagicRingView(state: AppModel.MagicRingState(accepted: true, message: "Signed in as NCOM"),
                      onFinish: {}, frozenAt: 1.4, glassPanel: b)
            .frame(width: 360, height: 480)
            .clipShape(.rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
    }

    @ViewBuilder private func e_glassCard(_ b: Bool, _ t: Color) -> some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            Text("Signatures at a glance").font(.headline)
            Text("3 apps tracked \u{00B7} soonest in 2d 4h").font(.subheadline).foregroundStyle(.secondary)
        }
        if b { FlatCard { content } } else { GlassCard { content } }
    }

    @ViewBuilder private func e_glassCardTinted(_ b: Bool, _ t: Color) -> some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            Text("Never let an app expire").font(.headline)
            Text("Refresh All turns on LocalDevVPN, which then opens SideStore.").font(.caption).foregroundStyle(.secondary)
        }
        if b { FlatCard(tint: t) { content } } else { GlassCard(tinted: true) { content } }
    }

    @ViewBuilder private func e_statTile(_ b: Bool, _ t: Color) -> some View {
        if b { FlatStatTile(value: "3", label: "Tracked", systemImage: "timer", tint: t) }
        else { StatTile(value: "3", label: "Tracked", systemImage: "timer", tint: t, id: "gallery.stat") }
    }

    @ViewBuilder private func e_statStrip(_ b: Bool, _ t: Color) -> some View {
        if b {
            HStack(spacing: 10) {
                FlatStatTile(value: "3", label: "Tracked", systemImage: "timer", tint: t)
                FlatStatTile(value: "5", label: "In Library", systemImage: "shippingbox", tint: Ember.muted)
                FlatStatTile(value: "1", label: "Updates", systemImage: "arrow.down.app", tint: Ember.ok)
            }
        } else {
            StatStrip {
                StatTile(value: "3", label: "Tracked", systemImage: "timer", tint: t, id: "gallery.strip.1")
                StatTile(value: "5", label: "In Library", systemImage: "shippingbox", tint: Ember.muted, id: "gallery.strip.2")
                StatTile(value: "1", label: "Updates", systemImage: "arrow.down.app", tint: Ember.ok, id: "gallery.strip.3")
            }
        }
    }

    @ViewBuilder private func e_statIconDisc(_ b: Bool, _ t: Color) -> some View {
        let icon = Image(systemName: "timer").font(.headline).foregroundStyle(t).frame(width: 32, height: 32)
        if b { icon.glassEffect(.regular.tint(t.opacity(0.22)), in: .circle) }
        else { icon.background(t.opacity(0.16), in: .circle) }
    }

    @ViewBuilder private func e_ringGauge(_ b: Bool, _ t: Color) -> some View {
        RingGauge(progress: 0.62, tint: Ember.ok, glass: b) {
            Image(systemName: "timer").font(.title.weight(.semibold)).foregroundStyle(Ember.accentText)
        }
    }

    @ViewBuilder private func e_countdown(_ b: Bool, _ t: Color) -> some View {
        let content = VStack(alignment: .leading, spacing: 2) {
            Text("2d 4h").font(.system(size: 44, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.5)
            Text("left on Delta").foregroundStyle(.secondary)
        }
        if b { content.padding(14).glassEffect(.regular, in: .rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous)) }
        else { content }
    }

    @ViewBuilder private func e_expiryChart(_ b: Bool, _ t: Color) -> some View {
        if b { GalleryChart().padding(16).glassEffect(.regular, in: .rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous)) }
        else { GalleryChart() }
    }

    @ViewBuilder private func e_kitGauge(_ b: Bool, _ t: Color) -> some View {
        let g = Gauge(value: 2, in: 0...3) { EmptyView() } currentValueLabel: { Text("2/3").font(.caption2.bold()) }
            .gaugeStyle(.accessoryCircularCapacity).tint(t).scaleEffect(0.8)
        if b { g.padding(6).glassEffect(.regular, in: .circle) } else { g }
    }

    @ViewBuilder private func e_companionDisc(_ b: Bool, _ t: Color) -> some View {
        HStack(spacing: 14) {
            companionDisc(ok: true, glass: b)
            companionDisc(ok: false, glass: b)
        }
    }

    @ViewBuilder private func e_companionRow(_ b: Bool, _ t: Color) -> some View {
        let row = HStack(spacing: 12) {
            companionDisc(ok: true, glass: false)
            VStack(alignment: .leading, spacing: 2) {
                Text("SideStore").font(.subheadline.weight(.semibold))
                Text("Signs and refreshes your apps").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") {}.buttonStyle(.glass)
        }
        if b { row.padding(14).glassEffect(.regular, in: .rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous)) }
        else { row }
    }

    @ViewBuilder private func e_vpnHeader(_ b: Bool, _ t: Color) -> some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Loopback VPN").font(.headline)
                Spacer()
                StatusDot(ok: true)
                Text("On").font(.subheadline)
            }
            Text("utun4 \u{00B7} 10.7.0.1").font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        if b { content.padding(14).glassEffect(.regular, in: .rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous)) }
        else { content }
    }

    @ViewBuilder private func e_statusDot(_ b: Bool, _ t: Color) -> some View {
        let dots = HStack(spacing: 12) { StatusDot(ok: true); StatusDot(ok: false) }
        if b { dots.padding(12).glassEffect(.regular, in: .capsule) } else { dots }
    }

    @ViewBuilder private func e_factsStrip(_ b: Bool, _ t: Color) -> some View {
        GalleryFacts(glass: !b)
    }

    @ViewBuilder private func e_btnProminent(_ b: Bool, _ t: Color) -> some View {
        if b { Label("Refresh All", systemImage: "arrow.triangle.2.circlepath").flatButton(prominent: true, tint: t) }
        else { Button {} label: { Label("Refresh All", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(.emberProminent) }
    }

    @ViewBuilder private func e_btnGlass(_ b: Bool, _ t: Color) -> some View {
        if b { Label("Mark done", systemImage: "checkmark").flatButton(prominent: false, tint: t) }
        else { Button {} label: { Label("Mark done", systemImage: "checkmark") }.buttonStyle(.glass) }
    }

    @ViewBuilder private func e_btnPair(_ b: Bool, _ t: Color) -> some View {
        if b {
            HStack(spacing: 12) {
                Label("Turn on", systemImage: "bolt.horizontal.circle").frame(maxWidth: .infinity).flatButton(prominent: true, tint: t)
                Label("Turn off", systemImage: "bolt.slash").frame(maxWidth: .infinity).flatButton(prominent: false, tint: t)
            }
        } else {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {} label: { Label("Turn on", systemImage: "bolt.horizontal.circle").frame(maxWidth: .infinity) }
                        .buttonStyle(.emberProminent)
                    Button {} label: { Label("Turn off", systemImage: "bolt.slash").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass)
                }
            }
        }
    }

    @ViewBuilder private func e_btnSmallGlass(_ b: Bool, _ t: Color) -> some View {
        if b {
            HStack(spacing: 8) { Text("Open").flatButton(prominent: false, tint: t); Text("Scan").flatButton(prominent: false, tint: t) }
        } else {
            HStack(spacing: 8) { Button("Open") {}.buttonStyle(.glass); Button("Scan") {}.buttonStyle(.glass) }
        }
    }

    @ViewBuilder private func e_btnSignInOuija(_ b: Bool, _ t: Color) -> some View {
        let label = Label("Sign in with Ouija / NCOM", systemImage: "person.badge.key.fill")
            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
        if b { label.flatButton(prominent: true, tint: t) }
        else { Button {} label: { label }.buttonStyle(.emberProminent) }
    }

    @ViewBuilder private func e_btnGetLarge(_ b: Bool, _ t: Color) -> some View {
        let label = Text("Get").font(.headline).padding(.horizontal, 26).padding(.vertical, 4)
        if b { label.flatButton(prominent: true, tint: t) } else { Button {} label: { label }.buttonStyle(.emberProminent) }
    }

    @ViewBuilder private func e_btnListAction(_ b: Bool, _ t: Color) -> some View {
        if b { Button {} label: { Label("Add app", systemImage: "plus") }.buttonStyle(.glass) }
        else { Button {} label: { Label("Add app", systemImage: "plus") } }
    }

    @ViewBuilder private func e_btnDestructive(_ b: Bool, _ t: Color) -> some View {
        if b { Button("Sign out", role: .destructive) {}.buttonStyle(.glass) }
        else { Button("Sign out", role: .destructive) {} }
    }

    @ViewBuilder private func e_versionFooter(_ b: Bool, _ t: Color) -> some View {
        let text = Text("Discipline 0.5.0").font(.footnote).foregroundStyle(.secondary)
        if b { text.padding(.horizontal, 14).padding(.vertical, 8).glassEffect(.regular, in: .capsule) } else { text }
    }

    @ViewBuilder private func e_chip(_ b: Bool, _ t: Color) -> some View {
        GalleryChip(title: "Games", selected: false, glass: !b)
    }

    @ViewBuilder private func e_chipSelected(_ b: Bool, _ t: Color) -> some View {
        GalleryChip(title: "All", selected: true, glass: !b)
    }

    @ViewBuilder private func e_getPill(_ b: Bool, _ t: Color) -> some View {
        let pill = Text("Get").font(.subheadline.bold()).foregroundStyle(Ember.onAccent).padding(.horizontal, 16).padding(.vertical, 6)
        if b { pill.background(Ember.accent, in: .capsule) }
        else { pill.glassEffect(.regular.tint(Ember.accent), in: .capsule) }
    }

    @ViewBuilder private func e_badgePre(_ b: Bool, _ t: Color) -> some View {
        let tag = Text("PRE").font(.caption2.bold()).foregroundStyle(Ember.onAccent).padding(.horizontal, 6)
        if b { tag.background(Ember.orange, in: .capsule) } else { tag.glassEffect(.regular.tint(Ember.orange), in: .capsule) }
    }

    @ViewBuilder private func e_badgeUpdate(_ b: Bool, _ t: Color) -> some View {
        let tag = Text("Update").font(.caption.bold()).foregroundStyle(Ember.onAccent).padding(.horizontal, 8).padding(.vertical, 2)
        if b { tag.background(Ember.orange, in: .capsule) } else { tag.glassEffect(.regular.tint(Ember.orange), in: .capsule) }
    }

    @ViewBuilder private func e_badgeFeatured(_ b: Bool, _ t: Color) -> some View {
        let tag = Text("FEATURED").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
        Group {
            if b { tag.glassEffect(.regular, in: .capsule) } else { tag.background(Ember.black.opacity(0.45), in: Capsule()) }
        }
        .padding(14)
        .background(Ember.heroGradient,
                    in: .rect(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private func e_capabilityBadge(_ b: Bool, _ t: Color) -> some View {
        let lines = VStack(alignment: .leading, spacing: 6) {
            Text("\u{2705} Signable on a free Apple ID").font(.caption2.bold())
            Text("\u{26A0}\u{FE0F} Paid developer account needed").font(.caption2.bold())
            Text("\u{274C} Apple approval only").font(.caption2.bold())
        }
        if b { lines.padding(14).glassEffect(.regular, in: .rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous)) }
        else { lines }
    }

    @ViewBuilder private func e_trendingCard(_ b: Bool, _ t: Color) -> some View {
        GalleryTrendingCard(glass: b)
    }

    @ViewBuilder private func e_storeRow(_ b: Bool, _ t: Color) -> some View {
        let row = HStack(spacing: 14) {
            GalleryIcon(size: 58, colors: [Ember.flame, Ember.red], symbol: "gamecontroller.fill")
            VStack(alignment: .leading, spacing: 3) {
                Text("Delta").font(.headline).lineLimit(1)
                Text("Game emulator").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text("Games \u{00B7} AltStore").font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("Get").font(.subheadline.bold()).padding(.horizontal, 16).padding(.vertical, 6)
                .glassEffect(.regular.tint(Ember.accent.opacity(0.25)), in: Capsule())
        }
        if b { row.padding(14).glassEffect(.regular, in: .rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous)) }
        else { row.padding(.vertical, 8) }
    }

    @ViewBuilder private func e_storeIcon(_ b: Bool, _ t: Color) -> some View {
        let icon = GalleryIcon(size: 60, colors: [Ember.flame, Ember.red], symbol: "gamecontroller.fill", hairline: true)
        if b { icon.padding(8).glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous)) } else { icon }
    }

    @ViewBuilder private func e_appIcon(_ b: Bool, _ t: Color) -> some View {
        let icon = GalleryIcon(size: 56, colors: [Ember.charcoal, Ember.steel], symbol: "music.note")
        if b { icon.padding(8).glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous)) } else { icon }
    }

    @ViewBuilder private func e_reasonRow(_ b: Bool, _ t: Color) -> some View {
        let lines = VStack(alignment: .leading, spacing: 6) {
            Text("Why it's here").font(.headline)
            Label("Featured by AltStore", systemImage: "checkmark.seal").font(.subheadline)
            Label("Updated this week", systemImage: "checkmark.seal").font(.subheadline)
        }
        if b { lines.padding(14).glassEffect(.regular, in: .rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous)) }
        else { lines }
    }

    @ViewBuilder private func e_screenshotThumb(_ b: Bool, _ t: Color) -> some View {
        let shot = LinearGradient(colors: [Ember.charcoal, Ember.steel], startPoint: .top, endPoint: .bottom)
            .frame(width: 92, height: 170)
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
        if b { shot.padding(8).glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous)) } else { shot }
    }

    @ViewBuilder private func e_sourceRow(_ b: Bool, _ t: Color) -> some View {
        let row = HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AltStore Official").font(.subheadline.weight(.semibold))
                Text("https://apps.altstore.io").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Ember.accentText).font(.caption)
        }
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_spinner(_ b: Bool, _ t: Color) -> some View {
        let s = HStack(spacing: 18) { ProgressView().controlSize(.large); ProgressView() }
        if b { s.padding(14).glassEffect(.regular, in: .capsule) } else { s }
    }

    @ViewBuilder private func e_emptyState(_ b: Bool, _ t: Color) -> some View {
        let content = VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Couldn't load the store").font(.headline)
            Text("Check your connection and pull to retry.").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        if b { content.padding(18).glassEffect(.regular, in: .rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous)) }
        else { content }
    }

    @ViewBuilder private func e_listSection(_ b: Bool, _ t: Color) -> some View {
        if b {
            VStack(alignment: .leading, spacing: 6) {
                Text("APPS").font(.footnote).foregroundStyle(.secondary).padding(.leading, 16)
                VStack(spacing: 0) {
                    HStack { Text("Delta"); Spacer(); Text("5d 3h").foregroundStyle(.secondary) }.padding(14)
                    Divider().padding(.leading, 14)
                    HStack { Text("Provenance"); Spacer(); Text("1d 2h").foregroundStyle(.secondary) }.padding(14)
                }
                .glassEffect(.regular, in: .rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
                Text("Swipe a row to stop tracking.").font(.footnote).foregroundStyle(.secondary).padding(.leading, 16)
            }
        } else {
            List {
                Section {
                    HStack { Text("Delta"); Spacer(); Text("5d 3h").foregroundStyle(.secondary) }
                    HStack { Text("Provenance"); Spacer(); Text("1d 2h").foregroundStyle(.secondary) }
                } header: { Text("Apps") } footer: { Text("Swipe a row to stop tracking.") }
            }
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .frame(height: 220)
        }
    }

    @ViewBuilder private func e_navRow(_ b: Bool, _ t: Color) -> some View {
        let row = HStack {
            Label("Setup checklist", systemImage: "checklist")
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
        }
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_libraryRow(_ b: Bool, _ t: Color) -> some View {
        let row = HStack(spacing: 12) {
            GalleryIcon(size: 44, colors: [Ember.charcoal, Ember.steel], symbol: "music.note")
            VStack(alignment: .leading) {
                Text("Eclipse").font(.headline)
                Text("1.4.2 \u{00B7} Imported from Files").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
        }
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_labeledRow(_ b: Bool, _ t: Color) -> some View {
        let row = LabeledContent("Size", value: "12.4 MB")
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_trackedRow(_ b: Bool, _ t: Color) -> some View {
        let row = HStack {
            VStack(alignment: .leading) {
                Text("Delta").font(.headline)
                Text("7-day signature").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("5d 3h").font(.subheadline.monospacedDigit().bold()).foregroundStyle(Ember.ok)
            Button("Refreshed") {}.buttonStyle(.glass)
        }
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_releaseAssetRow(_ b: Bool, _ t: Color) -> some View {
        let row = HStack {
            VStack(alignment: .leading) {
                Text("Delta-1.6.3.ipa").font(.subheadline.weight(.semibold))
                Text("38.2 MB").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Get") {}.buttonStyle(.emberProminent)
        }
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_savedRepoRow(_ b: Bool, _ t: Color) -> some View {
        let row = HStack {
            Image(systemName: "shippingbox").foregroundStyle(Ember.accent)
            Text("rileytestut/Delta")
            Spacer()
            Text("Update").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                .glassEffect(.regular.tint(Ember.orange), in: .capsule)
        }
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_setupStepRow(_ b: Bool, _ t: Color) -> some View {
        let row = HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Ember.ok)
            VStack(alignment: .leading, spacing: 4) {
                Text("Install SideStore").font(.subheadline.weight(.semibold))
                Text("Signs your apps on this iPhone.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Get") {}.buttonStyle(.glass)
        }
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_capabilityRow(_ b: Bool, _ t: Color) -> some View {
        let row = VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Push notifications").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\u{26A0}\u{FE0F}").font(.caption2.bold())
            }
            Text("Needs a paid developer account to sign.").font(.caption).foregroundStyle(.secondary)
            Text("aps-environment").font(.caption2.monospaced())
        }
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_guardRow(_ b: Bool, _ t: Color) -> some View {
        let row = HStack {
            GalleryIcon(size: 32, colors: [Ember.charcoal, Ember.steel], symbol: "music.note")
            Text("Eclipse")
            Spacer()
            Button("Scan") {}.buttonStyle(.glass)
        }
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_findingLabel(_ b: Bool, _ t: Color) -> some View {
        let row = Label("No known trackers found in Eclipse", systemImage: "checkmark.shield")
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_accountRow(_ b: Bool, _ t: Color) -> some View {
        let row = HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 30)).foregroundStyle(Ember.ok)
            VStack(alignment: .leading, spacing: 2) {
                Text("Saidie").font(.headline)
                Text("Signed in with Ouija \u{00B7} key 7F3A\u{2026}C21E").font(.footnote).foregroundStyle(.secondary)
            }
        }
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_installOuijaBlock(_ b: Bool, _ t: Color) -> some View {
        let row = VStack(alignment: .leading, spacing: 6) {
            Label("Install Ouija to pair", systemImage: "arrow.down.app").font(.headline)
            Text("Sign in with Ouija / NCOM needs the Ouija app on this iPhone. Discipline can't pair without it.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_toggle(_ b: Bool, _ t: Color) -> some View {
        let row = Toggle(isOn: .constant(true)) { Label("Auto refresh", systemImage: "arrow.triangle.2.circlepath") }
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_budgetGauge(_ b: Bool, _ t: Color) -> some View {
        let row = VStack(alignment: .leading, spacing: 8) {
            HStack { Text("App IDs this week"); Spacer(); Text("3/10").font(.subheadline.monospacedDigit().bold()) }
            EmberProgressBar(progress: 0.3, glass: !b)
        }
        cellRow(row)
    }

    @ViewBuilder private func e_menuPicker(_ b: Bool, _ t: Color) -> some View {
        let row = HStack {
            Text("Appearance"); Spacer()
            Picker("Appearance", selection: .constant(0)) {
                Text("System").tag(0); Text("Light").tag(1); Text("Dark").tag(2)
            }.labelsHidden()
        }
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_textField(_ b: Bool, _ t: Color) -> some View {
        let row = TextField("github.com/owner/repo or owner/repo", text: .constant(""))
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_secureField(_ b: Bool, _ t: Color) -> some View {
        let row = SecureField("Personal access token (optional)", text: .constant(""))
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_datePicker(_ b: Bool, _ t: Color) -> some View {
        let row = DatePicker("Signed / refreshed", selection: .constant(Date(timeIntervalSince1970: 1_793_000_000)))
        if b { glassRow(row) } else { cellRow(row) }
    }

    @ViewBuilder private func e_cameraFrame(_ b: Bool, _ t: Color) -> some View {
        let cam = Rectangle().fill(Color.black)
            .overlay(Image(systemName: "qrcode.viewfinder").font(.system(size: 44)).foregroundStyle(.white.opacity(0.7)))
            .frame(width: 130, height: 130)
            .clipShape(.rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
        if b { cam.padding(8).glassEffect(.regular, in: .rect(cornerRadius: DisciplineShape.cornerRadius + 8, style: .continuous)) }
        else { cam }
    }

}

/// One numbered element: big number, name, source file, current state, then A and B.
struct GalleryRow: View {
    let item: GalleryItem
    let a: AnyView
    let b: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(item.id)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.8)
                    .frame(minWidth: 78, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(item.statusText).font(.caption2.weight(.heavy)).foregroundStyle(item.statusColor)
                    Text(item.file).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            switch item.layout {
            case .pair:
                HStack(alignment: .top, spacing: 10) {
                    tile("A \u{00B7} NOW") { a }
                    if let b { tile(item.bTitle) { b } }
                }
            case .stack:
                VStack(spacing: 8) {
                    tile("A \u{00B7} NOW") { a }
                    if let b { tile(item.bTitle) { b } }
                }
            case .solo:
                tile("AS IT IS NOW") { a }
            case .scaled:
                HStack(alignment: .top, spacing: 10) {
                    tile("A \u{00B7} NOW") { scaled(a) }
                    if let b { tile(item.bTitle) { scaled(b) } }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(.secondary.opacity(0.35)).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gallery.item.\(item.id)")
    }

    private func tile<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.heavy)).foregroundStyle(.secondary)
            content()
                .padding(12)
                .frame(maxWidth: .infinity)
                .background { GalleryPad() }
                .clipShape(.rect(cornerRadius: 20, style: .continuous))   // anything too wide shows as cut here, not off-screen
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scaled(_ v: AnyView) -> some View {
        v.frame(width: 360, height: 480)
            .scaleEffect(0.42, anchor: .topLeading)
            .frame(width: 151, height: 202, alignment: .topLeading)
    }
}

#endif
