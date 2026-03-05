import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var languageManager: LanguageManager
    
    @State private var selectedTab: SettingsTab
    
    // 初始化时可以指定默认打开的标签页
    init(initialTab: SettingsTab = .general) {
        _selectedTab = State(initialValue: initialTab)
    }
    
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "settings.general"
        // case license = "settings.license"  // 已隐藏（软件免费化）
        case advanced = "settings.advanced"
        // case storage = "settings.storage"  // 暂时隐藏缓存管理
        case versionCheck = "settings.version_check"
        case about = "settings.about"
        
        var id: String { rawValue }
        
        var iconName: String {
            switch self {
            case .general: return "globe"
            // case .license: return "key.fill"  // 已隐藏
            case .advanced: return "gearshape.2"
            // case .storage: return "internaldrive"
            case .versionCheck: return "arrow.triangle.2.circlepath"
            case .about: return "info.circle"
            }
        }
        
        var title: String {
            LocalizedString(rawValue)
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧导航栏
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: tab.iconName)
                                .frame(width: 20)
                            Text(tab.title)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                }
                
                Spacer()
            }
            .frame(width: 200)
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 右侧内容区域
            VStack(alignment: .leading, spacing: 0) {
                // 标题栏
                HStack {
                    Text(selectedTab.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                
                Divider()
                
                // 内容区域
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch selectedTab {
                        case .general:
                            generalSettings
                        case .advanced:
                            advancedSettings
                        // case .storage:
                        //     storageSettings
                        case .versionCheck:
                            versionCheckSettings
                        case .about:
                            aboutSettings
                        }
                    }
                    .padding(24)
                }
            }
            .frame(minWidth: 500)
        }
        .frame(width: 700, height: 500)
        .onAppear {
            // 免费化后 License 标签页已隐藏，暂停监听切换通知
            // NotificationCenter.default.addObserver(
            //     forName: NSNotification.Name("SwitchToLicenseTab"),
            //     object: nil,
            //     queue: .main
            // ) { _ in
            //     withAnimation(.easeInOut(duration: 0.2)) {
            //         selectedTab = .license
            //     }
            // }
        }
    }
    
    // MARK: - 常规设置
    
    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 语言设置
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString("language.title"))
                    .font(.headline)
                
                HStack(spacing: 0) {
                    ForEach(LanguageManager.Language.allCases) { lang in
                        Button {
                            languageManager.setLanguage(lang)
                        } label: {
                            Text(lang.displayName)
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(languageManager.currentLanguage == lang ? Color(red: 0.4, green: 0.9, blue: 0.7) : Color.gray.opacity(0.1))
                                .foregroundColor(languageManager.currentLanguage == lang ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )
            }
        }
    }
    
    // MARK: - 高级设置
    
    @AppStorage("maxConcurrentDownloads") private var maxConcurrentDownloads: Int = 2
    @AppStorage("preventSleepDuringDownload") private var preventSleepDuringDownload: Bool = true
    
    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 同时下载任务数
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedString("advanced.concurrent_downloads"))
                    .font(.headline)
                
                HStack(spacing: 10) {
                    ForEach([1, 2, 3, 5], id: \.self) { count in
                        Button {
                            maxConcurrentDownloads = count
                        } label: {
                            Text("\(count)")
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 60, height: 36)
                                .background(maxConcurrentDownloads == count ? Color(red: 0.4, green: 0.9, blue: 0.7) : Color.gray.opacity(0.15))
                                .foregroundColor(maxConcurrentDownloads == count ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Text(LocalizedString("advanced.concurrent_downloads.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // 防止系统睡眠
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $preventSleepDuringDownload) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedString("advanced.prevent_sleep"))
                            .font(.headline)
                        Text(LocalizedString("advanced.prevent_sleep.description"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color(red: 0.4, green: 0.9, blue: 0.7))
            }
        }
    }
    
    // MARK: - 缓存管理
    
    @StateObject private var cacheManager = CacheManager.shared
    @State private var showClearConfirmation = false
    
    private var storageSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 总缓存大小
            HStack {
                Text("storage.total_cache".localized)
                    .font(.headline)
                
                Spacer()
                
                Text(cacheManager.cacheSize)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            
            // 缓存详情
            VStack(alignment: .leading, spacing: 8) {
                CacheItemRow(icon: "photo.stack", title: "storage.thumbnail_cache".localized, description: "storage.thumbnail_cache_desc".localized, size: cacheManager.thumbnailCacheSize)
                CacheItemRow(icon: "list.bullet.rectangle", title: "storage.download_records".localized, description: "storage.download_records_desc".localized, size: cacheManager.downloadRecordsSize)
                CacheItemRow(icon: "doc.text", title: "storage.temp_files".localized, description: "storage.temp_files_desc".localized, size: cacheManager.tempFilesSize)
            }
            
            Divider()
            
            Button {
                showClearConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("storage.clear_all".localized)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .alert("storage.clear_confirm_title".localized, isPresented: $showClearConfirmation) {
                Button("storage.clear_confirm_no".localized, role: .cancel) { }
                Button("storage.clear_confirm_yes".localized, role: .destructive) {
                    cacheManager.clearAllCache()
                }
            } message: {
                Text("storage.clear_confirm_message".localized)
            }
        }
    }
    
    // MARK: - 版本检测
    
    @StateObject private var versionChecker = VersionChecker.shared
    @State private var isCheckingUpdate = false
    @State private var showUpdateAlert = false
    
    private var versionCheckSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString("version.current"))
                    .font(.headline)
                
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("iSave \(version)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    checkForUpdates()
                } label: {
                    HStack {
                        if isCheckingUpdate {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(LocalizedString("version.check_update"))
                    }
                    .frame(width: 200, height: 40)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isCheckingUpdate)
                
                if let info = versionChecker.versionInfo {
                    if versionChecker.hasNewVersion {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(format: LocalizedString("version.new_version"), info.latest))
                                .font(.body.weight(.medium))
                                .foregroundStyle(.mint)
                            
                            Button(LocalizedString("update.view_details")) {
                                showUpdateAlert = true
                            }
                        }
                        .padding(.top, 8)
                    } else {
                        Text(LocalizedString("version.up_to_date"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                }
            }
        }
        .sheet(isPresented: $showUpdateAlert) {
            UpdateAlertView(versionChecker: versionChecker, isPresented: $showUpdateAlert)
        }
    }
    
    private func checkForUpdates() {
        isCheckingUpdate = true
        
        Task {
            await versionChecker.checkForUpdates()
            isCheckingUpdate = false
        }
    }
    
    // MARK: - 关于
    
    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 访问网站
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedString("menu.website"))
                    .font(.headline)
                
                Link("https://www.ifansclub.com", destination: URL(string: "https://www.ifansclub.com")!)
                    .font(.body)
            }
            
            Divider()
            
            // 版本信息
            VStack(alignment: .leading, spacing: 8) {
                Text("版本信息")
                    .font(.headline)
                
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                Text("iSave \(version)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 辅助视图

struct CacheItemRow: View {
    let icon: String
    let title: String
    let description: String
    let size: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(size)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}
