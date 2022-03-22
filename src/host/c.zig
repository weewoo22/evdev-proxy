pub const libinput = @cImport({
    @cInclude("libinput.h");
});
pub const libevdev = @cImport({
    @cInclude("libevdev/libevdev.h");
    @cInclude("libevdev/libevdev-uinput.h");
});
pub const uinput = @cImport({
    @cInclude("linux/uinput.h");
});
