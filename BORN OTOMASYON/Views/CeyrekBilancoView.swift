import SwiftUI
import SwiftData

// MARK: - Çeyreklik Bilanço Ana Ekranı

struct CeyrekBilancoView: View {
    @Environment(\.modelContext)        private var context
    @Environment(\.dismiss)             private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Query private var brandDefs: [BrandDefinition]
    @Query private var giderler:  [GiderKalemi]

    // Seçili dönem
    @State private var secilenYil:    Int = Calendar.current.component(.year, from: Date())
    @State private var secilenCeyrek: Int = {
        let ay = Calendar.current.component(.month, from: Date())
        return (ay - 1) / 3 + 1
    }()

    @State private var bilanco: CeyrekBilanco? = nil
    @State private var otoHesaplaniyor = false
    @State private var pdfData:   Data? = nil
    @State private var xlsxData:  Data? = nil
    @State private var showPDF    = false
    @State private var showXLSX   = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    donemSecici
                    if let b = bilanco {
                        bilancoIcerigi(b)
                    } else {
                        ContentUnavailableView("Bilanço Yükleniyor", systemImage: "doc.text")
                            .padding(40)
                    }
                }
            }
            .navigationTitle("Çeyreklik Bilanço")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .onAppear { yukle() }
        .onChange(of: secilenYil)    { _, _ in yukle() }
        .onChange(of: secilenCeyrek) { _, _ in yukle() }
        .sheet(isPresented: $showPDF) {
            if let data = pdfData {
                ActivityView(items: [data], filename: "bilanco_\(secilenYil)_Q\(secilenCeyrek).pdf")
            }
        }
        .sheet(isPresented: $showXLSX) {
            if let data = xlsxData {
                ActivityView(items: [data], filename: "bilanco_\(secilenYil)_Q\(secilenCeyrek).xlsx")
            }
        }
    }

    // MARK: Dönem Seçici

    private var donemSecici: some View {
        HStack(spacing: 16) {
            // Yıl
            HStack(spacing: 4) {
                Button { secilenYil -= 1 } label: { Image(systemName: "chevron.left") }
                Text(String(secilenYil)).font(.headline).frame(width: 56)
                Button { secilenYil += 1 } label: { Image(systemName: "chevron.right") }
            }
            .foregroundStyle(.primary)

            Spacer()

            // Çeyrek
            HStack(spacing: 4) {
                ForEach(1...4, id: \.self) { q in
                    Button("Q\(q)") { secilenCeyrek = q }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(secilenCeyrek == q ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(secilenCeyrek == q ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Spacer()

            // Oto-hesapla butonu
            Button {
                otoHesapla()
            } label: {
                HStack(spacing: 4) {
                    if otoHesaplaniyor {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Oto-Hesapla")
                }
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(otoHesaplaniyor)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
    }

    // MARK: Ana İçerik

    @ViewBuilder
    private func bilancoIcerigi(_ b: CeyrekBilanco) -> some View {
        VStack(spacing: 12) {
            // Gelir Tablosu Özeti
            gelirTablosuKart(b)

            // Bilanço: Aktif | Pasif
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 12) {
                    aktifSutun(b)
                    pasifSutun(b)
                }
            } else {
                VStack(spacing: 12) {
                    aktifSutun(b)
                    pasifSutun(b)
                }
            }

            // Denge Göstergesi
            dengeGosterge(b)

            // Notlar
            notlarAlani(b)
        }
        .padding()
    }

    // MARK: Gelir Tablosu Kartı

    private func gelirTablosuKart(_ b: CeyrekBilanco) -> some View {
        GroupBox {
            VStack(spacing: 0) {
                GelirTablosuSatiri(lbl: "Net Satışlar",
                                   deger: b.netSatislar, manuel: true, ilk: true) { yeni in
                    b.netSatislar = yeni; kaydet()
                }
                GelirTablosuSatiri(lbl: "(-) SMM (Oto)",
                                   deger: b.smmOto, manuel: false, ilk: false) { _ in }

                Divider().padding(.vertical, 4)

                TumSatir(lbl: "BRÜT KÂR", deger: b.brutKar)

                GelirTablosuSatiri(lbl: "(-) Operasyonel Gider",
                                   deger: b.opGiderOto, manuel: true, ilk: false) { yeni in
                    b.opGiderOto = yeni; kaydet()
                }

                Divider().padding(.vertical, 4)

                TumSatir(lbl: "DÖNEM NET KARI", deger: b.donemNetKari, vurgula: true)
            }
        } label: {
            Label("Gelir Tablosu — \(b.ceyrekBasligi) \(b.yil)", systemImage: "chart.bar.doc.horizontal")
                .font(.subheadline.bold())
        }
    }

    // MARK: Aktif Sütun

    private func aktifSutun(_ b: CeyrekBilanco) -> some View {
        GroupBox {
            VStack(spacing: 0) {
                bilancoBaslik("DÖNEN VARLIKLAR")
                BilancoSatiri(lbl: "Nakit / Banka",        deger: b.nakit,          manuel: true)  { b.nakit         = $0; kaydet() }
                BilancoSatiri(lbl: "Ticari Alacaklar",     deger: b.alacaklar,      manuel: true)  { b.alacaklar     = $0; kaydet() }
                BilancoSatiri(lbl: "Stok (Oto)",           deger: b.stokOto,        manuel: false) { _ in }
                BilancoSatiri(lbl: "Diğer Dönen",          deger: b.digerDonen,     manuel: true)  { b.digerDonen    = $0; kaydet() }

                Divider().padding(.vertical, 6)
                bilancoBaslik("DURAN VARLIKLAR")
                BilancoSatiri(lbl: "Sabit Kıymet (Brüt)", deger: b.sabitKiymetBrut, manuel: true) { b.sabitKiymetBrut = $0; kaydet() }
                BilancoSatiri(lbl: "Birikmiş Amortisman", deger: b.birikmisBrut,   manuel: true)  { b.birikmisBrut  = $0; kaydet() }
                BilancoSatiri(lbl: "  → Net",             deger: b.sabitKiymetNet,  manuel: false) { _ in }
                BilancoSatiri(lbl: "Diğer Duran",         deger: b.digerDuran,     manuel: true)  { b.digerDuran    = $0; kaydet() }

                Divider().padding(.vertical, 4)
                TumSatir(lbl: "TOPLAM AKTİF", deger: b.toplamAktif)
            }
        } label: {
            Label("AKTİF", systemImage: "arrow.right.square").font(.subheadline.bold())
        }
    }

    // MARK: Pasif Sütun

    private func pasifSutun(_ b: CeyrekBilanco) -> some View {
        GroupBox {
            VStack(spacing: 0) {
                bilancoBaslik("KISA VADELİ BORÇLAR")
                BilancoSatiri(lbl: "Ticari Borçlar",       deger: b.kisaVadeli,  manuel: true) { b.kisaVadeli  = $0; kaydet() }

                Divider().padding(.vertical, 6)
                bilancoBaslik("UZUN VADELİ BORÇLAR")
                BilancoSatiri(lbl: "Banka Kredileri",      deger: b.uzunVadeli,  manuel: true) { b.uzunVadeli  = $0; kaydet() }

                Divider().padding(.vertical, 6)
                bilancoBaslik("ÖZ KAYNAK")
                BilancoSatiri(lbl: "Sermaye",              deger: b.sermaye,     manuel: true) { b.sermaye     = $0; kaydet() }
                BilancoSatiri(lbl: "Geçmiş Yıl Karları",  deger: b.gecmisKarlar, manuel: true) { b.gecmisKarlar = $0; kaydet() }
                BilancoSatiri(lbl: "Dönem Net Karı (Oto)", deger: b.donemNetKari, manuel: false) { _ in }
                BilancoSatiri(lbl: "  → Öz Kaynak",        deger: b.ozKaynak,    manuel: false) { _ in }

                Divider().padding(.vertical, 4)
                TumSatir(lbl: "TOPLAM PASİF", deger: b.toplamPasif)
            }
        } label: {
            Label("PASİF", systemImage: "arrow.left.square").font(.subheadline.bold())
        }
    }

    // MARK: Denge

    private func dengeGosterge(_ b: CeyrekBilanco) -> some View {
        HStack {
            Image(systemName: b.dengeSaglandı ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(b.dengeSaglandı ? .green : .red)
            if b.dengeSaglandı {
                Text("Bilanço Dengesi Sağlandı")
                    .font(.subheadline.bold()).foregroundStyle(.green)
            } else {
                Text("Fark: \(tlFmt(abs(b.fark)))")
                    .font(.subheadline.bold()).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(b.dengeSaglandı ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Notlar

    private func notlarAlani(_ b: CeyrekBilanco) -> some View {
        GroupBox("Notlar") {
            TextEditor(text: Binding(
                get: { b.notlar },
                set: { b.notlar = $0; kaydet() }
            ))
            .frame(minHeight: 80)
            .font(.caption)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Kapat") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    if let b = bilanco {
                        let sirket = brandDefs.first?.name ?? "BORN OTOMASYON"
                        let logo   = brandDefs.first?.antetImage
                        let svc = BilancoExportService(bilanco: b, sirketAdi: sirket, logoImage: logo)
                        pdfData = svc.generate()
                        showPDF = true
                    }
                } label: {
                    Label("PDF Paylaş", systemImage: "doc.richtext")
                }

                Button {
                    if let b = bilanco {
                        let sirket = brandDefs.first?.name ?? "BORN OTOMASYON"
                        var svc = BilancoXLSXService(bilanco: b, sirketAdi: sirket)
                        xlsxData = svc.generate()
                        showXLSX = true
                    }
                } label: {
                    Label("Excel İndir (.xlsx)", systemImage: "tablecells")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    // MARK: Yardımcılar

    private func yukle() {
        bilanco = CeyrekBilanco.upsert(yil: secilenYil, ceyrek: secilenCeyrek, in: context)
    }

    private func kaydet() {
        bilanco?.kayitTarihi = Date()
        try? context.save()
    }

    private func otoHesapla() {
        guard let b = bilanco else { return }
        otoHesaplaniyor = true
        let sonuc = BilancoService.hesapla(yil: secilenYil, ceyrek: secilenCeyrek, context: context)
        b.smmOto  = sonuc.smm
        b.stokOto = sonuc.stok
        kaydet()
        otoHesaplaniyor = false
    }

    private func bilancoBaslik(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

// MARK: - Gelir Tablosu Satırı

private struct GelirTablosuSatiri: View {
    let lbl: String
    let deger: Double
    let manuel: Bool
    let ilk: Bool
    let onCommit: (Double) -> Void

    @State private var metin: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(lbl)
                .font(.caption)
                .foregroundStyle(manuel ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if manuel {
                ZStack(alignment: .trailing) {
                    // TextField her zaman hierarchy'de — programmatic focus çalışsın
                    TextField("0", text: $metin)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.caption.bold())
                        .frame(width: 110)
                        .focused($focused)
                        .opacity(focused ? 1 : 0)
                        .onChange(of: focused) { _, isFocused in
                            if isFocused {
                                metin = deger == 0 ? "" : String(Int(deger.rounded()))
                            } else {
                                commit()
                            }
                        }
                    if !focused {
                        Text(deger == 0 ? "Girin" : tlFmt(deger))
                            .font(.caption.bold())
                            .foregroundStyle(deger == 0 ? .tertiary : .primary)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: 110, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
            } else {
                Text(tlFmt(deger))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func commit() {
        let clean = metin.trimmingCharacters(in: .whitespaces)
        let digits = clean.filter { $0.isNumber }
        if let v = Double(digits), !digits.isEmpty { onCommit(v) }
        else if clean.isEmpty { onCommit(0) }
    }
}

// MARK: - Bilanço Satırı

private struct BilancoSatiri: View {
    let lbl: String
    let deger: Double
    let manuel: Bool
    let onCommit: (Double) -> Void

    @State private var metin: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(lbl)
                .font(.caption)
                .foregroundStyle(manuel ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if manuel {
                ZStack(alignment: .trailing) {
                    TextField("0", text: $metin)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.caption.bold())
                        .frame(width: 100)
                        .focused($focused)
                        .opacity(focused ? 1 : 0)
                        .onChange(of: focused) { _, isFocused in
                            if isFocused {
                                metin = deger == 0 ? "" : String(Int(deger.rounded()))
                            } else {
                                commit()
                            }
                        }
                    if !focused {
                        Text(deger == 0 ? "Girin" : tlFmt(deger))
                            .font(.caption.bold())
                            .foregroundStyle(deger == 0 ? .tertiary : .primary)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: 100, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
            } else {
                Text(tlFmt(deger))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func commit() {
        let clean = metin.trimmingCharacters(in: .whitespaces)
        let digits = clean.filter { $0.isNumber }
        if let v = Double(digits), !digits.isEmpty { onCommit(v) }
        else if clean.isEmpty { onCommit(0) }
    }
}

// MARK: - Toplam Satırı

private struct TumSatir: View {
    let lbl: String
    let deger: Double
    var vurgula: Bool = false

    var body: some View {
        HStack {
            Text(lbl).font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(tlFmt(deger)).font(.caption.bold())
                .foregroundStyle(vurgula ? (deger >= 0 ? .green : .red) : .primary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background((vurgula ? (deger >= 0 ? Color.green : Color.red) : Color.accentColor).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - TL Formatlayıcı (yardımcı)

private func tlFmt(_ v: Double) -> String {
    let fmt = NumberFormatter()
    fmt.numberStyle = .decimal
    fmt.maximumFractionDigits = 0
    fmt.locale = Locale(identifier: "tr_TR")
    let s = fmt.string(from: NSNumber(value: abs(v))) ?? "\(Int(abs(v)))"
    return (v < 0 ? "−" : "") + s + " ₺"
}

// MARK: - Paylaşım Sheet

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let filename: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Geçici dosya yaz (XLSX/PDF için doğru isimle paylaşım)
        if let data = items.first as? Data {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try? data.write(to: url)
            return UIActivityViewController(activityItems: [url], applicationActivities: nil)
        }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
