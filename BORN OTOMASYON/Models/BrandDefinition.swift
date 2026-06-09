import SwiftData
import UIKit
import Foundation

@Model final class BrandDefinition {
    var name:           String = ""
    var antetImagePath: String = ""   // (legacy — lokal fallback)
    var orderIndex:     Int    = 0
    var antetImageData: Data? = nil   // CloudKit inline Data olarak senkronize edilir

    // ── Marka başına Global Gider Ayarları ───────────────────────────────
    var giderLabel1:  String = "İP ÇUVAL"
    var giderLabel2:  String = "% Fire"
    var giderLabel3:  String = "Elektrik/GAZ"
    var giderLabel4:  String = "Nakliye"
    var giderLabel5:  String = "İşçilik"
    var giderValue1:  Double = 262.0
    var giderValue2:  Double = 2.0
    var giderValue3:  Double = 270.0
    var giderValue4:  Double = 700.0
    var giderValue5:  Double = 2000.0
    var karPct:       Double = 17.0

    init(name: String, orderIndex: Int = 0) {
        self.name       = name
        self.orderIndex = orderIndex
    }

    // Antet görselini yükle: CloudKit data → lokal dosya → Asset Catalog
    var antetImage: UIImage? {
        if let data = antetImageData, let img = UIImage(data: data) { return img }
        if !antetImagePath.isEmpty,
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = docs.appendingPathComponent(antetImagePath)
            if let img = UIImage(contentsOfFile: url.path) { return img }
        }
        let assetName = name.replacingOccurrences(of: " ", with: "") + "Antet"
        return UIImage(named: assetName) ?? UIImage(named: "AlapalaYemAntet")
    }

    var hasCustomAntet: Bool {
        if antetImageData != nil { return true }
        return !antetImagePath.isEmpty &&
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
