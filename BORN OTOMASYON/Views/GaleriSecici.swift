import SwiftUI
import UIKit

// MARK: - Galeri Seçici (UIImagePickerController tabanlı — her zaman Fotoğraflar açar)

struct GaleriSecici: UIViewControllerRepresentable {
    var onSecim: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType       = .photoLibrary
        picker.allowsEditing    = false
        picker.delegate         = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject,
                              UIImagePickerControllerDelegate,
                              UINavigationControllerDelegate {
        let parent: GaleriSecici
        init(_ parent: GaleriSecici) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let img = info[.originalImage] as? UIImage {
                parent.onSecim(img)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
