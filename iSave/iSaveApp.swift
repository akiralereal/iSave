
import SwiftUI
import AppKit

@main
struct iSaveApp: App {
    @StateObject private var languageManager = LanguageManager.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(languageManager)
        }
        .commands {
            // 替换默认的帮助菜单
            CommandGroup(replacing: .help) {
                Link(LocalizedString("menu.website"), destination: URL(string: "https://www.ifansclub.com")!)
            }
        }
        
        // 添加设置窗口 - 系统会自动添加"设置..."菜单项
        Settings {
            SettingsView()
                .environmentObject(languageManager)
        }
    }
}

// MARK: - AppDelegate for Status Bar
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusBarMenu: NSMenu?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 创建状态栏图标
        setupStatusBar()
    }
    
    private func setupStatusBar() {
        // 创建状态栏项
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // 尝试使用自定义状态栏图标
            if let customIcon = NSImage(named: "status_icon") {
                // 设置图标尺寸
                customIcon.size = NSSize(width: 18, height: 18)
                button.image = customIcon
            } else {
                // 使用 SF Symbol 作为默认图标
                let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
                let symbolImage = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "iSave")?
                    .withSymbolConfiguration(config)
                symbolImage?.isTemplate = true
                button.image = symbolImage
            }
        }
        
        // 创建菜单
        statusBarMenu = NSMenu()
        
        // 添加"打开主面板"菜单项
        let showWindowItem = NSMenuItem(
            title: LocalizedString("menu.show_window"),
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        showWindowItem.target = self
        statusBarMenu?.addItem(showWindowItem)
        
        // 添加分隔符
        statusBarMenu?.addItem(NSMenuItem.separator())
        
        // 添加"退出"菜单项
        let quitItem = NSMenuItem(
            title: LocalizedString("menu.quit"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        statusBarMenu?.addItem(quitItem)
        
        // 设置菜单
        statusItem?.menu = statusBarMenu
    }
    
    @objc private func showMainWindow() {
        // 激活应用并显示主窗口
        NSApp.activate(ignoringOtherApps: true)
        
        // 显示所有窗口
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

/// 使用当前语言 Bundle 获取本地化字符串
func LocalizedString(_ key: String) -> String {
    return Bundle.localizedBundle.localizedString(forKey: key, value: nil, table: nil)
}
