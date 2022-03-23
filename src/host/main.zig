const std = @import("std");
const log = std.log;

const c = @import("./c.zig");

pub fn pressEvDevKeyCombo(fd: c_int) !void {
    c.emit(fd, c.EV_KEY, c.KEY_LEFTCTRL, 1);
    c.emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
    c.emit(fd, c.EV_KEY, c.KEY_RIGHTCTRL, 1);
    c.emit(fd, c.EV_SYN, c.SYN_REPORT, 0);

    c.emit(fd, c.EV_KEY, c.KEY_LEFTCTRL, 0);
    c.emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
    c.emit(fd, c.EV_KEY, c.KEY_RIGHTCTRL, 0);
    c.emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
}

pub fn main() !u8 {
    log.info("Starting evdev-proxy", .{});
    defer log.info("Exiting evdev-proxy", .{});

    // Get new udev library context
    var udev_handle: *c.udev = c.udev_new() orelse {
        log.err("Failed to create udev library context", .{});
        return 1;
    };

    // Create a new libinput context from udev. Notifications about new and removed devices will be
    // provided by udev
    var libinput_handle: *c.libinput = c.libinput_udev_create_context(
        &.{
            .open_restricted = struct {
                pub fn openRestricted(
                    path: [*c]const u8,
                    flags: c_int,
                    user_data: ?*anyopaque,
                ) callconv(.C) c_int {
                    _ = user_data; // Discard unused user data parameter

                    var fd = std.c.open(path, @intCast(c_uint, flags));

                    return if (fd < 0) -1 else fd;
                }
            }.openRestricted,
            .close_restricted = struct {
                pub fn closeRestricted(fd: c_int, user_data: ?*anyopaque) callconv(.C) void {
                    _ = user_data;

                    _ = std.c.close(fd);
                }
            }.closeRestricted,
        },
        null,
        udev_handle,
    ) orelse {
        log.err("Failed to initialized libinput context", .{});

        return 1;
    };
    defer _ = c.libinput_unref(libinput_handle);

    if (c.libinput_udev_assign_seat(libinput_handle, "seat0") != 0) {
        log.err("Failed to assign a seat to libinput context", .{});
        return 1;
    }

    var libinput_fd = c.libinput_get_fd(libinput_handle);
    var epoll_fd = try std.os.epoll_create1(0);
    defer std.os.close(epoll_fd);
    var epoll_event: std.os.linux.epoll_event = std.mem.zeroes(std.os.linux.epoll_event);
    epoll_event.events = std.os.linux.EPOLL.IN;
    epoll_event.data.fd = libinput_fd;
    std.os.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_ADD, libinput_fd, &epoll_event) catch {
        log.err("Failed to configure epoll", .{});
        return 1;
    };
    var epoll_events: [32]std.os.linux.epoll_event = undefined;

    // Create proxy evdev device from scratch
    var proxy_device: *c.libevdev = c.libevdev_new() orelse {
        log.err("Failed to create new libevdev device for evdev-proxy", .{});
        return 1;
    };
    defer c.libevdev_free(proxy_device);

    // Change device name returned by libevdev_get_name()
    c.libevdev_set_name(proxy_device, "EvDev Proxy");

    var ui_dev: ?*c.libevdev_uinput = undefined;
    const err = c.libevdev_uinput_create_from_device(
        proxy_device,
        c.LIBEVDEV_UINPUT_OPEN_MANAGED,
        &ui_dev,
    );
    // Create a uinput device based on our libevdev device
    if (err < 0) {
        log.err("Failed to create uinput device: {s}", .{c.strerror(std.c._errno().*)});
        return 1;
    }
    defer c.libevdev_uinput_destroy(ui_dev);

    const symlink_path = "/dev/input/by-id/evdev-proxy";
    const device_path = c.libevdev_uinput_get_devnode(ui_dev);
    std.fs.deleteFileAbsolute(symlink_path) catch {};
    try std.os.symlink(std.mem.span(device_path), symlink_path);

    while (true) {
        // Wait for I/O from epoll file descriptor
        _ = std.os.epoll_wait(epoll_fd, epoll_events[0..epoll_events.len], 0);

        if (c.libinput_dispatch(libinput_handle) < 0) {
            log.err("Failed to dispatch libinput events", .{});
            return 1;
        }

        // Retrieve events from libinput event queue, or continue if no event is available
        while (c.libinput_get_event(libinput_handle)) |event| {
            defer c.libinput_event_destroy(event);

            switch (c.libinput_event_get_type(event)) {
                c.LIBINPUT_EVENT_DEVICE_ADDED, c.LIBINPUT_EVENT_DEVICE_REMOVED => |event_type| {
                    const device = c.libinput_event_get_device(event);
                    const device_name = c.libinput_device_get_name(device);

                    if (event_type == c.LIBINPUT_EVENT_DEVICE_ADDED) {
                        log.info("New event device added: \"{s}\"", .{device_name});
                    } else {
                        log.info("Device removed: \"{s}\"", .{device_name});
                    }
                },
                // Keyboard event representing a key press/release
                c.LIBINPUT_EVENT_KEYBOARD_KEY => {
                    const keyboard_event = c.libinput_event_get_keyboard_event(event);
                    const key_code = c.libinput_event_keyboard_get_key(keyboard_event);
                    const key_state = c.libinput_event_keyboard_get_key_state(keyboard_event);

                    log.debug("Keyboard event: {} {}", .{ key_code, key_state });

                    if (c.libevdev_uinput_write_event(
                        ui_dev,
                        c.EV_KEY, // Event type
                        key_code, // Event code
                        if (key_state == c.LIBINPUT_KEY_STATE_PRESSED) 1 else 0, // Event value
                    ) < 0) {
                        log.err("Unable to forward keyboard event", .{});
                    }
                    if (c.libevdev_uinput_write_event(
                        ui_dev,
                        c.EV_SYN,
                        c.SYN_REPORT,
                        0,
                    ) < 0) {
                        log.err("Unable to forward report for keyboard event", .{});
                    }
                },
                c.LIBINPUT_EVENT_POINTER_MOTION => {
                    // const pointer_event = c.libinput_event_get_pointer_event(event);
                },
                c.LIBINPUT_EVENT_POINTER_MOTION_ABSOLUTE => {
                    // const pointer_event = c.libinput_event_get_pointer_event(event);

                    // if (c.libevdev_uinput_write_event() < 0) {}
                },
                else => continue,
            }
        }
    }

    return 0;
}
