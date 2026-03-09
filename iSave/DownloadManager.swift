import Foundation
import SwiftUI
import Combine
import IOKit.pwr_mgt

// MARK: - UserDefaults Extension

extension UserDefaults {
    @objc dynamic var maxConcurrentDownloadsValue: Int {
        return integer(forKey: "maxConcurrentDownloads") == 0 ? 2 : integer(forKey: "maxConcurrentDownloads")
    }
    
    @objc dynamic var preventSleepValue: Bool {
        if object(forKey: "preventSleepDuringDownload") == nil {
            return true // 默认开启
        }
        return bool(forKey: "preventSleepDuringDownload")
    }
}

// MARK: - Download Task Model

enum DownloadStatus: String, Codable {
    case waiting
    case downloading
    case paused
    case completed
    case failed
    case stopped
    
    var displayName: String {
        switch self {
        case .waiting: return LocalizedString("status.waiting")
        case .downloading: return LocalizedString("status.downloading")
        case .paused: return LocalizedString("status.paused")
        case .completed: return LocalizedString("status.completed")
        case .failed: return LocalizedString("status.failed")
        case .stopped: return LocalizedString("status.paused")
        }
    }
}

class DownloadTask: Identifiable, ObservableObject {
    let id: UUID
    let url: String
    let createdAt: Date
    let outputFormat: String
    let videoQuality: String
    let audioQuality: String
    let destinationPath: String
    
    @Published var status: DownloadStatus = .waiting
    @Published var log: String = ""
    @Published var progress: String = ""
    @Published var isFetchingInfo: Bool = false  // 标识是否在获取信息
    @Published var actualResolution: String = ""  // 实际下载的分辨率
    @Published var actualAudioQuality: String = ""  // 实际的音频码率/质量
    @Published var duration: String = ""  // 视频时长
    @Published var fileSize: String = ""  // 文件大小
    @Published var filePath: String = ""  // 下载文件的完整路径
    @Published var thumbnailURL: String = ""  // 视频缩略图 URL
    @Published var triedBrowsers: [String] = []  // 已尝试的浏览器列表
    @Published var requiresLogin: Bool = false    // 是否需要登录才能下载
    @Published var isImageDownload: Bool = false  // 是否为图片下载（gallery-dl）
    @Published var downloadedMediaCount: Int = 0  // 已下载文件数（gallery-dl）
    @Published var totalMediaCount: Int = 0       // 总文件数（gallery-dl）
    
    var process: Process?
    
    init(
        id: UUID = UUID(),
        url: String,
        createdAt: Date = Date(),
        outputFormat: String,
        videoQuality: String,
        audioQuality: String,
        destinationPath: String,
        status: DownloadStatus = .waiting
    ) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.outputFormat = outputFormat
        self.videoQuality = videoQuality
        self.audioQuality = audioQuality
        self.destinationPath = destinationPath
        self.status = status
    }
    
    var statusColor: Color {
        switch status {
        case .waiting: return .orange
        case .downloading: return .blue
        case .paused: return .yellow
        case .completed: return .green
        case .failed: return .red
        case .stopped: return .gray
        }
    }
    
    var canPause: Bool {
        status == .downloading
    }
    
    var canResume: Bool {
        status == .paused
    }
    
    var canStop: Bool {
        status == .downloading || status == .paused || status == .waiting
    }
    
    var canRetry: Bool {
        status == .failed || status == .stopped
    }
}

// MARK: - Download History (Codable for persistence)

struct DownloadRecord: Identifiable, Codable {
    let id: UUID
    let url: String
    let createdAt: Date
    let completedAt: Date?
    let outputFormat: String
    let videoQuality: String
    let audioQuality: String
    let destinationPath: String
    let status: DownloadStatus
    let actualResolution: String
    let actualAudioQuality: String
    let duration: String
    let fileSize: String
    let filePath: String
    let thumbnailURL: String
    let progress: String
    let isImageDownload: Bool
    let downloadedMediaCount: Int
    let totalMediaCount: Int
    
    init(from task: DownloadTask, completedAt: Date? = nil) {
        self.id = task.id
        self.url = task.url
        self.createdAt = task.createdAt
        self.completedAt = completedAt
        self.outputFormat = task.outputFormat
        self.videoQuality = task.videoQuality
        self.audioQuality = task.audioQuality
        self.destinationPath = task.destinationPath
        self.status = task.status
        self.actualResolution = task.actualResolution
        self.actualAudioQuality = task.actualAudioQuality
        self.duration = task.duration
        self.fileSize = task.fileSize
        self.filePath = task.filePath
        self.thumbnailURL = task.thumbnailURL
        self.progress = task.progress
        self.isImageDownload = task.isImageDownload
        self.downloadedMediaCount = task.downloadedMediaCount
        self.totalMediaCount = task.totalMediaCount
    }
}

// MARK: - Download Manager

class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    
    @Published var tasks: [DownloadTask] = []
    @Published var ytdlpPath: String = ""
    @Published var ytdlpAvailable: Bool = false
    @Published var ffmpegAvailable: Bool = false
    @Published var galleryDlPath: String = ""
    @Published var galleryDlAvailable: Bool = false
    @Published var maxConcurrentDownloads: Int = 2
    
    private let tasksKey = "downloadTasks"
    private var cancellables = Set<AnyCancellable>()
    private var powerAssertionID: IOPMAssertionID = 0
    private var isPreventingSleep = false
    
    init() {
        loadTasks()
        checkYtDlpAvailability()
        checkFfmpegAvailability()
        checkGalleryDlAvailability()
        
        // 监听设置变化
        UserDefaults.standard.publisher(for: \.maxConcurrentDownloadsValue)
            .sink { [weak self] newValue in
                self?.maxConcurrentDownloads = newValue
                self?.startNextDownloadIfNeeded()
            }
            .store(in: &cancellables)
        
        // 监听防止睡眠设置变化
        UserDefaults.standard.publisher(for: \.preventSleepValue)
            .sink { [weak self] _ in
                self?.updatePowerAssertion()
            }
            .store(in: &cancellables)
        
        // 监听下载任务状态变化
        $tasks
            .sink { [weak self] _ in
                self?.updatePowerAssertion()
            }
            .store(in: &cancellables)
        
        // 初始化设置值
        maxConcurrentDownloads = UserDefaults.standard.maxConcurrentDownloadsValue
    }
    
    // MARK: - Helper Functions
    
    // MARK: - Power Assertion Management
    
    private func updatePowerAssertion() {
        let shouldPreventSleep = UserDefaults.standard.preventSleepValue && hasActiveDownloads()
        
        if shouldPreventSleep && !isPreventingSleep {
            createPowerAssertion()
        } else if !shouldPreventSleep && isPreventingSleep {
            releasePowerAssertion()
        }
    }
    
    private func hasActiveDownloads() -> Bool {
        return tasks.contains { $0.status == .downloading }
    }
    
    private func createPowerAssertion() {
        let reason = "iSave is downloading videos" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &powerAssertionID
        )
        
        if result == kIOReturnSuccess {
            isPreventingSleep = true
            print("✅ Power assertion created: System will not sleep during downloads")
        } else {
            print("❌ Failed to create power assertion")
        }
    }
    
    private func releasePowerAssertion() {
        if powerAssertionID != 0 {
            let result = IOPMAssertionRelease(powerAssertionID)
            if result == kIOReturnSuccess {
                isPreventingSleep = false
                powerAssertionID = 0
                print("✅ Power assertion released: System can sleep normally")
            }
        }
    }
    
    deinit {
        releasePowerAssertion()
    }
    
    // MARK: - Helper Functions
    
    /// 将秒数转换为时长格式字符串 (mm:ss 或 hh:mm:ss)
    private func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    // MARK: - yt-dlp and ffmpeg Path Resolution
    
    func checkYtDlpAvailability() {
        ytdlpPath = resolveYtDlpPath()
        ytdlpAvailable = FileManager.default.isExecutableFile(atPath: ytdlpPath)
    }
    
    func checkFfmpegAvailability() {
        // 只使用打包的 ffmpeg
        if let bundledPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            ffmpegAvailable = FileManager.default.isExecutableFile(atPath: bundledPath)
        } else {
            ffmpegAvailable = false
        }
    }
    
    func checkGalleryDlAvailability() {
        galleryDlPath = resolveGalleryDlPath()
        galleryDlAvailable = FileManager.default.isExecutableFile(atPath: galleryDlPath)
    }
    
    func resolveGalleryDlPath() -> String {
        if let bundledPath = Bundle.main.path(forResource: "gallery-dl", ofType: nil) {
            if FileManager.default.isExecutableFile(atPath: bundledPath) {
                return bundledPath
            }
        }
        return ""
    }
    
    /// 判断 URL 是否为 Instagram 链接
    func isInstagramURL(_ url: String) -> Bool {
        guard let urlObj = URL(string: url), let host = urlObj.host?.lowercased() else { return false }
        return host.contains("instagram.com") || host.contains("instagr.am")
    }

    /// 判断 URL 是否为 YouTube 链接
    func isYouTubeURL(_ url: String) -> Bool {
        guard let urlObj = URL(string: url), let host = urlObj.host?.lowercased() else { return false }
        return host.contains("youtube.com") || host.contains("youtu.be") || host.contains("youtube-nocookie.com")
    }
    
    /// 从 Instagram URL 提取 shortcode，例如 https://www.instagram.com/p/DVaw3oKEjlf/ -> DVaw3oKEjlf
    func extractInstagramShortcode(from url: String) -> String? {
        let pattern = #"/(?:p|reel|tv|reels)/([A-Za-z0-9_-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let range = Range(match.range(at: 1), in: url) else { return nil }
        return String(url[range])
    }
    
    func resolveFfmpegPath() -> String? {
        // 只使用打包的 ffmpeg
        if let bundledPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            if FileManager.default.isExecutableFile(atPath: bundledPath) {
                return bundledPath
            }
        }
        return nil
    }
    
    func resolveYtDlpPath() -> String {
        // Use bundled yt-dlp in app resources
        if let bundledPath = Bundle.main.path(forResource: "yt-dlp", ofType: nil) {
            if FileManager.default.isExecutableFile(atPath: bundledPath) {
                return bundledPath
            }
        }
        
        // Fallback: should not happen if properly bundled
        return ""
    }
    
    // MARK: - Task Management
    
    func addTask(
        url: String,
        outputFormat: String,
        videoQuality: String,
        audioQuality: String,
        destinationPath: String
    ) {
        let task = DownloadTask(
            url: url,
            outputFormat: outputFormat,
            videoQuality: videoQuality,
            audioQuality: audioQuality,
            destinationPath: destinationPath
        )
        
        DispatchQueue.main.async {
            self.tasks.insert(task, at: 0)
            self.saveTasks()  // 保存新任务
            // 任务添加后立即尝试开始下载
            self.startNextDownloadIfNeeded()
        }
    }
    
    /// 公开方法：启动所有等待中的任务
    func startAllWaitingTasks() {
        startNextDownloadIfNeeded()
    }
    
    private func startNextDownloadIfNeeded() {
        let activeCount = tasks.filter { $0.status == .downloading }.count
        guard activeCount < maxConcurrentDownloads else { return }
        
        if let nextTask = tasks.first(where: { $0.status == .waiting }) {
            startDownload(task: nextTask)
        }
    }
    
    // 从磁盘获取实际文件大小并格式化
    private func updateFileSizeFromDisk(task: DownloadTask) {
        let fileURL = URL(fileURLWithPath: task.filePath)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: task.filePath),
           let fileSize = attributes[.size] as? Int64 {
            // 格式化文件大小
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
            formatter.countStyle = .binary  // 使用 KiB, MiB, GiB
            let formattedSize = formatter.string(fromByteCount: fileSize)
            task.fileSize = formattedSize
            print("📊 Updated file size from disk: \(formattedSize) for \(fileURL.lastPathComponent)")
        }
    }
    
    func startDownload(task: DownloadTask, browser: String? = nil, forceYtDlp: Bool = false) {
        // Instagram 链接使用 gallery-dl（除非明确要求 yt-dlp）
        if !forceYtDlp && isInstagramURL(task.url) && galleryDlAvailable {
            startGalleryDlDownload(task: task, browser: browser)
            return
        }
        
        guard ytdlpAvailable else {
            DispatchQueue.main.async {
                task.status = .failed
                task.log += "\(self.logTS())[error] yt-dlp not found\n"
            }
            return
        }

        // 第一次下载时，自动使用系统默认浏览器的 cookies
        let effectiveBrowser: String?
        if browser == nil {
            let def = defaultBrowser()
            effectiveBrowser = def
            if let def {
                DispatchQueue.main.async { task.triedBrowsers.append(def) }
            }
        } else {
            effectiveBrowser = browser
        }

        DispatchQueue.main.async {
            task.status = .downloading
            task.isFetchingInfo = true  // 设置标识
            task.progress = ""  // 清空进度文案
            if let browser = effectiveBrowser {
                if task.triedBrowsers.count == 1 {
                    task.log += "\(self.logTS())[start] 开始下载（使用 \(browser.capitalized) Cookies）: \(task.url)\n"
                } else {
                    task.log += "\(self.logTS())[retry] 使用 \(browser.capitalized) Cookies 重试下载\n"
                }
            } else {
                task.log += "\(self.logTS())[start] 开始下载: \(task.url)\n"
            }
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        
        // 使用标准输出模板
        let outputTemplate = "\(task.destinationPath)/%(title)s.%(ext)s"
        let args = buildArguments(
            url: task.url,
            outputTemplate: outputTemplate,
            outputFormat: task.outputFormat,
            videoQuality: task.videoQuality,
            audioQuality: task.audioQuality,
            browser: effectiveBrowser
        )
        
        process.arguments = args
        
        var env = ProcessInfo.processInfo.environment
        
        // 将打包的工具路径添加到 PATH 前面，保留系统 PATH
        if let resourcePath = Bundle.main.resourcePath {
            let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = "\(resourcePath):\(currentPath)"
        }
        
        // 设置 ffmpeg 位置（yt-dlp 会使用这个环境变量）
        if let ffmpegPath = resolveFfmpegPath() {
            env["FFMPEG_LOCATION"] = (ffmpegPath as NSString).deletingLastPathComponent
        }
        
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let str = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    task.log += str
                    
                    // 按行分割处理，以便正确捕获跨行的数据
                    let lines = str.components(separatedBy: .newlines)
                    
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty { continue }
                        
                        // 提取时长
                        if task.duration.isEmpty {
                            // 匹配时长格式: "01:23:45" 或 "12:34" 或 "5:30"
                            let durationPattern = #"^\d{1,2}:\d{2}(:\d{2})?$"#
                            if let regex = try? NSRegularExpression(pattern: durationPattern),
                               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                                task.duration = trimmed
                                print("⏱️ Captured duration string: \(trimmed)")
                            }
                            // 匹配纯秒数格式（如 TikTok）: "45" 或 "123.5"
                            else if let seconds = Double(trimmed), seconds > 0 && seconds < 86400 {
                                // 转换秒数为 mm:ss 或 hh:mm:ss 格式
                                task.duration = self.formatDuration(seconds: Int(seconds))
                                print("⏱️ Captured duration from seconds: \(seconds)s -> \(task.duration)")
                            }
                        }
                        
                        // 提取缩略图 URL（可能会跨行）
                        // 如果已有不完整的 URL，尝试拼接扩展名
                        if !task.thumbnailURL.isEmpty && task.thumbnailURL.hasPrefix("http") && 
                           !task.thumbnailURL.contains(".jpg") && !task.thumbnailURL.contains(".jpeg") &&
                           !task.thumbnailURL.contains(".png") && !task.thumbnailURL.contains(".webp") {
                            // 单独的扩展名行（如 "c.jpg"），拼接到之前的 URL
                            if trimmed.count < 30 && !trimmed.hasPrefix("http") &&
                               (trimmed.hasSuffix(".jpg") || trimmed.hasSuffix(".jpeg") || 
                                trimmed.hasSuffix(".png") || trimmed.hasSuffix(".webp") ||
                                trimmed.contains(".jpg") || trimmed.contains(".jpeg") ||
                                trimmed.contains(".png") || trimmed.contains(".webp")) {
                                task.thumbnailURL += trimmed
                            }
                        }
                        // 如果还没有完整的缩略图 URL，尝试捕获新的
                        else if task.thumbnailURL.isEmpty || 
                                (!task.thumbnailURL.contains(".jpg") && !task.thumbnailURL.contains(".jpeg") &&
                                 !task.thumbnailURL.contains(".png") && !task.thumbnailURL.contains(".webp")) {
                            // 匹配完整的 URL（http:// 或 https:// 开头）
                            if (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) &&
                               !trimmed.contains(" ") {
                                // 如果 URL 看起来不完整（没有扩展名），暂存起来等待下一行
                                if !trimmed.hasSuffix(".jpg") && !trimmed.hasSuffix(".jpeg") && 
                                   !trimmed.hasSuffix(".png") && !trimmed.hasSuffix(".webp") {
                                    task.thumbnailURL = trimmed
                                } 
                                // 完整的 URL，直接保存
                                else {
                                    task.thumbnailURL = trimmed
                                }
                            }
                        }
                    }
                    
                    // Extract progress info
                    if str.contains("%") && str.contains("[download]") {
                        let lines = str.components(separatedBy: "\r")
                        if let lastLine = lines.last(where: { $0.contains("%") && $0.contains("[download]") }) {
                            // 解析: [download] 55.7% of 186.66MiB at 6.15MiB/s ETA 00:13
                            let pattern = #"([0-9.]+)%\s+of\s+([0-9.]+[KMGT]i?B).*?at\s+([0-9.]+[KMGT]i?B/s)"#
                            if let regex = try? NSRegularExpression(pattern: pattern),
                               let match = regex.firstMatch(in: lastLine, range: NSRange(lastLine.startIndex..., in: lastLine)) {
                                let percent = (lastLine as NSString).substring(with: match.range(at: 1))
                                let total = (lastLine as NSString).substring(with: match.range(at: 2))
                                let speed = (lastLine as NSString).substring(with: match.range(at: 3))
                                
                                // 保存文件大小（只在第一次捕获时保存，避免被音频流覆盖）
                                if task.fileSize.isEmpty {
                                    task.fileSize = total
                                }
                                
                                // 格式: 进度 30.7% · 6.15MiB/s · 共 186.66MiB
                                var progressText = "进度 \(percent)% · \(speed) · 共 \(total)"
                                
                                // 如果有时长，添加到后面
                                if !task.duration.isEmpty {
                                    progressText += " · 时长 \(task.duration)"
                                }
                                
                                task.isFetchingInfo = false  // 开始下载后取消获取信息状态
                                task.progress = progressText
                            } else {
                                // 如果解析失败，保留原始格式
                                task.isFetchingInfo = false
                                task.progress = lastLine.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    }
                    
                    // 提取文件路径 - 多种模式匹配
                    if task.filePath.isEmpty {
                        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // 模式0: --print after_move:filepath 输出的完整路径（绝对路径）
                        if trimmed.hasPrefix("/") && (trimmed.hasSuffix(".mp4") || trimmed.hasSuffix(".mp3") || 
                                                       trimmed.hasSuffix(".m4a") || trimmed.hasSuffix(".webm") ||
                                                       trimmed.hasSuffix(".mkv") || trimmed.hasSuffix(".mov") ||
                                                       trimmed.hasSuffix(".jpg") || trimmed.hasSuffix(".jpeg") ||
                                                       trimmed.hasSuffix(".png") || trimmed.hasSuffix(".webp") ||
                                                       trimmed.hasSuffix(".gif")) {
                            task.filePath = trimmed
                            print("📁 Captured file path from print: \(trimmed)")
                        }
                        // 模式1: "[download] Destination: /path/to/file.mp4"
                        if str.contains("Destination:") {
                            let parts = str.components(separatedBy: "Destination:")
                            if parts.count > 1 {
                                let path = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                                if !path.isEmpty {
                                    task.filePath = path
                                    print("📁 Captured file path from Destination: \(path)")
                                }
                            }
                        }
                        // 模式2: "[Merger] Merging formats into \"path/to/file.mp4\""
                        if str.contains("[Merger] Merging formats into") {
                            if let startIdx = str.range(of: "[Merger] Merging formats into \"")?.upperBound,
                               let endIdx = str[startIdx...].range(of: "\"")?.lowerBound {
                                let path = String(str[startIdx..<endIdx])
                                task.filePath = path
                                print("📁 Captured file path from Merger: \(path)")
                            }
                        }
                        // 模式3: "[download] /path/to/file.mp4 has already been downloaded"
                        if str.contains("has already been downloaded") {
                            if let startIdx = str.range(of: "[download] ")?.upperBound,
                               let endIdx = str.range(of: " has already been downloaded")?.lowerBound {
                                let path = String(str[startIdx..<endIdx])
                                task.filePath = path
                                print("📁 Captured file path from already downloaded: \(path)")
                            }
                        }
                        // 模式4: "[ExtractAudio] Destination: /path/to/file.mp3"
                        if str.contains("[ExtractAudio] Destination:") {
                            let parts = str.components(separatedBy: "[ExtractAudio] Destination:")
                            if parts.count > 1 {
                                let path = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                                if !path.isEmpty {
                                    task.filePath = path
                                    print("📁 Captured file path from ExtractAudio: \(path)")
                                }
                            }
                        }
                    }
                    
                    // 解析实际分辨率 - 优先捕获 --print 输出的分辨率
                    if task.actualResolution.isEmpty {
                        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        // --print %(resolution)s 输出格式: "1920x1080" 或 "1280x720" 单独一行
                        if let range = trimmed.range(of: "^\\d{3,4}x\\d{3,4}$", options: .regularExpression) {
                            task.actualResolution = String(trimmed[range])
                        }
                        // 或者在日志中匹配分辨率
                        else if let range = str.range(of: "\\b(\\d{3,4})x(\\d{3,4})\\b", options: .regularExpression) {
                            task.actualResolution = String(str[range])
                        }
                        // 匹配 "1080p" 或 "720p" 等格式
                        else if let range = str.range(of: "\\b(\\d{3,4})p\\b", options: .regularExpression) {
                            task.actualResolution = String(str[range])
                        }
                    }
                    
                    // 解析实际音频码率
                    if task.actualAudioQuality.isEmpty {
                        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        // --print %(abr)skbps 输出格式: "128kbps" 或 "192kbps" 单独一行
                        if let range = trimmed.range(of: "^\\d+kbps$", options: .regularExpression) {
                            task.actualAudioQuality = String(trimmed[range])
                        }
                        // 或者在日志中匹配音频码率
                        else if let range = str.range(of: "\\b(\\d+)k\\b", options: .regularExpression) {
                            let kbps = String(str[range])
                            task.actualAudioQuality = kbps + "bps"
                        }
                    }
                }
            }
        }
        
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                if task.status == .downloading {
                    if proc.terminationStatus == 0 {
                        task.status = .completed
                        task.log += "\n\(self?.logTS() ?? "")--- 下载完成 ---\n"
                        
                        // 下载完成后，获取实际文件大小
                        if !task.filePath.isEmpty {
                            self?.updateFileSizeFromDisk(task: task)
                        }
                    } else if proc.terminationStatus == 15 || proc.terminationStatus == 9 {
                        // SIGTERM or SIGKILL - user stopped
                        task.status = .stopped
                        task.log += "\n\(self?.logTS() ?? "")--- 已停止 ---\n"
                    } else {
                        // 检查是否是需要登录的错误
                        let needsLogin = self?.checkIfLoginRequired(log: task.log) ?? false
                        
                        if needsLogin {
                            // 只尝试本机已安装且有该域名 Cookie 的浏览器
                            let browsers = self?.availableBrowsers(for: task.url) ?? []
                            let nextBrowser = browsers.first { !task.triedBrowsers.contains($0) }
                            
                            if let browser = nextBrowser {
                                task.triedBrowsers.append(browser)
                                task.log += "\n\(self?.logTS() ?? "")--- 检测到需要登录，尝试使用 \(browser.capitalized) Cookies ---\n"
                                self?.startDownload(task: task, browser: browser)
                                return
                            } else {
                                // 所有浏览器都尝试过了
                                task.log += "\n\(self?.logTS() ?? "")--- 已尝试所有浏览器的 Cookies，均失败 ---\n"
                                // 在任务上标记需要登录，展示 Row 提示
                                task.requiresLogin = true
                            }
                        }
                        
                        task.status = .failed
                        task.log += "\n\(self?.logTS() ?? "")--- 下载失败 (status: \(proc.terminationStatus)) ---\n"
                    }
                }
                
                task.process = nil
                self?.saveTasks()  // 保存任务状态
                self?.startNextDownloadIfNeeded()
            }
        }
        
        task.process = process
        
        do {
            task.log += "\(logTS())执行: \(ytdlpPath) \(args.joined(separator: " "))\n"
            try process.run()
        } catch {
            DispatchQueue.main.async {
                task.status = .failed
                task.log += "\(self.logTS())启动失败: \(error.localizedDescription)\n"
            }
        }
    }
    
    private func buildArguments(
        url: String,
        outputTemplate: String,
        outputFormat: String,
        videoQuality: String,
        audioQuality: String,
        browser: String? = nil
    ) -> [String] {
        var args: [String] = []
        args += ["-o", outputTemplate]
        
        // 指定打包的 ffmpeg 位置
        if let ffmpegPath = resolveFfmpegPath() {
            let ffmpegDir = (ffmpegPath as NSString).deletingLastPathComponent
            args += ["--ffmpeg-location", ffmpegDir]
        }
        
        // 移除可能导致 416 错误的断点续传设置
        // 使用默认行为（.part 临时文件）更稳定
        args += ["--no-overwrites"]  // 如果文件已存在则跳过
        
        // 只下载单个视频，不下载播放列表/合集
        args += ["--no-playlist"]
        
        // 如果指定了浏览器，使用该浏览器的 cookies
        if let browser = browser {
            args += ["--cookies-from-browser", browser]
        }
        
        // 输出视频信息用于解析分辨率、音质、时长、文件路径和缩略图
        args += ["--print", "%(resolution)s"]
        args += ["--print", "%(abr)skbps"]  // 输出音频码率
        args += ["--print", "%(duration_string)s"]  // 输出时长（格式化字符串）
        args += ["--print", "%(duration)s"]  // 输出时长（秒数，作为备用）
        args += ["--print", "%(thumbnail)s"]  // 输出缩略图 URL
        args += ["--print", "after_move:filepath"]  // 输出最终文件路径
        args += ["--progress"]  // 强制显示下载进度
        
        let isAudioOnly = outputFormat == "mp3" || outputFormat == "m4a"
        
        if isAudioOnly {
            args += ["-f", "ba/b"]
            args += ["-x", "--audio-format", outputFormat]
            args += ["--audio-quality", audioQuality]
        } else {
            // 使用更宽松的格式选择器，支持 m3u8 等格式
            if let resLimit = parseResolutionLimit(from: videoQuality) {
                // 有分辨率限制时，提供多个回退选项（包括 m3u8）
                args += ["-f", "bv*[height<=\(resLimit)]+ba/b[height<=\(resLimit)]/b[height<=\(resLimit)]/best[height<=\(resLimit)]/best"]
            } else {
                // 没有分辨率限制，使用最佳质量
                args += ["-f", "bv*+ba/b/best"]
            }
            args += ["--merge-output-format", outputFormat]
        }
        
        args.append(url)
        return args
    }
    
    private func parseResolutionLimit(from quality: String) -> Int? {
        switch quality {
        case "2160p": return 2160
        case "1440p": return 1440
        case "1080p": return 1080
        case "720p": return 720
        case "480p": return 480
        case "360p": return 360
        case "240p": return 240
        case "144p": return 144
        default: return nil
        }
    }
    
    // MARK: - Gallery-dl Download (Instagram)
    
    private func startGalleryDlDownload(task: DownloadTask, browser: String? = nil) {
        guard galleryDlAvailable else {
            // gallery-dl 不可用时回退到 yt-dlp
            DispatchQueue.main.async {
                task.log += "\(self.logTS())[info] gallery-dl 不可用，回退到 yt-dlp\n"
            }
            startDownload(task: task, browser: browser, forceYtDlp: true)
            return
        }
        
        // 第一次下载时，自动使用系统默认浏览器的 cookies
        let effectiveBrowser: String?
        if browser == nil {
            let def = defaultBrowser()
            effectiveBrowser = def
            if let def {
                DispatchQueue.main.async { task.triedBrowsers.append(def) }
            }
        } else {
            effectiveBrowser = browser
        }
        
        DispatchQueue.main.async {
            task.status = .downloading
            task.isFetchingInfo = true
            task.isImageDownload = true
            task.progress = ""
            if let browser = effectiveBrowser {
                if task.triedBrowsers.count == 1 {
                    task.log += "\(self.logTS())[start] 使用 gallery-dl 下载（\(browser.capitalized) Cookies）: \(task.url)\n"
                } else {
                    task.log += "\(self.logTS())[retry] 使用 \(browser.capitalized) Cookies 重试下载\n"
                }
            } else {
                task.log += "\(self.logTS())[start] 使用 gallery-dl 下载: \(task.url)\n"
            }
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: galleryDlPath)
        
        var args: [String] = []
        
        // 基础目录
        args += ["-d", task.destinationPath]
        
        // 从 URL 提取 shortcode（/p/xxx、/reel/xxx、/tv/xxx）
        let shortcode = extractInstagramShortcode(from: task.url) ?? "unknown"
        
        // 子目录结构: instagram/{用户名}/{yyyyMMddHHmmss}_{shortcode}/
        // {date:%Y%m%d%H%M%S} 是帖子发布时间（年月日时分秒）
        args += ["-o", "directory=[\"instagram\", \"{username}\", \"{date:%Y%m%d%H%M%S}_\(shortcode)\"]"]
        
        // 文件名: 1.jpg, 2.jpg, 3.mp4 ...
        args += ["-f", "{num}.{extension}"]
        
        // 详细输出（用于解析进度和文件路径）
        args += ["-v"]
        
        // 如果指定了浏览器，使用该浏览器的 cookies
        if let browser = effectiveBrowser {
            args += ["--cookies-from-browser", browser]
        }
        
        args.append(task.url)
        
        process.arguments = args
        
        var env = ProcessInfo.processInfo.environment
        if let resourcePath = Bundle.main.resourcePath {
            let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = "\(resourcePath):\(currentPath)"
        }
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        var downloadedFiles: [String] = []
        var totalFileCount = 0
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let str = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    task.log += str
                    
                    let lines = str.components(separatedBy: .newlines)
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty { continue }
                        
                        task.isFetchingInfo = false
                        
                        // 提取缩略图 URL（Instagram 缩略图）
                        if task.thumbnailURL.isEmpty {
                            if let range = trimmed.range(of: "https://[^\\s\"']+\\.jpg[^\\s\"']*", options: .regularExpression) {
                                task.thumbnailURL = String(trimmed[range])
                            }
                        }
                        
                        // 捕获下载的文件路径
                        // gallery-dl 输出格式: "/path/to/file"
                        if trimmed.hasPrefix(task.destinationPath) || trimmed.hasPrefix("/") {
                            let possiblePath = trimmed
                            let imageExts = [".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic"]
                            let videoExts = [".mp4", ".mov", ".mkv", ".webm", ".m4v"]
                            let allExts = imageExts + videoExts
                            
                            if allExts.contains(where: { possiblePath.lowercased().hasSuffix($0) }) {
                                let isFirst = downloadedFiles.isEmpty
                                downloadedFiles.append(possiblePath)
                                totalFileCount = downloadedFiles.count
                                task.downloadedMediaCount = totalFileCount
                                task.filePath = possiblePath  // 保存最新的文件路径
                                task.progress = "已下载 \(totalFileCount) 个文件"
                                // 第一个下载文件作为封面，优先使用本地 file:// 路径，避免远程时效链接失效
                                if isFirst {
                                    task.thumbnailURL = "file://" + possiblePath
                                }
                                print("📁 gallery-dl downloaded: \(possiblePath)")
                            }
                        }
                        
                        // 匹配 gallery-dl 的下载动作日志
                        // 格式: "# https://..." 或 "[download] Writing ... to ..."
                        if trimmed.contains("Downloading") || trimmed.contains("Writing") {
                            totalFileCount += 1
                            task.progress = "正在下载第 \(totalFileCount) 个文件..."
                        }
                        
                        // 捕获 gallery-dl 的文件保存路径
                        // 格式: /path/to/instagram_xxx_1.jpg
                        if let range = trimmed.range(of: "(['\"]?)(/[^'\"\\s]+\\.(jpg|jpeg|png|webp|gif|mp4|mov|mkv|webm))\\1", options: .regularExpression) {
                            let matchedStr = String(trimmed[range])
                            let cleanPath = matchedStr.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                            if FileManager.default.fileExists(atPath: cleanPath) || cleanPath.hasPrefix(task.destinationPath) {
                                if !downloadedFiles.contains(cleanPath) {
                                    let isFirst = downloadedFiles.isEmpty
                                    downloadedFiles.append(cleanPath)
                                    task.downloadedMediaCount = downloadedFiles.count
                                    task.filePath = cleanPath
                                    task.progress = "已下载 \(downloadedFiles.count) 个文件"
                                    if isFirst {
                                        task.thumbnailURL = "file://" + cleanPath
                                    }
                                    print("📁 gallery-dl file: \(cleanPath)")
                                }
                            }
                        }
                    }
                }
            }
        }
        
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                if task.status == .downloading {
                    if proc.terminationStatus == 0 {
                        task.status = .completed
                        let fileCount = downloadedFiles.count
                        task.downloadedMediaCount = fileCount
                        task.totalMediaCount = fileCount  // 完成后用实际数修正总数确保100%
                        task.progress = fileCount > 0 ? "共下载 \(fileCount) 个文件" : "下载完成"
                        if task.isImageDownload, let firstFile = downloadedFiles.first {
                            task.thumbnailURL = "file://" + firstFile
                        }
                        task.log += "\n\(self?.logTS() ?? "")--- 下载完成（共 \(fileCount) 个文件）---\n"
                        
                        // 更新文件大小
                        if !task.filePath.isEmpty {
                            self?.updateFileSizeFromDisk(task: task)
                        }
                    } else if proc.terminationStatus == 15 || proc.terminationStatus == 9 {
                        task.status = .stopped
                        task.log += "\n\(self?.logTS() ?? "")--- 已停止 ---\n"
                    } else {
                        // 检查是否需要登录
                        let needsLogin = task.log.lowercased().contains("login") || 
                                        task.log.lowercased().contains("401") ||
                                        task.log.lowercased().contains("authentication") ||
                                        task.log.contains("请先登录")
                        
                        if needsLogin {
                            let browsers = self?.availableBrowsers(for: task.url) ?? []
                            let nextBrowser = browsers.first { !task.triedBrowsers.contains($0) }
                            
                            if let browser = nextBrowser {
                                task.triedBrowsers.append(browser)
                                task.log += "\n\(self?.logTS() ?? "")--- 检测到需要登录，尝试使用 \(browser.capitalized) Cookies ---\n"
                                self?.startGalleryDlDownload(task: task, browser: browser)
                                return
                            } else {
                                task.requiresLogin = true
                                task.log += "\n\(self?.logTS() ?? "")--- 已尝试所有浏览器的 Cookies，均失败 ---\n"
                            }
                        }
                        
                        task.status = .failed
                        task.log += "\n\(self?.logTS() ?? "")--- 下载失败 (status: \(proc.terminationStatus)) ---\n"
                    }
                }
                
                task.process = nil
                self?.saveTasks()
                self?.startNextDownloadIfNeeded()
            }
        }
        
        task.process = process
        
        do {
            task.log += "\(logTS())执行: \(galleryDlPath) \(args.joined(separator: " "))\n"
            try process.run()
        } catch {
            DispatchQueue.main.async {
                task.status = .failed
                task.log += "\(self.logTS())启动失败: \(error.localizedDescription)\n"
            }
        }
    }
    
    // MARK: - Log Helpers

    /// 返回当前时间戳字符串，格式 [HH:mm:ss]
    private func logTS() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return "[\(f.string(from: Date()))] "
    }

    // 检测是否需要登录
    /// 返回本机已安装、且 Cookie 数据库中有目标域名记录的浏览器列表（默认浏览器优先）
    private func availableBrowsers(for url: String) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let domain = URL(string: url)?.host ?? ""
        let checks: [(String, String)] = [
            ("chrome",  "\(home)/Library/Application Support/Google/Chrome"),
            ("safari",  "\(home)/Library/Cookies/Cookies.binarycookies"),
            ("edge",    "\(home)/Library/Application Support/Microsoft Edge"),
            ("firefox", "\(home)/Library/Application Support/Firefox/Profiles"),
        ]
        let detected = checks.compactMap { (browser, path) -> String? in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return hasCookiesForDomain(browser: browser, domain: domain) ? browser : nil
        }
        // 将系统默认浏览器排到第一位
        let def = defaultBrowser()
        if let def, let idx = detected.firstIndex(of: def), idx != 0 {
            var sorted = detected
            sorted.remove(at: idx)
            sorted.insert(def, at: 0)
            return sorted
        }
        return detected
    }

    /// 获取 macOS 系统默认浏览器名称（chrome/safari/firefox/edge），识别不到返回 nil
    private func defaultBrowser() -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
              let bundleID = Bundle(url: appURL)?.bundleIdentifier else { return nil }
        let id = bundleID.lowercased()
        if id.contains("chrome")  { return "chrome" }
        if id.contains("firefox") { return "firefox" }
        if id.contains("edge")    { return "edge" }
        if id.contains("safari")  { return "safari" }
        return nil
    }

    /// 检查指定浏览器的 Cookie 数据库中是否存在该域名的记录
    /// Chrome/Edge/Firefox 查 SQLite；Safari 只检查是否安装（格式无法直接解析）
    private func hasCookiesForDomain(browser: String, domain: String) -> Bool {
        guard !domain.isEmpty else { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let rootDomain = extractRootDomain(from: domain)

        switch browser {
        case "chrome":
            return queryChromiumCookies(baseDir: "\(home)/Library/Application Support/Google/Chrome",
                                        domain: rootDomain)
        case "edge":
            return queryChromiumCookies(baseDir: "\(home)/Library/Application Support/Microsoft Edge",
                                        domain: rootDomain)
        case "firefox":
            let profilesPath = "\(home)/Library/Application Support/Firefox/Profiles"
            guard let profiles = try? FileManager.default.contentsOfDirectory(atPath: profilesPath) else { return true }
            for profile in profiles {
                let db = "\(profilesPath)/\(profile)/cookies.sqlite"
                if queryCookieDB(at: db, domain: rootDomain, table: "moz_cookies", hostColumn: "host") {
                    return true
                }
            }
            return false
        case "safari":
            // Safari cookie 格式为二进制 plist，无法简单查询，安装即视为可用
            return true
        default:
            return true
        }
    }

    /// 遍历 Chromium 系所有 Profile 目录查找 Cookie（解决多 Profile 问题）
    private func queryChromiumCookies(baseDir: String, domain: String) -> Bool {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: baseDir) else { return false }
        // Profile 目录名：Default, Profile 1, Profile 2, ...
        let profileDirs = entries.filter { $0 == "Default" || $0.hasPrefix("Profile ") }
        for dir in profileDirs {
            let db = "\(baseDir)/\(dir)/Cookies"
            if queryCookieDB(at: db, domain: domain, table: "cookies", hostColumn: "host_key") {
                return true
            }
        }
        return false
    }

    /// 从域名中提取根域名，如 www.instagram.com -> instagram.com
    private func extractRootDomain(from domain: String) -> String {
        let parts = domain.split(separator: ".").map(String.init)
        if parts.count >= 2 { return parts.suffix(2).joined(separator: ".") }
        return domain
    }

    /// 复制 SQLite 文件到临时目录后查询，避免浏览器锁定问题
    private func queryCookieDB(at path: String, domain: String, table: String, hostColumn: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return false }

        let tmpPath = NSTemporaryDirectory() + "isave_ck_\(UUID().uuidString).sqlite"
        defer { try? fm.removeItem(atPath: tmpPath) }

        do {
            try fm.copyItem(atPath: path, toPath: tmpPath)
        } catch {
            return true // 无法读取时保守处理：让 yt-dlp 去尝试
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [tmpPath, "SELECT COUNT(*) FROM \(table) WHERE \(hostColumn) LIKE '%\(domain)%';"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return true
        }
        let output = (try? pipe.fileHandleForReading.readToEnd())
            .flatMap { String(data: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        return (Int(output) ?? 0) > 0
    }

    private func checkIfLoginRequired(log: String) -> Bool {
        let loginKeywords = [
            "unavailable for certain audiences",
            "login required",
            "Sign in to confirm",
            "private video",
            "members-only",
            "This video is private",
            "requires authentication",
            "requires sign in",
            "This content may be inappropriate",
            "age-restricted",
            "请先登录",
            "需要登录"
        ]
        
        let lowercasedLog = log.lowercased()
        return loginKeywords.contains { keyword in
            lowercasedLog.contains(keyword.lowercased())
        }
    }
    
    // MARK: - Pause / Resume / Stop
    
    func pauseTask(_ task: DownloadTask) {
        guard let process = task.process, task.status == .downloading else { return }
        
        // 获取进程 ID，发送 SIGSTOP 信号到整个进程组
        let pid = process.processIdentifier
        kill(-pid, SIGSTOP)  // 负号表示发送到整个进程组
        
        DispatchQueue.main.async {
            task.status = .paused
            task.log += "\n\(self.logTS())--- 已暂停 ---\n"
        }
    }
    
    func resumeTask(_ task: DownloadTask) {
        guard let process = task.process, task.status == .paused else { return }
        
        // 发送 SIGCONT 信号到整个进程组，恢复所有子进程
        let pid = process.processIdentifier
        kill(-pid, SIGCONT)  // 负号表示发送到整个进程组
        
        DispatchQueue.main.async {
            task.status = .downloading
            task.log += "\n\(self.logTS())--- 继续下载 ---\n"
        }
    }
    
    func stopTask(_ task: DownloadTask) {
        if let process = task.process {
            process.terminate()
        }
        
        DispatchQueue.main.async {
            task.status = .stopped
            task.log += "\n\(self.logTS())--- 已停止 ---\n"
            task.process = nil
        }
        
        startNextDownloadIfNeeded()
    }
    
    func retryTask(_ task: DownloadTask) {
        DispatchQueue.main.async {
            // 清除之前的错误状态
            task.status = .waiting
            task.triedBrowsers.removeAll()
            task.requiresLogin = false  // 重试时重置登录提示
            task.progress = ""
            task.log += "\n\(self.logTS())--- 重新尝试下载 ---\n"
        }
        
        // 立即启动下载，不等待队列
        startDownload(task: task)
    }
    
    func removeTask(_ task: DownloadTask) {
        if task.status == .downloading || task.status == .paused {
            stopTask(task)
        }
        
        DispatchQueue.main.async {
            self.tasks.removeAll { $0.id == task.id }
            self.saveTasks()  // 保存更改
        }
    }
    
    // 清空所有下载记录（不删除文件）
    func clearAllTasks() {
        // 停止所有正在下载的任务
        for task in tasks where task.status == .downloading || task.status == .paused {
            stopTask(task)
        }
        
        DispatchQueue.main.async {
            self.tasks.removeAll()
            self.saveTasks()  // 清空持久化数据
        }
    }
    
    // MARK: - Persistence
    
    private func saveTasks() {
        let records = tasks.map { DownloadRecord(from: $0, completedAt: nil) }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: tasksKey)
        }
    }
    
    private func loadTasks() {
        if let data = UserDefaults.standard.data(forKey: tasksKey),
           let records = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            // 将持久化的记录转换回 DownloadTask
            tasks = records.map { record in
                let task = DownloadTask(
                    id: record.id,
                    url: record.url,
                    createdAt: record.createdAt,
                    outputFormat: record.outputFormat,
                    videoQuality: record.videoQuality,
                    audioQuality: record.audioQuality,
                    destinationPath: record.destinationPath,
                    status: record.status
                )
                // 恢复运行时信息
                task.actualResolution = record.actualResolution
                task.actualAudioQuality = record.actualAudioQuality
                task.duration = record.duration
                task.fileSize = record.fileSize
                task.filePath = record.filePath
                task.thumbnailURL = record.thumbnailURL
                task.progress = record.progress
                task.isImageDownload = record.isImageDownload
                task.downloadedMediaCount = record.downloadedMediaCount
                task.totalMediaCount = record.totalMediaCount
                
                // 兼容旧记录：IG 缩略图若仍是远程 URL，优先切换到本地已下载文件
                if task.isImageDownload,
                   !task.filePath.isEmpty,
                   FileManager.default.fileExists(atPath: task.filePath),
                   !task.thumbnailURL.hasPrefix("file://") {
                    task.thumbnailURL = "file://" + task.filePath
                }
                return task
            }
        }
    }
}
