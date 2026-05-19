//
//  ImageCacheManager.swift
//  Netcall
//
//  Created by Yann Bonafons on 10/05/2026.
//

import Foundation
import UIKit

public protocol ImageCacheManagerProtocol: Sendable {
    func get(forKey imageURLString: String, useDisk: Bool) -> UIImage?
    func save(_ image: UIImage, for imageURLString: String, saveToDisk: Bool)
}

final public class ImageCacheManager: ImageCacheManagerProtocol, @unchecked Sendable {
    static public let defaultCountLimit = 100
    
    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    
    public init(countLimit: Int = ImageCacheManager.defaultCountLimit) {
        memoryCache.countLimit = countLimit
    }

    public func get(forKey imageURLString: String, useDisk: Bool) -> UIImage? {
        if let cached = memoryCache.object(forKey: imageURLString as NSString) {
            return cached
        }
        
        if useDisk {
            let diskPath = cachePath(for: imageURLString)
            if let data = try? Data(contentsOf: diskPath), let image = UIImage(data: data) {
                memoryCache.setObject(image,
                                      forKey: imageURLString as NSString)
                return image
            }
        }
        return nil
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
}
