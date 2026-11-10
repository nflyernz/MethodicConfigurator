"""
Reproduce a Tk root lifecycle followed by an idle layout update.

This file is part of ArduPilot Methodic Configurator. https://github.com/ArduPilot/MethodicConfigurator

SPDX-FileCopyrightText: 2026 nflyernz <319460892+nflyernz@users.noreply.github.com>

SPDX-License-Identifier: GPL-3.0-or-later
"""

# ruff: noqa: INP001, T201, S101

import sys
import tkinter as tk
from tkinter import font as tkfont
from tkinter import ttk


def mark(message: str) -> None:
    """Flush a marker before a possible native crash."""
    print(message, flush=True)


def run_control() -> None:
    """Match the layout_root fixture's initial display configuration and cleanup."""
    mark("control: before Tk()")
    root = tk.Tk()
    mark("control: after Tk()")
    try:
        root.withdraw()
        mark("control: after withdraw")
        mark(f"runtime: Tcl {root.tk.call('info', 'patchlevel')}; Tk {root.tk.call('package', 'require', 'Tk')}")

        original_scaling = float(root.tk.call("tk", "scaling"))
        fonts = {name: tkfont.nametofont(name, root=root) for name in tkfont.names(root) if name.startswith("Tk")}
        original_fonts = {name: font.configure() for name, font in fonts.items()}
        style = ttk.Style(root)
        original_theme = style.theme_use()
        try:
            mark("control: before theme and 96-DPI font setup")
            style.theme_use("alt")
            root.tk.call("tk", "scaling", 96 / 72)
            for name in tkfont.names(root):
                if name.startswith("Tk"):
                    tkfont.nametofont(name, root=root).configure(family="Arial", size=10)
            mark("control: before initial update_idletasks")
            root.update_idletasks()
            mark("control: after initial update_idletasks")
        finally:
            mark("control: before display restoration")
            root.tk.call("tk", "scaling", original_scaling)
            for name, font in fonts.items():
                original_font = original_fonts[name]
                assert original_font is not None
                font.configure(**original_font)
            style.theme_use(original_theme)
            root.update_idletasks()
            mark("control: after display restoration")
    finally:
        mark("control: before destroy")
        root.destroy()
        mark("control: after destroy")


def main() -> None:
    """Run one independently launched diagnostic mode."""
    if len(sys.argv) != 2 or sys.argv[1] not in {"control", "prior-root"}:
        message = "usage: tk_root_idle_reproducer.py {control|prior-root}"
        raise SystemExit(message)
    mark(f"mode: {sys.argv[1]}; Python: {sys.version}; executable: {sys.executable}")
    if sys.argv[1] == "prior-root":
        mark("prior-root: before bare Tk()")
        prior = tk.Tk()
        mark("prior-root: after bare Tk(); before destroy")
        prior.destroy()
        mark("prior-root: after destroy")
    run_control()
    mark("result: completed")


if __name__ == "__main__":
    main()
