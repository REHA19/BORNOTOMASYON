import Foundation
import SwiftUI

// MARK: - Alpha Vantage API Response

struct CommodityResponse: Decodable {
    let name:     String
    let interval: String
    let unit:     String
    let data:     [CommodityDataPoint]
}

struct CommodityDataPoint: Codable {
    let date:  String
    let value: String
    var doubleValue: Double? { Double(value) }
}

// MARK: - Domain Model

struct CommodityPrice: Identifiable, Codable {
    let id:           String   // symbol
    let symbol:       String
    let displayName:  String
    let unit:         String
    let latestPrice:  Double
    let previousPrice:Double?
    let points:       [CommodityDataPoint]

    var changePercent: Double? {
        guard let p = previousPrice, p > 0 else { return nil }
        return (latestPrice - p) / p * 100
    }

    var change3Month: Double? {
        guard points.count >= 3, let old = points[2].doubleValue, old > 0 else { return nil }
        return (latestPrice - old) / old * 100
    }

    var trend: PriceTrend {
        guard let c = changePercent else { return .unknown }
        if c > 2  { return .rising  }
        if c < -2 { return .falling }
        return .stable
    }
}

// MARK: - Price Trend

enum PriceTrend {
    case rising, stable, falling, unknown

    var label: String {
        switch self {
        case .rising:  return "Yükseliyor"
        case .stable:  return "Yatay"
        case .falling: return "Düşüyor"
        case .unknown: return "Veri Yok"
        }
    }

    var icon: String {
        switch self {
        case .rising:  return "arrow.up.right.circle.fill"
        case .falling: return "arrow.down.right.circle.fill"
        case .stable:  return "arrow.right.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .rising:  return .red     // alıcı için kötü
        case .falling: return .green   // alıcı için iyi
        case .stable:  return .orange
        case .unknown: return .gray
        }
    }
}

// MARK: - Purchase Urgency

enum PurchaseUrgency: Int, Comparable {
    case critical    = 0   // < 3 gün
    case warning     = 1   // 3–7 gün
    case planning    = 2   // 7–14 gün
    case sufficient  = 3   // 14–30 gün
    case comfortable = 4   // > 30 gün
    case noData      = 5

    static func < (lhs: PurchaseUrgency, rhs: PurchaseUrgency) -> Bool { lhs.rawValue < rhs.rawValue }

    static func from(days: Double?) -> PurchaseUrgency {
        guard let d = days else { return .noData }
        switch d {
        case ..<3:    return .critical
        case 3..<7:   return .warning
        case 7..<14:  return .planning
        case 14..<30: return .sufficient
        default:      return .comfortable
        }
    }

    var label: String {
        switch self {
        case .critical:    return "KRİTİK"
        case .warning:     return "UYARI"
        case .planning:    return "PLANLAMA"
        case .sufficient:  return "YETERLİ"
        case .comfortable: return "RAHAT"
        case .noData:      return "VERİ YOK"
        }
    }

    var daysLabel: String {
        switch self {
        case .critical:    return "< 3 gün"
        case .warning:     return "3–7 gün"
        case .planning:    return "7–14 gün"
        case .sufficient:  return "14–30 gün"
        case .comfortable: return "> 30 gün"
        case .noData:      return "—"
        }
    }

    var color: Color {
        switch self {
        case .critical:    return .red
        case .warning:     return .orange
        case .planning:    return .yellow
        case .sufficient:  return .blue
        case .comfortable: return .green
        case .noData:      return .gray
        }
    }
}

// MARK: - Buy Recommendation

enum BuyRecommendation {
    case buyNow        // kritik stok → hemen al
    case buyThisWeek   // uyarı seviyesi
    case buyAhead      // fiyat yükseliyor + planlama seviyesi → erken al
    case consider      // yeterli stok, fiyat yatay/yükseliyor
    case waitForDrop   // rahat stok + fiyat düşüyor → bekle
    case monitor       // rahat stok, fiyat normal

    var label: String {
        switch self {
        case .buyNow:      return "Hemen Al"
        case .buyThisWeek: return "Bu Hafta Al"
        case .buyAhead:    return "Öne Al"
        case .consider:    return "Değerlendir"
        case .waitForDrop: return "Fiyat Düşümünü Bekle"
        case .monitor:     return "İzle"
        }
    }

    var icon: String {
        switch self {
        case .buyNow:      return "cart.fill.badge.plus"
        case .buyThisWeek: return "cart.badge.plus"
        case .buyAhead:    return "arrow.up.forward.circle.fill"
        case .consider:    return "lightbulb.fill"
        case .waitForDrop: return "clock.arrow.circlepath"
        case .monitor:     return "eye.fill"
        }
    }

    var color: Color {
        switch self {
        case .buyNow:      return .red
        case .buyThisWeek: return .orange
        case .buyAhead:    return .purple
        case .consider:    return .blue
        case .waitForDrop: return .green
        case .monitor:     return .gray
        }
    }

    static func from(urgency: PurchaseUrgency, trend: PriceTrend) -> BuyRecommendation {
        switch (urgency, trend) {
        case (.critical, _):               return .buyNow
        case (.warning, _):                return .buyThisWeek
        case (.planning, .rising):         return .buyAhead
        case (.planning, _):               return .buyThisWeek
        case (.sufficient, .rising):       return .consider
        case (.sufficient, .falling):      return .waitForDrop
        case (.comfortable, .rising):      return .consider
        case (.comfortable, .falling):     return .waitForDrop
        default:                           return .monitor
        }
    }
}

// MARK: - Combined Market Info

struct MaterialMarketInfo: Identifiable {
    let id:         String   // materialCode
    let material:   Material
    let stockDays:  Double?
    let commodity:  CommodityPrice?
    var aiAnalysis: String?

    var urgency: PurchaseUrgency { .from(days: stockDays) }

    var recommendation: BuyRecommendation {
        .from(urgency: urgency, trend: commodity?.trend ?? .unknown)
    }
}
