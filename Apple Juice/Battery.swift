//
// Battery.swift
// Apple Juice
// https://github.com/raphaelhanneken/apple-juice
//

import Foundation
import IOKit.ps
import IOKit.pwr_mgt

///  Notification name for the power source changed callback.
let powerSourceChangedNotification = "com.raphaelhanneken.apple-juice.powersourcechanged"

///  Posts a notification every time the power source changes.
private let powerSourceCallback: IOPowerSourceCallbackType = { _ in
    NotificationCenter.default.post(name: Notification.Name(rawValue: powerSourceChangedNotification),
                                    object: nil)
}

///  Accesses the battery's IO service.
final class Battery {

    ///  The battery's IO service name.
    private let batteryIOServiceName = "AppleSmartBattery"

    ///  An IOService object that matches battery's IO service dictionary.
    private var service: io_object_t = 0

    /// Holds the battery instance.
    private static var battery: Battery?


    ///  The current status of the battery, e.g. charging.
    var state: BatteryState? {
        guard
            let charging   = isCharging,
            let plugged    = isPlugged,
            let charged    = isCharged,
            let percentage = percentage else {
                return nil
        }
        if charged && plugged {
            return .pluggedAndCharged
        }
        if charging {
            return .charging(percentage: percentage)
        } else {
            return .discharging(percentage: percentage)
        }
    }

    ///  The remaining time until the battery is empty or fully charged
    ///  in a human readable format, e.g. hh:mm.
    var timeRemainingFormatted: String {
        // Unwrap required information.
        guard let charged = isCharged, let plugged = isPlugged else {
            return NSLocalizedString("Unknown", comment: "Translate Unknown")
        }
        // Check if the battery is charged and plugged into an unlimited power supply.
        if charged && plugged {
            return NSLocalizedString("Charged", comment: "Translate Charged")
        }
        // The battery is (dis)charging, display the remaining time.
        if let time = timeRemaining {
            return String(format: "%d:%02d", arguments: [time / 60, time % 60])
        } else {
            return NSLocalizedString("Calculating", comment: "Translate Calculating")
        }
    }

    ///  The remaining time in _minutes_ until the battery is empty or fully charged.
    var timeRemaining: Int? {
        // Get the estimated time remaining.
        let time = IOPSGetTimeRemainingEstimate()

        switch time {
            // kIOPSTimeRemainingUnknown
        case -1.0:
            // The remaining time is currently unknown.
            return nil
            // kIOPSTimeRemainingUnlimited
        case -2.0:
            // The battery is connected to a power outlet, get the remaining time
            // until the battery is fully charged directly from the IOService.
            if let prop = getRegistryPropertyForKey(.timeRemaining) as? Int, prop < 600 {
                return prop
            }
            return nil
        default:
            // Return the estimated time divided by 60 (seconds to minutes).
            return Int(time / 60)
        }
    }

    ///  The current percentage, based on the current charge and the maximum capacity.
    var percentage: Int? {
        // Unwrap the required information.
        guard let capacity = capacity, let charge = charge else {
            return nil
        }
        // Calculate the current percentage.
        return Int(round(Double(charge) / Double(capacity) * 100.0))
    }

    ///  The current charge in mAh.
    var charge: Int? {
        return getRegistryPropertyForKey(.currentCharge) as? Int
    }

    ///  The maximum capacity in mAh.
    var capacity: Int? {
        return getRegistryPropertyForKey(.maxCapacity) as? Int
    }

    ///  The source from which the Mac currently draws its power.
    var powerSource: String {
        guard let plugged = isPlugged else {
            return NSLocalizedString("Unknown", comment: "Translate Unknown")
        }
        // Check whether the MacBook currently is plugged into a power adapter.
        if plugged {
            return NSLocalizedString("Power Adapter", comment: "Translate Power Adapter")
        } else {
            return NSLocalizedString("Battery", comment: "Translate Battery")
        }
    }

    ///  Checks whether the battery is charging and connected to a power outlet.
    var isCharging: Bool? {
        return getRegistryPropertyForKey(.isCharging) as? Bool
    }

    ///  Checks whether the battery is fully charged.
    var isCharged: Bool? {
        return getRegistryPropertyForKey(.fullyCharged) as? Bool
    }

    ///  Checks whether the battery is plugged into an unlimited power supply.
    var isPlugged: Bool? {
        return getRegistryPropertyForKey(.isPlugged) as? Bool
    }

    ///  Calculates the current power usage in Watts.
    var powerUsage: Double? {
        guard
            let voltage  = getRegistryPropertyForKey(.voltage) as? Double,
            let amperage = getRegistryPropertyForKey(.amperage) as? Double else {
            return nil
        }
        return round(((voltage * amperage) / 1_000_000) * 10) / 10
    }

    /// The number of charging cycles.
    var cycleCount: Int? {
        return getRegistryPropertyForKey(.cycleCount) as? Int
    }

    /// The battery's current temperature.
    var temperature: Double? {
        guard let temp = getRegistryPropertyForKey(.temperature) as? Double else {
            return nil
        }
        return (temp / 100)
    }

    // MARK: - Methods

    /// Create an new battery instance.
    ///
    /// - Returns: An instantiated battery object.
    class func instance() throws -> Battery? {
        if battery == nil {
            battery = try Battery()
        }
        return battery
    }

    ///  Initializes a new Battery object.
    private init() throws {
        // Try opening a connection to the battery's IOService.
        try openServiceConnection()
        // Create a RunLoopSource to post a notification, whenever the power source chages.
        let loop = IOPSNotificationCreateRunLoopSource(powerSourceCallback, nil).takeRetainedValue()
        // Add the notification loop to the current run loop.
        CFRunLoopAddSource(CFRunLoopGetCurrent(), loop, CFRunLoopMode.defaultMode)
    }

    // MARK: - Private

    ///  Opens a connection to the battery's IOService object.
    ///
    ///  - throws: A BatteryError if something went wrong.
    private func openServiceConnection() throws {
        // Check if the IOService connection is still open.
        if service != 0 {
            if !closeServiceConnection() {
                // Throw a connectionAlreadyOpen Exception if the
                // IOService connection won't close.
                throw BatteryError.connectionAlreadyOpen("Closing the IOService connection failed.")
            }
        }
        // Get an IOService object for the defined battery service name.
        service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceNameMatching(batteryIOServiceName))
        if service == 0 {
            // Throw a serviceNotFound exception if the supplied IOService couldn't be opened.
            throw BatteryError.serviceNotFound("Opening the provided IOService (\(batteryIOServiceName)) failed.")
        }
    }

    ///  Closes the connection the the battery's IOService object.
    ///
    ///  - returns: True, whether the IOService connection was successfully closed.
    private func closeServiceConnection() -> Bool {
        // Release the IOService object and reset the service property.
        if kIOReturnSuccess == IOObjectRelease(service) {
            service = 0
        }
        return (service == 0)
    }

    ///  Get the registry entry's property for the supplied SmartBatteryKey.
    ///
    ///  - parameter key: A SmartBatteryKey to get the corresponding registry entry's property.
    ///  - returns:       The registry entry for the provided SmartBatteryKey.
    private func getRegistryPropertyForKey(_ key: SmartBatteryKeys) -> AnyObject? {
        return IORegistryEntryCreateCFProperty(service, key.rawValue as CFString!, nil, 0).takeRetainedValue()
    }
}
