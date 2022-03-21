const std = @import("std");

pub fn build(builder: *std.build.Builder) void {
    const target = builder.standardTargetOptions(.{});
    const mode = builder.standardReleaseOptions();

    const host = builder.addExecutable("evdev-proxy", "src/host/main.zig");
    host.setTarget(target);
    host.setBuildMode(mode);
    host.install();

    const guest = builder.addExecutable("evdev-proxy", "src/guest/main.zig");
    guest.setTarget(.{ .cpu_arch = .x86_64, .os_tag = .windows });
    guest.setBuildMode(mode);
    guest.install();

    const run_cmd = host.run();
    run_cmd.step.dependOn(builder.getInstallStep());
    if (builder.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = builder.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
