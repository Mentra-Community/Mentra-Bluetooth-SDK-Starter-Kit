import CoreImage
import ExpoModulesCore
import ImageIO
import UIKit

public class MentraBarcodeScannerModule: Module {
  private var documentInteractionController: UIDocumentInteractionController?
  private var documentInteractionDelegate: DocumentInteractionPreviewDelegate?

  public func definition() -> ModuleDefinition {
    Name("MentraBarcodeScanner")

    AsyncFunction("isSupported") {
      true
    }

    AsyncFunction("scanImage") { (imageUri: String) -> [[String: Any]] in
      try scanImage(imageUri: imageUri)
    }

    AsyncFunction("createTestBarcodeImage") { (value: String) -> [String: Any] in
      try createTestBarcodeImage(value: value)
    }

    AsyncFunction("getImageMetadata") { (imageUri: String) -> [String: Any?] in
      try getImageMetadata(imageUri: imageUri)
    }

    AsyncFunction("openImage") { (imageUri: String) in
      try openImage(imageUri: imageUri)
    }.runOnQueue(.main)
  }

  private func scanImage(imageUri: String) throws -> [[String: Any]] {
    guard let url = URL(string: imageUri) else {
      throw BarcodeScannerError("Invalid image URI.")
    }
    let data = try Data(contentsOf: url)
    return try StillImageBarcodeScanner(imageData: data).scan()
  }

  private func createTestBarcodeImage(value: String) throws -> [String: Any] {
    let safeValue = value.isEmpty ? "MENTRA-BARCODE-12345" : value
    guard let filter = CIFilter(name: "CICode128BarcodeGenerator") else {
      throw BarcodeScannerError("Code 128 barcode generator is unavailable.")
    }
    filter.setValue(Data(safeValue.utf8), forKey: "inputMessage")
    filter.setValue(16.0, forKey: "inputQuietSpace")
    guard let outputImage = filter.outputImage else {
      throw BarcodeScannerError("Could not generate barcode image.")
    }

    let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 3, y: 3))
    let context = CIContext()
    guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
      throw BarcodeScannerError("Could not render barcode image.")
    }
    guard let pngData = UIImage(cgImage: cgImage).pngData() else {
      throw BarcodeScannerError("Could not encode barcode image.")
    }

    let fileUrl = FileManager.default.temporaryDirectory
      .appendingPathComponent("mentra-barcode-test-\(UUID().uuidString).png")
    try pngData.write(to: fileUrl, options: .atomic)
    return [
      "fileUri": fileUrl.absoluteString,
      "value": safeValue,
      "byteCount": pngData.count,
    ]
  }

  private func getImageMetadata(imageUri: String) throws -> [String: Any?] {
    guard let url = URL(string: imageUri) else {
      throw BarcodeScannerError("Invalid image URI.")
    }
    let data = try Data(contentsOf: url)
    guard
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    else {
      throw BarcodeScannerError("Could not read image metadata.")
    }

    let width = intValue(properties[kCGImagePropertyPixelWidth as String])
    let height = intValue(properties[kCGImagePropertyPixelHeight as String])
    let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let focalLength35mm = intValue(exif?[kCGImagePropertyExifFocalLenIn35mmFilm as String])
    return [
      "width": width,
      "height": height,
      "focalLength35mm": focalLength35mm,
      "estimatedFov": estimatedFov(width: width, height: height, focalLength35mm: focalLength35mm),
      "imuMetadata": imuMetadata(from: exif),
    ]
  }

  private func imuMetadata(from exif: [String: Any]?) -> [String: Any?]? {
    guard
      let json = userCommentJson(exif?[kCGImagePropertyExifUserComment as String]),
      let data = json.data(using: .utf8),
      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }

    let samples = payload["samples"] as? [Any]
    return [
      "version": positiveIntValue(payload["version"]),
      "sampleCount": positiveIntValue(payload["sampleCount"]),
      "samplingRateHz": positiveIntValue(payload["samplingRateHz"]),
      "durationMs": nonNegativeDouble(payload["durationMs"]),
      "clockSource": nonEmptyString(payload["clockSource"]),
      "startTimeNs": stringValue(payload["startTimeNs"]),
      "recordingStartElapsedRealtimeNs": stringValue(payload["recordingStartElapsedRealtimeNs"]),
      "videoStartElapsedRealtimeNs": stringValue(payload["videoStartElapsedRealtimeNs"]),
      "exifTruncated": boolValue(payload["exifTruncated"]),
      "firstSample": sampleSummary(samples?.first),
      "lastSample": sampleSummary(samples?.last),
    ]
  }

  private func userCommentJson(_ value: Any?) -> String? {
    let raw: String?
    if let string = value as? String {
      raw = string
    } else if let data = value as? Data {
      raw = String(data: data, encoding: .utf8)
    } else if let nsData = value as? NSData {
      raw = String(data: nsData as Data, encoding: .utf8)
    } else {
      raw = nil
    }
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
          let start = trimmed.firstIndex(of: "{"),
          let end = trimmed.lastIndex(of: "}"),
          start < end else {
      return nil
    }
    return String(trimmed[start...end])
  }

  private func sampleSummary(_ sample: Any?) -> [String: Any?]? {
    guard let values = sample as? [Any], values.count >= 7 else {
      return nil
    }
    return [
      "relativeTimeMs": nonNegativeDouble(values[0]),
      "accel": vector(values, offset: 1),
      "gyro": vector(values, offset: 4),
    ]
  }

  private func vector(_ values: [Any], offset: Int) -> [Double]? {
    guard values.count >= offset + 3,
          let x = doubleValue(values[offset]),
          let y = doubleValue(values[offset + 1]),
          let z = doubleValue(values[offset + 2]) else {
      return nil
    }
    return [x, y, z]
  }

  private func positiveIntValue(_ value: Any?) -> Int? {
    guard let number = doubleValue(value), number > 0 else {
      return nil
    }
    return Int(number)
  }

  private func nonNegativeDouble(_ value: Any?) -> Double? {
    guard let number = doubleValue(value), number >= 0 else {
      return nil
    }
    return number
  }

  private func doubleValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    if let string = value as? String {
      return Double(string)
    }
    return nil
  }

  private func stringValue(_ value: Any?) -> String? {
    if let number = value as? NSNumber {
      return number.stringValue
    }
    if let string = value as? String {
      return string.isEmpty ? nil : string
    }
    return nil
  }

  private func boolValue(_ value: Any?) -> Bool? {
    if let bool = value as? Bool {
      return bool
    }
    if let number = value as? NSNumber {
      return number.boolValue
    }
    return nil
  }

  private func nonEmptyString(_ value: Any?) -> String? {
    guard let string = value as? String, !string.isEmpty else {
      return nil
    }
    return string
  }

  private func openImage(imageUri: String) throws {
    guard let url = URL(string: imageUri) else {
      throw BarcodeScannerError("Invalid image URI.")
    }
    if !url.isFileURL {
      UIApplication.shared.open(url)
      return
    }
    guard let viewController = appContext?.utilities?.currentViewController() else {
      throw BarcodeScannerError("Could not find a view controller to open the image.")
    }
    let controller = UIDocumentInteractionController(url: url)
    let delegate = DocumentInteractionPreviewDelegate { [weak self] in
      self?.appContext?.utilities?.currentViewController()
    }
    controller.delegate = delegate
    documentInteractionController = controller
    documentInteractionDelegate = delegate
    if !controller.presentPreview(animated: true) {
      if !controller.presentOptionsMenu(from: viewController.view.bounds, in: viewController.view, animated: true) {
        throw BarcodeScannerError("No image viewer is available for this file.")
      }
    }
  }

  private func intValue(_ value: Any?) -> Int? {
    if let number = value as? NSNumber {
      let intValue = number.intValue
      return intValue > 0 ? intValue : nil
    }
    if let string = value as? String, let intValue = Int(string), intValue > 0 {
      return intValue
    }
    return nil
  }

  private func estimatedFov(width: Int?, height: Int?, focalLength35mm: Int?) -> [String: Any]? {
    guard let focalLength35mm, focalLength35mm > 0 else {
      return nil
    }
    let aspect: Double
    if let width, let height, height > 0 {
      aspect = Double(width) / Double(height)
    } else {
      aspect = 4.0 / 3.0
    }
    let sensorHeight = fullFrameDiagonalMm / sqrt((aspect * aspect) + 1.0)
    let sensorWidth = sensorHeight * aspect
    return [
      "basis": "35mm_equivalent",
      "focalLength35mm": focalLength35mm,
      "diagonalDegrees": fovDegrees(sensorMm: fullFrameDiagonalMm, focalLengthMm: Double(focalLength35mm)),
      "horizontalDegrees": fovDegrees(sensorMm: sensorWidth, focalLengthMm: Double(focalLength35mm)),
      "verticalDegrees": fovDegrees(sensorMm: sensorHeight, focalLengthMm: Double(focalLength35mm)),
    ]
  }

  private func fovDegrees(sensorMm: Double, focalLengthMm: Double) -> Double {
    2.0 * atan(sensorMm / (2.0 * focalLengthMm)) * 180.0 / Double.pi
  }

}

private let fullFrameDiagonalMm = 43.266615305567875

private final class DocumentInteractionPreviewDelegate: NSObject, UIDocumentInteractionControllerDelegate {
  private let viewControllerProvider: () -> UIViewController?

  init(viewControllerProvider: @escaping () -> UIViewController?) {
    self.viewControllerProvider = viewControllerProvider
  }

  func documentInteractionControllerViewControllerForPreview(
    _ controller: UIDocumentInteractionController
  ) -> UIViewController {
    viewControllerProvider() ?? UIViewController()
  }
}

final class BarcodeScannerError: Exception, @unchecked Sendable {
  private let message: String

  init(_ message: String) {
    self.message = message
    super.init()
  }

  override var reason: String {
    message
  }
}
