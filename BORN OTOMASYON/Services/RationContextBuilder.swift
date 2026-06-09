import Foundation

// MARK: - Rasyon AI bağlamı
// FormulaEditorVM'in canlı durumunu (hammaddeler, kısıtlar, son çözüm) modele
// verilebilecek kompakt Türkçe metne çevirir. Tamamen değer-tipi okuma yapar.

enum RationContextBuilder {

    /// Asistan oturumu için sistem talimatı (rol + kurallar).
    static let systemInstructions = """
    Sen bir hayvan yemi (rasyon) formülasyon uzmanısın. Kullanıcı bir karma yem \
    formülü üzerinde çalışıyor ve sana o formülün güncel durumu veriliyor.

    Kurallar:
    - SADECE sana verilen formül bağlamına dayan. Bilmediğin değeri uydurma.
    - Önerilerin SOMUT ve sayısal olsun: hangi hammaddenin min%/max%'ını ne yapacağını, \
      hangi besin kısıtını nasıl değiştireceğini net yaz (örn: "Mısır 58 max'ını %60'a çıkar").
    - Maliyeti düşürmek için: ucuz hammaddelerin üst sınırını artırmayı, pahalıların \
      alt sınırını düşürmeyi öner. Besin kısıtlarını ihlal etme.
    - Kısa, madde madde ve Türkçe yanıt ver. Gereksiz uzun açıklama yapma.
    - Sen formülü doğrudan değiştiremezsin; kullanıcı önerini uygulayıp "Hesapla"ya basar.
    """

    /// Mevcut formül durumunu metne çevirir. Main thread'de çağrılmalı.
    static func build(vm: FormulaEditorVM) -> String {
        var s = "## FORMÜL\n"
        s += "Kod: \(vm.code)  |  Ad: \(vm.name)  |  Parti: \(Int(vm.totalKg)) kg\n\n"

        // ── Hammaddeler ──────────────────────────────────────────────
        s += "## HAMMADDELER (kod | ad | min% | max% | çözüm% | ₺/ton)\n"
        let activeIngs = vm.ingredients.filter { $0.isActive }
        if activeIngs.isEmpty {
            s += "(aktif hammadde yok)\n"
        } else {
            for ing in activeIngs {
                let price = ing.overridePriceTLPerTon ?? 0
                let priceStr = price > 0 ? String(format: "%.0f", price) : "—"
                let stock = ing.hasStock ? "" : " [STOK YOK]"
                s += String(format: "- %@ | %@ | %.1f | %.1f | %.2f | %@%@\n",
                            ing.code, ing.name, ing.minPct, ing.maxPct, ing.mixPct, priceStr, stock)
            }
        }
        s += "\n"

        // ── Besin kısıtları ──────────────────────────────────────────
        s += "## BESİN KISITLARI (besin | min | max | mevcut değer | birim)\n"
        let activeCons = vm.constraints.filter { $0.isActive && ($0.minValue != nil || $0.maxValue != nil) }
        if activeCons.isEmpty {
            s += "(aktif kısıt yok)\n"
        } else {
            for c in activeCons {
                let mn = c.minValue.map { String(format: "%.2f", $0) } ?? "—"
                let mx = c.maxValue.map { String(format: "%.2f", $0) } ?? "—"
                let cur = c.currentValue.map { String(format: "%.2f", $0) } ?? "—"
                s += "- \(c.resolvedDisplayName) | \(mn) | \(mx) | \(cur) | \(c.unit)\n"
            }
        }
        s += "\n"

        // ── Son çözüm ────────────────────────────────────────────────
        s += "## SON ÇÖZÜM\n"
        if let solve = vm.lastSolve {
            s += String(format: "Maliyet: %.2f ₺/ton  |  Durum: %@\n",
                        solve.costPerTon, solve.isFeasible ? "Uygun (tüm kısıtlar sağlandı)" : "Kısmi/Uygun değil")
        } else {
            s += "Henüz çözülmemiş — kullanıcıya önce 'Hesapla'yı çalıştırmasını öner.\n"
        }
        return s
    }
}
