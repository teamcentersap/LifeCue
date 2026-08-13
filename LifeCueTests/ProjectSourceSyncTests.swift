import XCTest

/// Locates the LifeCue checkout root for source-scanning tests.
/// Order: scheme env → test-bundle snapshot (device) → walk `#filePath` → walk cwd.
enum LifeCueRepositoryRoot {
    static func resolve(filePath: String = #filePath) throws -> URL {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        for key in ["LIFECUE_REPO_ROOT", "SRCROOT", "PROJECT_DIR"] {
            if let raw = env[key], !raw.isEmpty {
                let candidate = URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
                if isRepositoryRoot(candidate, fileManager: fm) {
                    return candidate
                }
            }
        }

        // Physical devices cannot read Mac SRCROOT; the test target copies a snapshot
        // into LifeCueTests.xctest/LifeCueRepoRoot via Scripts/copy_lifecue_repo_snapshot_for_tests.sh.
        let bundleSnapshot = Bundle(for: ProjectSourceSyncTests.self).bundleURL
            .appendingPathComponent("LifeCueRepoRoot", isDirectory: true)
            .standardizedFileURL
        if isRepositoryRoot(bundleSnapshot, fileManager: fm) {
            return bundleSnapshot
        }

        if let root = walkForRepositoryRoot(
            startingAt: URL(fileURLWithPath: filePath).standardizedFileURL,
            fileManager: fm
        ) {
            return root
        }

        if let root = walkForRepositoryRoot(
            startingAt: URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true).standardizedFileURL,
            fileManager: fm
        ) {
            return root
        }

        struct RootNotFound: Error, CustomStringConvertible {
            var description: String {
                "Could not locate LifeCue repository root (LifeCue.xcodeproj + LifeCue/ + LifeCueTests/). Set LIFECUE_REPO_ROOT/SRCROOT, or ensure the test bundle snapshot copy phase ran."
            }
        }
        throw RootNotFound()
    }

    private static func walkForRepositoryRoot(startingAt start: URL, fileManager: FileManager) -> URL? {
        var current = start
        if !current.hasDirectoryPath {
            current.deleteLastPathComponent()
        }
        while true {
            if isRepositoryRoot(current, fileManager: fileManager) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    private static func isRepositoryRoot(_ url: URL, fileManager: FileManager) -> Bool {
        let pbx = url.appendingPathComponent("LifeCue.xcodeproj/project.pbxproj")
        let app = url.appendingPathComponent("LifeCue", isDirectory: true)
        let tests = url.appendingPathComponent("LifeCueTests", isDirectory: true)
        return fileManager.fileExists(atPath: pbx.path)
            && fileManager.fileExists(atPath: app.path)
            && fileManager.fileExists(atPath: tests.path)
    }
}

final class ProjectSourceSyncTests: XCTestCase {
    func testXcodeProjectIncludesAllSwiftSources() throws {
        let root = try LifeCueRepositoryRoot.resolve()

        let projectFile = root
            .appendingPathComponent("LifeCue.xcodeproj/project.pbxproj")
        let projectContents = try String(contentsOf: projectFile, encoding: .utf8)

        let lifeCueSources = try swiftFiles(in: root.appendingPathComponent("LifeCue"))
        let testSources = try swiftFiles(in: root.appendingPathComponent("LifeCueTests"))

        for relativePath in lifeCueSources + testSources {
            XCTAssertTrue(
                projectContains(relativePath, in: projectContents),
                "Missing from Xcode project: \(relativePath)"
            )
        }
    }

    /// Matches generator-quoted (`path = "…"`) and unquoted (`path = …;`) PBXFileReference forms.
    private func projectContains(_ relativePath: String, in projectContents: String) -> Bool {
        projectContents.contains("path = \"\(relativePath)\"")
            || projectContents.contains("path = \(relativePath);")
    }

    private func swiftFiles(in directory: URL) throws -> [String] {
        let root = directory.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let rootPath = root.path
        guard let enumerator = FileManager.default.enumerator(
            at: directory.resolvingSymlinksInPath(),
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        var paths: [String] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            let filePath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard filePath.hasPrefix(rootPath + "/") else {
                XCTFail("Could not relativize \(filePath) against \(rootPath)")
                continue
            }
            paths.append(String(filePath.dropFirst(rootPath.count + 1)))
        }
        return paths.sorted()
    }
}
