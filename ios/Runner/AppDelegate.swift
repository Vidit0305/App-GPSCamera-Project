import CoreGraphics
import Flutter
import ImageIO
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ImageNativePlugin") {
      ImageNativePlugin.register(with: registrar)
    }
  }
}

// MARK: - Native image helpers (channel "com.gpscamera/image_native")

/// EXIF read/write and JPEG encoding using ImageIO.
///
/// - readMetadata: CGImageSourceCopyPropertiesAtIndex
/// - writeMetadata: lossless update via CGImageDestinationCopyImageSource (no recompression)
/// - encodeJpeg: encodes raw RGBA pixels and embeds metadata copied from a source image
/// - stripGpsCopy: copy with kCGImageMetadataShouldExcludeGPS
final class ImageNativePlugin: NSObject, FlutterPlugin {
  private struct NativeError: Error {
    let code: String
    let message: String
  }

  private let queue = DispatchQueue(label: "com.gpscamera.image_native", qos: .userInitiated)

  private static let writableFormats: Set<String> = ["jpeg", "png", "heic", "heif", "tiff"]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.gpscamera/image_native", binaryMessenger: registrar.messenger())
    let instance = ImageNativePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let method = call.method
    guard ["readMetadata", "writeMetadata", "encodeJpeg", "stripGpsCopy"].contains(method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    queue.async {
      var reply: Any? = nil
      do {
        switch method {
        case "readMetadata":
          reply = try self.readMetadata(path: try Self.string(args, "path"))
        case "writeMetadata":
          let values = args["values"] as? [String: Any] ?? [:]
          try self.writeMetadata(path: try Self.string(args, "path"), values: values)
        case "encodeJpeg":
          reply = try self.encodeJpeg(args)
        case "stripGpsCopy":
          try self.stripGpsCopy(
            source: try Self.string(args, "sourcePath"), output: try Self.string(args, "outputPath"))
        default:
          break
        }
      } catch let e as NativeError {
        DispatchQueue.main.async {
          result(FlutterError(code: e.code, message: e.message, details: nil))
        }
        return
      } catch {
        let ns = error as NSError
        let code =
          (ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError)
          ? "NO_SPACE" : "\(method.uppercased())_FAILED"
        DispatchQueue.main.async {
          result(FlutterError(code: code, message: error.localizedDescription, details: nil))
        }
        return
      }
      DispatchQueue.main.async { result(reply) }
    }
  }

  // MARK: Helpers

  private static func string(_ args: [String: Any], _ key: String) throws -> String {
    guard let v = args[key] as? String, !v.isEmpty else {
      throw NativeError(code: "BAD_ARGS", message: "Missing argument '\(key)'.")
    }
    return v
  }

  private static func formatName(_ uti: String) -> String {
    switch uti {
    case "public.jpeg": return "jpeg"
    case "public.png": return "png"
    case "public.heic": return "heic"
    case "public.heif": return "heif"
    case "public.tiff": return "tiff"
    case "org.webmproject.webp": return "webp"
    case "com.compuserve.gif": return "gif"
    case "public.avif": return "avif"
    default: return uti.isEmpty ? "unknown" : uti
    }
  }

  private static func describe(_ value: Any) -> String {
    if let arr = value as? [Any] { return arr.map { describe($0) }.joined(separator: ", ") }
    return "\(value)"
  }

  private static func properties(of source: CGImageSource) -> [String: Any] {
    return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
  }

  private static func replaceItem(at target: URL, with tmp: URL) throws {
    let fm = FileManager.default
    if fm.fileExists(atPath: target.path) {
      _ = try fm.replaceItemAt(target, withItemAt: tmp)
    } else {
      try fm.moveItem(at: tmp, to: target)
    }
  }

  /// Lossless copy of an image with metadata changes (no pixel recompression).
  private func copySource(
    from inURL: URL, to outURL: URL, metadata: CGImageMetadata?, excludeGPS: Bool
  ) throws {
    guard let src = CGImageSourceCreateWithURL(inURL as CFURL, nil),
      let type = CGImageSourceGetType(src)
    else {
      throw NativeError(code: "READ_FAILED", message: "The image could not be opened.")
    }
    guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, type, 1, nil) else {
      throw NativeError(
        code: "UNSUPPORTED_FORMAT",
        message:
          "Metadata cannot be written to \(Self.formatName(type as String).uppercased()) files on iOS.")
    }
    var options: [String: Any] = [:]
    if let metadata = metadata {
      options[kCGImageDestinationMetadata as String] = metadata
      options[kCGImageDestinationMergeMetadata as String] = true
    }
    if excludeGPS {
      options[kCGImageMetadataShouldExcludeGPS as String] = true
    }
    var error: Unmanaged<CFError>?
    // CGImageDestinationFinalize must not be called after CopyImageSource.
    if !CGImageDestinationCopyImageSource(dest, src, options as CFDictionary, &error) {
      let msg = error?.takeRetainedValue().localizedDescription ?? "unknown error"
      try? FileManager.default.removeItem(at: outURL)
      throw NativeError(
        code: "WRITE_FAILED",
        message: "This image's metadata could not be updated losslessly: \(msg)")
    }
  }

  // MARK: Read

  private func readMetadata(path: String) throws -> [String: Any] {
    guard FileManager.default.fileExists(atPath: path) else {
      throw NativeError(code: "NOT_FOUND", message: "File not found: \(path)")
    }
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
      throw NativeError(code: "READ_FAILED", message: "The image could not be opened.")
    }
    var out: [String: Any] = [:]
    let format = Self.formatName((CGImageSourceGetType(src) as String?) ?? "")
    out["format"] = format
    out["writeSupported"] = Self.writableFormats.contains(format)

    let props = Self.properties(of: src)
    let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
    let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
    let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]

    func s(_ dict: [String: Any], _ key: CFString) -> String? {
      guard let v = dict[key as String] else { return nil }
      let str = Self.describe(v).trimmingCharacters(in: .whitespacesAndNewlines)
      return str.isEmpty ? nil : str
    }
    func n(_ dict: [String: Any], _ key: CFString) -> Double? {
      return (dict[key as String] as? NSNumber)?.doubleValue
    }

    out["dateTimeOriginal"] = s(exif, kCGImagePropertyExifDateTimeOriginal)
    out["dateTimeDigitized"] = s(exif, kCGImagePropertyExifDateTimeDigitized)
    out["dateTime"] = s(tiff, kCGImagePropertyTIFFDateTime)
    out["offsetTimeOriginal"] = s(exif, kCGImagePropertyExifOffsetTimeOriginal)
    out["offsetTime"] = s(exif, kCGImagePropertyExifOffsetTime)
    out["imageDescription"] = s(tiff, kCGImagePropertyTIFFImageDescription)
    out["artist"] = s(tiff, kCGImagePropertyTIFFArtist)
    out["copyright"] = s(tiff, kCGImagePropertyTIFFCopyright)
    out["make"] = s(tiff, kCGImagePropertyTIFFMake)
    out["model"] = s(tiff, kCGImagePropertyTIFFModel)
    out["software"] = s(tiff, kCGImagePropertyTIFFSoftware)
    out["userComment"] = s(exif, kCGImagePropertyExifUserComment)
    out["gpsDateStamp"] = s(gps, kCGImagePropertyGPSDateStamp)
    out["gpsTimeStamp"] = s(gps, kCGImagePropertyGPSTimeStamp)

    if var lat = n(gps, kCGImagePropertyGPSLatitude), var lon = n(gps, kCGImagePropertyGPSLongitude) {
      if (s(gps, kCGImagePropertyGPSLatitudeRef) ?? "N").uppercased() == "S" { lat = -abs(lat) }
      if (s(gps, kCGImagePropertyGPSLongitudeRef) ?? "E").uppercased() == "W" { lon = -abs(lon) }
      out["gpsLatitude"] = lat
      out["gpsLongitude"] = lon
    }
    if var alt = n(gps, kCGImagePropertyGPSAltitude) {
      if Int(n(gps, kCGImagePropertyGPSAltitudeRef) ?? 0) == 1 { alt = -abs(alt) }
      out["gpsAltitude"] = alt
    }
    if let o = (props[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue {
      out["orientation"] = o
    }
    if let w = (props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
      let h = (props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue
    {
      out["imageWidth"] = w
      out["imageHeight"] = h
    }

    var raw: [String: String] = [:]
    for (key, value) in props {
      if let dict = value as? [String: Any] {
        let group = key.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        for (k, v) in dict {
          var text = Self.describe(v).trimmingCharacters(in: .whitespacesAndNewlines)
          if text.isEmpty { continue }
          if text.count > 300 { text = String(text.prefix(300)) + "…" }
          raw["\(group).\(k)"] = text
        }
      } else {
        raw[key] = Self.describe(value)
      }
    }
    out["rawTags"] = raw
    return out.filter { !($0.value is NSNull) }
  }

  // MARK: Write

  private func writeMetadata(path: String, values: [String: Any]) throws {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
      let type = CGImageSourceGetType(src)
    else {
      throw NativeError(code: "READ_FAILED", message: "The image could not be opened.")
    }
    let format = Self.formatName(type as String)
    guard Self.writableFormats.contains(format) else {
      throw NativeError(
        code: "UNSUPPORTED_FORMAT",
        message:
          "EXIF writing is not supported for \(format.uppercased()) files on iOS (supported: JPEG, PNG, HEIC, TIFF)."
      )
    }
    let existingGps =
      Self.properties(of: src)[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]

    func has(_ k: String) -> Bool { values.keys.contains(k) }
    func str(_ k: String) -> String? {
      guard let v = values[k], !(v is NSNull) else { return nil }
      return v as? String
    }
    func num(_ k: String) -> Double? {
      guard let v = values[k], !(v is NSNull) else { return nil }
      return (v as? NSNumber)?.doubleValue
    }

    // --- GPS changes
    var gpsSet: [String: Any] = [:]
    var gpsRemove: Set<String> = []
    if has("gpsLatitude") || has("gpsLongitude") {
      if let lat = num("gpsLatitude"), let lon = num("gpsLongitude") {
        gpsSet[kCGImagePropertyGPSLatitude as String] = abs(lat)
        gpsSet[kCGImagePropertyGPSLatitudeRef as String] = lat >= 0 ? "N" : "S"
        gpsSet[kCGImagePropertyGPSLongitude as String] = abs(lon)
        gpsSet[kCGImagePropertyGPSLongitudeRef as String] = lon >= 0 ? "E" : "W"
      } else {
        gpsRemove.formUnion([
          kCGImagePropertyGPSLatitude as String, kCGImagePropertyGPSLatitudeRef as String,
          kCGImagePropertyGPSLongitude as String, kCGImagePropertyGPSLongitudeRef as String,
        ])
      }
    }
    if has("gpsAltitude") {
      if let alt = num("gpsAltitude") {
        gpsSet[kCGImagePropertyGPSAltitude as String] = abs(alt)
        gpsSet[kCGImagePropertyGPSAltitudeRef as String] = alt < 0 ? 1 : 0
      } else {
        gpsRemove.formUnion([
          kCGImagePropertyGPSAltitude as String, kCGImagePropertyGPSAltitudeRef as String,
        ])
      }
    }
    for (key, prop) in [
      ("gpsDateStamp", kCGImagePropertyGPSDateStamp), ("gpsTimeStamp", kCGImagePropertyGPSTimeStamp),
    ] where has(key) {
      if let v = str(key), !v.isEmpty {
        gpsSet[prop as String] = v
      } else {
        gpsRemove.insert(prop as String)
      }
    }

    // --- EXIF / TIFF text changes (removal is written as an empty string)
    let textMap: [(String, CFString, CFString)] = [
      ("dateTimeOriginal", kCGImagePropertyExifDictionary, kCGImagePropertyExifDateTimeOriginal),
      ("dateTimeDigitized", kCGImagePropertyExifDictionary, kCGImagePropertyExifDateTimeDigitized),
      ("offsetTimeOriginal", kCGImagePropertyExifDictionary, kCGImagePropertyExifOffsetTimeOriginal),
      ("offsetTimeDigitized", kCGImagePropertyExifDictionary, kCGImagePropertyExifOffsetTimeDigitized),
      ("offsetTime", kCGImagePropertyExifDictionary, kCGImagePropertyExifOffsetTime),
      ("userComment", kCGImagePropertyExifDictionary, kCGImagePropertyExifUserComment),
      ("dateTime", kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFDateTime),
      ("imageDescription", kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFImageDescription),
      ("artist", kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFArtist),
      ("copyright", kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFCopyright),
    ]

    let textMeta = CGImageMetadataCreateMutable()
    var textChanges = 0
    for (key, dict, prop) in textMap where has(key) {
      let value = (str(key) ?? "") as NSString
      _ = CGImageMetadataSetValueMatchingImageProperty(textMeta, dict, prop, value)
      textChanges += 1
    }

    func gpsMetadata(_ entries: [String: Any], into meta: CGMutableImageMetadata) {
      for (k, v) in entries {
        _ = CGImageMetadataSetValueMatchingImageProperty(
          meta, kCGImagePropertyGPSDictionary, k as CFString, v as AnyObject)
      }
    }

    let dir = url.deletingLastPathComponent()
    let tmp1 = dir.appendingPathComponent(".\(UUID().uuidString).tmp")
    let tmp2 = dir.appendingPathComponent(".\(UUID().uuidString).tmp")
    defer {
      try? FileManager.default.removeItem(at: tmp1)
      try? FileManager.default.removeItem(at: tmp2)
    }

    if gpsRemove.isEmpty {
      // Single lossless pass merging all changes.
      if textChanges == 0 && gpsSet.isEmpty { return }
      gpsMetadata(gpsSet, into: textMeta)
      try copySource(from: url, to: tmp1, metadata: textMeta, excludeGPS: false)
      try Self.replaceItem(at: url, with: tmp1)
    } else {
      // Pass 1: drop all GPS (and apply text changes).
      try copySource(
        from: url, to: tmp1, metadata: textChanges > 0 ? textMeta : nil, excludeGPS: true)
      // Pass 2: merge back the GPS values that should remain.
      var remaining = existingGps
      for k in gpsRemove { remaining.removeValue(forKey: k) }
      for (k, v) in gpsSet { remaining[k] = v }
      // Drop tags that are meaningless without coordinates/altitude.
      if remaining[kCGImagePropertyGPSLatitude as String] == nil {
        remaining.removeValue(forKey: kCGImagePropertyGPSLatitudeRef as String)
        remaining.removeValue(forKey: kCGImagePropertyGPSLongitudeRef as String)
      }
      if remaining[kCGImagePropertyGPSAltitude as String] == nil {
        remaining.removeValue(forKey: kCGImagePropertyGPSAltitudeRef as String)
      }
      let hasData = remaining.keys.contains { $0 != (kCGImagePropertyGPSVersion as String) }
      if hasData {
        let gpsMeta = CGImageMetadataCreateMutable()
        gpsMetadata(remaining, into: gpsMeta)
        try copySource(from: tmp1, to: tmp2, metadata: gpsMeta, excludeGPS: false)
        try Self.replaceItem(at: url, with: tmp2)
      } else {
        try Self.replaceItem(at: url, with: tmp1)
      }
    }
  }

  // MARK: Encode

  private func encodeJpeg(_ args: [String: Any]) throws -> [String: Any] {
    guard let data = (args["rgba"] as? FlutterStandardTypedData)?.data,
      let width = (args["width"] as? NSNumber)?.intValue,
      let height = (args["height"] as? NSNumber)?.intValue,
      let outputPath = args["outputPath"] as? String
    else {
      throw NativeError(code: "BAD_ARGS", message: "Missing encodeJpeg arguments.")
    }
    let quality = (args["quality"] as? NSNumber)?.intValue ?? 92
    let sourcePath = args["metadataSourcePath"] as? String
    let resetOrientation = (args["resetOrientation"] as? NSNumber)?.boolValue ?? true

    guard width > 0, height > 0, data.count >= width * height * 4 else {
      throw NativeError(code: "BAD_ARGS", message: "Pixel buffer does not match \(width)x\(height).")
    }
    guard let provider = CGDataProvider(data: data as CFData),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else {
      throw NativeError(code: "ENCODE_FAILED", message: "Could not create the image for encoding.")
    }

    var props: [String: Any] = [:]
    var sourceOrientation = 1
    if let sp = sourcePath,
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: sp) as CFURL, nil)
    {
      let p = Self.properties(of: src)
      for key in [
        kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary,
        kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
        kCGImagePropertyExifAuxDictionary,
      ] {
        if let d = p[key as String] { props[key as String] = d }
      }
      sourceOrientation = (p[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
    }
    let orientation = resetOrientation ? 1 : sourceOrientation

    var exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
    exif[kCGImagePropertyExifPixelXDimension as String] = width
    exif[kCGImagePropertyExifPixelYDimension as String] = height
    props[kCGImagePropertyExifDictionary as String] = exif

    var tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
    tiff[kCGImagePropertyTIFFOrientation as String] = orientation
    props[kCGImagePropertyTIFFDictionary as String] = tiff
    props[kCGImagePropertyOrientation as String] = orientation
    props[kCGImageDestinationLossyCompressionQuality as String] =
      Double(min(max(quality, 1), 100)) / 100.0

    let outURL = URL(fileURLWithPath: outputPath)
    try? FileManager.default.createDirectory(
      at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let tmpURL = URL(fileURLWithPath: outputPath + ".tmp")
    guard
      let dest = CGImageDestinationCreateWithURL(
        tmpURL as CFURL, "public.jpeg" as CFString, 1, nil)
    else {
      throw NativeError(code: "ENCODE_FAILED", message: "Could not create the JPEG file.")
    }
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      try? FileManager.default.removeItem(at: tmpURL)
      throw NativeError(code: "ENCODE_FAILED", message: "JPEG encoding failed (is the device out of storage?).")
    }
    try Self.replaceItem(at: outURL, with: tmpURL)
    var size: Int64 = 0
    if let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath),
      let n = attrs[.size] as? NSNumber
    {
      size = n.int64Value
    }
    return ["fileSize": size]
  }

  // MARK: Strip GPS

  private func stripGpsCopy(source: String, output: String) throws {
    let outURL = URL(fileURLWithPath: output)
    try? FileManager.default.createDirectory(
      at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let tmp = URL(fileURLWithPath: output + ".tmp")
    defer { try? FileManager.default.removeItem(at: tmp) }
    try copySource(from: URL(fileURLWithPath: source), to: tmp, metadata: nil, excludeGPS: true)
    try Self.replaceItem(at: outURL, with: tmp)
  }
}
