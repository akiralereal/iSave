import SwiftUI
import Foundation
import Combine

// MARK: - Version Info Model
struct VersionInfo: Codable {
    let appId: String
    let latest: String
    let minSupported: String
    let build: Int
    let title: String
    let notes: [String]
    let pubDate: String
    let downloadUrl: String
    let releasePage: String
    let mandatory: Bool
}

// MARK: - Version Checker
@MainActor
class VersionChecker: ObservableObject {
    static let shared = VersionChecker()
    
    @Published var hasNewVersion = false
    @Published var versionInfo: VersionInfo?
    @Published var showUpdateAlert = false
    
    private let versionURL = "https://raw.githubusercontent.com/akiralereal/iSave/main/iSave/Resources/version.json"
    private var hasShownAutoAlert = false // 标记是否已经自动显示过弹窗
    
    private init() {}
    
    /// 检查版本更新
    /// - Parameter autoShowAlert: 是否自动显示弹窗（启动时为true，手动检查为false）
    func checkForUpdates(autoShowAlert: Bool = false) async {
        guard let url = URL(string: versionURL) else {
            print("⚠️ [VersionChecker] URL 无效")
            return
        }
        
        print("🔍 [VersionChecker] 开始检查更新... autoShowAlert=\(autoShowAlert)")
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let info = try JSONDecoder().decode(VersionInfo.self, from: data)
            
            versionInfo = info
            
            // 获取当前版本信息
            let currentVersion = getCurrentVersion()
            let currentBuild = getCurrentBuild()
            
            print("🔍 [VersionChecker] 当前版本: \(currentVersion)(\(currentBuild)), 最新版本: \(info.latest)(\(info.build))")
            
            // 比较版本号
            if shouldUpdate(current: currentVersion, latest: info.latest, currentBuild: currentBuild, latestBuild: info.build) {
                hasNewVersion = true
                print("🔍 [VersionChecker] 有新版本! hasShownAutoAlert=\(hasShownAutoAlert)")
                
                // 只在自动检查且未显示过时才自动弹窗
                if autoShowAlert && !hasShownAutoAlert {
                    showUpdateAlert = true
                    hasShownAutoAlert = true
                    print("🔍 [VersionChecker] showUpdateAlert 已设为 true")
                }
            } else {
                print("🔍 [VersionChecker] 已是最新版本，无需更新")
            }
        } catch {
            print("检查版本更新失败: \(error)")
        }
    }
    
    /// 获取当前应用版本号
    private func getCurrentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
    }
    
    /// 获取当前构建号
    private func getCurrentBuild() -> Int {
        if let buildString = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           let build = Int(buildString) {
            return build
        }
        return 0
    }
    
    /// 判断是否需要更新
    private func shouldUpdate(current: String, latest: String, currentBuild: Int, latestBuild: Int) -> Bool {
        // 只比较版本号，忽略 build 号
        let comparison = compareVersion(current, latest)
        return comparison == .orderedAscending
    }
    
    /// 判断当前版本是否过低
    private func isVersionTooOld(current: String, minSupported: String) -> Bool {
        return compareVersion(current, minSupported) == .orderedAscending
    }
    
    /// 比较两个版本号
    private func compareVersion(_ v1: String, _ v2: String) -> ComparisonResult {
        let components1 = v1.split(separator: ".").compactMap { Int($0) }
        let components2 = v2.split(separator: ".").compactMap { Int($0) }
        
        let maxLength = max(components1.count, components2.count)
        
        for i in 0..<maxLength {
            let num1 = i < components1.count ? components1[i] : 0
            let num2 = i < components2.count ? components2[i] : 0
            
            if num1 < num2 {
                return .orderedAscending
            } else if num1 > num2 {
                return .orderedDescending
            }
        }
        
        return .orderedSame
    }
    
    /// 打开下载页面
    func openDownloadPage() {
        guard let info = versionInfo,
              let url = URL(string: info.downloadUrl) else { return }
        NSWorkspace.shared.open(url)
    }
    
    /// 打开发布说明页面
    func openReleasePage() {
        guard let info = versionInfo,
              let url = URL(string: info.releasePage) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Update Alert View
struct UpdateAlertView: View {
    @ObservedObject var versionChecker: VersionChecker
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.mint)
                Text(versionChecker.versionInfo?.title ?? LocalizedString("update.new_version_available"))
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            // 更新说明
            if let notes = versionChecker.versionInfo?.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedString("update.release_notes"))
                        .font(.headline)
                    
                    ForEach(notes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text(note)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // 版本信息
            HStack {
                Text(LocalizedString("update.current_version"))
                Text(getCurrentVersion())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(LocalizedString("update.latest_version"))
                Text(versionChecker.versionInfo?.latest ?? "")
                    .foregroundStyle(.mint)
                    .font(.caption.weight(.medium))
            }
            .font(.caption)
            
            // 按钮
            HStack(spacing: 12) {
                if versionChecker.versionInfo?.mandatory != true {
                    Button(LocalizedString("update.later")) {
                        isPresented = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
                
                Button(LocalizedString("update.view_details")) {
                    versionChecker.openReleasePage()
                }
                
                Button(LocalizedString("update.download_now")) {
                    versionChecker.openDownloadPage()
                    if versionChecker.versionInfo?.mandatory != true {
                        isPresented = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
    
    private func getCurrentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
    }
}
