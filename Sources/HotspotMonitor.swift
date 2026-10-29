import AVFoundation
import CoreBluetooth
import UIKit
import Combine

/// 扫描到 / 已绑定的 BLE 设备
struct DiscoveredDevice: Identifiable, Hashable {
    let id: String          // CBPeripheral.identifier.uuidString
    let name: String
    let uuidString: String
    var rssi: Int
}

/// 车机蓝牙 -> 个人热点 自动开关核心逻辑
///
/// 两种检测模式：
///  1. 常驻(音频保活)：用 AVAudioSession 监听蓝牙音频路由变化，后台靠无声音频保活。
///     适用所有经典蓝牙车机，最稳；App 需后台常驻（车载充电时耗电可忽略）。
///  2. 省电(BLE唤醒)：绑定车机 BLE 的 peripheral UUID 后对其保持"待连接"，
///     车机出现/消失时由系统唤醒 App（真正的事件驱动，几乎不耗电）。
///     注意：iOS 后台扫描不允许 withServices: nil，所以必须先在前台扫描并绑定。
///
/// 开关热点由「快捷指令」App 里自建的「设定个人热点」动作完成（iOS 16 自带该动作），
/// 本 App 只用 shortcuts:// URL 触发它：全程公开 API、无私有框架、无特殊 entitlement。
final class HotspotMonitor: NSObject, ObservableObject {
    static let shared = HotspotMonitor()

    enum MonitorMode: String, CaseIterable, Identifiable {
        case audio = "常驻(音频保活)"
        case ble = "省电(BLE唤醒)"
        var id: String { rawValue }
    }

    // MARK: - 配置（持久化）
    @Published var targetDeviceName: String {
        didSet { UserDefaults.standard.set(targetDeviceName, forKey: "targetDeviceName") }
    }
    @Published var onShortcutName: String {
        didSet { UserDefaults.standard.set(onShortcutName, forKey: "onShortcutName") }
    }
    @Published var offShortcutName: String {
        didSet { UserDefaults.standard.set(offShortcutName, forKey: "offShortcutName") }
    }
    @Published var mode: MonitorMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }
    @Published var boundUUID: String? {
        didSet { UserDefaults.standard.set(boundUUID, forKey: "boundUUID") }
    }
    @Published var boundName: String {
        didSet { UserDefaults.standard.set(boundName, forKey: "boundName") }
    }

    @Published private(set) var isMonitoring = false
    @Published private(set) var lastAction = "未启动"
    @Published private(set) var currentRouteName = "无"
    @Published private(set) var detectedConnected = false
    @Published private(set) var discovered: [DiscoveredDevice] = []
    @Published private(set) var bleInfo = "未绑定车机"
    @Published private(set) var isScanning = false

    private let session = AVAudioSession.sharedInstance()
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var appliedConnected: Bool? = nil

    // MARK: - BLE 内部状态
    private var central: CBCentralManager?
    private var peripheralMap: [String: CBPeripheral] = [:]
    private var boundPeripheral: CBPeripheral?
    private var bleConnected = false
    private var lastBLESeen = Date.distantPast
    private var bleWatchdog: Timer?
    private var presenceFallback = false   // 车机 BLE 不可连接时，退回"广播存在性"检测

    init() {
        let d = UserDefaults.standard
        _targetDeviceName = Published(initialValue: d.string(forKey: "targetDeviceName") ?? "")
        _onShortcutName  = Published(initialValue: d.string(forKey: "onShortcutName") ?? "车机热点开")
        _offShortcutName = Published(initialValue: d.string(forKey: "offShortcutName") ?? "车机热点关")
        let m = d.string(forKey: "mode").flatMap { MonitorMode(rawValue: $0) } ?? .ble
        _mode = Published(initialValue: m)
        _boundUUID = Published(initialValue: d.string(forKey: "boundUUID"))
        _boundName = Published(initialValue: d.string(forKey: "boundName") ?? "")
    }

    // MARK: - 生命周期
    /// 必须尽早创建 CBCentralManager（带 restoreIdentifier），后台被唤醒时系统才能回调 willRestoreState
    func prepareCentral() {
        guard central == nil else { return }
        let opts: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: "carhotspot.restore" as NSString,
            CBCentralManagerOptionShowPowerAlertKey: false
        ]
        central = CBCentralManager(delegate: self, queue: nil, options: opts)
    }

    /// App 被系统唤醒/重新打开后，若上次是监控状态则自动恢复
    func autoStartIfNeeded() {
        prepareCentral()
        if UserDefaults.standard.bool(forKey: "wasMonitoring") { start() }
    }

    // MARK: - 启停
    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        UserDefaults.standard.set(true, forKey: "wasMonitoring")
        appliedConnected = nil
        switch mode {
        case .audio:
            setupAudioSession()
            startSilentPlayback()
            NotificationCenter.default.addObserver(
                self, selector: #selector(routeChanged),
                name: AVAudioSession.routeChangeNotification, object: nil)
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.evaluateAudioRoute()
            }
            evaluateAudioRoute()
        case .ble:
            presenceFallback = false
            prepareCentral()
            if central?.state == .poweredOn { bleReady() }
            bleWatchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                self?.bleTick()
            }
            bleInfo = boundUUID == nil ? "未绑定车机，请先扫描绑定" : "等待车机出现…"
        }
        lastAction = "监控中（\(mode.rawValue)）"
    }

    func stop() {
        isMonitoring = false
        UserDefaults.standard.set(false, forKey: "wasMonitoring")
        NotificationCenter.default.removeObserver(
            self, name: AVAudioSession.routeChangeNotification, object: nil)
        timer?.invalidate(); timer = nil
        player?.stop(); player = nil
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        if let p = boundPeripheral { central?.cancelPeripheralConnection(p) }
        central?.stopScan(); isScanning = false
        bleWatchdog?.invalidate(); bleWatchdog = nil
        bleConnected = false
        detectedConnected = false
        lastAction = "已停止"
    }

    /// 手动触发一次，用于快速验证快捷指令是否生效
    func testRun(_ turnOn: Bool) {
        runShortcut(named: turnOn ? onShortcutName : offShortcutName)
        lastAction = turnOn ? "手动测试：开热点" : "手动测试：关热点"
    }

    // MARK: - 音频保活（常驻模式）
    private func setupAudioSession() {
        do {
            // mixWithOthers：无声播放不抢占车机音乐；duckOthers：不压低其他音频
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch { print("AVAudioSession setup error: \(error)") }
    }

    private func startSilentPlayback() {
        guard let url = Self.silentWavURL() else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1   // 无限循环
            player?.volume = 0           // 静音
            player?.play()
        } catch { print("silent playback error: \(error)") }
    }

    @objc private func routeChanged(_ note: Notification) { evaluateAudioRoute() }

    private func evaluateAudioRoute() {
        let outputs = session.currentRoute.outputs
        let names = outputs.map { $0.portName }
        currentRouteName = names.isEmpty ? "无" : names.joined(separator: ", ")
        let connected = outputs.contains(where:) { out in
            let isBT = out.portType == .bluetoothHFP ||
                       out.portType == .bluetoothA2DP ||
                       out.portType == .bluetoothLEAudio
            let nameOK = targetDeviceName.isEmpty ||
                         out.portName.localizedCaseInsensitiveContains(targetDeviceName)
            return isBT && nameOK
        }
        detectedConnected = connected
        applyState(connected: connected)
    }

    // MARK: - BLE 绑定
    func startScan() {
        prepareCentral()
        guard let central = central, central.state == .poweredOn, !isScanning else { return }
        isScanning = true
        discovered.removeAll()
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central?.stopScan()
        isScanning = false
    }

    /// 用户从列表里选中车机 -> 绑定并保持"待连接"
    func selectDevice(_ dev: DiscoveredDevice) {
        var peripheral: CBPeripheral? = peripheralMap[dev.id]
        if peripheral == nil {
            peripheral = retrieve(uuidString: dev.uuidString)
        }
        guard let p = peripheral else { return }
        bind(peripheral: p, name: dev.name)
    }

    private func retrieve(uuidString: String) -> CBPeripheral? {
        guard let central = central,
              let uuid = UUID(uuidString: uuidString) else { return nil }
        return central.retrievePeripherals(withIdentifiers: [uuid]).first
    }

    func unbind() {
        if let p = boundPeripheral { central?.cancelPeripheralConnection(p) }
        boundPeripheral = nil
        boundUUID = nil
        boundName = ""
        presenceFallback = false
        bleConnected = false
        bleInfo = "未绑定车机"
    }

    private func bind(peripheral: CBPeripheral, name: String) {
        boundPeripheral = peripheral
        peripheralMap[peripheral.identifier.uuidString] = peripheral
        boundUUID = peripheral.identifier.uuidString
        boundName = name
        presenceFallback = false
        stopScan()
        connectIfNeeded()
        bleInfo = peripheral.state == .connected ? "已连接：\(name)" : "等待车机出现…"
    }

    // MARK: - BLE 内部
    private func bleReady() {
        guard let central = central, central.state == .poweredOn else { return }
        if let uuidStr = boundUUID {
            var peripheral: CBPeripheral? = peripheralMap[uuidStr]
            if peripheral == nil {
                peripheral = retrieve(uuidString: uuidStr)
            }
            if let p = peripheral {
                bind(peripheral: p, name: boundName.isEmpty ? (p.name ?? "车机") : boundName)
            } else {
                bleInfo = "等待车机出现…"
            }
        } else {
            bleInfo = "未绑定车机，请先扫描绑定"
        }
    }

    private func connectIfNeeded() {
        guard let central = central, central.state == .poweredOn,
              let p = boundPeripheral, !presenceFallback else { return }
        switch p.state {
        case .connected:
            handleBLEConnected()
        case .connecting:
            break
        default:
            central.connect(p, options: nil)
        }
    }

    private func handleBLEConnected() {
        guard !bleConnected else { return }
        bleConnected = true
        detectedConnected = true
        bleInfo = "已连接：\(boundName.isEmpty ? (boundPeripheral?.name ?? "车机") : boundName)"
        applyState(connected: true)
    }

    private func handleBLEDisconnected() {
        guard bleConnected else { return }
        bleConnected = false
        detectedConnected = false
        bleInfo = "等待车机出现…"
        applyState(connected: false)
    }

    private func bleTick() {
        guard isMonitoring, mode == .ble else { return }
        // 断开时持续重连，保持"待连接"状态，车机再次出现时系统才会唤醒
        if !presenceFallback, let p = boundPeripheral, p.state == .disconnected {
            connectIfNeeded()
        }
        // 广播存在性兜底（车机 BLE 不可连接时使用）：15s 内没再收到广播即视为断开
        if presenceFallback && bleConnected && Date().timeIntervalSince(lastBLESeen) > 15 {
            handleBLEDisconnected()
        }
    }

    private func matchesTarget(_ name: String) -> Bool {
        targetDeviceName.isEmpty || name.localizedCaseInsensitiveContains(targetDeviceName)
    }

    // MARK: - 统一触发（仅在状态变化时执行，避免重复刷快捷指令）
    private func applyState(connected: Bool) {
        guard isMonitoring else { return }
        guard appliedConnected != connected else { return }
        appliedConnected = connected
        let name = connected ? onShortcutName : offShortcutName
        runShortcut(named: name)
        lastAction = connected ? "车机已连 -> 开热点" : "车机已断 -> 关热点"
    }

    private func runShortcut(named name: String) {
        guard !name.isEmpty else { return }
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") else { return }
        UIApplication.shared.open(url, options: [:]) { ok in
            print("[HotspotMonitor] open \(name) -> \(ok)")
        }
    }

    // MARK: - 生成 1 秒静音 WAV 用于后台保活
    private static func silentWavURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("silent_loop.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let sampleRate: UInt32 = 8000
        let seconds: UInt32 = 1
        let numSamples = sampleRate * seconds
        let dataSize = numSamples * 2 // 16-bit 单声道

        var data = Data()
        func u32(_ v: UInt32) {
            data.append(UInt8(v & 0xff)); data.append(UInt8((v >> 8) & 0xff))
            data.append(UInt8((v >> 16) & 0xff)); data.append(UInt8((v >> 24) & 0xff))
        }
        func u16(_ v: UInt16) {
            data.append(UInt8(v & 0xff)); data.append(UInt8((v >> 8) & 0xff))
        }

        data.append(contentsOf: "RIFF".utf8)
        u32(36 + dataSize)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        u32(16)
        u16(1)               // PCM
        u16(1)               // 单声道
        u32(sampleRate)
        u32(sampleRate * 2)  // byteRate
        u16(2)               // blockAlign
        u16(16)              // bitsPerSample
        data.append(contentsOf: "data".utf8)
        u32(dataSize)
        data.append(Data(count: Int(dataSize))) // 全零 = 静音

        do { try data.write(to: url) } catch { return nil }
        return url
    }
}

// MARK: - CoreBluetooth
extension HotspotMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if isMonitoring && mode == .ble { bleReady() }
        } else {
            bleInfo = "蓝牙未开启"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "未知设备"
        peripheralMap[peripheral.identifier.uuidString] = peripheral
        let dev = DiscoveredDevice(id: peripheral.identifier.uuidString,
                                   name: name,
                                   uuidString: peripheral.identifier.uuidString,
                                   rssi: RSSI.intValue)
        DispatchQueue.main.async {
            if let idx = self.discovered.firstIndex(where: { $0.id == dev.id }) {
                self.discovered[idx] = dev
            } else {
                self.discovered.append(dev)
            }
        }
        // 广播存在性兜底：只有在"未绑定 / 不可连接"时才用它判断
        guard boundPeripheral == nil || presenceFallback else { return }
        guard matchesTarget(name) else { return }
        lastBLESeen = Date()
        if !bleConnected {
            bleConnected = true
            detectedConnected = true
            applyState(connected: true)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        bleInfo = "已连接：\(boundName.isEmpty ? (peripheral.name ?? "车机") : boundName)"
        handleBLEConnected()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        handleBLEDisconnected()
        // 立刻重连，保持"待连接"状态，便于下次车机出现时被唤醒
        if !presenceFallback, central.state == .poweredOn {
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        // 该 BLE 不可连接：退回广播存在性检测
        presenceFallback = true
        bleInfo = "该车机 BLE 不可连接，已退回广播检测（后台可能不触发，建议改用常驻模式）"
        lastBLESeen = Date()
        startScan()
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // 系统因蓝牙事件在后台唤醒 App
        if let list = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let p = list.first {
            let name = boundName.isEmpty ? (p.name ?? "车机") : boundName
            bind(peripheral: p, name: name)
        } else {
            bleReady()
        }
    }
}
