import CoreBluetooth

class BluetoothScanner: NSObject, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager!
    var currentDevices: [BLEDevice] = []
    override init() { super.init(); centralManager = CBCentralManager(delegate: self, queue: nil) }
    func startScanning() { if centralManager.state == .poweredOn { centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]) } }
    func stopScanning() { centralManager.stopScan() }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {}
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let device = BLEDevice(identifier: peripheral.identifier.uuidString, rssi: RSSI.intValue)
        if let idx = currentDevices.firstIndex(where: { $0.identifier == device.identifier }) { currentDevices[idx] = device } else { currentDevices.append(device) }
    }
}
