pub usingnamespace @cImport({
    @cInclude("libinput.h");
    @cInclude("libevdev/libevdev.h");
    @cInclude("libevdev/libevdev-uinput.h");
    @cInclude("string.h"); // strerror(3)
    // @cInclude("linux/uinput.h"); // EV_KEY, EV_REL, etc.
});
