import AVFoundation
import DJIExtractCore

/// Top-level QuickTime metadata written into exported movies.
enum QuickTimeMetadata {
    static func items(timestamp: CaptureTimestamp, contentIdentifier: String? = nil) -> [AVMetadataItem] {
        var items = [
            item(.quickTimeMetadataCreationDate, timestamp.quickTimeCreationDate),
            item(.quickTimeMetadataMake, CameraIdentity.make),
            item(.quickTimeMetadataModel, CameraIdentity.model),
        ]
        if let contentIdentifier {
            items.append(item(AVMetadataIdentifier("mdta/com.apple.quicktime.content.identifier"), contentIdentifier))
        }
        return items
    }

    private static func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
    }
}
