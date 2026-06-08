import SwiftData
import Foundation

@Model final class PriceListArchive {
    var brand:    String = "Alapala"
    var period:   String = ""
    var savedAt:  Date   = Date()
    var fileName: String = ""

    init(brand: String, period: String, fileName: String) {
        self.brand    = brand
        self.period   = period
        self.fileName = fileName
        self.savedAt  = Date()
    }

    var fileURL: URL? {
        guard !fileName.isEmpty else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(fileName)
    }

    var displayDate: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "tr_TR")
        df.dateFormat = "dd MMMM yyyy, HH:mm"
        return df.string(from: savedAt)
    }

    var fileExists: Bool {
        guard let url = fileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
