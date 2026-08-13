import Foundation
import UniformTypeIdentifiers
import SwiftUI

extension UTType {
    /// Exported type identifier: com.lifecue.backup
    static var lifeCueBackup: UTType {
        UTType(exportedAs: "com.lifecue.backup")
    }
}

struct LifeCueBackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.lifeCueBackup, .json] }
    static var writableContentTypes: [UTType] { [.lifeCueBackup] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupValidationError.unreadable
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
