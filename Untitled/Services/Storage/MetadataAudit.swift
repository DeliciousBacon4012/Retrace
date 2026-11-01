import Foundation
import ImageIO

/// Reads finished image data back and lists anything in it beyond the pixels, their size and
/// resolution, and a color profile. Used to refuse writing a file that should be clean.
///
/// It checks what ImageIO itself reports, so it sees exactly what other apps will see.
nonisolated enum MetadataAudit {
    /// Human-readable names of what's left, such as "GPS" or "EXIF DateTimeOriginal".
    /// Empty when the data holds nothing but the image.
    static func leftovers(in data: Data) -> [String] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        var found: [String] = []
        if CGImageSourceGetCount(source) > 1 {
            found.append("extra images")
        }
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            found += leftovers(inProperties: properties)
        }
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            found += leftovers(inXMP: metadata)
        }
        return found
    }

    /// Whole groups that never belong in a clean file.
    private static let forbiddenGroups: [(String, String)] = [
        (kCGImagePropertyGPSDictionary as String, "GPS"),
        (kCGImagePropertyIPTCDictionary as String, "IPTC"),
        (kCGImagePropertyExifAuxDictionary as String, "EXIF lens and serial details"),
        (kCGImagePropertyMakerAppleDictionary as String, "Apple maker note"),
        (kCGImagePropertyMakerCanonDictionary as String, "maker note"),
        (kCGImagePropertyMakerNikonDictionary as String, "maker note"),
        (kCGImagePropertyMakerFujiDictionary as String, "maker note"),
        (kCGImagePropertyMakerOlympusDictionary as String, "maker note"),
        (kCGImagePropertyMakerPentaxDictionary as String, "maker note"),
        (kCGImagePropertyMakerMinoltaDictionary as String, "maker note"),
        (kCGImageProperty8BIMDictionary as String, "Photoshop data"),
        (kCGImagePropertyDNGDictionary as String, "camera raw data"),
        (kCGImagePropertyThumbnailImages as String, "embedded thumbnail"),
    ]

    /// Technical fields ImageIO fills in from the pixels themselves. Anything else is left over.
    private static let allowedEXIF: Set<String> = [
        kCGImagePropertyExifPixelXDimension as String,
        kCGImagePropertyExifPixelYDimension as String,
        kCGImagePropertyExifColorSpace as String,
        kCGImagePropertyExifVersion as String,
        kCGImagePropertyExifFlashPixVersion as String,
        kCGImagePropertyExifComponentsConfiguration as String,
    ]

    private static let allowedTIFF: Set<String> = [
        kCGImagePropertyTIFFXResolution as String,
        kCGImagePropertyTIFFYResolution as String,
        kCGImagePropertyTIFFResolutionUnit as String,
        kCGImagePropertyTIFFOrientation as String,
        kCGImagePropertyTIFFCompression as String,
        kCGImagePropertyTIFFPhotometricInterpretation as String,
        kCGImagePropertyTIFFTileWidth as String,
        kCGImagePropertyTIFFTileLength as String,
    ]

    /// PNG text chunks.
    private static let forbiddenPNG: [String] = [
        kCGImagePropertyPNGAuthor as String,
        kCGImagePropertyPNGComment as String,
        kCGImagePropertyPNGCopyright as String,
        kCGImagePropertyPNGCreationTime as String,
        kCGImagePropertyPNGDescription as String,
        kCGImagePropertyPNGDisclaimer as String,
        kCGImagePropertyPNGModificationTime as String,
        kCGImagePropertyPNGSoftware as String,
        kCGImagePropertyPNGSource as String,
        kCGImagePropertyPNGTitle as String,
        kCGImagePropertyPNGWarning as String,
    ]

    private static func leftovers(inProperties properties: [String: Any]) -> [String] {
        var found: [String] = []
        for (key, name) in forbiddenGroups where properties[key] != nil {
            found.append(name)
        }
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            found += exif.keys.filter { !allowedEXIF.contains($0) }.map { "EXIF \($0)" }.sorted()
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            found += tiff.keys.filter { !allowedTIFF.contains($0) }.map { "TIFF \($0)" }.sorted()
        }
        if let png = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any] {
            found += forbiddenPNG.filter { png[$0] != nil }.map { "PNG \($0)" }
        }
        return found
    }

    /// XMP namespaces that only ever hold descriptive or personal details. EXIF and TIFF
    /// values also show up as XMP, but those are checked above.
    private static let forbiddenXMPPrefixes: Set<String> = [
        "dc", "xmp", "xmpMM", "xmpRights", "xmpDM", "photoshop", "Iptc4xmpCore", "Iptc4xmpExt",
        "aux", "exifEX", "crs", "lr", "plus",
    ]

    private static func leftovers(inXMP metadata: CGImageMetadata) -> [String] {
        var found: [String] = []
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { _, tag in
            if let prefix = CGImageMetadataTagCopyPrefix(tag) as String?, forbiddenXMPPrefixes.contains(prefix) {
                let name = CGImageMetadataTagCopyName(tag) as String? ?? "?"
                found.append("XMP \(prefix):\(name)")
            }
            return true
        }
        return found
    }
}
