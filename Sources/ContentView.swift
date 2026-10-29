import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = HotspotMonitor.shared

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("监控开关")) {
                    Toggle("后台监控车机蓝牙", isOn: Binding(
                        get: { monitor.isMonitoring },
                        set: { on in
                            if on { monitor.start() } else { monitor.stop() }
                        }))
                    Text("状态：\(monitor.lastAction)")
                    HStack {
                        Text("车机判定：")
                        Text(monitor.detectedConnected ? "已连接" : "未连接")
                            .foregroundColor(monitor.detectedConnected ? .green : .secondary)
                    }
                    .font(.footnote)
                    if monitor.mode == .ble {
                        Text("BLE：\(monitor.bleInfo)")
                            .font(.footnote).foregroundColor(.secondary)
                    } else {
                        Text("当前音频输出：\(monitor.currentRouteName)")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }

                Section(header: Text("检测模式")) {
                    Picker("模式", selection: $monitor.mode) {
                        ForEach(HotspotMonitor.MonitorMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: monitor.mode) { _ in
                        if monitor.isMonitoring { monitor.stop(); monitor.start() }
                    }
                    Text("省电(BLE唤醒)：先绑定车机，之后车机出现/消失由系统唤醒，几乎不耗电。")
                        .font(.caption).foregroundColor(.secondary)
                    Text("常驻(音频保活)：适用所有车机，App 需后台常驻（车载充电时耗电极低）。")
                        .font(.caption).foregroundColor(.secondary)
                }

                if monitor.mode == .ble {
                    Section(header: Text("绑定车机 BLE")) {
                        if monitor.boundUUID == nil {
                            Button(monitor.isScanning ? "停止扫描" : "扫描周边 BLE") {
                                if monitor.isScanning { monitor.stopScan() } else { monitor.startScan() }
                            }
                            ForEach(monitor.discovered) { dev in
                                Button { monitor.selectDevice(dev) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(dev.name).font(.body)
                                            Text(dev.uuidString)
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text("\(dev.rssi) dBm")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                            Text("上车后在前台点「扫描周边 BLE」，找到你的车机点一下即绑定。")
                                .font(.caption).foregroundColor(.secondary)
                        } else {
                            HStack {
                                Text(monitor.boundName.isEmpty ? (monitor.boundUUID ?? "") : monitor.boundName)
                                    .font(.footnote)
                                    .lineLimit(1)
                                Spacer()
                                Button("重新选择") { monitor.unbind() }
                            }
                        }
                    }
                }

                Section(header: Text("快捷指令名称")) {
                    TextField("开启热点快捷指令", text: $monitor.onShortcutName)
                    TextField("关闭热点快捷指令", text: $monitor.offShortcutName)
                    Text("在「快捷指令」App 自建两条：动作都选「设定个人热点」，分别设为打开 / 关闭。")
                        .font(.caption).foregroundColor(.secondary)
                    HStack {
                        Button("测试开") { monitor.testRun(true) }
                        Spacer()
                        Button("测试关") { monitor.testRun(false) }
                    }
                }

                Section(header: Text("说明")) {
                    Text("锁屏时 openURL 可能被系统延后到解锁后执行；上车时通常会解锁手机，下车关热点可能延后到下次亮屏，属系统限制。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("车机热点自动")
        }
    }
}
