//
// StatusIcon.swift
// Apple Juice
// https://github.com/raphaelhanneken/apple-juice
//

import Cocoa

///  Define the BatteryUIKit path
fileprivate let batteryIconPath = "/System/Library/PrivateFrameworks/BatteryUIKit.framework/Versions/A/Resources/"

///  Defines the filenames for Apple's battery images.
///
///  - left:     Left-hand side capacity bar cap.
///  - right:    Right-hand side capacity bar cap.
///  - middle:   Capacity bar filler filename.
///  - empty:    Empty battery filename.
///  - charged:  Charged and plugged battery filename.
///  - charging: Charging battery filename.
///  - dead:     IOService already open filename.
///  - none:     Battery IOService not found filename.
fileprivate enum BatteryImage: String {
    case left     = "BatteryLevelCapB-L.pdf"
    case right    = "BatteryLevelCapB-R.pdf"
    case middle   = "BatteryLevelCapB-M.pdf"
    case empty    = "BatteryEmpty.pdf"
    case charged  = "BatteryChargedAndPlugged.pdf"
    case charging = "BatteryCharging.pdf"
    case dead     = "BatteryDeadCropped.pdf"
    case none     = "BatteryNone.pdf"
}

///  Draws the status bar image.
struct StatusIcon {

    ///  Add a little offset to draw the capacity bar in the correct position.
    private let capacityOffsetX: CGFloat = 2.0

    ///  Caches the last drawn battery image.
    private var cache: BatteryImageCache?

    // MARK: - Methods

    ///  Draws a battery image for the supplied BatteryStatusType.
    ///
    ///  - parameter status: The BatteryStatusType, which to draw the image for.
    ///  - returns:          The battery image for the provided battery status.
    mutating func drawBatteryImage(forStatus status: BatteryState) -> NSImage? {
        // Check if the required image is cached.
        if let cache = self.cache, cache.batteryStatus == status {
            return cache.image
        }

        // Cache a new battery image.
        switch status {
        case .charging:
            cache = BatteryImageCache(forStatus: status,
                                      withImage: batteryImage(named: .charging))
        case .pluggedAndCharged:
            cache = BatteryImageCache(forStatus: status,
                                      withImage: batteryImage(named: .charged))
        case let .discharging(percentage):
            cache = BatteryImageCache(forStatus: status,
                                      withImage: dischargingBatteryImage(forPercentage: percentage))
        }
        // Return the new image.
        return cache?.image
    }

    ///  Draws a battery image according to the provided BatteryError.
    ///
    ///  - parameter err: The BatteryError, which to draw the battery image for.
    ///  - returns:       The battery image for the supplied BatteryError.
    func drawBatteryImage(forError err: BatteryError?) -> NSImage? {
        guard let error = err else {
            return nil
        }
        // Get the corresponding image for the supplied error.
        switch error {
        case .connectionAlreadyOpen:
            return batteryImage(named: .dead)
        case .serviceNotFound:
            return batteryImage(named: .none)
        }
    }

    // MARK: - Private

    ///  Draws a battery icon based on the battery's current percentage.
    ///
    ///  - parameter percentage: The current percentage of the battery.
    ///  - returns:              A battery image for the supplied percentage.
    private func dischargingBatteryImage(forPercentage percentage: Int) -> NSImage? {
        // Get the required images to draw the battery icon.
        guard let batteryEmpty   = batteryImage(named: .empty),
            let capacityCapLeft  = batteryImage(named: .left),
            let capacityCapRight = batteryImage(named: .right),
            let capacityFill     = batteryImage(named: .middle) else {
                return nil
        }
        // Get the capacity bar's height.
        let capacityHeight = capacityFill.size.height
        // Calculate the offset to achieve that little gap between the capacity bar and the outline.
        let capacityOffsetY = batteryEmpty.size.height - (capacityHeight + capacityOffsetX)
        // Calculate the capacity bar's width.
        let capacityWidth = CGFloat(round(Double(percentage) / drawingPrecision)) * capacityFill.size.width
        // Define the drawing rect in which to draw the capacity bar in.
        let drawingRect = NSRect(x: capacityOffsetX, y: capacityOffsetY,
                                 width: capacityWidth, height: capacityHeight)
        // Draw a special battery icon for low percentages, otherwise
        // drawThreePartImage glitches.
        if drawingRect.width < (2 * capacityFill.size.width) {
            if let img = NSImage(named: NSImage.Name(rawValue: "LowBattery")) {
                img.isTemplate = true
                return img
            }
        }

        // Draw the actual menu bar image.
        drawThreePartImage(withFrame: drawingRect, canvas: batteryEmpty, startCap: capacityCapLeft,
                           fill: capacityFill, endCap: capacityCapRight)

        return batteryEmpty
    }

    ///  Opens an image file for the supplied image name.
    ///
    ///  - parameter name: The name of the requested image.
    ///  - returns:        The requested image.
    private func batteryImage(named name: BatteryImage) -> NSImage? {
        // Get the battery image for the supplied BatteryImage name.
        guard let img = NSImage(contentsOfFile: batteryIconPath + name.rawValue) else {
            return nil
        }
        // Define the image as template.
        img.isTemplate = true

        return img
    }

    ///  Draws a three-part image onto a specified canvas image.
    ///
    ///  - parameter rect:  The rectangle in which to draw the images.
    ///  - parameter img:   The image on which to draw the three-part image.
    ///  - parameter start: The image located on the left end of the frame.
    ///  - parameter fill:  The image used to fill the gap between the start and the end images.
    ///  - parameter end:   The image located on the right end of the frame.
    private func drawThreePartImage(withFrame rect: NSRect, canvas img: NSImage,
                                    startCap start: NSImage, fill: NSImage, endCap end: NSImage) {
        img.lockFocus()
        NSDrawThreePartImage(rect, start, fill, end, false, .copy, 1, false)
        img.unlockFocus()
    }
}
