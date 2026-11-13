const std = @import("std");
const u = std.os.uefi;
const hid = @import("I2cIo.zig");

// ---------------------------------------------------------------- Simple Pointer
const State = extern struct { x: i32, y: i32, z: i32, left: bool, right: bool };
const Mode = extern struct { x: u64, y: u64, z: u64, left: bool, right: bool };
const Pointer = extern struct {
    reset: *const fn (*Pointer, bool) callconv(u.cc) u.Status,
    get_state: *const fn (*Pointer, *State) callconv(u.cc) u.Status,
    wait: u.Event,
    mode: *Mode,
};
const pointer_guid align(8) = u.protocol.SimplePointer.guid;
var mode: Mode = .{ .x = 4, .y = 4, .z = 0, .left = true, .right = true };
var pointer: Pointer = .{ .reset = reset, .get_state = getState, .wait = undefined, .mode = &mode };
var state: State = std.mem.zeroes(State);
var ready = false;

// ---------------------------------------------------------------- HID-over-I2C
// Root cause of "dead after restart": a warm reset does not power-cycle the pad,
// so it keeps whatever the OS left (SLEEP and/or Precision-Touchpad mode). The old
// driver only did blind reads and dropped every report that was not ID 1.
// Fix: read the HID descriptor, SET_POWER(ON), RESET (back to mouse mode), then poll.
const hid_desc_reg: u16 = 0x0001; // ELAN/ASUE1306; validated against the descriptor
const op_reset: u8 = 0x01;
const op_set_power: u8 = 0x08;
const tick_100ns: u64 = 200_000; // 20 ms poll

const Phase = enum { find, read_desc, power_on, reset, reset_wait, run };

var phase: Phase = .find;
var io: ?*hid.I2cIo = null;
var completion: u.Event = undefined;
var timer: u.Event = undefined;
var exit_event: u.Event = undefined;
var pending = false;
var stopping = false;
var result: u.Status = .success;
var rx: [64]u8 = undefined;
var tx: [4]u8 = undefined;
var packet: hid.Packet = .{ .count = 1, .operations = .{
    .{ .flags = hid.read_flag, .length = 0, .data = &rx },
    .{ .flags = hid.read_flag, .length = 0, .data = &rx },
} };

var cmd_reg: u16 = 0;
var in_len: u32 = 16; // same read size the original driver used
var have_desc = false;
var wait: u32 = 0; // ticks to sleep before the next step
var tries: u32 = 0;
var bad: u32 = 0; // consecutive failed reads in .run
var foreign: u32 = 0; // well-formed reports that are not mouse ID 1
var seen_good = false;
var reinits: u32 = 0;
var publish_div: u32 = 0;
var recheck: u32 = 0; // ticks since the I2C handle was last verified

// ---------------------------------------------------------------- diagnostics
// Volatile NVRAM variable, readable from macOS:  nvram -p | grep tp-diag
// (works with a RELEASE OpenCore build; no DEBUG log needed)
const Diag = extern struct {
    magic: u32, // "TPD1"
    phase: u8, // 0 find,1 read_desc,2 power_on,3 reset,4 reset_wait,5 run
    io_found: u8,
    have_desc: u8,
    seen_good: u8,
    reinits: u8,
    pad: [3]u8,
    io_index: u32,
    io_revision: u32,
    cmd_reg: u16,
    in_len: u16,
    vendor: u16,
    product: u16,
    find_attempts: u32,
    queue_fail: u32,
    good: u32, // valid mouse (ID 1) reports
    idle: u32, // successful zero-length reads
    foreign: u32, // reports with another ID / too short
    bad: u32, // failed reads in run phase
    last_queue_status: u64,
    phase_status: [6]u64, // last I2C status per phase
    phase_count: [6]u16, // completions per phase
    desc_head: [12]u8, // first bytes returned by the descriptor read
    last_report: [8]u8, // last non-idle input report
};
const diag_name = std.unicode.utf8ToUtf16LeStringLiteral("tp-diag");
const diag_guid align(8) = u.Guid{
    .time_low = 0x7C436110,
    .time_mid = 0xAB2A,
    .time_high_and_version = 0x4BBB,
    .clock_seq_high_and_reserved = 0xA8,
    .clock_seq_low = 0x80,
    .node = .{ 0xFE, 0x41, 0x99, 0x5C, 0x9F, 0x82 },
};
var diag: Diag = std.mem.zeroes(Diag);
var diag_sent: Diag = std.mem.zeroes(Diag);

fn publish() void {
    diag.magic = 0x31445054;
    diag.phase = @intFromEnum(phase);
    diag.io_found = @intFromBool(io != null);
    diag.have_desc = @intFromBool(have_desc);
    diag.seen_good = @intFromBool(seen_good);
    diag.reinits = @truncate(reinits);
    diag.cmd_reg = cmd_reg;
    diag.in_len = @truncate(in_len);
    if (io) |d| {
        diag.io_index = d.index;
        diag.io_revision = d.revision;
    }
    if (std.mem.eql(u8, std.mem.asBytes(&diag), std.mem.asBytes(&diag_sent))) return;
    diag_sent = diag;
    // BS | RT access, volatile
    _ = u.system_table.runtime_services.setVariable(diag_name, &diag_guid, 6, @sizeOf(Diag), &diag);
}

fn bs() *u.tables.BootServices {
    return u.system_table.boot_services.?;
}

fn le16(b: []const u8, off: usize) u16 {
    return @as(u16, b[off]) | (@as(u16, b[off + 1]) << 8);
}

// ---------------------------------------------------------------- pointer protocol
fn reset(_: *Pointer, _: bool) callconv(u.cc) u.Status {
    const old = bs().raiseTpl(16);
    defer bs().restoreTpl(old);
    state = std.mem.zeroes(State);
    ready = false;
    return .success;
}

fn getState(_: *Pointer, out: *State) callconv(u.cc) u.Status {
    const old = bs().raiseTpl(16);
    defer bs().restoreTpl(old);
    if (!ready) return .not_ready;
    out.* = state;
    state.x = 0;
    state.y = 0;
    ready = false;
    return .success;
}

fn waitForInput(event: u.Event, _: ?*anyopaque) callconv(u.cc) void {
    if (ready) _ = bs().signalEvent(event);
}

// ---------------------------------------------------------------- I2C requests
fn submit() bool {
    const dev = io orelse return false;
    @memset(&rx, 0);
    result = .not_ready;
    pending = true;
    const st = dev.queue(dev, 0, completion, &packet, &result);
    if (st != .success) {
        pending = false;
        diag.queue_fail +|= 1;
        diag.last_queue_status = @intFromEnum(st);
        return false;
    }
    return true;
}

fn readInput(len: u32) bool {
    packet.count = 1;
    packet.operations[0] = .{ .flags = hid.read_flag, .length = len, .data = &rx };
    return submit();
}

fn readReg(reg: u16, len: u32) bool {
    tx[0] = @truncate(reg);
    tx[1] = @truncate(reg >> 8);
    packet.count = 2;
    packet.operations[0] = .{ .flags = 0, .length = 2, .data = &tx };
    packet.operations[1] = .{ .flags = hid.read_flag, .length = len, .data = &rx };
    return submit();
}

fn command(opcode: u8) bool {
    tx = .{ @truncate(cmd_reg), @truncate(cmd_reg >> 8), 0x00, opcode };
    packet.count = 1;
    packet.operations[0] = .{ .flags = 0, .length = 4, .data = &tx };
    return submit();
}

// ---------------------------------------------------------------- state machine
fn advance(p: Phase, ticks: u32) void {
    phase = p;
    wait = ticks;
    tries = 0;
}

fn enterRun() void {
    advance(.run, 0);
    bad = 0;
    foreign = 0;
    seen_good = false;
}

fn retry() void {
    tries += 1;
    if (tries < 3) {
        wait = 2;
        return;
    }
    // Init failed: fall back to plain polling (the original behaviour).
    enterRun();
}

fn parseDescriptor() bool {
    const d = rx[0..30];
    @memcpy(&diag.desc_head, d[0..12]);
    diag.vendor = le16(d, 20);
    diag.product = le16(d, 22);
    if (le16(d, 0) != 30 or le16(d, 2) != 0x0100) return false; // length, bcdVersion
    if (le16(d, 20) != 0x04F3) return false; // ELAN vendor id
    const max_in = le16(d, 10);
    cmd_reg = le16(d, 16);
    in_len = @min(@max(@as(u32, max_in), 16), rx.len);
    return true;
}

fn recoverIfStuck() void {
    if (seen_good or !have_desc or reinits >= 3) return;
    if (bad < 150 and foreign < 25) return; // ~3 s of nothing usable
    reinits += 1;
    advance(.power_on, 0);
}

fn handleReport(ok: bool) void {
    if (!ok) {
        bad +|= 1;
        diag.bad +|= 1;
        recoverIfStuck();
        return;
    }
    bad = 0;
    const len = le16(&rx, 0);
    if (len == 0) { // idle
        diag.idle +|= 1;
        return;
    }
    @memcpy(&diag.last_report, rx[0..8]);
    if (len < 6 or rx[2] != 1) {
        foreign +|= 1;
        diag.foreign +|= 1;
        recoverIfStuck();
        return;
    }
    seen_good = true;
    diag.good +|= 1;
    const dx: i8 = @bitCast(rx[4]);
    const dy: i8 = @bitCast(rx[5]);
    const left = rx[3] & 1 != 0;
    const right = rx[3] & 2 != 0;
    const old = bs().raiseTpl(16);
    defer bs().restoreTpl(old);
    if (dx == 0 and dy == 0 and left == state.left and right == state.right) return;
    state.x +|= dx;
    state.y +|= dy;
    state.left = left;
    state.right = right;
    ready = true;
}

fn finished(_: u.Event, _: ?*anyopaque) callconv(u.cc) void {
    pending = false;
    if (stopping) return;
    const ok = result == .success;
    diag.phase_status[@intFromEnum(phase)] = @intFromEnum(result);
    diag.phase_count[@intFromEnum(phase)] +|= 1;
    switch (phase) {
        .find => {},
        .read_desc => if (ok and parseDescriptor()) {
            have_desc = true;
            advance(.power_on, 0);
        } else retry(),
        .power_on => if (ok) advance(.reset, 1) else retry(),
        .reset => if (ok) advance(.reset_wait, 5) else retry(), // pad needs ~100 ms
        .reset_wait => {
            if (ok and rx[0] == 0 and rx[1] == 0) {
                enterRun(); // reset acknowledged (0x0000)
            } else {
                tries += 1;
                if (tries > 60) enterRun(); // ~1.2 s, go on best-effort
            }
        },
        .run => handleReport(ok),
    }
}

fn tick(_: u.Event, _: ?*anyopaque) callconv(u.cc) void {
    if (stopping) return;
    publish_div += 1;
    if (publish_div >= 25) { // ~0.5 s, only writes when something changed
        publish_div = 0;
        publish();
    }
    if (pending) return;
    if (wait != 0) {
        wait -= 1;
        return;
    }
    // Firmware or OpenCore may reconnect the I2C stack (ConnectDrivers, option ROM
    // reload, ...) and recreate the child handle: a cached I2cIo would then dangle.
    if (phase != .find) {
        recheck += 1;
        if (recheck >= 50) { // ~1 s
            recheck = 0;
            const now = hid.findTouchpad();
            if (now != io) {
                io = now;
                reinits = 0;
                advance(if (now == null) .find else .read_desc, 0);
                return;
            }
        }
    }
    switch (phase) {
        .find => {
            // Handle may not exist yet (load order / firmware fast path): keep looking.
            diag.find_attempts +|= 1;
            io = hid.findTouchpad();
            if (io == null) {
                wait = 9; // 200 ms
                return;
            }
            advance(.read_desc, 0);
        },
        .read_desc => if (!readReg(hid_desc_reg, 30)) retry(),
        .power_on => if (!command(op_set_power)) retry(),
        .reset => if (!command(op_reset)) retry(),
        .reset_wait, .run => {
            if (!readInput(in_len)) {
                if (phase == .run) {
                    bad +|= 1;
                    recoverIfStuck();
                } else {
                    tries += 1;
                }
            }
        },
    }
}

// Stop polling before the OS takes the I2C controller; let an in-flight transfer end.
fn onExitBootServices(_: u.Event, _: ?*anyopaque) callconv(u.cc) void {
    stopping = true;
    _ = bs().setTimer(timer, .timer_cancel, 0);
    const status: *volatile u.Status = &result;
    var waited: usize = 0;
    while (pending and status.* == .not_ready and waited < 5000) : (waited += 50) {
        _ = bs().stall(50);
    }
    publish();
}

// ---------------------------------------------------------------- entry
const NotifyFn = *const fn (u.Event, ?*anyopaque) callconv(u.cc) void;

pub fn main() u.Status {
    const specs = [_]struct { kind: u32, func: NotifyFn, out: *u.Event }{
        .{ .kind = 0x100, .func = waitForInput, .out = &pointer.wait },
        .{ .kind = 0x200, .func = finished, .out = &completion },
        .{ .kind = 0x80000200, .func = tick, .out = &timer },
        .{ .kind = 0x201, .func = onExitBootServices, .out = &exit_event },
    };
    var made: usize = 0;
    var status: u.Status = .success;
    while (made < specs.len) : (made += 1) {
        status = bs().createEvent(specs[made].kind, 8, specs[made].func, null, specs[made].out);
        if (status != .success) break;
    }
    if (status != .success) {
        for (specs[0..made]) |s| _ = bs().closeEvent(s.out.*);
        return status;
    }

    // TPL_CALLBACK keeps the timer from firing until the protocol is installed.
    const old = bs().raiseTpl(8);
    defer bs().restoreTpl(old);
    status = bs().setTimer(timer, .timer_periodic, tick_100ns);
    if (status == .success) {
        // Zig 0.14.1 declares this parameter as Handle; UEFI takes *Handle.
        const install: *const fn (*u.Handle, *align(8) const u.Guid, u.tables.InterfaceType, *anyopaque) callconv(u.cc) u.Status = @ptrCast(bs().installProtocolInterface);
        var image_handle = u.handle;
        status = install(&image_handle, &pointer_guid, .efi_native_interface, &pointer);
    }
    if (status != .success) {
        for (specs) |s| _ = bs().closeEvent(s.out.*);
    } else {
        publish(); // proves the driver started, even if the touchpad is never found
    }
    return status;
}
