import SwiftUI
import AppKit
internal import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var versionChecker = VersionChecker.shared
    @EnvironmentObject var languageManager: LanguageManager
    
    @State private var urlText: String = ""
    @AppStorage("downloadDestination") private var downloadDestinationRaw: String = "downloads"
    @AppStorage("customDownloadPath") private var customDownloadPath: String = ""
    @State private var showSettings = false
    @State private var showClearConfirmation = false
    @State private var showEmptyClipboardAlert = false
    @State private var showInvalidLinkAlert = false
    @AppStorage("showThumbnails") private var showThumbnails: Bool = true

    enum OutputKind: String, CaseIterable, Identifiable {
        // 视频格式
        case mp4, mkv
        // 音频格式
        case mp3, m4a

        var id: String { rawValue }

        var isAudioOnly: Bool {
            switch self {
            case .mp3, .m4a: return true
            default: return false
            }
        }
        
        var displayName: String {
            switch self {
            case .mp4: return "\(rawValue) (\(LocalizedString("format.video")))"
            case .mp3: return "\(rawValue) (\(LocalizedString("format.audio")))"
            default: return rawValue
            }
        }
    }

    enum VideoQuality: String, CaseIterable, Identifiable {
        case best, p2160, p1440, p1080, p720, p480, p360, p240, p144

        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .best: return LocalizedString("quality.best")
            case .p2160: return LocalizedString("quality.2160p")
            case .p1440: return LocalizedString("quality.1440p")
            case .p1080: return LocalizedString("quality.1080p")
            case .p720: return LocalizedString("quality.720p")
            case .p480: return LocalizedString("quality.480p")
            case .p360: return LocalizedString("quality.360p")
            case .p240: return LocalizedString("quality.240p")
            case .p144: return LocalizedString("quality.144p")
            }
        }

        var heightLimit: Int? {
            switch self {
            case .best: return nil
            case .p2160: return 2160
            case .p1440: return 1440
            case .p1080: return 1080
            case .p720: return 720
            case .p480: return 480
            case .p360: return 360
            case .p240: return 240
            case .p144: return 144
            }
        }
        
        var ytdlpValue: String {
            switch self {
            case .best: return "best"
            case .p2160: return "2160p"
            case .p1440: return "1440p"
            case .p1080: return "1080p"
            case .p720: return "720p"
            case .p480: return "480p"
            case .p360: return "360p"
            case .p240: return "240p"
            case .p144: return "144p"
            }
        }
    }

    enum AudioQuality: CaseIterable, Identifiable {
        case kbps320, kbps256, kbps192, kbps128, kbps96, kbps64

        var id: String { ytdlpValue }

        var ytdlpValue: String {
            switch self {
            case .kbps320: return "320K"
            case .kbps256: return "256K"
            case .kbps192: return "192K"
            case .kbps128: return "128K"
            case .kbps96:  return "96K"
            case .kbps64:  return "64K"
            }
        }

        var label: String {
            switch self {
            case .kbps320: return "320 kbps"
            case .kbps256: return "256 kbps"
            case .kbps192: return "192 kbps"
            case .kbps128: return "128 kbps"
            case .kbps96:  return "96 kbps"
            case .kbps64:  return "64 kbps"
            }
        }
    }

    enum DownloadDestination: String, CaseIterable, Identifiable {
        case downloads
        case desktop
        case movies
        case custom

        var id: String { rawValue }

        var label: String {
            switch self {
            case .downloads: return LocalizedString("destination.downloads")
            case .desktop: return LocalizedString("destination.desktop")
            case .movies: return LocalizedString("destination.movies")
            case .custom: return LocalizedString("destination.custom")
            }
        }
    }

    @State private var downloadDestination: DownloadDestination = .downloads
    @State private var outputKind: OutputKind = .mp4
    @State private var videoQuality: VideoQuality = .best
    @State private var audioQuality: AudioQuality = .kbps320
    
    /// 当前保存路径（用于显示）
    private var currentSavePath: String {
        if !customDownloadPath.isEmpty {
            return customDownloadPath
        }
        return resolveDestinationFolderPath()
    }
    
    /// 下拉菜单显示的文本
    private var destinationDisplayName: String {
        if downloadDestination == .custom && !customDownloadPath.isEmpty {
            // 显示文件夹名称
            return URL(fileURLWithPath: customDownloadPath).lastPathComponent
        }
        return downloadDestination.label
    }
    

    /// 是否有等待或停止的任务
    private var hasWaitingOrStoppedTasks: Bool {
        downloadManager.tasks.contains { $0.status == .waiting || $0.status == .stopped }
    }
    
    /// 是否有下载中的任务
    private var hasDownloadingTasks: Bool {
        downloadManager.tasks.contains { $0.status == .downloading }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top bar with paste and clear buttons
            HStack(spacing: 12) {
                // 粘贴并下载按钮
                Button {
                    if let clipboardString = NSPasteboard.general.string(forType: .string), !clipboardString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let trimmedString = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
                        // 验证是否是有效的URL
                        if isValidVideoURL(trimmedString) {
                            // 使用规范化后的 URL（自动补全 https://）
                            urlText = normalizeURL(trimmedString)
                            // 直接开始下载
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                addDownloadTask()
                            }
                        } else {
                            showInvalidLinkAlert = true
                        }
                    } else {
                        showEmptyClipboardAlert = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 16))
                        Text(LocalizedString("action.paste"))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 120, height: 36)
                    .background(.mint)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help(LocalizedString("action.paste"))
                .alert(LocalizedString("alert.empty_clipboard.title"), isPresented: $showEmptyClipboardAlert) {
                    Button(LocalizedString("action.ok"), role: .cancel) { }
                } message: {
                    Text(LocalizedString("alert.empty_clipboard.message"))
                }
                .alert(LocalizedString("alert.invalid_link.title"), isPresented: $showInvalidLinkAlert) {
                    Button(LocalizedString("action.ok"), role: .cancel) { }
                } message: {
                    Text(LocalizedString("alert.invalid_link.message"))
                }
                
                Spacer()
                
                Spacer()
                
                // 清空记录按钮
                VStack(alignment: .center, spacing: 2) {
                    Button {
                        showClearConfirmation = true
                    } label: {
                        Text(LocalizedString("action.clear_records"))
                            .foregroundStyle(.red)
                            .frame(width: 140, height: 36)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(downloadManager.tasks.isEmpty)
                    .alert(LocalizedString("alert.clear_records.title"), isPresented: $showClearConfirmation) {
                        Button(LocalizedString("action.cancel"), role: .cancel) { }
                        Button(LocalizedString("action.confirm"), role: .destructive) {
                            downloadManager.clearAllTasks()
                        }
                    } message: {
                        Text(LocalizedString("alert.clear_records.message"))
                    }
                    
                    Text(LocalizedString("action.clear_records_hint"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    // 显示/隐藏缩略图按钮
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showThumbnails.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showThumbnails ? "eye" : "eye.slash")
                                .font(.system(size: 12))
                            Text(LocalizedString(showThumbnails ? "action.hide_thumbnails" : "action.show_thumbnails"))
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(showThumbnails ? Color(red: 0.4, green: 0.9, blue: 0.7) : .secondary)
                        .frame(width: 140, height: 36)
                        .background(showThumbnails ? Color(red: 0.4, green: 0.9, blue: 0.7).opacity(0.12) : Color.gray.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .frame(height: 36, alignment: .top)  // 固定高度，顶部对齐
            }

            // Settings
            VStack(alignment: .leading, spacing: 16) {
                // 第一行：格式、画质、音质
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Text(LocalizedString("main.format"))
                        Menu {
                            ForEach(OutputKind.allCases) { kind in
                                Button(kind.displayName) {
                                    outputKind = kind
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(outputKind.rawValue)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        .id(languageManager.effectiveLanguageCode)
                        .fixedSize()
                    }

                    HStack(spacing: 8) {
                        Text(LocalizedString("main.video_quality"))
                        Menu {
                            ForEach(VideoQuality.allCases) { q in
                                Button(q.displayName) {
                                    videoQuality = q
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(videoQuality.displayName)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        .disabled(outputKind.isAudioOnly)
                        .id(languageManager.effectiveLanguageCode)
                        .fixedSize()
                    }

                    HStack(spacing: 8) {
                        Text(LocalizedString("main.audio_quality"))
                        Menu {
                            ForEach(AudioQuality.allCases) { q in
                                Button(q.label) {
                                    audioQuality = q
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(audioQuality.label)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        .disabled(!outputKind.isAudioOnly)
                        .id(languageManager.effectiveLanguageCode)
                        .fixedSize()
                    }
                    
                    Spacer()
                }
                                // Instagram 提示小字
                Text("Instagram 链接无需设置参数，默认下载最高画质原始格式")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                                // 第二行：保存位置、路径显示、清空记录按钮
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Text(LocalizedString("main.save_location"))
                        
                        Menu {
                            ForEach(DownloadDestination.allCases) { d in
                                Button(d.label) {
                                    if d == .custom {
                                        // 选择自定义时弹出文件选择器
                                        pickDownloadFolder()
                                    } else {
                                        downloadDestination = d
                                        customDownloadPath = ""
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(downloadDestination == .custom && !customDownloadPath.isEmpty 
                                     ? URL(fileURLWithPath: customDownloadPath).lastPathComponent 
                                     : downloadDestination.label)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                        }
                        .frame(width: 120)
                    }

                    Button {
                        openFolder(path: currentSavePath)
                    } label: {
                        HStack(spacing: 4) {
                            Text(currentSavePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Image(systemName: "arrow.right.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(LocalizedString("main.open_folder"))

                    Spacer()
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Download Tasks
            downloadTasksView
        }
        .padding()
        .frame(minWidth: 750, minHeight: 550)
        .navigationTitle("iSave")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(initialTab: .general)
                .environmentObject(languageManager)
        }
        .overlay {
            // 用 overlay + sheet 避免同一层级多个 .sheet 冲突（macOS 12–13 只有第一个生效）
            Color.clear
                .frame(width: 0, height: 0)
                .sheet(isPresented: $versionChecker.showUpdateAlert) {
                    UpdateAlertView(versionChecker: versionChecker, isPresented: $versionChecker.showUpdateAlert)
                }
        }

        .onAppear {
            if let saved = DownloadDestination(rawValue: downloadDestinationRaw) {
                downloadDestination = saved
            } else {
                downloadDestination = .downloads
            }
            downloadManager.checkYtDlpAvailability()
            downloadManager.checkFfmpegAvailability()
            downloadManager.checkGalleryDlAvailability()
            
            // 启动时检查版本更新
            Task {
                await versionChecker.checkForUpdates(autoShowAlert: true)
            }
            
            // 添加通知监听
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("PasteAndDownload"),
                object: nil,
                queue: .main
            ) { _ in
                pasteAndDownload()
            }
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("StartAllTasks"),
                object: nil,
                queue: .main
            ) { _ in
                startAllTasks()
            }
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("StopAllTasks"),
                object: nil,
                queue: .main
            ) { _ in
                stopAllTasks()
            }            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ClearAllTasks"),
                object: nil,
                queue: .main
            ) { _ in
                showClearConfirmation = true
            }
        }
        .onChange(of: downloadDestination) { newValue in
            downloadDestinationRaw = newValue.rawValue
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var downloadTasksView: some View {
        if downloadManager.tasks.isEmpty {
            VStack {
                Spacer()
                Text(LocalizedString("main.no_tasks"))
                    .foregroundStyle(.secondary)
                Text(LocalizedString("main.no_tasks_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 250)
            .contextMenu {
                Button {
                    pasteAndDownload()
                } label: {
                    Label(LocalizedString("action.paste"), systemImage: "doc.on.clipboard")
                }
                
                Divider()
                
                Button {
                    showClearConfirmation = true
                } label: {
                    Label(LocalizedString("action.clear_records"), systemImage: "trash")
                }
                .disabled(downloadManager.tasks.isEmpty)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(downloadManager.tasks) { task in
                        DownloadTaskRow(task: task, manager: downloadManager)
                        Divider()
                    }
                }
            }
            .padding(.top, -8)
            .frame(minHeight: 250)
            .contextMenu {
                Button {
                    pasteAndDownload()
                } label: {
                    Label(LocalizedString("action.paste"), systemImage: "doc.on.clipboard")
                }
                
                Divider()
                
                Button {
                    startAllTasks()
                } label: {
                    Label(LocalizedString("action.start_all"), systemImage: "play.fill")
                }
                .disabled(!hasWaitingOrStoppedTasks)
                
                Button {
                    stopAllTasks()
                } label: {
                    Label(LocalizedString("action.stop_all"), systemImage: "pause.fill")
                }
                .disabled(!hasDownloadingTasks)
                
                Divider()
                
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Label(LocalizedString("action.clear_all"), systemImage: "trash")
                }
            }
        }
    }
    
    
    // MARK: - Actions
    
    private func normalizeURL(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果已经有协议前缀，直接返回
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        
        // 如果没有协议前缀，自动添加 https://
        return "https://" + trimmed
    }
    
    private func isValidVideoURL(_ urlString: String) -> Bool {
        let normalizedURL = normalizeURL(urlString)
        
        // 尝试创建 URL 对象并检查是否有有效的 host
        guard let url = URL(string: normalizedURL), 
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        
        // 检查 host 是否包含点号（基本的域名格式检查）
        return host.contains(".")
    }
    
    private func addDownloadTask() {
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        
        let destPath = resolveDestinationFolderPath()
        
        downloadManager.addTask(
            url: url,
            outputFormat: outputKind.rawValue,
            videoQuality: videoQuality.ytdlpValue,
            audioQuality: audioQuality.ytdlpValue,
            destinationPath: destPath
        )
        
        urlText = ""
    }
    
    private func resolveDestinationFolderPath() -> String {
        // 如果有自定义路径，优先使用
        if !customDownloadPath.isEmpty {
            return customDownloadPath
        }
        
        // 否则使用下拉菜单选择的位置
        switch downloadDestination {
        case .downloads:
            let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            return dir?.path ?? (NSHomeDirectory() + "/Downloads")
        case .desktop:
            let dir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            return dir?.path ?? (NSHomeDirectory() + "/Desktop")
        case .movies:
            let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            return dir?.path ?? (NSHomeDirectory() + "/Movies")
        case .custom:
            // 自定义路径，如果没有设置则返回 Downloads
            if !customDownloadPath.isEmpty {
                return customDownloadPath
            }
            let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            return dir?.path ?? (NSHomeDirectory() + "/Downloads")
        }
    }

    private func pickDownloadFolder() {
        let panel = NSOpenPanel()
        panel.title = LocalizedString("main.select_folder_title")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = LocalizedString("main.select_button")

        if panel.runModal() == .OK, let url = panel.url {
            customDownloadPath = url.path
            downloadDestination = .custom
        }
    }
    
    private func openFolder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Context Menu Actions
    
    /// 粘贴并下载
    private func pasteAndDownload() {
        if let clipboardString = NSPasteboard.general.string(forType: .string), 
           !clipboardString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmedString = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidVideoURL(trimmedString) {
                urlText = normalizeURL(trimmedString)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    addDownloadTask()
                }
            } else {
                showInvalidLinkAlert = true
            }
        } else {
            showEmptyClipboardAlert = true
        }
    }
    
    /// 开始所有等待或停止的任务
    private func startAllTasks() {
        for task in downloadManager.tasks where task.status == .stopped {
            downloadManager.retryTask(task)
        }
        // 触发下载队列处理，启动所有等待中的任务
        downloadManager.startAllWaitingTasks()
    }
    
    /// 停止所有下载中的任务
    private func stopAllTasks() {
        for task in downloadManager.tasks where task.status == .downloading {
            downloadManager.stopTask(task)
        }
    }
}

#Preview {
    ContentView()
}
