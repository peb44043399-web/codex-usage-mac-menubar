import AppKit
import Foundation

struct LimitWindow: Codable, Equatable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date?

    var remainingPercent: Double {
        min(100.0, max(0.0, 100.0 - usedPercent))
    }
}

struct CreditInfo: Codable, Equatable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: Double?
}

struct QuotaSnapshot: Codable, Equatable {
    let eventTimestamp: Date?
    let filePath: String
    let limitId: String?
    let limitName: String?
    let planType: String?
    let primary: LimitWindow?
    let secondary: LimitWindow?
    let credits: CreditInfo?
}

struct QuotaMenuSummary {
    let fiveHourRemaining: String
    let fiveHourReset: String
    let weeklyRemaining: String
    let weeklyReset: String
}

struct FileCandidate {
    let url: URL
    let modifiedAt: Date
}

final class QuotaReader {
    private let fileManager = FileManager.default
    private let codexHome: URL
    private let preferredLimitId: String
    private let lookbackDays: Int
    private let isoFormatter: ISO8601DateFormatter

    init(codexHome: URL? = nil) {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            self.codexHome = URL(fileURLWithPath: override, isDirectory: true)
        } else if let codexHome {
            self.codexHome = codexHome
        } else {
            self.codexHome = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }

        preferredLimitId = ProcessInfo.processInfo.environment["CODEX_LIMIT_ID"] ?? "codex"
        lookbackDays = Int(ProcessInfo.processInfo.environment["CODEX_QUOTA_LOOKBACK_DAYS"] ?? "") ?? 3

        isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func latestSnapshot() -> QuotaSnapshot? {
        let sessionsRoot = codexHome.appendingPathComponent("sessions", isDirectory: true)
        let recentFiles = recentSessionJSONLFiles(under: sessionsRoot, limit: 48)

        if let snapshot = scanCandidates(recentFiles) {
            return snapshot
        }

        let broaderSessionFiles = recursiveJSONLFiles(under: sessionsRoot, limit: 96)
        if let snapshot = scanCandidates(broaderSessionFiles) {
            return snapshot
        }

        let archivedRoot = codexHome.appendingPathComponent("archived_sessions", isDirectory: true)
        let archivedFiles = recursiveJSONLFiles(under: archivedRoot, limit: 16)
        if let snapshot = scanCandidates(archivedFiles) {
            return snapshot
        }

        return nil
    }

    func debugLines(limit: Int = 20) -> [String] {
        var lines: [String] = []
        let sessionsRoot = codexHome.appendingPathComponent("sessions", isDirectory: true)
        let archivedRoot = codexHome.appendingPathComponent("archived_sessions", isDirectory: true)

        for (name, files) in [
            ("recent sessions", recentSessionJSONLFiles(under: sessionsRoot, limit: limit)),
            ("all sessions fallback", recursiveJSONLFiles(under: sessionsRoot, limit: limit)),
            ("archived fallback", recursiveJSONLFiles(under: archivedRoot, limit: limit)),
        ] {
            lines.append("\(name) candidates \(files.count)")

            for file in files {
                let snapshot = scanTail(of: file.url)
                let hit = snapshot.map { snapshot in
                    let limitId = snapshot.limitId ?? "--"
                    let event = snapshot.eventTimestamp?.description ?? "--"
                    return "hit \(limitId) \(event)"
                } ?? "miss"

                lines.append("\(file.modifiedAt) \(hit) \(file.url.path)")
            }
        }

        return lines
    }

    private func scanCandidates(_ files: [FileCandidate]) -> QuotaSnapshot? {
        var bestPreferred: QuotaSnapshot?
        var bestFallback: QuotaSnapshot?

        for file in files {
            if
                let bestPreferred,
                let eventTimestamp = bestPreferred.eventTimestamp,
                file.modifiedAt <= eventTimestamp
            {
                break
            }

            if let snapshot = scanTail(of: file.url) {
                if snapshot.limitId == preferredLimitId {
                    bestPreferred = newer(bestPreferred, snapshot)
                } else {
                    bestFallback = newer(bestFallback, snapshot)
                }
            }
        }

        return bestPreferred ?? bestFallback
    }

    private func recentSessionJSONLFiles(under root: URL, limit: Int) -> [FileCandidate] {
        let calendar = Calendar.current
        var candidates: [FileCandidate] = []

        for offset in 0..<max(1, lookbackDays) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else {
                continue
            }

            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard
                let year = components.year,
                let month = components.month,
                let day = components.day
            else {
                continue
            }

            let dayURL = root
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", day), isDirectory: true)

            candidates.append(contentsOf: jsonlFilesDirectlyUnder(dayURL))
        }

        return Array(candidates.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(limit))
    }

    private func jsonlFilesDirectlyUnder(_ directory: URL) -> [FileCandidate] {
        guard
            let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var candidates: [FileCandidate] = []

        for url in urls where url.pathExtension == "jsonl" {
            do {
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                candidates.append(FileCandidate(url: url, modifiedAt: values.contentModificationDate ?? .distantPast))
            } catch {
                continue
            }
        }

        return candidates
    }

    private func recursiveJSONLFiles(under root: URL, limit: Int) -> [FileCandidate] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [FileCandidate] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }

            do {
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                candidates.append(FileCandidate(url: url, modifiedAt: values.contentModificationDate ?? .distantPast))
            } catch {
                continue
            }
        }

        return Array(candidates.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(limit))
    }

    private func scanTail(of url: URL) -> QuotaSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer {
            try? handle.close()
        }

        let maxBytes: UInt64 = 4 * 1024 * 1024
        let endOffset = (try? handle.seekToEnd()) ?? 0
        var best: QuotaSnapshot?

        if endOffset <= maxBytes * 2 {
            if let snapshot = scanRegion(handle: handle, url: url, offset: 0, length: endOffset) {
                best = newer(best, snapshot)
            }
        } else {
            if let snapshot = scanRegion(handle: handle, url: url, offset: endOffset - maxBytes, length: maxBytes) {
                best = newer(best, snapshot)
            }

            // Current active Codex session files can grow large while the most recent
            // rate-limit event remains near the beginning of the JSONL file.
            if let snapshot = scanRegion(handle: handle, url: url, offset: 0, length: maxBytes) {
                best = newer(best, snapshot)
            }
        }

        return best
    }

    private func scanRegion(handle: FileHandle, url: URL, offset: UInt64, length: UInt64) -> QuotaSnapshot? {
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return nil
        }

        let data = handle.readData(ofLength: Int(length))
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var best: QuotaSnapshot?

        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains("\"rate_limits\"") else { continue }
            guard let lineData = String(line).data(using: .utf8) else { continue }
            guard
                let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let rateLimits = rateLimitsDictionary(in: object)
            else {
                continue
            }

            let snapshot = QuotaSnapshot(
                eventTimestamp: parseDate(object["timestamp"]),
                filePath: url.path,
                limitId: rateLimits["limit_id"] as? String,
                limitName: rateLimits["limit_name"] as? String,
                planType: rateLimits["plan_type"] as? String,
                primary: parseWindow(rateLimits["primary"]),
                secondary: parseWindow(rateLimits["secondary"]),
                credits: parseCredits(rateLimits["credits"])
            )

            best = newer(best, snapshot)
        }

        return best
    }

    private func rateLimitsDictionary(in object: [String: Any]) -> [String: Any]? {
        if let rateLimits = object["rate_limits"] as? [String: Any] {
            return rateLimits
        }

        if
            let payload = object["payload"] as? [String: Any],
            let rateLimits = payload["rate_limits"] as? [String: Any]
        {
            return rateLimits
        }

        return nil
    }

    private func newer(_ left: QuotaSnapshot?, _ right: QuotaSnapshot) -> QuotaSnapshot {
        guard let left else { return right }

        let leftDate = left.eventTimestamp ?? .distantPast
        let rightDate = right.eventTimestamp ?? .distantPast
        return rightDate > leftDate ? right : left
    }

    private func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        if let date = isoFormatter.date(from: string) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: string)
    }

    private func parseWindow(_ value: Any?) -> LimitWindow? {
        guard let dict = value as? [String: Any] else { return nil }
        guard
            let usedPercent = number(dict["used_percent"]),
            let windowMinutesNumber = number(dict["window_minutes"])
        else {
            return nil
        }

        let resetsAt: Date?
        if let seconds = number(dict["resets_at"]) {
            resetsAt = Date(timeIntervalSince1970: seconds)
        } else {
            resetsAt = nil
        }

        return LimitWindow(
            usedPercent: usedPercent,
            windowMinutes: Int(windowMinutesNumber.rounded()),
            resetsAt: resetsAt
        )
    }

    private func parseCredits(_ value: Any?) -> CreditInfo? {
        guard let dict = value as? [String: Any] else { return nil }
        return CreditInfo(
            hasCredits: dict["has_credits"] as? Bool,
            unlimited: dict["unlimited"] as? Bool,
            balance: number(dict["balance"])
        )
    }

    private func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }
}

final class SnapshotCache {
    private let fileManager = FileManager.default
    private let cacheURL: URL
    private let maxAgeSeconds: TimeInterval = 8 * 24 * 60 * 60

    init() {
        let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)

        cacheURL = baseURL
            .appendingPathComponent("local.codex.quota-menubar", isDirectory: true)
            .appendingPathComponent("last-snapshot.json")
    }

    func load() -> QuotaSnapshot? {
        guard
            let data = try? Data(contentsOf: cacheURL)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let snapshot = try? decoder.decode(QuotaSnapshot.self, from: data) else {
            return nil
        }

        if
            let eventTimestamp = snapshot.eventTimestamp,
            Date().timeIntervalSince(eventTimestamp) > maxAgeSeconds
        {
            return nil
        }

        return snapshot
    }

    func save(_ snapshot: QuotaSnapshot) {
        do {
            try fileManager.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            return
        }
    }
}

final class StatusFormatter {
    private let dateFormatter: DateFormatter
    private let shortTimeFormatter: DateFormatter
    private let monthDayFormatter: DateFormatter

    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium

        shortTimeFormatter = DateFormatter()
        shortTimeFormatter.dateFormat = "HH:mm"

        monthDayFormatter = DateFormatter()
        monthDayFormatter.locale = Locale(identifier: "zh_CN")
        monthDayFormatter.dateFormat = "M月d日"
    }

    func barRows(for snapshot: QuotaSnapshot?) -> (top: String, bottom: String) {
        guard let snapshot else {
            return ("5h --", "w --")
        }

        let fiveHour = window(minutes: 300, in: snapshot) ?? snapshot.primary
        let weekly = window(minutes: 10080, in: snapshot) ?? snapshot.secondary

        return (
            "5h \(percentText(fiveHour?.remainingPercent))",
            "w \(percentText(weekly?.remainingPercent))"
        )
    }

    func barTitle(for snapshot: QuotaSnapshot?) -> String {
        let rows = barRows(for: snapshot)
        return "Codex \(rows.top) \(rows.bottom)"
    }

    func menuSummary(for snapshot: QuotaSnapshot?) -> QuotaMenuSummary {
        guard let snapshot else {
            return QuotaMenuSummary(
                fiveHourRemaining: "--",
                fiveHourReset: "--",
                weeklyRemaining: "--",
                weeklyReset: "--"
            )
        }

        let fiveHour = window(minutes: 300, in: snapshot) ?? snapshot.primary
        let weekly = window(minutes: 10080, in: snapshot) ?? snapshot.secondary

        return QuotaMenuSummary(
            fiveHourRemaining: percentText(fiveHour?.remainingPercent),
            fiveHourReset: timeText(fiveHour?.resetsAt),
            weeklyRemaining: percentText(weekly?.remainingPercent),
            weeklyReset: monthDayText(weekly?.resetsAt)
        )
    }

    func menuLines(for snapshot: QuotaSnapshot?) -> [String] {
        guard let snapshot else {
            return [
                "No local Codex rate-limit event found.",
                "Use Codex once or run /status, then refresh.",
            ]
        }

        let fiveHour = window(minutes: 300, in: snapshot) ?? snapshot.primary
        let weekly = window(minutes: 10080, in: snapshot) ?? snapshot.secondary
        var lines: [String] = []

        if let fiveHour {
            lines.append("5小时剩余用量: \(percentText(fiveHour.remainingPercent))")
            lines.append("5h刷新时间: \(dateText(fiveHour.resetsAt))")
        } else {
            lines.append("5小时剩余用量: --")
            lines.append("5h刷新时间: --")
        }

        if let weekly {
            lines.append("周剩余用量: \(percentText(weekly.remainingPercent))")
            lines.append("weekly刷新时间: \(dateText(weekly.resetsAt))")
        } else {
            lines.append("周剩余用量: --")
            lines.append("weekly刷新时间: --")
        }

        return lines
    }

    private func window(minutes: Int, in snapshot: QuotaSnapshot) -> LimitWindow? {
        [snapshot.primary, snapshot.secondary]
            .compactMap { $0 }
            .first { $0.windowMinutes == minutes }
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))%"
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "--" }
        return dateFormatter.string(from: date)
    }

    private func timeText(_ date: Date?) -> String {
        guard let date else { return "--" }
        return shortTimeFormatter.string(from: date)
    }

    private func monthDayText(_ date: Date?) -> String {
        guard let date else { return "--" }
        return monthDayFormatter.string(from: date)
    }
}

enum GaugeIcon {
    static func draw(in rect: NSRect, color: NSColor, pointSize: CGFloat, weight: NSFont.Weight = .medium) {
        if drawSystemSymbol(in: rect, color: color, pointSize: pointSize, weight: weight) {
            return
        }

        drawFallback(in: rect, color: color)
    }

    private static func drawSystemSymbol(in rect: NSRect, color: NSColor, pointSize: CGFloat, weight: NSFont.Weight) -> Bool {
        let names = [
            "gauge.with.dots.needle.50percent",
            "gauge.with.needle",
            "gauge.medium",
        ]

        guard let image = names.lazy.compactMap({ NSImage(systemSymbolName: $0, accessibilityDescription: nil) }).first else {
            return false
        }

        let configured = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        ) ?? image

        let tinted = tintedImage(configured, color: color)
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        return true
    }

    private static func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
        let output = NSImage(size: image.size)
        let rect = NSRect(origin: .zero, size: image.size)

        output.lockFocus()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        color.set()
        rect.fill(using: .sourceIn)
        output.unlockFocus()

        return output
    }

    private static func drawFallback(in rect: NSRect, color: NSColor) {
        color.setStroke()

        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.40

        let arc = NSBezierPath()
        arc.lineWidth = max(1.6, radius * 0.22)
        arc.lineCapStyle = .round
        arc.appendArc(withCenter: center, radius: radius, startAngle: 205, endAngle: -25, clockwise: true)
        arc.stroke()

        let needle = NSBezierPath()
        needle.lineWidth = arc.lineWidth
        needle.lineCapStyle = .round
        needle.move(to: center)
        needle.line(to: NSPoint(x: center.x + radius * 0.66, y: center.y - radius * 0.25))
        needle.stroke()

        color.setFill()
        let dotSize = max(2.4, radius * 0.34)
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - dotSize / 2,
                y: center.y - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
        ).fill()
    }
}

final class QuotaStatusView: NSView {
    var onClick: (() -> Void)?
    private var topLabel = "5h"
    private var topValue = "--"
    private var bottomLabel = "w"
    private var bottomValue = "--"

    override var acceptsFirstResponder: Bool {
        true
    }

    func update(top: String, bottom: String) {
        (topLabel, topValue) = splitRow(top, fallbackLabel: "5h")
        (bottomLabel, bottomValue) = splitRow(bottom, fallbackLabel: "w")
        needsDisplay = true
        display()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func mouseUp(with event: NSEvent) {
    }

    override func rightMouseDown(with event: NSEvent) {
        mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let iconSize: CGFloat = 17
        drawIcon(in: NSRect(x: 5, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize))

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]

        let valueStyle = NSMutableParagraphStyle()
        valueStyle.alignment = .right
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: valueStyle,
        ]

        let lineHeight: CGFloat = 9.5
        let topY = bounds.midY - 0.4
        let bottomY = bounds.midY - lineHeight + 0.4
        let labelX: CGFloat = 27
        let valueX: CGFloat = 41

        (topLabel as NSString).draw(
            with: NSRect(x: labelX, y: topY, width: 15, height: lineHeight),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: labelAttributes
        )
        (bottomLabel as NSString).draw(
            with: NSRect(x: labelX, y: bottomY, width: 15, height: lineHeight),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: labelAttributes
        )
        (topValue as NSString).draw(
            with: NSRect(x: valueX, y: topY, width: bounds.width - valueX - 5, height: lineHeight),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: valueAttributes
        )
        (bottomValue as NSString).draw(
            with: NSRect(x: valueX, y: bottomY, width: bounds.width - valueX - 5, height: lineHeight),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: valueAttributes
        )
    }

    private func drawIcon(in rect: NSRect) {
        GaugeIcon.draw(in: rect, color: .labelColor, pointSize: 15, weight: .semibold)
    }

    private func splitRow(_ text: String, fallbackLabel: String) -> (String, String) {
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return (fallbackLabel, "--")
        }

        return (parts[0], parts[1])
    }
}

final class QuotaSummaryMenuView: NSView {
    private let summary: QuotaMenuSummary

    init(summary: QuotaMenuSummary) {
        self.summary = summary
        super.init(frame: NSRect(x: 0, y: 0, width: 252, height: 64))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawGaugeIcon(in: NSRect(x: 14, y: 9, width: 18, height: 18))

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]

        ("剩余用量" as NSString).draw(
            with: NSRect(x: 38, y: 9, width: 132, height: 18),
            options: [.usesLineFragmentOrigin],
            attributes: titleAttributes
        )

        drawRow(label: "5 小时", remaining: summary.fiveHourRemaining, reset: summary.fiveHourReset, y: 30)
        drawRow(label: "1 周", remaining: summary.weeklyRemaining, reset: summary.weeklyReset, y: 48)
    }

    private func drawRow(label: String, remaining: String, reset: String, y: CGFloat) {
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]

        let valueStyle = NSMutableParagraphStyle()
        valueStyle.alignment = .right

        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: valueStyle,
        ]

        (label as NSString).draw(
            with: NSRect(x: 38, y: y, width: 72, height: 17),
            options: [.usesLineFragmentOrigin],
            attributes: labelAttributes
        )

        (remaining as NSString).draw(
            with: NSRect(x: 124, y: y, width: 42, height: 17),
            options: [.usesLineFragmentOrigin],
            attributes: valueAttributes
        )

        (reset as NSString).draw(
            with: NSRect(x: 174, y: y, width: 60, height: 17),
            options: [.usesLineFragmentOrigin],
            attributes: valueAttributes
        )
    }

    private func drawGaugeIcon(in rect: NSRect) {
        GaugeIcon.draw(in: rect, color: .secondaryLabelColor, pointSize: 16, weight: .regular)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let reader = QuotaReader()
    private let cache = SnapshotCache()
    private let formatter = StatusFormatter()
    private let refreshInterval: TimeInterval = 10
    private let refreshQueue = DispatchQueue(label: "local.codex-quota-menubar.refresh", qos: .utility)
    private var statusItem: NSStatusItem?
    private var statusView: QuotaStatusView?
    private var timer: Timer?
    private var currentSnapshot: QuotaSnapshot?
    private var isRefreshInFlight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: 68)
        let view = QuotaStatusView(frame: NSRect(x: 0, y: 0, width: 68, height: NSStatusBar.system.thickness))
        view.onClick = { [weak self] in
            self?.showMenu()
        }
        statusView = view
        statusItem?.view = view
        applySnapshot(cache.load())
        requestRefresh()

        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.requestRefresh()
        }
    }

    @objc private func refreshFromMenu() {
        requestRefresh()
    }

    @objc private func revealSource() {
        guard let path = currentSnapshot?.filePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func requestRefresh() {
        guard !isRefreshInFlight else { return }
        isRefreshInFlight = true
        let previousSnapshot = currentSnapshot

        refreshQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.reader.latestSnapshot()
            if let snapshot, snapshot != previousSnapshot {
                self.cache.save(snapshot)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRefreshInFlight = false

                if let snapshot {
                    if snapshot != self.currentSnapshot {
                        self.applySnapshot(snapshot)
                    }
                } else if self.currentSnapshot == nil {
                    self.applySnapshot(nil)
                }
            }
        }
    }

    private func applySnapshot(_ snapshot: QuotaSnapshot?) {
        currentSnapshot = snapshot
        let rows = formatter.barRows(for: currentSnapshot)
        statusView?.update(top: rows.top, bottom: rows.bottom)
    }

    private func showMenu() {
        rebuildMenu(showDebug: NSEvent.modifierFlags.contains(.option))

        if let menu = statusItem?.menu {
            statusItem?.popUpMenu(menu)
        }
    }

    private func rebuildMenu(showDebug: Bool = false) {
        let menu = NSMenu()

        let summaryItem = NSMenuItem()
        summaryItem.view = QuotaSummaryMenuView(summary: formatter.menuSummary(for: currentSnapshot))
        menu.addItem(summaryItem)

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "刷新", action: #selector(refreshFromMenu), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        if showDebug {
            let revealItem = NSMenuItem(title: "打开日志", action: #selector(revealSource), keyEquivalent: "")
            revealItem.target = self
            revealItem.isEnabled = currentSnapshot != nil
            menu.addItem(revealItem)
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }
}

if CommandLine.arguments.contains("--debug-scan") {
    for line in QuotaReader().debugLines() {
        print(line)
    }
    exit(0)
}

if CommandLine.arguments.contains("--print-once") {
    let snapshot = QuotaReader().latestSnapshot()
    let formatter = StatusFormatter()
    print(formatter.barTitle(for: snapshot))
    for line in formatter.menuLines(for: snapshot) {
        print(line)
    }
    exit(snapshot == nil ? 1 : 0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
