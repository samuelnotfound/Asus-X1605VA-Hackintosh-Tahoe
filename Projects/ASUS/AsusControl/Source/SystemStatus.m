#import "SystemStatus.h"
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <CoreGraphics/CoreGraphics.h>
#include <mach/mach.h>
#include <math.h>

@interface AsusSystemStatus () {
    host_cpu_load_info_data_t _previous;
    BOOL _hasCPU;
}
@end
@implementation AsusSystemStatus
- (NSDictionary *)sample {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    host_cpu_load_info_data_t cpu = {0};
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    mach_port_t host = mach_host_self();
    if (host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&cpu, &count) == KERN_SUCCESS) {
        if (_hasCPU) {
            uint64_t total = 0, idle = 0;
            for (unsigned i = 0; i < CPU_STATE_MAX; ++i) {
                uint32_t delta = cpu.cpu_ticks[i] - _previous.cpu_ticks[i];
                total += delta; if (i == CPU_STATE_IDLE) idle = delta;
            }
            if (total) result[@"CPUPercent"] = @((total - idle) * 100.0 / total);
        }
        _previous = cpu; _hasCPU = YES;
    }
    vm_statistics64_data_t memory = {0}; count = HOST_VM_INFO64_COUNT;
    vm_size_t page = 0;
    if (host_page_size(host, &page) == KERN_SUCCESS && host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&memory, &count) == KERN_SUCCESS) {
        uint64_t total = NSProcessInfo.processInfo.physicalMemory;
        uint64_t used = ((uint64_t)memory.active_count + memory.wire_count + memory.compressor_page_count) * page;
        used = MIN(used, total);
        result[@"MemoryUsed"] = @(used); result[@"MemoryTotal"] = @(total);
        if (total) result[@"MemoryPercent"] = @(used * 100.0 / total);
    }
    mach_port_deallocate(mach_task_self(), host);
    result[@"LowPowerMode"] = @(NSProcessInfo.processInfo.lowPowerModeEnabled);
    result[@"Uptime"] = @(NSProcessInfo.processInfo.systemUptime);
    double idle = CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType);
    if (isfinite(idle) && idle >= 0) result[@"IdleSeconds"] = @(idle);
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (info) {
        CFStringRef providing = IOPSGetProvidingPowerSourceType(info);
        if (providing && (CFEqual(providing, CFSTR(kIOPSACPowerValue)) || CFEqual(providing, CFSTR(kIOPSBatteryPowerValue)))) {
            result[@"PowerSourceKnown"] = @YES;
            result[@"ACPower"] = @([(__bridge NSString *)providing isEqualToString:@kIOPSACPowerValue]);
        }
        CFArrayRef sources = IOPSCopyPowerSourcesList(info);
        if (sources) {
            for (id item in (__bridge NSArray *)sources) {
                NSDictionary *battery = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(info, (__bridge CFTypeRef)item);
                if (![battery[@kIOPSTypeKey] isEqual:@kIOPSInternalBatteryType]) continue;
                double maximum = [battery[@kIOPSMaxCapacityKey] doubleValue];
                if (maximum > 0) {
                    result[@"BatteryKnown"] = @YES;
                    result[@"BatteryPercent"] = @(MAX(0, MIN(100, [battery[@kIOPSCurrentCapacityKey] doubleValue] * 100.0 / maximum)));
                }
                result[@"Charging"] = @([battery[@kIOPSIsChargingKey] boolValue]);
                NSString *health = battery[@"BatteryHealth"];
                if ([health isKindOfClass:NSString.class]) result[@"BatteryHealth"] = health;
            }
            CFRelease(sources);
        }
        CFRelease(info);
    }
    NSURL *disk = [NSURL fileURLWithPath:@"/"];
    NSDictionary *storage = [disk resourceValuesForKeys:@[NSURLVolumeTotalCapacityKey, NSURLVolumeAvailableCapacityKey, NSURLVolumeNameKey] error:NULL];
    NSNumber *total = storage[NSURLVolumeTotalCapacityKey], *free = storage[NSURLVolumeAvailableCapacityKey];
    if (total && free && total.unsignedLongLongValue > 0) {
        result[@"DiskTotal"] = total; result[@"DiskFree"] = free;
        result[@"DiskName"] = storage[NSURLVolumeNameKey] ?: @"Startup disk";
    }
    return result;
}
@end
