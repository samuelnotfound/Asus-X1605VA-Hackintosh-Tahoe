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
    weak var actions: AsusPaneActions?
    func flag(_ values: [String: Any], _ key: String) -> Bool { (values[key] as? NSNumber)?.boolValue ?? false }
    func number(_ values: [String: Any], _ key: String) -> Int { (values[key] as? NSNumber)?.intValue ?? 0 }
    var devices: Bool { !busy && flag(hardware, "DeviceControlAllowed") }
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
                power
                input
            }.formStyle(.grouped)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor))
    }
    private var power: some View {
        Group {
            Section {
                HStack(spacing:12) {
                    profileCard(2,title:"Performance",symbol:"speedometer",detail:"Prioritize cooling for demanding tasks.")
                    profileCard(0,title:"Standard",symbol:"fan",detail:"Balance performance and fan noise.")
                    profileCard(1,title:"Whisper",symbol:"leaf",detail:"Keep fan noise lower for lighter tasks.")
                }.listRowInsets(EdgeInsets(top:0,leading:0,bottom:0,trailing:0)).listRowBackground(Color.clear)
            } header: { Text("Fan Profile") }
            Section {
                Toggle("Full Speed",isOn:Binding(get:{ model.number(hardware,"FanRequestedMode") == 1 },set:{ enabled in
                    let profile = enabled ? 3 : model.number(hardware,"ThermalProfile")
                    model.actions?.changeSetting("QuickProfile",value:NSNumber(value:profile))
                })).disabled(!model.devices || !model.profileAllowed(3))
                LabeledContent("Fan speed",value:model.flag(hardware,"FanReadingValid") ? "\(model.number(hardware,"FanRPM")) RPM" : "Unavailable")
            } footer: {
                Text("Profiles adjust fan speed automatically. Full Speed keeps the fan running at its full-speed setting.").fixedSize(horizontal:false,vertical:true)
            }
            Section {
                Toggle("Battery Care",isOn:model.bool("BatteryCare")).disabled(!model.devices || !model.flag(hardware,"BatteryCareAvailable"))
                Toggle("Full charging for 24 hours",isOn:Binding(get:{ fullCharging },set:{ model.actions?.changeSetting("FullCharge",value:NSNumber(value:$0)) }))
                    .disabled(!model.devices || !model.flag(hardware,"BatteryCareAvailable") || !model.flag(preferences,"BatteryCare"))
            } header: { Text("Battery") } footer: {
                Text(fullCharging ? "Charging to 100% is allowed until \(fullChargeEnd). Battery Care then returns to 80%." : "Battery Care limits charging to 80%. Temporarily allow 100% for 24 hours when you need a full charge.")
                    .fixedSize(horizontal:false,vertical:true)
            }
        }
    }
    private func profileCard(_ profile:Int,title:String,symbol:String,detail:String) -> some View {
        let selected=model.flag(hardware,"ThermalProfileValid") && model.number(hardware,"ThermalProfile") == profile && model.number(hardware,"FanRequestedMode") != 1
        return Button {
            model.actions?.changeSetting("QuickProfile",value:NSNumber(value:profile))
        } label: {
            VStack(alignment:.leading,spacing:10) {
                HStack(alignment:.top) {
                    Image(systemName:symbol).font(.system(size:25,weight:.regular))
                    Spacer(minLength:0)
                    if selected { Image(systemName:"checkmark.circle.fill").font(.system(size:16)) }
                }.foregroundStyle(selected ? Color.accentColor : Color.primary)
                Text(title).font(.system(size:14,weight:.semibold)).foregroundStyle(.primary)
                Text(detail).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:0)
            }.padding(14).frame(maxWidth:.infinity,minHeight:154,maxHeight:154,alignment:.topLeading)
                .background(selected ? Color.accentColor.opacity(0.10) : Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).stroke(selected ? Color.accentColor : Color(nsColor:.separatorColor),lineWidth:selected ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).disabled(!model.devices || !model.profileAllowed(profile))
            .accessibilityLabel("\(title) fan profile").accessibilityValue(selected ? "Selected" : "Not selected")
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
}
