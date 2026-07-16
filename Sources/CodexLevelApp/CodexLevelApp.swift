import AppKit
import CodexLevelCore
import Combine
import SwiftUI

enum LoadState<Value: Sendable>: Sendable {
    case loading
    case value(Value)
    case failure(CodexDataError)
}

@MainActor
final class CodexLevelViewModel: ObservableObject {
    typealias ProfileLoader = @Sendable () async -> LoadState<CodexProfile>
    typealias WeeklyLimitLoader = @Sendable () async -> LoadState<WeeklyRateLimit>

    @Published private(set) var profile: LoadState<CodexProfile> = .loading
    @Published private(set) var weeklyLimit: LoadState<WeeklyRateLimit> = .loading
    @Published private(set) var resetCredits: [CodexResetCredit] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdatedAt: Date?
    private let profileLoader: ProfileLoader
    private let weeklyLimitLoader: WeeklyLimitLoader
    private var automaticRefreshTask: Task<Void, Never>?
    private var resetCreditsTask: Task<Void, Never>?

    init(
        profileLoader: @escaping ProfileLoader = CodexLevelViewModel.loadProfile,
        weeklyLimitLoader: @escaping WeeklyLimitLoader = CodexLevelViewModel.loadWeeklyLimit,
        startsAutomatically: Bool = true
    ) {
        self.profileLoader = profileLoader
        self.weeklyLimitLoader = weeklyLimitLoader
        guard startsAutomatically else { return }

        Task { [weak self] in
            await self?.refresh(includeResetCredits: true)
        }
        automaticRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
            }
        }
    }

    deinit {
        automaticRefreshTask?.cancel()
        resetCreditsTask?.cancel()
    }

    var levelProgress: LevelProgress? {
        guard case let .value(profile) = profile else { return nil }
        return LevelProgress(lifetimeTokens: profile.lifetimeTokens)
    }

    var currentPlan: CodexPlan? {
        guard case let .value(limit) = weeklyLimit else { return nil }
        return limit.plan
    }

    var menuBarTitle: String {
        guard let levelProgress else {
            return isLoading ? "Codex · Loading…" : "Codex Level · —"
        }
        return "Codex Lv.\(levelProgress.level) · \(Int(levelProgress.percentToNextLevel))%"
    }

    func refresh(includeResetCredits: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        if includeResetCredits {
            refreshResetCredits()
        }

        async let profileResult = profileLoader()
        async let limitResult = weeklyLimitLoader()
        let results = await (profileResult, limitResult)
        switch results.0 {
        case .value:
            profile = results.0
        case .failure:
            if case .loading = profile {
                profile = results.0
            }
        case .loading:
            break
        }
        switch results.1 {
        case .value:
            weeklyLimit = results.1
        case .failure:
            if case .loading = weeklyLimit {
                weeklyLimit = results.1
            }
        case .loading:
            break
        }
        if case .value = results.0 {
            lastUpdatedAt = Date()
        } else if case .value = results.1 {
            lastUpdatedAt = Date()
        }
        isLoading = false
    }

    private func refreshResetCredits() {
        resetCreditsTask?.cancel()
        resetCreditsTask = Task { [weak self] in
            let credits = await Self.loadResetCredits()
            guard !Task.isCancelled else { return }
            self?.resetCredits = credits
        }
    }

    func retryWeeklyLimit() async {
        guard !isLoading else { return }
        isLoading = true
        weeklyLimit = .loading
        let result = await weeklyLimitLoader()
        weeklyLimit = result
        if case .value = result {
            lastUpdatedAt = Date()
        }
        isLoading = false
    }

    nonisolated static func loadProfile() async -> LoadState<CodexProfile> {
        do {
            let credentials = try CodexCredentials.load()
            return .value(try await CodexProfileClient().fetchProfile(credentials: credentials))
        } catch let error as CodexDataError {
            return .failure(error)
        } catch {
            return .failure(.networkFailure)
        }
    }

    nonisolated static func loadWeeklyLimit() async -> LoadState<WeeklyRateLimit> {
        do {
            let credentials = try CodexCredentials.load()
            return .value(try await CodexOAuthUsageClient().readWeeklyRateLimit(credentials: credentials))
        } catch {
            do {
                return .value(try await CodexAppServerClient().readWeeklyRateLimit())
            } catch let error as CodexDataError {
                return .failure(error)
            } catch {
                return .failure(.appServerFailure)
            }
        }
    }

    private nonisolated static func loadResetCredits() async -> [CodexResetCredit] {
        guard let credentials = try? CodexCredentials.load() else { return [] }
        return (try? await CodexResetCreditsClient().fetchAvailableCredits(credentials: credentials)) ?? []
    }
}

@main
private struct CodexLevelApp: App {
    @NSApplicationDelegateAdaptor(CodexLevelAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class CodexLevelAppDelegate: NSObject, NSApplicationDelegate {
    private let model = CodexLevelViewModel()
    private var statusItemController: StatusItemController?
    private var globalHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let controller = StatusItemController(model: model)
        statusItemController = controller
        globalHotKey = try? GlobalHotKey { [weak controller] in
            controller?.togglePopover()
        }
    }
}

@MainActor
private final class StatusItemController: NSObject {
    private let model: CodexLevelViewModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var modelObservation: AnyCancellable?

    init(model: CodexLevelViewModel) {
        self.model = model
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "Codex Level · ⌥L"
        }

        let hostingController = NSHostingController(rootView: CodexLevelPopover(model: model))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController

        updateTitle()
        modelObservation = model.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateTitle()
            }
        }
    }

    @objc func togglePopover() {
        switch PopoverToggleAction.next(isPopoverShown: popover.isShown) {
        case .show:
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        case .close:
            popover.performClose(nil)
        }
    }

    private func updateTitle() {
        statusItem.button?.title = model.menuBarTitle
    }
}

private struct CodexLevelPopover: View {
    @ObservedObject var model: CodexLevelViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(alignment: .leading, spacing: 20) {
                profileSection
                weeklySection
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)

            Divider()
            footer
        }
        .frame(width: 368)
        .background(NativeMenuBackground())
        .onAppear {
            Task { await model.refresh() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 7) {
                    Text(greeting)
                        .font(.system(size: 21, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let plan = model.currentPlan {
                        PlanDiamondBadge(plan: plan)
                            .layoutPriority(1)
                            .help("\(plan.displayName) plan")
                            .accessibilityLabel("\(plan.displayName) plan")
                    }
                }

                if case let .value(profile) = model.profile {
                    let progress = LevelProgress(lifetimeTokens: profile.lifetimeTokens)
                    Text(levelIdentity(progress))
                        .font(.system(size: 17, weight: .medium))
                        .lineLimit(1)
                } else if case .failure = model.profile {
                    Text("Profile unavailable")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(updateStatus)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    @ViewBuilder
    private var profileSection: some View {
        switch model.profile {
        case .loading:
            loadingView
        case let .value(profile):
            let progress = LevelProgress(lifetimeTokens: profile.lifetimeTokens)
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    statCard(
                        label: "Total usage",
                        value: TokenCountFormatter.short(profile.lifetimeTokens),
                        help: profile.lifetimeTokens.formatted(.number.grouping(.automatic)) + " tokens")
                    statCard(
                        label: "Current streak",
                        value: streakText(profile.currentStreakDays),
                        help: nil)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Level progress")
                        .font(.system(size: 16, weight: .semibold))

                    HStack {
                        Text(levelProgressTarget(progress))
                        Spacer()
                        Text(levelProgressPercent(progress))
                    }
                    .font(.system(size: 14))
                    .monospacedDigit()

                    if let nextMilestone = progress.nextMilestone {
                        Text(TokenCountFormatter.short(nextMilestone - profile.lifetimeTokens) + " remaining")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    ProgressView(value: progress.percentToNextLevel, total: 100)
                        .tint(.accentColor)
                        .controlSize(.small)
                }
            }
        case let .failure(error):
            VStack(alignment: .leading, spacing: 7) {
                Label("Profile data unavailable", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 15, weight: .medium))
                Text(error.localizedDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Usage")
                .font(.system(size: 16, weight: .semibold))

            switch model.weeklyLimit {
            case .loading:
                loadingView
            case let .value(limit):
                HStack {
                    Text(limit.usedPercent.formatted(.number.precision(.fractionLength(0 ... 1))) + "% used")
                    Spacer()
                    Text(RelativeResetFormatter.string(until: limit.resetsAt))
                }
                .font(.system(size: 14))
                .monospacedDigit()

                ProgressView(value: limit.usedPercent, total: 100)
                    .tint(.accentColor)
                    .controlSize(.small)
            case let .failure(error):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Weekly usage unavailable")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .help(error.localizedDescription)
                    Button("Retry") {
                        Task { await model.retryWeeklyLimit() }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 14))
                    .disabled(model.isLoading)
                }
            }

            if !model.resetCredits.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                resetCreditsSection
            }
        }
    }

    private var resetCreditsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Limit Reset Credits")
                .font(.system(size: 14, weight: .medium))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.resetCredits.count == 1 ? "1 available" : "\(model.resetCredits.count) available")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "clock")
                    Text(resetCreditsExpirySummary)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await model.refresh(includeResetCredits: true) }
            } label: {
                Label(model.isLoading ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
            .buttonStyle(.plain)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private var greeting: String {
        guard case let .value(profile) = model.profile,
              let name = profile.preferredName
        else {
            return "Hi"
        }
        return "Hi, \(name)"
    }

    private var updateStatus: String {
        if model.isLoading { return "Updating…" }
        if model.lastUpdatedAt != nil { return "Updated just now" }
        return "Update unavailable"
    }

    private func levelIdentity(_ progress: LevelProgress) -> String {
        progress.visualSymbol.isEmpty
            ? "Lv.\(progress.level)"
            : "Lv.\(progress.level) · \(progress.visualSymbol)"
    }

    private func levelProgressTarget(_ progress: LevelProgress) -> String {
        guard let nextMilestone = progress.nextMilestone else {
            return "Max level · Lv.\(progress.level)"
        }
        return "Next Lv.\(progress.level + 1) · \(TokenCountFormatter.short(nextMilestone))"
    }

    private func levelProgressPercent(_ progress: LevelProgress) -> String {
        let displayPercent = progress.nextMilestone == nil
            ? 100
            : min(progress.percentToNextLevel, 99.99)
        return String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), displayPercent)
    }

    private func streakText(_ days: UInt64?) -> String {
        guard let days else { return "—" }
        return days == 1 ? "1 day" : "\(days) days"
    }

    private var resetCreditsExpirySummary: String {
        var items = model.resetCredits.prefix(4).map { credit in
            guard let expiresAt = credit.expiresAt else { return "No expiry" }
            let relative = RelativeResetFormatter.string(until: expiresAt)
            return relative.hasPrefix("Resets in ")
                ? String(relative.dropFirst("Resets in ".count))
                : relative
        }
        let hiddenCount = model.resetCredits.count - items.count
        if hiddenCount > 0 {
            items.append("+\(hiddenCount)")
        }
        return items.joined(separator: " · ")
    }

    private func statCard(label: String, value: String, help: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .monospacedDigit()
                .help(help ?? "")
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

enum PlanDiamondAsset {
    private static var resourceBundle: Bundle {
        if let resourcesURL = Bundle.main.resourceURL,
           let packagedBundle = Bundle(
               url: resourcesURL.appendingPathComponent("CodexLevel_CodexLevelApp.bundle"))
        {
            return packagedBundle
        }
        return Bundle.module
    }

    static func resourceName(for plan: CodexPlan) -> String {
        switch plan {
        case .go: "plan-diamond-go"
        case .plus: "plan-diamond-plus"
        case .pro5x: "plan-diamond-pro5x"
        case .pro20x: "plan-diamond-pro20x"
        }
    }

    static func resourceURL(for plan: CodexPlan) -> URL? {
        resourceBundle.url(
            forResource: resourceName(for: plan),
            withExtension: "png")
    }
}

private struct PlanDiamondBadge: View {
    let plan: CodexPlan

    var body: some View {
        Image(
            nsImage: PlanDiamondAsset.resourceURL(for: plan)
                .flatMap(NSImage.init(contentsOf:)) ?? NSImage())
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: 32, height: 20)
        .fixedSize()
    }
}

private struct NativeMenuBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
