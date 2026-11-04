import SwiftUI
import DisciplineCore

struct HomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statStrip
                    expiryHero
                    if model.trackedApps.count > 1 { signaturesCard }
                    companionsCard
                    vpnCard
                }
                .padding()
            }
            .disciplineBackdrop()
            .navigationTitle("Discipline")
            .refreshable { model.refreshEnvironment() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.refreshEnvironment(); model.show("Status updated") } label: {
                        Label("Check status", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("home.checkStatus")
                }
            }
        }
    }

    private var statStrip: some View {
        StatStrip {
            StatTile(value: "\(model.trackedApps.count)", label: "Tracked", systemImage: "timer",
                     tint: Ember.accentText, id: "home.stat.tracked")
            StatTile(value: "\(model.library.count)", label: "In Library", systemImage: "shippingbox",
                     tint: Ember.muted, id: "home.stat.library")
            StatTile(value: "\(model.savedRepos.filter(\.hasUpdate).count)", label: "Updates", systemImage: "arrow.down.app",
                     tint: Ember.ok, id: "home.stat.updates")
        }
    }

    private var signaturesCard: some View {
        GlassCard {
            Text("Signatures at a glance").font(.headline)
            ExpiryChart()
        }
    }

    private var expiryHero: some View {
        GlassCard(tinted: true) {
            Text("Never let an app expire").font(.headline)
            if let app = model.soonest {
                let status = model.tracker.status(of: app, now: model.now)
                HStack(spacing: 16) {
                    RingGauge(progress: status.fractionLeft(of: app.tier), tint: status.tintColor, glass: false) {
                        Image(systemName: "timer").font(.title.weight(.semibold)).foregroundStyle(Ember.sand)
                    }
                    .accessibilityIdentifier("home.ring")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ExpiryTracker.shortText(status))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .accessibilityIdentifier("home.countdown")
                        Text("left on \(app.name)").foregroundStyle(.secondary)
                    }
                }
                EmberProgressBar(progress: status.fractionLeft(of: app.tier))
                    .accessibilityLabel("Signature time left")
                    .accessibilityValue("\(Int((status.fractionLeft(of: app.tier) * 100).rounded())) percent")
                    .accessibilityIdentifier("home.progress")
            } else {
                Text("Track your sideloaded apps in Expiry and Discipline counts down their signatures.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("home.noTracked")
            }
            // No GlassEffectContainer here: inside one, the orange glass was drawn over the button labels (Nov 3 simulator run).
            Group {
                HStack(spacing: 12) {
                    Button { Task { await model.refreshAll() } } label: {
                        Label("Refresh All", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.emberProminent)
                    .accessibilityIdentifier("home.refreshAll")

                    Button { model.markAllRefreshed() } label: {
                        Label("Mark done", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(model.trackedApps.isEmpty)
                    .accessibilityIdentifier("home.markAllRefreshed")
                }
            }
            Text("Refresh All turns on LocalDevVPN, which then opens SideStore. Tap Refresh All there, then Mark done here.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var companionsCard: some View {
        GlassCard {
            HStack {
                Text("Your sideloading kit").font(.headline)
                Spacer()
                Gauge(value: Double(model.installed.count), in: 0...Double(max(1, Companion.allCases.count))) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(model.installed.count)/\(Companion.allCases.count)").font(.caption2.bold())
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Ember.glow)
                .scaleEffect(0.8)
                .accessibilityIdentifier("home.kitGauge")
            }
            ForEach(Companion.allCases) { c in
                HStack(spacing: 12) {
                    Image(systemName: model.installed.contains(c) ? "checkmark" : "arrow.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(model.installed.contains(c) ? Ember.ok : Ember.accentText)
                        .frame(width: 34, height: 34)
                        .background((model.installed.contains(c) ? Ember.ok : Ember.orange).opacity(0.16), in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.displayName).font(.subheadline.weight(.semibold))
                        Text(c.role).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.installed.contains(c) ? "Open" : "Get") { Task { await model.openCompanion(c) } }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("home.open.\(c.rawValue)")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.companion.\(c.rawValue)")
            }
        }
    }

    private var vpnCard: some View {
        GlassCard {
            HStack {
                Text("Loopback VPN").font(.headline)
                Spacer()
                StatusDot(ok: model.tunnelIsUp)
                Text(model.tunnelIsUp ? "On" : "Off").font(.subheadline)
                    .accessibilityIdentifier("home.tunnelState")
            }
            if case .connected(let iface, let addr) = model.tunnel {
                Text("\(iface) · \(addr.description)").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            // No GlassEffectContainer here: inside one, the orange glass was drawn over the button labels (Nov 3 simulator run).
            Group {
                HStack(spacing: 12) {
                    Button { Task { await model.vpnOn() } } label: { Label("Turn on", systemImage: "bolt.horizontal.circle").frame(maxWidth: .infinity) }
                        .buttonStyle(.emberProminent)
                        .accessibilityIdentifier("home.vpnOn")
                    Button { Task { await model.vpnOff() } } label: { Label("Turn off", systemImage: "bolt.slash").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("home.vpnOff")
                }
            }
            Text("Needed whenever SideStore installs or refreshes. Traffic never leaves your phone.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
