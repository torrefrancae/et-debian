#!/usr/bin/env python3
"""Centered green overlay while Shift, Ctrl, or Cmd is held (et-debian / et-debianvm)."""
import fcntl
import os
import signal
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk
import cairo
from Xlib.display import Display

# X modifier map indexes: Shift=0, Ctrl=2, Mod4/Super(Cmd)=6
# Display order: Ctrl, Shift, Cmd -> "Ctrl+Shift"
CHIPS = (
    (2, "Ctrl"),
    (0, "Shift"),
    (6, "Cmd"),
)
PAD = 50
RADIUS = 24

CSS = b"""
window { background-color: rgba(0,0,0,0); }
label {
  font-family: sans-serif;
  font-size: 96px;
  font-weight: 700;
  color: #ffffff;
}
"""


def keymap_bytes(raw):
    if isinstance(raw, (bytes, bytearray)):
        return raw
    if isinstance(raw, str):
        return raw.encode("latin1")
    return bytes(raw)


def key_down(data, code):
    return bool(data[code >> 3] & (1 << (code & 7)))


def singleton():
    disp = os.environ.get("DISPLAY", "none").replace("/", "_").replace(":", "")
    path = "/tmp/modifier-hud-%s-%s.lock" % (os.getuid(), disp)
    handle = open(path, "w")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit(0)
    handle.write(str(os.getpid()))
    handle.flush()
    return handle


class Hud:
    def __init__(self, preview):
        self.dpy = Display()
        modmap = self.dpy.get_modifier_mapping()
        self.watch = []
        for index, label in CHIPS:
            codes = [code for code in modmap[index] if code]
            self.watch.append((label, codes))
        self.preview = preview
        self.shown = None

        self.win = Gtk.Window(type=Gtk.WindowType.POPUP)
        self.win.set_title("modifier-hud")
        self.win.set_decorated(False)
        self.win.set_accept_focus(False)
        self.win.set_focus_on_map(False)
        self.win.set_skip_taskbar_hint(True)
        self.win.set_skip_pager_hint(True)
        self.win.set_keep_above(True)
        self.win.set_type_hint(Gdk.WindowTypeHint.NOTIFICATION)
        self.win.stick()
        self.win.set_app_paintable(True)
        screen = Gdk.Screen.get_default()
        visual = screen.get_rgba_visual()
        if visual is not None:
            self.win.set_visual(visual)
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        self.label = Gtk.Label()
        self.label.set_justify(Gtk.Justification.CENTER)
        self.label.set_halign(Gtk.Align.CENTER)
        self.label.set_valign(Gtk.Align.CENTER)
        self.win.add(self.label)
        self.win.connect("draw", self.on_draw)
        self.win.connect("realize", self.pass_through)
        self.win.connect("size-allocate", lambda *_args: self.apply_shape())
        GLib.timeout_add(40, self.poll)
        if preview:
            GLib.timeout_add(1600, Gtk.main_quit)

    def round_rect(self, cr, x, y, width, height, radius):
        cr.new_sub_path()
        cr.arc(x + width - radius, y + radius, radius, -3.14159 / 2, 0)
        cr.arc(x + width - radius, y + height - radius, radius, 0, 3.14159 / 2)
        cr.arc(x + radius, y + height - radius, radius, 3.14159 / 2, 3.14159)
        cr.arc(x + radius, y + radius, radius, 3.14159, 3 * 3.14159 / 2)
        cr.close_path()

    def on_draw(self, _widget, cr):
        width = self.win.get_allocated_width()
        height = self.win.get_allocated_height()
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)
        self.round_rect(cr, 4, 4, max(1, width - 8), max(1, height - 8), RADIUS)
        # solid green fill
        cr.set_source_rgb(0.09, 0.64, 0.29)
        cr.fill()
        return False

    def pass_through(self, _widget):
        gdk_window = self.win.get_window()
        if gdk_window is not None:
            gdk_window.input_shape_combine_region(cairo.Region(), 0, 0)

    def apply_shape(self):
        if self.win.get_window() is None:
            return
        width = self.win.get_allocated_width()
        height = self.win.get_allocated_height()
        if width < 20 or height < 20:
            return
        surface = cairo.ImageSurface(cairo.FORMAT_A1, width, height)
        cr = cairo.Context(surface)
        self.round_rect(cr, 4, 4, width - 8, height - 8, RADIUS)
        cr.fill()
        region = Gdk.cairo_region_create_from_surface(surface)
        self.win.shape_combine_region(region)

    def active_labels(self):
        if self.preview:
            return [label for _index, label in CHIPS]
        data = keymap_bytes(self.dpy.query_keymap())
        found = []
        for label, codes in self.watch:
            if any(key_down(data, code) for code in codes):
                found.append(label)
        return found

    def place(self):
        display = Gdk.Display.get_default()
        _screen, x, y = display.get_default_seat().get_pointer().get_position()
        geo = display.get_monitor_at_point(x, y).get_geometry()
        text = self.label.get_preferred_size()[1]
        # hug the text: ~50px padding each side, not near-fullscreen wide
        width = max(120, text.width + PAD * 2)
        height = max(text.height + PAD * 2, 1)
        self.win.set_size_request(width, height)
        self.win.resize(width, height)
        self.win.move(
            geo.x + (geo.width - width) // 2,
            geo.y + (geo.height - height) // 2,
        )
        self.apply_shape()

    def poll(self):
        try:
            labels = self.active_labels()
        except Exception:
            Gtk.main_quit()
            return False
        token = tuple(labels)
        if token == self.shown and self.win.get_visible():
            return True
        self.shown = token
        if not labels:
            self.win.hide()
            return True
        self.label.set_text("+".join(labels))
        self.win.show_all()
        self.place()
        self.pass_through(self.win)
        self.win.queue_draw()
        return True


def main():
    if not os.environ.get("DISPLAY"):
        return 0
    preview = "--test" in sys.argv
    if not preview:
        singleton()
    signal.signal(signal.SIGTERM, lambda *_args: Gtk.main_quit())
    Hud(preview)
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
