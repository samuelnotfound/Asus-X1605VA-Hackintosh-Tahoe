// Copyright (c) 2026 samuelnotfound. MIT License.
import AppKit
import SwiftUI

private final class SettingsModel: ObservableObject {
    @Published var hardware: [String: Any] = [:]
    @Published var system: [String: Any] = [:]
    @Published var preferences: [String: Any] = [:]
    @Published var message = ""
    @Published var error = false
    @Published var busy = false
    @Published var version = ""
    @Published var tab = 0
    weak var actions: AsusPaneActions?
    func flag(_ values: [String: Any], _ key: String) -> Bool { (values[key] as? NSNumber)?.boolValue ?? false }
    func number(_ values: [String: Any], _ key: String) -> Int { (values[key] as? NSNumber)?.intValue ?? 0 }
    var devices: Bool { !busy && flag(hardware, "DeviceControlAllowed") }
    var mode: Int { (flag(preferences, "SplitProfiles") ? 1 : 0) + (flag(preferences, "FollowLowPower") ? 2 : 0) }
    func bool(_ key: String) -> Binding<Bool> {
        Binding(get: { self.flag(self.preferences,key) }, set: { self.actions?.changeSetting(key,value:NSNumber(value:$0)) })
    }
    func integer(_ key: String) -> Binding<Int> {
        Binding(get: { self.number(self.preferences,key) }, set: { self.actions?.changeSetting(key,value:NSNumber(value:$0)) })
    }
    var currentProfile: String {
        if number(hardware,"FanRequestedMode") == 1 { return "Full Speed" }
        return flag(hardware,"ThermalProfileValid") ? profileName(number(hardware,"ThermalProfile")) : "Unavailable"
    }
    func profileAllowed(_ profile: Int, onAC: Bool? = nil) -> Bool {
        let ac = onAC ?? flag(system,"ACPower")
        if profile == 3 { return ac || flag(hardware,"FullSpeedOnBattery") }
        if profile != 2 { return true }
        if !ac && !flag(hardware,"PerformanceOnBattery") { return false }
        // Configuring an AC policy is allowed on battery; it will apply only
        // when the power and battery restrictions are satisfied.
        if onAC != nil { return true }
        let minimum = (hardware["PerformanceMinimumBattery"] as? NSNumber)?.intValue ?? 40
        return flag(system,"PowerSourceKnown") && (minimum == 0 || flag(system,"BatteryKnown") && number(system,"BatteryPercent") > minimum)
    }
}
private func profileName(_ value: Int) -> String { ["Standard","Whisper","Performance","Full Speed"].indices.contains(value) ? ["Standard","Whisper","Performance","Full Speed"][value] : "Unavailable" }

// Keep tab navigation as a standard AppKit segmented control. It embeds
// cleanly in legacy PreferencePanes hosts, including offscreen host rendering.
private struct SectionPicker: NSViewRepresentable {
    @Binding var selection: Int
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let view=NSSegmentedControl(labels:["Power","Input Devices","System Status"],trackingMode:.selectOne,target:context.coordinator,action:#selector(Coordinator.changed(_:)))
        view.segmentDistribution = .fillEqually
        view.setAccessibilityLabel("Settings section")
        return view
    }
    func updateNSView(_ view:NSSegmentedControl,context:Context) {
        view.selectedSegment=selection; context.coordinator.parent=self
    }
    final class Coordinator:NSObject {
        var parent:SectionPicker
        init(_ parent:SectionPicker) { self.parent=parent }
        @objc func changed(_ sender:NSSegmentedControl) { parent.selection=sender.selectedSegment }
    }
}

private struct SettingsScreen: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmTouchpad = false
    private var hardware: [String:Any] { model.hardware }
    private var system: [String:Any] { model.system }
    private var preferences: [String:Any] { model.preferences }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ASUS Control").font(.headline)
                Spacer()
                Text(model.version.replacingOccurrences(of:"ASUS Control ",with:""))
                    .font(.caption2).foregroundStyle(.tertiary)
            }.padding(.horizontal,20).padding(.top,16).padding(.bottom,12)
            SectionPicker(selection:$model.tab)
                .frame(height:24).padding(.horizontal,20).padding(.bottom,8)
            Form {
                if !model.message.isEmpty && model.message != "Settings applied." {
                    Section {
                        HStack(alignment:.top) {
                            if model.error { Image(systemName:"exclamationmark.triangle").foregroundStyle(.orange) }
                            Text(model.message).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                            if model.error && model.devices {
                                Spacer()
                                Button("Try Again") { model.actions?.retrySettings() }
                            }
                        }
                    }
                }
                if model.tab == 0 { power }
                else if model.tab == 1 { input }
                else { status }
            }.formStyle(.grouped).id(model.tab)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor))
    }
    @ViewBuilder private func profiles(_ title: String,key: String,onAC: Bool? = nil) -> some View {
        Picker(title,selection:model.integer(key)) {
            ForEach(0..<4,id:\.self) { value in
                if onAC != false || model.profileAllowed(value,onAC:false) {
                    Text(profileName(value)).tag(value).disabled(!model.profileAllowed(value,onAC:onAC))
                }
            }
        }.disabled(!model.devices || !model.flag(hardware,"ThermalProfileValid"))
    }
    private var power: some View {
        Group {
            Section {
                LabeledContent("Fan speed",value:model.flag(hardware,"FanReadingValid") ? "\(model.number(hardware,"FanRPM")) RPM" : "Unavailable")
                Picker("Profile switching",selection:Binding(get:{model.mode},set:{model.actions?.selectProfileMode($0)})) {
                    Text("Manual").tag(0)
                    Text("Power source").tag(1)
                    Text("Low Power Mode").tag(2)
                    Text("Power source & Low Power Mode").tag(3)
                }.disabled(!model.devices)
                if model.mode == 1 || model.mode == 3 {
                    profiles("On power adapter",key:"ACProfile",onAC:true)
                    profiles("On battery",key:"BatteryProfile",onAC:false)
                } else {
                    profiles(model.mode == 2 ? "Normal profile" : "Fan profile",key:"ManualProfile")
                }
                LabeledContent("Active profile",value:model.currentProfile)
            } header: { Text("Fan") } footer: {
                Text(fanHelp).fixedSize(horizontal:false,vertical:true)
            }
            Section {
                Toggle("Battery Care",isOn:model.bool("BatteryCare")).disabled(!model.devices || !model.flag(hardware,"BatteryCareAvailable"))
                Toggle("Full charging for 24 hours",isOn:Binding(get:{ fullCharging },set:{ model.actions?.changeSetting("FullCharge",value:NSNumber(value:$0)) }))
                    .disabled(!model.devices || !model.flag(hardware,"BatteryCareAvailable") || !model.flag(preferences,"BatteryCare"))
                if let requested = hardware["ChargeLimitRequested"] as? NSNumber {
                    LabeledContent("Requested charging limit",value:"\(requested.intValue)%")
                }
            } header: { Text("Battery") } footer: {
                Text(fullCharging ? "Charging to 100% is allowed until \(fullChargeEnd). Battery Care then returns to 80%." : "Battery Care limits charging to 80%. Temporarily allow 100% for 24 hours when you need a full charge.")
                    .fixedSize(horizontal:false,vertical:true)
            }
        }
    }
    private var fanHelp: String {
        var help = "Standard balances cooling and noise. Whisper favors quieter operation. Performance prioritizes cooling. Full Speed overrides the automatic fan policy."
        if model.mode == 2 || model.mode == 3 { help += " Low Power Mode selects Whisper and restores your chosen profile when it turns off." }
        if model.number(preferences,"ACProfile") == 2 || model.number(preferences,"ManualProfile") == 2 {
            help += " On this device, Performance requires power adapter connection and more than 40% battery; Standard is used otherwise."
        }
        return help
    }
    private var fullCharging: Bool { model.flag(preferences,"BatteryCare") && ((preferences["FullChargeUntil"] as? NSNumber)?.doubleValue ?? 0) > Date().timeIntervalSince1970 }
    private var fullChargeEnd: String { Date(timeIntervalSince1970:(preferences["FullChargeUntil"] as? NSNumber)?.doubleValue ?? 0).formatted(date:.abbreviated,time:.shortened) }
    private var input: some View {
        Group {
            Section {
                Toggle("Touchpad",isOn:Binding(get:{model.flag(hardware,"TrackpadEnabled")},set:{enabled in
                    if enabled { model.actions?.setTouchpadEnabled(true) }
                    else { confirmTouchpad = true }
                })).disabled(!model.devices || !model.flag(hardware,"TrackpadControlAvailable"))
                if confirmTouchpad {
                    VStack(alignment:.leading,spacing:8) {
                        Text("Disable the touchpad? Press Fn + F6 to turn it back on.").foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        HStack {
                            Spacer()
                            Button("Cancel") { confirmTouchpad = false }
                            Button("Disable") { confirmTouchpad = false; model.actions?.setTouchpadEnabled(false) }
                        }
                    }
                }
                Picker("Function keys",selection:Binding(get:{model.flag(preferences,"FnHotkeys")},set:{model.actions?.changeSetting("FnHotkeys",value:NSNumber(value:$0))})) {
                    Text("Printed hotkeys").tag(true)
                    Text("F1–F12").tag(false)
                }.disabled(!model.devices || !model.flag(hardware,"FnLockAvailable"))
            } header: { Text("Input Devices") } footer: {
                Text("Hold Fn to use the other function-key behavior. If the touchpad is disabled, press Fn + F6 to enable it.").fixedSize(horizontal:false,vertical:true)
            }
            Section {
                Picker("Turn off when idle",selection:model.integer("BacklightSleepMode")) {
                    Text("Never").tag(0)
                    Text("On battery and power adapter").tag(1)
                    Text("On battery only").tag(2)
                }.disabled(!model.devices || !model.flag(hardware,"KeyboardControlAvailable"))
                if model.number(preferences,"BacklightSleepMode") != 0 {
                    Picker("After",selection:model.integer("BacklightTimeout")) {
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("3 minutes").tag(180)
                        Text("5 minutes").tag(300)
                        Text("10 minutes").tag(600)
                        Text("15 minutes").tag(900)
                    }.disabled(!model.devices || !model.flag(hardware,"KeyboardControlAvailable"))
                }
            } header: { Text("Keyboard Backlight") } footer: {
                Text("The keyboard light returns to its previous level when you resume using the computer. Brightness is adjusted with the keyboard keys.").fixedSize(horizontal:false,vertical:true)
            }
        }
    }
    private var status: some View {
        Group {
            Section("System") {
                LabeledContent("CPU usage",value:percentage("CPUPercent"))
                LabeledContent("Memory",value:memory)
                LabeledContent("Battery",value:model.flag(system,"BatteryKnown") ? "\(model.number(system,"BatteryPercent"))%" : "Unavailable")
                LabeledContent("Power source",value:model.flag(system,"PowerSourceKnown") ? (model.flag(system,"ACPower") ? "Power adapter" : "Battery") : "Unavailable")
                LabeledContent("Uptime",value:"\(model.number(system,"Uptime") / 3600)h \((model.number(system,"Uptime") / 60) % 60)m")
            }
            Section("Storage") {
                LabeledContent("Available",value:bytes("DiskFree"))
                LabeledContent("Capacity",value:bytes("DiskTotal"))
            }
            Section {
                Button("Open Activity Monitor") { model.actions?.openSystemTool("activity") }
                Button("Open Storage Settings") { model.actions?.openSystemTool("storage") }
            }
        }
    }
    private func percentage(_ key: String) -> String { (system[key] as? NSNumber).map { String(format:"%.0f%%",$0.doubleValue) } ?? "Reading…" }
    private func bytes(_ key: String) -> String { (system[key] as? NSNumber).map { ByteCountFormatter.string(fromByteCount:$0.int64Value,countStyle:.file) } ?? "Unavailable" }
    private var memory: String {
        guard let used=system["MemoryUsed"] as? NSNumber,let total=system["MemoryTotal"] as? NSNumber else { return "Unavailable" }
        return "\(ByteCountFormatter.string(fromByteCount:used.int64Value,countStyle:.memory)) of \(ByteCountFormatter.string(fromByteCount:total.int64Value,countStyle:.memory))"
    }
}

// Legacy preference-pane hosts can attach a fixed initial frame. Adopt the
// actual container on attachment and use ordinary AppKit autoresizing after it.
private final class SettingsHost: NSHostingView<SettingsScreen> {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        autoresizingMask = [.width,.height]
        if let parent=superview, parent.bounds.width > 0, parent.bounds.height > 0 {
            frame = parent.bounds
        }
    }
    override var intrinsicContentSize: NSSize { NSSize(width:NSView.noIntrinsicMetric,height:NSView.noIntrinsicMetric) }
}
@objc(AsusSettingsUI) final class AsusSettingsUI: NSObject {
    private let model=SettingsModel()
    @objc init(actions: AsusPaneActions) { super.init(); model.actions=actions }
    @objc func makeView() -> NSView {
        let view=SettingsHost(rootView:SettingsScreen(model:model))
        view.sizingOptions=[]
        view.frame=NSRect(x:0,y:0,width:660,height:760)
        return view
    }
    @objc func update(hardware:NSDictionary,system:NSDictionary,preferences:NSDictionary,message:String,error:Bool,busy:Bool,version:String) {
        model.hardware=hardware as? [String:Any] ?? [:]
        model.system=system as? [String:Any] ?? [:]
        model.preferences=preferences as? [String:Any] ?? [:]
        model.message=message; model.error=error; model.busy=busy; model.version=version
    }
    @objc func selectTab(_ tab:Int) { model.tab=tab }
}
