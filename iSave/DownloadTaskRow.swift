import SwiftUI
import AppKit
import AVFoundation

// MARK: - Debug Configuration
// 设置为 true 显示日志展开按钮，设置为 false 隐藏
let SHOW_LOG_BUTTON = false

// 自定义缩略图加载器
struct ThumbnailView: View {
    let taskID: UUID
    let url: String
    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var loadFailed = false
    
    /// 本地缩略图缓存目录
    static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ceaule.iSave")
            .appendingPathComponent("thumbnails")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    private var localCachePath: URL {
        ThumbnailView.cacheDir.appendingPathComponent("\(taskID.uuidString).jpg")
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if isLoading {
                ProgressView()
                    .frame(width: 120, height: 68)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 68)
                    .overlay(
                        VStack(spacing: 2) {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("加载失败")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    )
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        // 0. 处理本地文件（file:// 开头）
        if url.hasPrefix("file://") {
            let localPath = String(url.dropFirst(7))
            let videoExts = ["mp4", "mov", "mkv", "webm", "m4v"]
            let ext = (localPath as NSString).pathExtension.lowercased()
            
            if videoExts.contains(ext) {
                // 视频文件：提取第一帧
                DispatchQueue.global(qos: .userInitiated).async {
                    let asset = AVAsset(url: URL(fileURLWithPath: localPath))
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 240, height: 240)
                    let time = CMTime(seconds: 0, preferredTimescale: 600)
                    let cgImage = try? generator.copyCGImage(at: time, actualTime: nil)
                    DispatchQueue.main.async {
                        self.isLoading = false
                        if let cgImage {
                            self.image = NSImage(cgImage: cgImage, size: .zero)
                        } else {
                            self.loadFailed = true
                        }
                    }
                }
            } else {
                // 图片文件：直接加载
                DispatchQueue.global(qos: .userInitiated).async {
                    let nsImage = NSImage(contentsOfFile: localPath)
                    DispatchQueue.main.async {
                        self.isLoading = false
                        if let nsImage {
                            self.image = nsImage
                        } else {
                            self.loadFailed = true
                        }
                    }
                }
            }
            return
        }
        
        // 1. 优先从本地磁盘加载
        if FileManager.default.fileExists(atPath: localCachePath.path),
           let nsImage = NSImage(contentsOf: localCachePath) {
            self.image = nsImage
            self.isLoading = false
            return
        }
        
        // 2. 本地没有，从远程加载
        // 强制升级为 HTTPS（B 站 CDN 等部分平台返回 http:// 缩略图链接）
        let secureUrl = url.hasPrefix("http://") ? "https://" + url.dropFirst(7) : url
        guard let imageURL = URL(string: secureUrl) else {
            isLoading = false
            loadFailed = true
            return
        }
        
        var request = URLRequest(url: imageURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if error != nil {
                    loadFailed = true
                    return
                }
                
                guard let data = data, let nsImage = NSImage(data: data) else {
                    loadFailed = true
                    return
                }
                
                self.image = nsImage
                
                // 3. 存到本地磁盘，下次直接读本地
                DispatchQueue.global(qos: .background).async {
                    try? data.write(to: localCachePath)
                }
            }
        }.resume()
    }
}

struct DownloadTaskRow: View {
    @ObservedObject var task: DownloadTask
    @ObservedObject var manager: DownloadManager
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var showLog: Bool = true
    @State private var showLoginPopover: Bool = false
    @AppStorage("showThumbnails") private var showThumbnails: Bool = true
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // 缩略图
            if showThumbnails {
                if !task.thumbnailURL.isEmpty {
                    ThumbnailView(taskID: task.id, url: task.thumbnailURL)
                        .transition(.opacity)
                } else {
                    // 占位图
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 120, height: 68)
                        .overlay(
                            Image(systemName: task.isImageDownload ? "photo" : "video")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        )
                        .transition(.opacity)
                }
            } else {
                // 隐藏时的占位
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.08))
                    .frame(width: 120, height: 68)
                    .overlay(
                        Image(systemName: "eye.slash")
                            .font(.title3)
                            .foregroundStyle(.secondary.opacity(0.4))
                    )
                    .transition(.opacity)
            }
            
            VStack(alignment: .leading, spacing: 5) {
                // Header row
                HStack(alignment: .center, spacing: 12) {
                    // Status indicator
                    Circle()
                        .fill(task.statusColor)
                        .frame(width: 10, height: 10)
                    
                    // Status text
                    Text(task.status.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(task.statusColor.opacity(0.2))
                        .cornerRadius(4)
                    
                    // URL
                    Text(task.url)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    // 需要登录提示
                    if task.requiresLogin {
                        Button {
                            showLoginPopover = true
                        } label: {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .help(LocalizedString("toast.login_required.title"))
                        .popover(isPresented: $showLoginPopover, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(LocalizedString("toast.login_required.title"), systemImage: "lock.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.orange)
                                Text(String(format: LocalizedString("toast.login_required.message"), URL(string: task.url)?.host ?? task.url))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(maxWidth: 280)
                        }
                    }
                }
                
                // Info row
                HStack(spacing: 12) {
                    if !task.isImageDownload {
                        Label(task.outputFormat.uppercased(), systemImage: "doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        // 根据格式类型决定显示视频质量还是音频质量
                        let isAudioOnly = task.outputFormat == "mp3" || task.outputFormat == "m4a"
                        if !isAudioOnly {
                            let displayQuality = task.actualResolution.isEmpty ? (task.videoQuality == "best" ? LocalizedString("quality.best") : task.videoQuality) : task.actualResolution
                            Label(displayQuality, systemImage: "tv")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label(task.actualAudioQuality.isEmpty ? task.audioQuality : task.actualAudioQuality, systemImage: "waveform")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // 进度条（常显）
                    HStack(spacing: 4) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // 背景（灰色）
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 4)
                                
                                // 已完成部分（绿色）
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.green)
                                    .frame(width: geometry.size.width * progressPercentage, height: 4)
                            }
                        }
                        .frame(width: 80, height: 4)
                        
                        // 进度百分比
                        Text(progressText)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                    
                    // 进度信息（不含文件名）
                    if task.status == .downloading || task.status == .paused {
                        // 下载中显示进度详情（速度、大小、ETA）或获取信息提示
                        if task.isFetchingInfo || !task.progress.isEmpty || (task.isImageDownload && task.downloadedMediaCount > 0) {
                            Text(buildProgressInfo())
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else if task.status == .completed {
                        // 完成后显示: 共 XX · 时长 XX
                        if task.isImageDownload {
                            // IG 任务直接显示文件数（task.progress 已是"共下载 N 个文件"）
                            if !task.progress.isEmpty {
                                Text(task.progress)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else if !task.filePath.isEmpty {
                            Text(buildCompletedInfo())
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                }
                
                // 文件名单独一行（IG 任务不显示）
                if !task.isImageDownload && shouldShowFileName() {
                    HStack(spacing: 4) {
                        Text(getFileName())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)  // 中间截断，保留开头和后缀
                        
                        Spacer()
                    }
                }
            
            // Log (expandable) - 通过 SHOW_LOG_BUTTON 宏控制
            if SHOW_LOG_BUTTON && showLog {
                ScrollView {
                    Text(task.log.isEmpty ? LocalizedString("main.no_history") : task.log)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 150)
                .padding(8)
                .background(Color.black.opacity(0.05))
                .cornerRadius(4)
            }
        }
        .frame(minHeight: 68)
        
        Spacer()
        
        // 右侧控制区域（垂直居中）
        HStack(spacing: 16) {
            // 更多操作菜单按钮
            Menu {
                // 单个任务操作
                if task.status == .completed && !task.filePath.isEmpty {
                    Button {
                        openFileInFinder(path: task.filePath)
                    } label: {
                        Label(LocalizedString("action.show_in_finder"), systemImage: "folder")
                    }
                }
                
                Button {
                    copyLinkToClipboard()
                } label: {
                    Label(LocalizedString("action.copy_link"), systemImage: "doc.on.doc")
                }
                
                Button {
                    openLinkInBrowser()
                } label: {
                    Label(LocalizedString("action.open_in_browser"), systemImage: "safari")
                }
                
                Divider()
                
                if task.status == .waiting || task.status == .stopped {
                    Button {
                        manager.retryTask(task)
                    } label: {
                        Label(LocalizedString("action.continue_task"), systemImage: "play.fill")
                    }
                }
                
                if task.status == .downloading {
                    Button {
                        manager.stopTask(task)
                    } label: {
                        Label(LocalizedString("action.pause_task"), systemImage: "pause.fill")
                    }
                }
                
                Button(role: .destructive) {
                    manager.removeTask(task)
                } label: {
                    Label(LocalizedString("action.delete_task"), systemImage: "trash")
                }
                
                Divider()
                
                // 全局操作
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("PasteAndDownload"), object: nil)
                } label: {
                    Label(LocalizedString("action.paste"), systemImage: "doc.on.clipboard")
                }
                
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("StartAllTasks"), object: nil)
                } label: {
                    Label(LocalizedString("action.start_all"), systemImage: "play.fill")
                }
                
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("StopAllTasks"), object: nil)
                } label: {
                    Label(LocalizedString("action.stop_all"), systemImage: "pause.fill")
                }
                
                Button(role: .destructive) {
                    NotificationCenter.default.post(name: NSNotification.Name("ClearAllTasks"), object: nil)
                } label: {
                    Label(LocalizedString("action.clear_all"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(LocalizedString("action.more"))
            
            // 文件夹按钮（移到删除按钮左边）
            if !task.filePath.isEmpty {
                Button {
                    if !task.filePath.isEmpty {
                        // 如果有文件路径，打开并选中文件
                        openFileInFinder(path: task.filePath)
                    } else {
                        // 否则打开目标文件夹
                        openFolder(path: task.destinationPath)
                    }
                } label: {
                    Label("", systemImage: "folder")
                        .font(.title3)
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(task.filePath.isEmpty ? task.destinationPath : task.filePath)
            }
            
            // 重试按钮
            if task.canRetry {
                Button {
                    manager.retryTask(task)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help(LocalizedString("action.retry"))
            }
            
            // 暂停/恢复按钮（下载中或暂停时显示）
            if task.status == .downloading || task.status == .paused {
                Button {
                    if task.status == .downloading {
                        manager.pauseTask(task)
                    } else {
                        manager.resumeTask(task)
                    }
                } label: {
                    Image(systemName: task.status == .downloading ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help(task.status == .downloading ? LocalizedString("action.pause") : LocalizedString("action.resume"))
            }
            
            // 删除按钮
            Button {
                manager.removeTask(task)
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help(LocalizedString("action.remove"))
        }
        }
        .frame(maxWidth: .infinity, alignment: .leading)  // 确保占据整行宽度
        .contentShape(Rectangle())  // 确保整个区域可以响应交互
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contextMenu {
            // 单个任务操作
            if task.status == .completed && !task.filePath.isEmpty {
                Button {
                    openFileInFinder(path: task.filePath)
                } label: {
                    Label(LocalizedString("action.show_in_finder"), systemImage: "folder")
                }
            }
            
            Button {
                copyLinkToClipboard()
            } label: {
                Label(LocalizedString("action.copy_link"), systemImage: "doc.on.doc")
            }
            
            Button {
                openLinkInBrowser()
            } label: {
                Label(LocalizedString("action.open_in_browser"), systemImage: "safari")
            }
            
            Divider()
            
            if task.status == .waiting || task.status == .stopped {
                Button {
                    manager.retryTask(task)
                } label: {
                    Label(LocalizedString("action.continue_task"), systemImage: "play.fill")
                }
            }
            
            if task.status == .downloading {
                Button {
                    manager.stopTask(task)
                } label: {
                    Label(LocalizedString("action.pause_task"), systemImage: "pause.fill")
                }
            }
            
            Button(role: .destructive) {
                manager.removeTask(task)
            } label: {
                Label(LocalizedString("action.delete_task"), systemImage: "trash")
            }
            
            Divider()
            
            // 全局操作
            Button {
                pasteAndDownloadFromContextMenu()
            } label: {
                Label(LocalizedString("action.paste"), systemImage: "doc.on.clipboard")
            }
            
            Button {
                startAllTasksFromContextMenu()
            } label: {
                Label(LocalizedString("action.start_all"), systemImage: "play.fill")
            }
            .disabled(!hasWaitingOrStoppedTasks)
            
            Button {
                stopAllTasksFromContextMenu()
            } label: {
                Label(LocalizedString("action.stop_all"), systemImage: "pause.fill")
            }
            .disabled(!hasDownloadingTasks)
            
            Button(role: .destructive) {
                clearAllTasksFromContextMenu()
            } label: {
                Label(LocalizedString("action.clear_all"), systemImage: "trash")
            }
        }
    }
    
    // 计算进度百分比
    private var progressPercentage: Double {
        // IG 任务：基于文件数计算
        if task.isImageDownload {
            if task.status == .completed { return 1.0 }
            if task.downloadedMediaCount == 0 { return 0.0 }
            if task.totalMediaCount > 0 {
                return min(Double(task.downloadedMediaCount) / Double(task.totalMediaCount), 1.0)
            }
            // 总数未知时，用渐近函数估算（下得越多越接近但不到 100%）
            return min(Double(task.downloadedMediaCount) / Double(task.downloadedMediaCount + 1), 0.95)
        }
        
        // 已完成任务显示 100%
        if task.status == .completed {
            return 1.0
        }
        
        // 从进度字符串中提取百分比
        // 格式如: "[download] 29.5% of 162.97MiB at 7.52MiB/s ETA 00:15"
        let progressStr = task.progress
        if let range = progressStr.range(of: "\\d+\\.?\\d*%", options: .regularExpression) {
            let percentStr = String(progressStr[range]).replacingOccurrences(of: "%", with: "")
            if let percent = Double(percentStr) {
                return percent / 100.0
            }
        }
        
        return 0.0
    }
    
    // 进度文本
    private var progressText: String {
        // IG 任务：基于文件数
        if task.isImageDownload {
            if task.status == .completed { return "100%" }
            let pct = Int(progressPercentage * 100)
            return "\(pct)%"
        }
        
        if task.status == .completed {
            return "100%"
        }
        
        let progressStr = task.progress
        if let range = progressStr.range(of: "\\d+\\.?\\d*%", options: .regularExpression) {
            return String(progressStr[range])
        }
        
        return "0%"
    }
    
    // 构建完成后的文本
    private func buildCompletedText() -> String {
        let fileName = URL(fileURLWithPath: task.filePath).lastPathComponent
        var completedText = ""
        
        if !task.fileSize.isEmpty {
            completedText += "\(LocalizedString("info.total")) \(task.fileSize)"
        }
        
        if !task.duration.isEmpty {
            if !completedText.isEmpty {
                completedText += " · "
            }
            completedText += "\(LocalizedString("info.duration")) \(task.duration)"
        }
        
        if !completedText.isEmpty {
            completedText += " · "
        }
        completedText += fileName
        
        return completedText
    }
    
    // 构建下载中的进度文本，包含文件名
    private func buildProgressWithFileName() -> String {
        // 解析 task.progress: 进度 55.7% · 6.15MiB/s · 共 186.66MiB · 时长 10:06
        // 去掉“进度 XX%”部分，只保留后面的信息
        var text = task.progress
        
        // 匹配并移除“进度 XX%”
        if let range = text.range(of: #"进度 [0-9.]+%\s*·\s*"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        
        // 如果有文件路径，添加文件名
        if !task.filePath.isEmpty {
            let fileName = URL(fileURLWithPath: task.filePath).lastPathComponent
            if !text.isEmpty {
                text += " · "
            }
            text += fileName
        }
        
        return text
    }
    
    // MARK: - Context Menu Actions
    
    /// 是否有等待或停止的任务
    private var hasWaitingOrStoppedTasks: Bool {
        manager.tasks.contains { $0.status == .waiting || $0.status == .stopped }
    }
    
    /// 是否有下载中的任务
    private var hasDownloadingTasks: Bool {
        manager.tasks.contains { $0.status == .downloading }
    }
    
    /// 复制链接到剪切板
    private func copyLinkToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(task.url, forType: .string)
    }
    
    /// 在浏览器中打开链接
    private func openLinkInBrowser() {
        if let url = URL(string: task.url) {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// 从右键菜单粘贴并下载
    private func pasteAndDownloadFromContextMenu() {
        NotificationCenter.default.post(name: NSNotification.Name("PasteAndDownload"), object: nil)
    }
    
    /// 从右键菜单开始所有任务
    private func startAllTasksFromContextMenu() {
        NotificationCenter.default.post(name: NSNotification.Name("StartAllTasks"), object: nil)
    }
    
    /// 从右键菜单停止所有任务
    private func stopAllTasksFromContextMenu() {
        NotificationCenter.default.post(name: NSNotification.Name("StopAllTasks"), object: nil)
    }
    
    /// 从右键菜单清空所有任务
    private func clearAllTasksFromContextMenu() {
        NotificationCenter.default.post(name: NSNotification.Name("ClearAllTasks"), object: nil)
    }
    
    // 打开文件在访达中
    private func openFileInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
    
    // 判断是否应该显示文件名行
    private func shouldShowFileName() -> Bool {
        if task.status == .downloading || task.status == .paused {
            return !task.filePath.isEmpty
        } else if task.status == .completed {
            return !task.filePath.isEmpty
        }
        return false
    }
    
    // 获取文件名
    private func getFileName() -> String {
        if task.filePath.isEmpty {
            return ""
        }
        return URL(fileURLWithPath: task.filePath).lastPathComponent
    }
    
    // 构建下载中的进度信息（不含文件名）
    private func buildProgressInfo() -> String {
        // 如果正在获取信息，返回动态翻译的文案
        if task.isFetchingInfo {
            if task.isImageDownload {
                return LocalizedString("status.fetching_media_info")
            }            
            let isAudioOnly = task.outputFormat == "mp3" || task.outputFormat == "m4a"
            return isAudioOnly ? LocalizedString("status.fetching_audio_info") : LocalizedString("status.fetching_info")
        }
        
        // IG 任务：显示已下载文件数
        if task.isImageDownload {
            if task.downloadedMediaCount > 0 {
                return "已下载 \(task.downloadedMediaCount) 个文件"
            }
            return ""
        }
        
        // 解析 task.progress: 进度 55.7% · 6.15MiB/s · 共 186.66MiB · 时长 10:06
        // 去掉"进度 XX%"部分，只保留后面的信息
        var text = task.progress
        
        // 匹配并移除"进度 XX%"
        if let range = text.range(of: #"进度 [0-9.]+%\s*·\s*"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        
        return text
    }
    
    // 构建完成后的信息（不含文件名）
    private func buildCompletedInfo() -> String {
        var completedText = ""
        
        if !task.fileSize.isEmpty {
            completedText += "\(LocalizedString("info.total")) \(task.fileSize)"
        }
        
        if !task.duration.isEmpty {
            if !completedText.isEmpty {
                completedText += " · "
            }
            completedText += "\(LocalizedString("info.duration")) \(task.duration)"
        }
        
        return completedText
    }
    
    // 打开文件夹
    private func openFolder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
}
