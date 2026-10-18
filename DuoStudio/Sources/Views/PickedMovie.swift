import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// What `PhotosPicker` hands back for a chosen video: a temp-file copy we own. The picker's own
/// file is only valid inside the import closure, so it is copied out at once;
/// `StudioModel.importRoutine(from:)` deletes the copy when it is done.
struct PickedMovie: Transferable {
    let url: URL

    // UNVERIFIED (2026-10-18, written on Windows): the `FileRepresentation(contentType:exporting:
    // importing:)` closure shapes (`SentTransferredFile`, `ReceivedTransferredFile.file`) were
    // written from memory; check against the SDK on a Mac.
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

// Lives in the view layer so the model stays free of PhotosUI/SwiftUI.
extension StudioModel {
    /// A video chosen in `PhotosPicker`: loads it to a temp copy (`PickedMovie`), then imports it.
    func importPickedVideo(_ item: PhotosPickerItem) async {
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else {
            errorMessage = "Couldn't import that video."
            return
        }
        await importRoutine(from: movie.url)
    }
}
