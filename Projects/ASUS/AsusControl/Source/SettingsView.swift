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
    @Published var pendingControl = ""
    @Published var pendingValue: Int?
    func loading(_ key: String) -> Bool { busy && pendingControl == key }
    weak var actions: AsusPaneActions?
    func flag(_ values: [String: Any], _ key: String) -> Bool { (values[key] as? NSNumber)?.boolValue ?? false }
    func number(_ values: [String: Any], _ key: String) -> Int { (values[key] as? NSNumber)?.intValue ?? 0 }
    var devices: Bool { !busy && flag(hardware, "DeviceControlAllowed") }
    var fullSpeedAvailable: Bool { devices && flag(system,"PowerSourceKnown") && flag(system,"ACPower") }
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
        return flag(system,"PowerSourceKnown") && (minimum == 0 || flag(system,"BatteryKnown") && ((system["BatteryPercent"] as? NSNumber)?.doubleValue ?? 0) > Double(minimum))
    }
}
private func profileName(_ value: Int) -> String { ["Standard","Whisper","Performance","Full Speed"].indices.contains(value) ? ["Standard","Whisper","Performance","Full Speed"][value] : "Unavailable" }

// Use the actual AppKit indeterminate spinner at the same size everywhere.
private struct LoadingIndicator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSProgressIndicator {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.startAnimation(nil)
        return spinner
    }
    func updateNSView(_ view: NSProgressIndicator, context: Context) {}
    static func dismantleNSView(_ view: NSProgressIndicator, coordinator: ()) { view.stopAnimation(nil) }
}

private struct SettingsScreen: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmTouchpad = false
    private var hardware: [String:Any] { model.hardware }
    private var system: [String:Any] { model.system }
    private var preferences: [String:Any] { model.preferences }
    private var touchpadRecovery: String {
        guard let hotkeys = hardware["FnSelectedHotkeys"] as? NSNumber else { return "Use the touchpad key to turn it back on." }
        return hotkeys.boolValue ? "Press F6 to turn it back on." : "Press Fn + F6 to turn it back on."
    }
    private var spinner: some View {
        LoadingIndicator().frame(width:16,height:16).accessibilityLabel("Applying")
    }
    private func loadingRow<Content: View>(_ key: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing:8) {
            content().frame(maxWidth:.infinity,alignment:.leading)
            if model.loading(key) { spinner }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
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
                Section {
                    Text(model.version).font(.caption2).foregroundStyle(.tertiary)
                }.listRowBackground(Color.clear)
            }.formStyle(.grouped).scrollContentBackground(.hidden)
                .overlay(alignment:.topTrailing) {
                    if model.loading("all") { spinner.padding(.top,16).padding(.trailing,20) }
                }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    private var power: some View {
        Group {
            Section {
                HStack(spacing:12) {
                    profileCard(2,title:"Performance",symbol:"speedometer",detail:"Dynamically maximizes cooling performance for demanding tasks.")
                    profileCard(0,title:"Standard",symbol:"fan",detail:"Dynamically selects the best fan speed for everyday tasks.")
                    profileCard(1,title:"Whisper",symbol:"leaf",detail:"Dynamically minimizes fan speed for the quietest operation.")
                }.listRowInsets(EdgeInsets(top:0,leading:0,bottom:0,trailing:0)).listRowBackground(Color.clear)
            } header: { Text("Fan Profile") } footer: {
                Text("Performance mode requires: AC power and more than 40% battery.")
                    .fixedSize(horizontal:false,vertical:true)
            }
            Section {
                loadingRow("FullSpeed") {
                    Toggle("Full Speed",isOn:Binding(get:{ model.number(hardware,"FanRequestedMode") == 1 },set:{ enabled in
                        model.actions?.changeSetting("FullSpeed",value:NSNumber(value:enabled))
                    })).disabled(!model.fullSpeedAvailable).opacity(model.fullSpeedAvailable ? 1 : 0.4)
                }
                LabeledContent("Active profile",value:model.currentProfile)
                LabeledContent("Fan speed",value:model.flag(hardware,"FanReadingValid") ? "\(model.number(hardware,"FanRPM")) RPM" : "Unavailable")
            } footer: {
                Text("Full Speed overrides the selected profile.")
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
                    if selected { Image(systemName:"checkmark.circle.fill").font(.system(size:16)).accessibilityLabel("Active") }
                }.foregroundStyle(selected ? Color.accentColor : Color.primary)
                Text(title).font(.system(size:14,weight:.semibold)).foregroundStyle(.primary)
                Text(detail).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:0)
                if selected { Text("Active").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor) }
            }.padding(14).frame(maxWidth:.infinity,minHeight:202,maxHeight:202,alignment:.topLeading)
                .background(selected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).stroke(selected ? Color.accentColor : Color(nsColor:.separatorColor),lineWidth:selected ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius:12))
                .overlay(alignment:.bottomTrailing) {
                    if model.loading("QuickProfile") && model.pendingValue == profile { spinner.padding(14) }
                }
            .environment(\.isEnabled, true)
            .opacity(!model.profileAllowed(profile) && !selected ? 0.4 : 1)
        }.buttonStyle(.plain).disabled(!model.devices || !model.profileAllowed(profile))
            .accessibilityLabel("\(title) fan profile").accessibilityValue(selected ? "Active" : "Not active")
    }
    private var input: some View {
        Group {
            Section {
                loadingRow("Touchpad") {
                    Toggle("Touchpad",isOn:Binding(get:{model.flag(hardware,"TrackpadEnabled")},set:{enabled in
                        if enabled { model.actions?.setTouchpadEnabled(true) }
                        else { confirmTouchpad = true }
                    })).disabled(!model.devices || !model.flag(hardware,"TrackpadControlAvailable"))
                }
                if confirmTouchpad {
                    VStack(alignment:.leading,spacing:8) {
                        Text("Disable the touchpad? \(touchpadRecovery)").foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        HStack {
                            Spacer()
                            Button("Cancel") { confirmTouchpad = false }
                            Button("Disable") { confirmTouchpad = false; model.actions?.setTouchpadEnabled(false) }
                        }
                    }
                }
            } header: { Text("Input Devices") } footer: {
                Text(touchpadRecovery).fixedSize(horizontal:false,vertical:true)
            }
            Section {
                loadingRow("FnHotkeys") {
                    Picker("Function keys",selection:Binding(get:{model.flag(preferences,"FnHotkeys")},set:{model.actions?.changeSetting("FnHotkeys",value:NSNumber(value:$0))})) {
                        Text("Printed hotkeys").tag(true)
                        Text("F1–F12").tag(false)
                    }.disabled(!model.devices || !model.flag(hardware,"FnLockAvailable"))
                }
            } footer: {
                Text("Hold Fn to use the other function-key behavior.").fixedSize(horizontal:false,vertical:true)
            }
            Section {
                loadingRow("BacklightSleepMode") {
                    Picker("Turn off when idle",selection:model.integer("BacklightSleepMode")) {
                        Text("Never").tag(0)
                        Text("On battery and power adapter").tag(1)
                        Text("On battery only").tag(2)
                    }.disabled(!model.devices || !model.flag(hardware,"KeyboardControlAvailable"))
                }
                if model.number(preferences,"BacklightSleepMode") != 0 {
                    loadingRow("BacklightTimeout") {
                        Picker("After",selection:model.integer("BacklightTimeout")) {
                            Text("30 seconds").tag(30)
                            Text("1 minute").tag(60)
                            Text("3 minutes").tag(180)
                            Text("5 minutes").tag(300)
                            Text("10 minutes").tag(600)
                            Text("15 minutes").tag(900)
                        }.disabled(!model.devices || !model.flag(hardware,"KeyboardControlAvailable"))
                    }
                }
            } header: { Text("Keyboard Backlight") } footer: {
                Text("The keyboard light returns to its previous level when you resume using the computer.").fixedSize(horizontal:false,vertical:true)
            }
        }
    }

}

// Legacy preference-pane hosts can attach a fixed initial frame. Adopt the
// actual container on attachment and use ordinary AppKit autoresizing after it.
private final class SettingsHost: NSHostingView<SettingsScreen> {
    override var isOpaque: Bool { false }
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
    @objc func update(hardware:NSDictionary,system:NSDictionary,preferences:NSDictionary,message:String,error:Bool,busy:Bool,version:String,pendingControl:String,pendingValue:NSNumber?) {
        model.hardware=hardware as? [String:Any] ?? [:]
        model.system=system as? [String:Any] ?? [:]
        model.preferences=preferences as? [String:Any] ?? [:]
        model.message=message; model.error=error; model.busy=busy; model.version=version
        model.pendingControl=pendingControl; model.pendingValue=pendingValue?.intValue
    }
}
