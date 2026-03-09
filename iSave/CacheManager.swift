import Foundation
import SwiftUI
import Combine

class CacheManager: ObservableObject {
    static let shared = CacheManager()
    
    @Published var cacheSize: String = "计算中..."
    @Published var thumbnailCacheSize: String = "0 KB"
    @Published var downloadRecordsSize: String = "0 KB"
    @Published var tempFilesSize: String = "0 KB"
    
    private init() {
        // 延迟计算，避免启动时阻塞
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.calculateCacheSize()
        }
    }
    
    // 计算缓存大小
    func calculateCacheSize() {
        cacheSize = "计算中..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            var totalSize: Int64 = 0
            
            // 1. 缩略图缓存（新目录 + 旧目录）
            var thumbnailSize: Int64 = 0
            for dir in self.thumbnailCacheDirectories() {
                if let size = self.directorySize(url: dir) {
                    thumbnailSize += size
                }
            }
            totalSize += thumbnailSize
            
            // 2. 下载记录 - 统计实际存在的记录
            let recordsCount = DownloadManager.shared.tasks.count
            var recordsSize: Int64 = 0
            if recordsCount > 0 {
                recordsSize = Int64(recordsCount * 512) // 每条记录约 512 bytes
                totalSize += recordsSize
            }
            
            // 3. 临时文件 - 不统计，设为0
            let tempSize: Int64 = 0
            
            DispatchQueue.main.async {
                self.cacheSize = self.formatBytes(totalSize)
                self.thumbnailCacheSize = self.formatBytes(thumbnailSize)
                self.downloadRecordsSize = self.formatBytes(recordsSize)
                self.tempFilesSize = self.formatBytes(tempSize)
            }
        }
    }
    
    // 清除所有缓存
    func clearAllCache() {
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. 清除 URLCache（图片缓存）- 彻底清除磁盘缓存
            URLCache.shared.removeAllCachedResponses()
            
            // 直接删除 URLCache 的磁盘缓存目录
            if let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                let urlCacheDir = cacheURL.appendingPathComponent("com.apple.URLCache")
                try? FileManager.default.removeItem(at: urlCacheDir)
            }
            
            // 2. 清除下载记录
            DispatchQueue.main.sync {
                DownloadManager.shared.clearAllTasks()
            }
            
            // 3. 清除应用缓存目录
            if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ceaule.iSave") {
                try? FileManager.default.removeItem(at: cacheDir)
                try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            }
            
            // 4. 清除缩略图持久缓存目录（Application Support）
            if let supportBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let supportThumbDir = supportBase
                    .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ceaule.iSave")
                    .appendingPathComponent("thumbnails")
                try? FileManager.default.removeItem(at: supportThumbDir)
                try? FileManager.default.createDirectory(at: supportThumbDir, withIntermediateDirectories: true)
            }
            
            // 清除完成后直接显示 0（不重新计算，避免统计到系统自动生成的索引文件）
            DispatchQueue.main.async {
                self.cacheSize = self.formatBytes(0)
                self.thumbnailCacheSize = self.formatBytes(0)
                self.downloadRecordsSize = self.formatBytes(0)
                self.tempFilesSize = self.formatBytes(0)
            }
        }
    }
    
    // 浅层计算目录大小（不递归）
    private func shallowDirectorySize(url: URL) -> Int64? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else {
            return nil
        }
        
        var totalSize: Int64 = 0
        for fileURL in files {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  let isDirectory = resourceValues.isDirectory else {
                continue
            }
            
            // 只统计文件，不递归目录
            if !isDirectory, let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
    
    // 计算目录大小
    private func directorySize(url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return nil
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }
        
        return totalSize
    }
    
    private func thumbnailCacheDirectories() -> [URL] {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ceaule.iSave"
        var dirs: [URL] = []
        
        if let supportBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            dirs.append(
                supportBase
                    .appendingPathComponent(bundleID)
                    .appendingPathComponent("thumbnails")
            )
        }
        
        if let cacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            dirs.append(
                cacheBase
                    .appendingPathComponent(bundleID)
                    .appendingPathComponent("thumbnails")
            )
        }
        
        return dirs
    }
    
    // 格式化字节大小
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
