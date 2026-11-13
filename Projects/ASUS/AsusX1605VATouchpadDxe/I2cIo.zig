const std = @import("std");
const uefi = std.os.uefi;

pub const read_flag: u32 = 1; // I2C_FLAG_READ

pub const Operation = extern struct { flags: u32, length: u32, data: [*]u8 };
pub const Packet = extern struct { count: usize, operations: [2]Operation };
pub const I2cIo = extern struct {
    queue: *const fn (*I2cIo, usize, ?uefi.Event, *Packet, ?*uefi.Status) callconv(uefi.cc) uefi.Status,
    device_guid: ?*const uefi.Guid,
    index: u32,
    revision: u32,
};
const io_guid align(8) = [16]u8{ 0x6b, 0x3e, 0x0a, 0xb6, 0xc4, 0x18, 0xe5, 0x46, 0xa2, 0x9a, 0xc9, 0xa1, 0x06, 0x65, 0xa2, 0x8e };
const touchpad_guid = [16]u8{ 0x14, 0xf4, 0xb3, 0xfd, 0xf5, 0xc0, 0x89, 0x43, 0x99, 0xf9, 0xff, 0xb5, 0xfc, 0xbd, 0x6e, 0x9c };

/// Returns the ASUE1306 I2C child, or null if it does not exist (yet) or is ambiguous.
pub fn findTouchpad() ?*I2cIo {
    const services = uefi.system_table.boot_services orelse return null;
    const guid: *align(8) const uefi.Guid = @ptrCast(&io_guid);
    var count: usize = 0;
    var handles: [*]uefi.Handle = undefined;
    const status = services.locateHandleBuffer(@enumFromInt(2), guid, null, &count, &handles);
    if (@intFromEnum(status) != 0) return null;
    defer _ = services.freePool(@ptrCast(handles));
    var match: ?*I2cIo = null;
    for (handles[0..count]) |handle| {
        var interface: ?*anyopaque = null;
        if (@intFromEnum(services.handleProtocol(handle, guid, &interface)) != 0) continue;
        const io: *I2cIo = @ptrCast(@alignCast(interface orelse continue));
        if (io.index != 1 or io.revision != 1) continue;
        const device_guid = io.device_guid orelse continue;
        if (!std.mem.eql(u8, std.mem.asBytes(device_guid), &touchpad_guid)) continue;
        if (match != null) return null;
        match = io;
    }
    return match;
}
