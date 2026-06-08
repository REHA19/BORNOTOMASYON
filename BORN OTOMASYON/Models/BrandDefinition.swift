import SwiftData
import UIKit
import Foundation

@Model final class BrandDefinition {
    var name:           String = ""
    var antetImagePath: String = ""   // Documents/antets/ altındaki dosya adı
    var orderIndex:     Int    = 0

    init(name: String, orderIndex: Int = 0) {
        self.name       = name
        self.orderIndex = orderIndex
    }

    // Antet görselini yükle (önce Documents, sonra Asset Catalog)
    var antetImage: UIImage? {
        if !antetImagePath.isEmpty,
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = docs.appendingPathComponent(antetImagePath)
            if let img = UIImage(contentsOfFile: url.path) { return img }
        }
        let assetName = name.replacingOccurrences(of: " ", with: "") + "Antet"
        return UIImage(named: assetName) ?? UIImage(named: "AlapalaYemAntet")
    }

    var hasCustomAntet: Bool {
        !antetImagePath.isEmpty &&
        FileManager.default.fileExists(
            atPath: (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent(antetImagePath).path) ?? ""
        )
    }

    // Antet kaydet
    static func saveAntetData(_ data: Data, for brandName: String) -> String? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = docs.appendingPathComponent("antets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = brandName.replacingOccurrences(of: " ", with: "_")
        let filename = "antet_\(safe).jpg"
        let url = dir.appendingPathComponent(filename)
        guard let img = UIImage(data: data),
              let jpeg = img.jpegData(compressionQuality: 0.90)
        else { return nil }
        try? jpeg.write(to: url)
        return "antets/\(filename)"
    }
}
