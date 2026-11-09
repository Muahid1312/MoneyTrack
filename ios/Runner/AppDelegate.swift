import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var privacyEpoch = 0
  private var privacyCover: UIView?
  override func applicationWillResignActive(_ application: UIApplication) {
    privacyEpoch += 1
    if privacyCover == nil, let view = window?.rootViewController?.view { let cover = UIView(frame: view.bounds); cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]; cover.backgroundColor = .black; view.addSubview(cover); privacyCover = cover }
    if let shown = window?.rootViewController?.presentedViewController as? QLPreviewController { shown.dismiss(animated: false) }
    super.applicationWillResignActive(application)
  }
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
  }
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      MoneyTrackDocuments().register(controller.binaryMessenger, controller: controller)
      MoneyTrackSecurity().register(controller.binaryMessenger) { [weak self] in
        let epoch = self?.privacyEpoch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
          if UIApplication.shared.applicationState == .active && self?.privacyEpoch == epoch { self?.privacyCover?.removeFromSuperview(); self?.privacyCover = nil }
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// Device-only Keychain storage. Biometric tokens are invalidated when the
// enrolled biometric set changes; the app PIN remains the fallback.
import Security
import LocalAuthentication

final class MoneyTrackSecurity {
  private let service = (Bundle.main.bundleIdentifier ?? "moneytrack") + ".security"
  func register(_ messenger: FlutterBinaryMessenger, privacyReady: @escaping () -> Void) {
    FlutterMethodChannel(name: "moneytrack/security", binaryMessenger: messenger).setMethodCallHandler { call, reply in
      switch call.method {
      case "privacyReady": privacyReady(); reply(nil)
      case "read":
        var query = self.query("pin.verifier.v1")
        query[kSecReturnData as String] = true
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { reply(nil) }
        else if status == errSecSuccess, let data = value as? Data, let text = String(data: data, encoding: .utf8) { reply(text) }
        else { reply(FlutterError(code: "DEVICE_SECURITY", message: "Device Keychain is unavailable", details: nil)) }
      case "write":
        guard let text = call.arguments as? String else {
          // Delete the verifier last so a failed removal retains PIN access.
          let biometricStatus = SecItemDelete(self.query("biometric.v1") as CFDictionary)
          guard biometricStatus == errSecSuccess || biometricStatus == errSecItemNotFound else {
            reply(FlutterError(code: "DEVICE_SECURITY", message: "Could not remove biometric unlock", details: nil)); return
          }
          let status = SecItemDelete(self.query("pin.verifier.v1") as CFDictionary)
          guard status == errSecSuccess || status == errSecItemNotFound else {
            reply(FlutterError(code: "DEVICE_SECURITY", message: "Could not remove device lock", details: nil)); return
          }
          reply(nil); return
        }
        let data = Data(text.utf8)
        var query = self.query("pin.verifier.v1")
        let attrs: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound { for (key,value) in attrs { query[key] = value }; status = SecItemAdd(query as CFDictionary, nil) }
        guard status == errSecSuccess else { reply(FlutterError(code: "DEVICE_SECURITY", message: "Could not save device lock", details: nil)); return }
        if let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any], config["biometric"] as? Bool != true {
          SecItemDelete(self.query("biometric.v1") as CFDictionary)
        }
        reply(nil)
      case "enroll": self.biometrics(true, reply)
      case "authenticate": self.biometrics(false, reply)
      default: reply(FlutterMethodNotImplemented)
      }
    }
  }
  private func query(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
  }
  private func biometrics(_ enroll: Bool, _ reply: @escaping FlutterResult) {
    let context = LAContext()
    context.localizedFallbackTitle = "Use app PIN"
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { reply(false); return }
    if enroll {
      context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Enable MoneyTrack biometric unlock") { ok, _ in
        guard ok else { DispatchQueue.main.async { reply(false) }; return }
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil) else {
          DispatchQueue.main.async { reply(false) }; return
        }
        var item = self.query("biometric.v1")
        SecItemDelete(item as CFDictionary)
        item[kSecAttrAccessControl as String] = access
        item[kSecUseAuthenticationContext as String] = context
        item[kSecValueData as String] = Data("moneytrack-unlock-v1".utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        DispatchQueue.main.async { reply(status == errSecSuccess) }
      }
    } else {
      DispatchQueue.global(qos: .userInitiated).async {
        var item = self.query("biometric.v1")
        item[kSecReturnData as String] = true
        item[kSecUseAuthenticationContext as String] = context
        item[kSecUseOperationPrompt as String] = "Unlock MoneyTrack"
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        let valid = status == errSecSuccess && (result as? Data) == Data("moneytrack-unlock-v1".utf8)
        DispatchQueue.main.async { reply(valid) }
      }
    }
  }
}

import PhotosUI
import QuickLook

final class MoneyTrackDocuments: NSObject, UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, QLPreviewControllerDataSource {
  private weak var controller: UIViewController?
  private var reply: FlutterResult?
  private var limit = 10 * 1024 * 1024
  private var previewURL: URL?
  func register(_ messenger: FlutterBinaryMessenger, controller: UIViewController) {
    self.controller = controller
    FlutterMethodChannel(name: "moneytrack/documents", binaryMessenger: messenger).setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      if call.method == "pick" {
        guard self.reply == nil else { result(FlutterError(code: "BUSY", message: "A picker is already open", details: nil)); return }
        let kind = args["kind"] as? String ?? "document"
        self.reply = result
        self.limit = kind == "backup" ? 32 * 1024 * 1024 : 10 * 1024 * 1024
        if kind == "camera" {
          guard UIImagePickerController.isSourceTypeAvailable(.camera) else { self.finish(nil); return }
          let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = self
          self.controller?.present(picker, animated: true)
        } else if kind == "gallery" {
          if #available(iOS 14, *) {
            var config = PHPickerConfiguration(); config.filter = .images; config.selectionLimit = 1
            let picker = PHPickerViewController(configuration: config); picker.delegate = self
            self.controller?.present(picker, animated: true)
          } else {
            let picker = UIImagePickerController(); picker.sourceType = .photoLibrary; picker.delegate = self
            self.controller?.present(picker, animated: true)
          }
        } else {
          let picker = UIDocumentPickerViewController(documentTypes: kind == "backup" ? ["public.data"] : ["com.adobe.pdf"], in: .import)
          picker.delegate = self; picker.allowsMultipleSelection = false
          self.controller?.present(picker, animated: true)
        }
      } else if call.method == "open" {
        guard let path = args["path"] as? String else { result(FlutterError(code: "OPEN", message: "Invalid file", details: nil)); return }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path + "/"
        let allowed = url.path.hasPrefix(home) && (url.path.contains("/moneytrack-data/generations/") && url.path.contains("/receipts/") || url.path.contains("/exports/")) && ["pdf","jpg","png"].contains(url.pathExtension.lowercased())
        guard allowed, FileManager.default.fileExists(atPath: url.path) else { result(FlutterError(code: "OPEN", message: "Private file unavailable", details: nil)); return }
        self.previewURL = url
        let preview = QLPreviewController(); preview.dataSource = self
        self.controller?.present(preview, animated: true); result(nil)
      } else { result(FlutterMethodNotImplemented) }
    }
  }
  private func finish(_ value: Any?) { let result = reply; reply = nil; DispatchQueue.main.async { result?(value) } }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { finish(nil); return }
    let maximum = limit
    DispatchQueue.global(qos: .userInitiated).async {
      let scope = url.startAccessingSecurityScopedResource(); defer { if scope { url.stopAccessingSecurityScopedResource() } }
      do {
        let handle = try FileHandle(forReadingFrom: url); defer { handle.closeFile() }
        let data = handle.readData(ofLength: maximum + 1)
        guard !data.isEmpty, data.count <= maximum else { throw NSError(domain: "Receipt", code: 1) }
        self.finish(["name": url.lastPathComponent, "bytes": FlutterStandardTypedData(bytes: data)])
      } catch { self.finish(FlutterError(code: "IMPORT", message: "File unreadable or too large", details: nil)) }
    }
  }
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true); finish(nil) }
  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    picker.dismiss(animated: true)
    guard let image = info[.originalImage] as? UIImage else { finish(nil); return }; completeImage(image)
  }
  func completeImage(_ image: UIImage) {
    guard image.size.width * image.size.height * image.scale * image.scale <= 40000000,
      let data = image.jpegData(compressionQuality: 0.9), data.count <= limit else {
      finish(FlutterError(code: "IMPORT", message: "Image too large", details: nil)); return
    }
    finish(["name": "Receipt.jpg", "bytes": FlutterStandardTypedData(bytes: data)])
  }
  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { previewURL! as NSURL }
}
@available(iOS 14, *)
extension MoneyTrackDocuments: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let provider = results.first?.itemProvider else { finish(nil); return }
    provider.loadObject(ofClass: UIImage.self) { object, _ in
      guard let image = object as? UIImage else { self.finish(nil); return }
      self.completeImage(image)
    }
  }
}
