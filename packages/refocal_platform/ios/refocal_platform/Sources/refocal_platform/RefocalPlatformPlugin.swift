// SPDX-License-Identifier: Apache-2.0
import Flutter
import UIKit

// TODO(iOS, needs a Mac): PHPickerViewController for pickImage, PHPhotoLibrary for saveToGallery.
// Not compiled or tested yet; getDirs only.
public class RefocalPlatformPlugin: NSObject, FlutterPlugin, RefocalPlatformApi {
  public static func register(with registrar: FlutterPluginRegistrar) {
    RefocalPlatformApiSetup.setUp(binaryMessenger: registrar.messenger(), api: RefocalPlatformPlugin())
  }

  func getDirs() throws -> AppDirs {
    let fm = FileManager.default
    let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                             appropriateFor: nil, create: true)
    let cache = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return AppDirs(support: support.path, cache: cache.path)
  }

  func lastExitReason() throws -> String? { nil }  // iOS has no exit reason API: unknown

  func pickImage(inboxDir: String) async throws -> PickedImage? {
    throw PigeonError(code: "unimplemented", message: "pickImage is not implemented on iOS yet", details: nil)
  }

  func saveToGallery(path: String, displayName: String, mimeType: String) async throws -> String {
    throw PigeonError(code: "unimplemented", message: "saveToGallery is not implemented on iOS yet", details: nil)
  }

  // ADR-0019: iOS pauses on willResignActive instead of a background service (TODO with S5).
  func requestNotificationPermission() async throws -> Bool { true }
  func startProcessing(title: String) throws {}
  func updateProcessing(text: String, percent: Int64) throws {}
  func stopProcessing(finishedText: String?) throws {}
}
