//
//  BLEService.swift
//  COVID-19
//
//  Created by Aleksandar Sergeev Petrov on 31.03.20.
//  Copyright © 2020 Upnetix AD. All rights reserved.
//

import Foundation
import CoreBluetooth
import CoreLocation

private enum BLEServiceConstants {

    // MARK: Beacon

    static let beaconServiceUUID: String = "81066062-41b5-409d-82e7-467cdb4ef80d" // General service uuid //"d3cd8565-e741-4941-950a-81042aee3ef0"
    static let beaconLocalName: String = "UpnetixBeacon"
    static let beaconLocalCharacteristicUUID: String = "b5265acc-4fae-4854-a5aa-e22561fcd423"

    // MARK: Timers

    static let updateTimerInterval: TimeInterval = 1
    static let processPeripheralTimerInterval: TimeInterval = 2
    static let restartScanTimerInterval: TimeInterval = 3
}

//

enum BLEDeviceRange {
    case unknown
    case far
    case near
    case immediate

    init(wirh proximity: Float) {
        if (proximity < -200) {
            self = .unknown
        } else if (proximity < -90) {
            self = .far
        } else if (proximity < -72) {
            self = .near
        } else if (proximity < 0) {
            self = .immediate
        } else {
            self = .unknown
        }
    }
}

extension BLEDeviceRange: CustomStringConvertible {
    var description: String {
        switch self {
            case .far:
                return "up to 100 meters"
            case .near:
                return "up to 15 meters"
            case .immediate:
                return "up to 5 meters"
            default:
                return "too far"
        }
    }
}

//

struct BLEDevice {
    let identifier: String
    let proximity: BLEDeviceRange
}

/*
 Note:
 Your app will crash if its Info.plist doesn’t include usage description keys for the types of data it needs to access.
 To access Core Bluetooth APIs on apps linked on or after iOS 13, include the NSBluetoothAlwaysUsageDescription key.
 In iOS 12 and earlier, include NSBluetoothPeripheralUsageDescription to access Bluetooth peripheral data.
 */

protocol BLEServiceDelegate: class {
    func service(_ service: BLEService, foundDevices devices: [BLEDevice])
    func service(_ service: BLEService, unauthorized isCentral: Bool)
}

//

final class BLEService: NSObject {

    // Device identifier
    let identifier: String

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!

    // Get notified when exit region - hope this will wake app when killed
    lazy var locationManager: CLLocationManager = {
        DispatchQueue.main.sync {
            let locationManager = CLLocationManager()
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.pausesLocationUpdatesAutomatically = false
            locationManager.distanceFilter = 10
            return locationManager
        }
    }()

    // Good practice, but I'm not able to fire timers
    private let backgroundConcurrentQueue = DispatchQueue(label: "com.scalefocus.bt", attributes: .concurrent)

    private weak var delegate: BLEServiceDelegate?

    // MARK: Store

    var peripheralDetected: [String: [NSNumber]] = [:]
    var peripheralsToBeValidated: [CBPeripheral] = []
    var peripheralUUIDSMatching: [String: String] = [:]
    var uuidsDetected: [String: [NSNumber]] = [:]

    // MARK: Object lifecycle

    init(with identifier: String, delegate: BLEServiceDelegate) {
        // set
        self.identifier = identifier
        self.delegate = delegate

        // call NSObject constructor
        super.init()

        // !!! If we use lazy var for centralManager -
        // centralManagerDidUpdateState will not be called when created
        centralManager = CBCentralManager(delegate: self,
                                          queue: backgroundConcurrentQueue,
                                          options: [CBCentralManagerOptionRestoreIdentifierKey : "com.scalefocus.bt.central"])
        // !!! Similar
        peripheralManager = CBPeripheralManager(delegate: self,
                                                queue: backgroundConcurrentQueue,
                                                options: [CBPeripheralManagerOptionRestoreIdentifierKey : "com.scalefocus.bt.peripheral"])

        // TODO: Add wait for Authorization timer
    }

    deinit {
        stopAdvertising()
        // This will stop report timer aswell
        stopScanForDevices()
    }

    // MARK: Advertising (Beacon)

    private func beaconServiceUUID() -> CBUUID {
        return CBUUID(string: BLEServiceConstants.beaconServiceUUID)
    }

    private func beaconCharacteristicUUID() -> CBUUID {
        return CBUUID(string: BLEServiceConstants.beaconLocalCharacteristicUUID)
    }

    // local characteristic
    private func beaconServiceCharacteristic() -> CBMutableCharacteristic {
        let dataUUID = identifier.data(using: .utf8)
        return CBMutableCharacteristic(type: beaconCharacteristicUUID(),
                                       properties: .read,
                                       value: dataUUID,
                                       permissions: .readable)
    }

    func startAdvertising() {
        let advertisingData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: BLEServiceConstants.beaconLocalName,
            CBAdvertisementDataServiceUUIDsKey: [beaconServiceUUID()]
        ]
        let service = CBMutableService(type: beaconServiceUUID(), primary: true)
        service.characteristics = [beaconServiceCharacteristic()]
        peripheralManager.removeAllServices()
        peripheralManager.add(service)
        peripheralManager.startAdvertising(advertisingData)
    }

    func stopAdvertising() {
        guard peripheralManager.isAdvertising else {
            return
        }
        peripheralManager.stopAdvertising()
    }

    private func isAdvertising() -> Bool {
        return peripheralManager.isAdvertising
    }

    // Unused, but could be helpfil
    private func canAdvertise() -> Bool {
        if #available(iOS 13.1, *) {
            return CBPeripheralManager.authorization == .allowedAlways
        } else if #available(iOS 13.0, *) {
            return peripheralManager.authorization == .allowedAlways
        } else if #available(iOS 7.0, *) {
            return CBPeripheralManager.authorizationStatus() == .authorized
        } else {
            return true
        }
    }

    // MARK: Monitoring

    private func startScanForDevices() {
        startReportTimer()
        startProcessPeripheralsTimer()

        let services: [CBUUID] = [CBUUID(string: BLEServiceConstants.beaconServiceUUID)]
        let options: [String: Any] = [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        self.centralManager.scanForPeripherals(withServices: services, options: options)
    }

    private func stopScanForDevices() {
        stopReportTimer()

        guard isScanning() else {
            return
        }

        centralManager.stopScan()
    }

    private func isScanning() -> Bool {
        return centralManager.isScanning
    }

    // Unused, but could be helpfil
    private func canScan() -> Bool {
        if #available(iOS 13.1, *) {
            return CBCentralManager.authorization == .allowedAlways
        } else if #available(iOS 13.0, *) {
            return centralManager.authorization == .allowedAlways
        }
        return true
    }

    // MARK: Timers

    private var reportTimer: DispatchSourceTimer?
    private var processPeripheralsTimer: DispatchSourceTimer?
    private var rescanTimer: DispatchSourceTimer?

    private func startProcessPeripheralsTimer() {
        processPeripheralsTimer = DispatchSource.singleTimer(interval: .seconds(Int(BLEServiceConstants.processPeripheralTimerInterval)),
                                                             leeway: .microseconds(300),
                                                             queue: backgroundConcurrentQueue,
                                                             handler: processPeripherals)
    }

    private func startReportTimer() {
        reportTimer = DispatchSource.repeatingTimer(interval: .seconds(Int(BLEServiceConstants.updateTimerInterval)),
                                                    leeway: .microseconds(300),
                                                    queue: backgroundConcurrentQueue,
                                                    handler: reportRangesToDelegate)
    }

    private func startRescanTimer() {
        rescanTimer = DispatchSource.singleTimer(interval: .seconds(Int(BLEServiceConstants.restartScanTimerInterval)),
                                                 leeway: .microseconds(300),
                                                 queue: backgroundConcurrentQueue,
                                                 handler: restartScanForDevices)
    }

    private func stopReportTimer() {
        reportTimer?.cancel()
        reportTimer = nil
    }

    @objc
    private func reportRangesToDelegate() {
        for (peripheralKey, peripheralUUID) in peripheralUUIDSMatching {
            let ranges = peripheralDetected[peripheralKey]
            uuidsDetected[peripheralUUID] = ranges
        }

        let devices = calculateRanges()
        DispatchQueue.main.async {
            self.delegate?.service(self, foundDevices: devices)
        }

        synchronized (self) {
            for peripheralKey in peripheralDetected.keys {
                var lastValues = peripheralDetected[peripheralKey]
                lastValues?.append(NSNumber(floatLiteral: -205))
                peripheralDetected[peripheralKey] = lastValues
            }
        }
    }

    @objc
    private func processPeripherals() {
        guard peripheralsToBeValidated.count > 0 else {
            startProcessPeripheralsTimer()
            return
        }

        // !!! This will stop report timer aswell
        stopScanForDevices()

        clearValues()

        synchronized(self) {
            for peripheral in peripheralsToBeValidated {
                centralManager.connect(peripheral, options: nil)
            }
        }

        startRescanTimer()
    }

    @objc
    private func restartScanForDevices() {
        cancelPeripheralToBeValidatedConnections()
        startScanForDevices()
    }

    // MARK: Ranges

    // !!! In meters
    private func calculateRanges() -> [BLEDevice] {
        var result: [BLEDevice] = []
        synchronized(self) {
            for (deviceUUID, lastValues) in uuidsDetected {
                let proximity = calculateDeviceRange(from: lastValues)
                result.append(BLEDevice(identifier: deviceUUID, proximity: proximity))
            }
        }
        return result
    }

    private func calculateDeviceRange(from lastValues: [NSNumber]) -> BLEDeviceRange {
        var proximity: Float = 0
        var counter: Float = 0
        for value in lastValues {
            if value.floatValue > -25 {
                var tempValue: Float = 0
                if counter > 0 {
                    tempValue = proximity / counter
                }

                if tempValue > -25 {
                    tempValue = -55 // ??? Magic constant
                }

                proximity += tempValue
            } else {
                proximity += value.floatValue
            }
            counter += 1
        }

        proximity = proximity / 10 // ??? Another Magic constant
        return BLEDeviceRange(wirh: proximity)
    }

    // MARK: Mutex

    private func synchronized(_ lock: Any, closure: () -> ()) {
        backgroundConcurrentQueue.sync {
            closure()
        }
    }

    // MARK: Clean

    private func cancelPeripheralToBeValidatedConnections() {
        synchronized (self) {
            for peripheral in peripheralsToBeValidated
                where (peripheral.state == .connecting || peripheral.state == .connected) {
                    centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }

    // unused but could be helpful
    private func clearValues() {
        synchronized (self) {
            peripheralDetected.removeAll()
            peripheralUUIDSMatching.removeAll()
            uuidsDetected.removeAll()
        }
    }

    // MARK: Region monitoring

    private func startMonitoring() {
        switch CLLocationManager.authorizationStatus() {
            case .authorizedAlways, .authorizedWhenInUse:
                if let regionCenter = locationManager.location?.coordinate {
                    startMonitoring(with: regionCenter)
            }
            default:
                locationManager.requestAlwaysAuthorization()
        }
    }

    private var currentRegion: CLCircularRegion?

    private func startMonitoring(with center: CLLocationCoordinate2D) {
        let region = CLCircularRegion(center: center,
                                      radius: CLLocationDistance(10), // TODO: Make it constant
            identifier: "com.upnetix.bt.region-monitoring")
        if let currentRegion = self.currentRegion {
            locationManager.stopMonitoring(for: currentRegion)
        }
        currentRegion = region
        locationManager.startMonitoring(for: region)
    }
}

// MARK: CBCentralManagerDelegate

extension BLEService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
            case .unknown:
                print("central.state is .unknown")
            // Temp state - Just wait for new state
            case .resetting:
                print("central.state is .resetting")
            // Temp state - Just wait for new state
            case .unsupported:
                print("central.state is .unsupported")
            // BLE is not supported - Do Nothing
            case .unauthorized:
                print("central.state is .unauthorized")
                // TODO: Ask user to change settings
                delegate?.service(self, unauthorized: true)
            case .poweredOff:
                print("central.state is .poweredOff")
                stopScanForDevices()
            case .poweredOn:
                print("central.state is .poweredOn")
                startScanForDevices()
            @unknown default:
                print("central.state is unknown")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        print("did discover peripheral: \(peripheral.identifier.uuidString.uppercased()), data:\(advertisementData), \(RSSI.floatValue)")

        synchronized(self) {
            guard var lastValues = peripheralDetected[peripheral.identifier.uuidString.uppercased()] else {
                peripheralsToBeValidated.append(peripheral)
                peripheralDetected[peripheral.identifier.uuidString.uppercased()] = []
                return
            }

            for (index, valueRange) in lastValues.enumerated() {
                if valueRange.floatValue <= -205 {  // I'm alive -> remove aging values
                    lastValues.remove(at: index)
                }
            }

            lastValues.append(RSSI)

            while lastValues.count > 10 {   // rolling average
                lastValues.remove(at: 0)
            }

            peripheralDetected[peripheral.identifier.uuidString.uppercased()] = lastValues
        } // end synchronized
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("connect peripheral: \(peripheral.identifier.uuidString.uppercased())")
        peripheral.delegate = self
        peripheral.discoverServices([beaconServiceUUID()])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("fail connect peripheral: \(peripheral.identifier.uuidString.uppercased())")
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        print("central will restore state")
        guard let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else {
            return
        }
        synchronized(self) {
            peripheralsToBeValidated = restoredPeripherals
        }

    }
}

// MARK: CBPeripheralManagerDelegate

extension BLEService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
            case .unknown:
                print("peripheral.state is .unknown")
            // Temp state - Just wait for new state
            case .resetting:
                print("peripheral.state is .resetting")
            // Temp state - Just wait for new stat
            case .unsupported:
                print("peripheral.state is .unsupported")
            // BLE is not supported - Do Nothing
            case .unauthorized:
                print("peripheral.state is .unauthorized")
                delegate?.service(self, unauthorized: false)
            case .poweredOff:
                print("peripheral.state is .poweredOff")
                stopAdvertising()
            case .poweredOn:
                print("peripheral.state is .poweredOn")
                startAdvertising()
            @unknown default:
                print("peripheral.state is unknown")
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("error starting advertising: \(error.localizedDescription)")
            return
        }
        print("did start advertising")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == beaconServiceCharacteristic().uuid else {
            // we don't need to answer for this request
            return
        }

        guard let value = beaconServiceCharacteristic().value as NSData? else {
            // !!! This should not be case
            return
        }

        guard request.offset > value.length else {
            peripheralManager.respond(to: request, withResult: .invalidOffset)
            return
        }

        let range = NSRange(location: request.offset, length: value.length - request.offset)
        request.value = value.subdata(with: range)
        peripheralManager.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        print("peripheral will restore state")
    }

}

// CBPeripheralDelegate

extension BLEService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        defer {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        if let error = error {
            print("error update value for characteristic: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value else {
            print("error update value for characteristic: no data")
            return
        }

        let peripheralUUID = String(data: data, encoding: .utf8)

        print("updated value for characteristic for: \(peripheral.identifier.uuidString.uppercased())")
        synchronized(self) {
            peripheralUUIDSMatching[peripheral.identifier.uuidString.uppercased()] = peripheralUUID?.uppercased()
            peripheralsToBeValidated.removeAll { $0 == peripheral }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("error discover characteristic: \(error.localizedDescription)")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        guard let characteristic = service.characteristics?.first else {
            print("error discover characteristic: characteristic not found")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        print("discover characteristic for \(peripheral.identifier.uuidString.uppercased())")
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("error discover services: \(error.localizedDescription)")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        guard let service = peripheral.services?.first else {
            print("error discover services: service not found")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        print("discover service for \(peripheral.identifier.uuidString.uppercased())")
        peripheral.discoverCharacteristics([beaconCharacteristicUUID()], for: service)
    }
}

// MARK: Create timers helpers

extension DispatchSource {
    class func singleTimer(interval: DispatchTimeInterval,
                           leeway: DispatchTimeInterval = .nanoseconds(0),
                           queue: DispatchQueue,
                           handler: @escaping () -> Void) -> DispatchSourceTimer {
        let result = DispatchSource.makeTimerSource(queue: queue)
        result.setEventHandler(handler: handler)
        result.schedule(deadline: .now() + interval, repeating: .never, leeway: leeway)
        result.resume()
        return result
    }

    class func repeatingTimer(interval: DispatchTimeInterval,
                              leeway: DispatchTimeInterval = .nanoseconds(0),
                              queue: DispatchQueue,
                              handler: @escaping () -> Void) -> DispatchSourceTimer {
        let result = DispatchSource.makeTimerSource(queue: queue)
        result.setEventHandler(handler: handler)
        result.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
        result.resume()
        return result
    }
}

// MARK: CLLocationManagerDelegate

extension BLEService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("location manager change authorization status")
        startMonitoring()
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("location manager exit region")
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("location manager exit region")
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        print("location manager start monitoring")
    }
}