import SwiftUI
import UniformTypeIdentifiers

// A backup file: JSON text with all devices and learned keys
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let s = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = s
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
