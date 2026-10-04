import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Opens in place: the user grants access to a directory, not a copied URL.
struct DestinationFolderPicker: UIViewControllerRepresentable {
  let onSelection: (URL) -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
    picker.allowsMultipleSelection = false
    picker.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    picker.delegate = context.coordinator
    return picker
  }
  func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    let parent: DestinationFolderPicker
    init(_ parent: DestinationFolderPicker) { self.parent = parent }
    func documentPicker(
      _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
    ) {
      if let folder = urls.first { parent.onSelection(folder) } else { parent.onCancel() }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
      parent.onCancel()
    }
  }
}
