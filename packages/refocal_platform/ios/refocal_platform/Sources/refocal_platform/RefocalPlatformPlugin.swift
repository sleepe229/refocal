// SPDX-License-Identifier: Apache-2.0
import Flutter
import UIKit

// TODO(iOS, needs a Mac): PHPickerViewController for pickImages, PHPhotoLibrary for saveToGallery.
// Not compiled or tested yet; getDirs only.
public class RefocalPlatformPlugin: NSObject, FlutterPlugin, RefocalPlatformApi {
  public static func register(with registrar: FlutterPluginRegistrar) {
    RefocalPlatformApiSetup.setUp(binaryMessenger: registrar.messenger(), api: RefocalPlatformPlugin())
  }

  /// PRIV-DATA-005: Application Support is backed up and holds prefs.sqlite; everything else
  /// (models, jobs, inbox, db.sqlite) lives in its "local" subdirectory, excluded from backup.
  func getDirs() throws -> AppDirs {
    let fm = FileManager.default
    let backedUp = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                              appropriateFor: nil, create: true)
    var support = backedUp.appendingPathComponent("local", isDirectory: true)
    try fm.createDirectory(at: support, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try support.setResourceValues(values)
    let cache = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return AppDirs(support: support.path, backedUp: backedUp.path, cache: cache.path)
  }

  func lastExitReason() throws -> String? { nil }  // iOS has no exit reason API: unknown

  func pickImages(inboxDir: String, maxCount: Int64) async throws -> PickedImages {
    throw PigeonError(code: "unimplemented", message: "pickImages is not implemented on iOS yet", details: nil)
  }

  func saveToGallery(path: String, displayName: String, mimeType: String) async throws -> String {
    throw PigeonError(code: "unimplemented", message: "saveToGallery is not implemented on iOS yet", details: nil)
  }

  func saveToFile(path: String, displayName: String, mimeType: String) async throws -> String? {
    throw PigeonError(code: "unimplemented", message: "saveToFile is not implemented on iOS yet", details: nil)
  }

  func shareFile(path: String, mimeType: String, chooserTitle: String) throws {
    throw PigeonError(code: "unimplemented", message: "shareFile is not implemented on iOS yet", details: nil)
  }

  // FR-SHARE-003: the Share Extension (App Group inbox) comes with the iOS build.
  func takeSharedImages(inboxDir: String) async throws -> PickedImages {
    PickedImages(images: [], failed: 0, failure: nil)
  }

  // ADR-0019: iOS pauses on willResignActive instead of a background service (TODO with S5).
  func requestNotificationPermission() async throws -> Bool { true }
  func startProcessing(texts: ProcessingTexts) throws {}
  func updateProcessing(text: String, percent: Int64) throws {}
  func stopProcessing(finishedText: String?) throws {}
}
