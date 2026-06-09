import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Fotoğraflar'dan seçici (PHPickerViewController — iOS + macOS Catalyst)

struct FotografSecici: UIViewControllerRepresentable {
    var onSecim: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter         = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: FotografSecici
        init(_ p: FotografSecici) { parent = p }

        func picker(_ picker: PHPickerViewController,
                    didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }
            result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                if let img = obj as? UIImage {
                    DispatchQueue.main.async { self.parent.onSecim(img) }
                }
            }
        }
    }
}

// MARK: - Dosyalar'dan seçici (UIDocumentPickerViewController — PDF + resim)

struct DosyaSecici: UIViewControllerRepresentable {
    var onSecim: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.jpeg, .png, .tiff, .heic, .pdf, .image]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DosyaSecici
        init(_ p: DosyaSecici) { parent = p }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first,
                  url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            if let img = UIImage(contentsOfFile: url.path) {
                DispatchQueue.main.async { self.parent.onSecim(img) }
                return
            }
            // PDF → ilk sayfa olarak render et
            if url.pathExtension.lowercased() == "pdf",
               let img = Self.pdfToImage(url) {
                DispatchQueue.main.async { self.parent.onSecim(img) }
            }
        }

        static func pdfToImage(_ url: URL) -> UIImage? {
            guard let doc  = CGPDFDocument(url as CFURL),
                  let page = doc.page(at: 1) else { return nil }
            let rect  = page.getBoxRect(.mediaBox)
            let scale: CGFloat = 2.0
            let size  = CGSize(width: rect.width * scale, height: rect.height * scale)
            UIGraphicsBeginImageContextWithOptions(size, true, 1)
            defer { UIGraphicsEndImageContext() }
            guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.scaleBy(x: scale, y: -scale)
            ctx.translateBy(x: 0, y: -rect.height)
            ctx.drawPDFPage(page)
            return UIGraphicsGetImageFromCurrentImageContext()
        }
    }
}

// MARK: - Kaynak seçim sarmalayıcısı (ViewModifier)

struct ResimYukleButon: View {
    let baslik:    String
    var ikon:      String = "photo.on.rectangle.angled"
    var onSecim:   (UIImage) -> Void

    @State private var showDialog  = false
    @State private var showFoto    = false
    @State private var showDosya   = false

    var body: some View {
        Button { showDialog = true } label: {
            Label(baslik, systemImage: ikon).foregroundStyle(.blue)
        }
        .confirmationDialog("Resim kaynağı seçin", isPresented: $showDialog) {
            Button("Fotoğraflardan Seç") { showFoto  = true }
            Button("Dosyalardan Seç")    { showDosya = true }
        }
        .sheet(isPresented: $showFoto) {
            FotografSecici { img in showFoto = false; onSecim(img) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showDosya) {
            DosyaSecici { img in showDosya = false; onSecim(img) }
        }
    }
}
