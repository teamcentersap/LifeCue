import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Loads image bytes from PhotosPicker without requesting full library access.
struct TransferableImageData: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            TransferableImageData(data: data)
        }
    }
}
