import Foundation
import Combine
import SwiftUI

/// 语言管理器 - 处理应用内语言切换
class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    /// 支持的语言列表
    enum Language: String, CaseIterable, Identifiable {
        case system = "system"
        case en = "en"
        case zhHans = "zh-Hans"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .system: return LocalizedString("language.system")
            case .en: return "English"
            case .zhHans: return "简体中文"
            }
        }
        
        var localizedDisplayName: String {
            switch self {
            case .system: return LocalizedString("language.system")
            case .en: return LocalizedString("language.english")
            case .zhHans: return LocalizedString("language.chinese_simplified")
            }
        }
    }
    
    /// 已适配的语言代码列表（不包含 system）
    static let supportedLanguageCodes: [String] = ["en", "zh-Hans"]
    
    /// 缓存的系统语言（在修改 AppleLanguages 之前获取）
    private static let cachedSystemLanguage: String = {
        // 获取系统真正的语言设置
        if let languages = CFPreferencesCopyValue(
            "AppleLanguages" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String], let first = languages.first {
            return first
        }
        return Locale.preferredLanguages.first ?? "en"
    }()
    
    private var storedLanguage: String {
        get { UserDefaults.standard.string(forKey: "appLanguage") ?? "system" }
        set { UserDefaults.standard.set(newValue, forKey: "appLanguage") }
    }
    
    @Published var currentLanguage: Language = .system
    
    /// 实际使用的语言代码
    @Published var effectiveLanguageCode: String = "en"
    
    private init() {
        // 从存储中恢复语言设置
        if let saved = Language(rawValue: storedLanguage) {
            currentLanguage = saved
        }
        applyLanguage()
    }
    
    /// 设置语言
    func setLanguage(_ language: Language) {
        guard language != currentLanguage else { return }
        
        // 延迟更新，避免在视图更新期间修改 @Published 属性
        DispatchQueue.main.async { [weak self] in
            self?.currentLanguage = language
            self?.storedLanguage = language.rawValue
            self?.applyLanguage()
        }
    }
    
    /// 应用语言设置
    private func applyLanguage() {
        let languageCode: String
        
        if currentLanguage == .system {
            // 跟随系统语言 - 使用缓存的系统语言
            let systemLanguage = Self.cachedSystemLanguage
            
            // 检查系统语言是否在支持列表中
            if let matched = Self.supportedLanguageCodes.first(where: { systemLanguage.hasPrefix($0) }) {
                languageCode = matched
            } else {
                // 不支持的语言，默认使用英语
                languageCode = "en"
            }
        } else {
            languageCode = currentLanguage.rawValue
        }
        
        // 设置 Bundle 语言
        UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        
        // 通知需要刷新界面
        Bundle.setLanguage(languageCode)
        
        // 更新语言代码，触发 UI 刷新
        effectiveLanguageCode = languageCode
        
        // 强制发送 objectWillChange 事件，确保所有观察者更新
        objectWillChange.send()
    }
    
    /// 获取本地化字符串
    func localizedString(_ key: String) -> String {
        return Bundle.localizedBundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

// MARK: - Bundle Extension for Runtime Language Switching

private var bundleKey: UInt8 = 0

private class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(Bundle.self, &bundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    static var localizedBundle: Bundle {
        if let bundle = objc_getAssociatedObject(Bundle.self, &bundleKey) as? Bundle {
            return bundle
        }
        return Bundle.main
    }
    
    static func setLanguage(_ language: String) {
        var bundle: Bundle?
        
        if let path = Bundle.main.path(forResource: language, ofType: "lproj") {
            bundle = Bundle(path: path)
        } else if let path = Bundle.main.path(forResource: "en", ofType: "lproj") {
            // 回退到英语
            bundle = Bundle(path: path)
        }
        
        objc_setAssociatedObject(Bundle.self, &bundleKey, bundle ?? Bundle.main, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        object_setClass(Bundle.main, LocalizedBundle.self)
    }
}

// MARK: - String Extension for Localization

extension String {
    var localized: String {
        return Bundle.localizedBundle.localizedString(forKey: self, value: nil, table: nil)
    }
}
