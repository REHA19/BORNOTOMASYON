import Foundation

// MARK: - Double helpers

extension Double {
    /// "1.234,5 kg"  (1 ondalık)
    var kgString: String { Fmt.kg1.string(from: NSNumber(value: self)).map { $0 + " kg" } ?? "\(self) kg" }

    /// "1.234 kg"  (tam sayı)
    var kgWholeString: String { Fmt.kg0.string(from: NSNumber(value: self)).map { $0 + " kg" } ?? "\(self) kg" }

    /// "1.234,5"  (birim yok)
    var decimalString: String { Fmt.kg1.string(from: NSNumber(value: self)) ?? "\(self)" }

    /// "1.234.567 ₺"  (tam sayı, Türk lirası)
    var tlString: String { (Fmt.tl.string(from: NSNumber(value: self)) ?? "\(Int(self))") + " ₺" }
}

// MARK: - Date helpers

extension Date {
    /// "20 Nisan 2026"
    var trShort: String { Fmt.dateShort.string(from: self) }

    /// "20 Nisan 2026, Pazartesi"
    var trLong: String { Fmt.dateLong.string(from: self) }

    /// "20 Nis 14:35"
    var trClock: String { Fmt.dateClock.string(from: self) }

    /// "Nisan 2026"
    var trMonthYear: String { Fmt.monthYear.string(from: self) }
}

// MARK: - Private formatter instances (uygulama ömrü boyunca tek seferlik)

private enum Fmt {
    static let kg1: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        f.locale = Locale(identifier: "tr_TR")
        return f
    }()

    static let tl: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "tr_TR")
        return f
    }()

    static let kg0: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "tr_TR")
        return f
    }()

    static let dateShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    static let dateLong: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM yyyy, EEEE"
        return f
    }()

    static let dateClock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM HH:mm"
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    // ISO string → Date (FormulaActiveResponse.validDate gibi)
    static let iso1: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f
    }()

    static let iso2: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static let iso3: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // "27.03.2026" veya "27.03.2026-27.03.2026" gibi API tarih aralığı formatı
    static let iso4: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()
}

// MARK: - ISO String → Date

private let _iso8601WithFraction: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let _iso8601Plain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

extension String {
    var isoDate: Date? {
        // ISO8601 ile değişken ondalık (7 basamak: "2026-04-27T16:38:58.9580613")
        if let d = _iso8601WithFraction.date(from: self) { return d }
        if let d = _iso8601Plain.date(from: self)         { return d }
        if let d = Fmt.iso1.date(from: self)              { return d }
        if let d = Fmt.iso2.date(from: self)              { return d }
        if let d = Fmt.iso3.date(from: self)              { return d }
        // "DD.MM.YYYY-DD.MM.YYYY" aralık formatı → başlangıç tarihini al
        return Fmt.iso4.date(from: String(self.prefix(10)))
    }
}
