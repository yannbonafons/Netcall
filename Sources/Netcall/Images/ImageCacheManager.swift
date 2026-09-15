//
//  ImageCacheManager.swift
//  Netcall
//
//  Created by Yann Bonafons on 10/05/2026.
//

import Foundation
import UIKit

protocol ImageCacheManagerProtocol: Sendable {
    func get(forKey imageURLString: String, useDisk: Bool) async -> UIImage?
    func save(_ image: UIImage, for imageURLString: String, saveToDisk: Bool)
}

final class ImageCacheManager: ImageCacheManagerProtocol {
    static public let defaultCountLimit = 100
    
    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    
    public init(countLimit: Int = ImageCacheManager.defaultCountLimit) {
        memoryCache.countLimit = countLimit
    }

    func get(forKey imageURLString: String, useDisk: Bool) async -> UIImage? {
        if let cached = memoryCache.object(forKey: imageURLString as NSString) {
            return cached
        }
        
        guard useDisk else {
            return nil
        }
        
        guard let image = await loadFromDisk(cachePath(for: imageURLString)) else {
            return nil
        }
        memoryCache.setObject(image, forKey: imageURLString as NSString)
        return image
    }
    
    public func save(_ image: UIImage, for imageURLString: String, saveToDisk: Bool) {
        memoryCache.setObject(image, forKey: imageURLString as NSString)
        
        if saveToDisk {
            Task(priority: .background) {
                let diskPath = cachePath(for: imageURLString)
                if let data = image.jpegData(compressionQuality: 0.8) {
                    try? data.write(to: diskPath)
                }
            }
        }
    }

    private func cachePath(for imageURLString: String) -> URL {
        let folder = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileName = String(imageURLString.hashValue)
        return folder.appendingPathComponent(fileName)
    }

    @concurrent
    private func loadFromDisk(_ url: URL) async -> UIImage? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }
}
