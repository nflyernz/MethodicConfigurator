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


def run_reduced(mode: str) -> None:
    """Vary one layout operation after a bare root lifecycle."""
    mark("prior-root: before bare Tk()")
    prior = tk.Tk()
    mark("prior-root: after bare Tk(); before destroy")
    prior.destroy()
    mark("prior-root: after destroy")

    mark("reduced: before second Tk()")
    root = tk.Tk()
    mark("reduced: after second Tk()")
    try:
        root.withdraw()
        mark("reduced: after withdraw")
        if mode == "theme-only":
            mark("reduced: before alt theme")
            ttk.Style(root).theme_use("alt")
            mark("reduced: after alt theme")
        elif mode == "dpi-only":
            mark("reduced: before 96-DPI scaling")
            root.tk.call("tk", "scaling", 96 / 72)
            mark("reduced: after 96-DPI scaling")
        elif mode == "font-only":
            mark("reduced: before named-font configuration")
            for name in tkfont.names(root):
                if name.startswith("Tk"):
                    tkfont.nametofont(name, root=root).configure(family="Arial", size=10)
            mark("reduced: after named-font configuration")
        mark("reduced: before update_idletasks")
        root.update_idletasks()
        mark("reduced: after update_idletasks")
    finally:
        mark("reduced: before destroy")
        root.destroy()
        mark("reduced: after destroy")


def run_no_second_withdrawal() -> None:
    """Process the second root's idle events without withdrawing it."""
    mark("no-withdraw: before first Tk()")
    first = tk.Tk()
    mark("no-withdraw: after first Tk(); before destroy")
    first.destroy()
    mark("no-withdraw: after first destroy")
    mark("no-withdraw: before second Tk()")
    second = tk.Tk()
    mark("no-withdraw: after second Tk(); before update_idletasks")
    try:
        second.update_idletasks()
        mark("no-withdraw: after update_idletasks")
    finally:
        mark("no-withdraw: before second destroy")
        second.destroy()
        mark("no-withdraw: after second destroy")


def run_one_interpreter() -> None:
    """Destroy a Toplevel while retaining its root interpreter."""
    mark("one-interpreter: before Tk()")
    root = tk.Tk()
    mark("one-interpreter: after Tk()")
    try:
        mark("one-interpreter: before Toplevel()")
        window = tk.Toplevel(root)
        mark("one-interpreter: after Toplevel(); before destroy")
        window.destroy()
        mark("one-interpreter: after Toplevel.destroy(); before root.withdraw")
        root.withdraw()
        mark("one-interpreter: after root.withdraw(); before update_idletasks")
        root.update_idletasks()
        mark("one-interpreter: after update_idletasks")
    finally:
        mark("one-interpreter: before root.destroy")
        root.destroy()
        mark("one-interpreter: after root.destroy")


def main() -> None:
    """Run one independently launched diagnostic mode."""
    if len(sys.argv) == 2 and sys.argv[1] in {"no-withdraw", "one-interpreter"}:
        mark(f"mode: {sys.argv[1]}; Python: {sys.version}; executable: {sys.executable}")
        if sys.argv[1] == "no-withdraw":
            run_no_second_withdrawal()
        else:
            run_one_interpreter()
        mark("result: completed")
        return
    if len(sys.argv) == 2 and sys.argv[1] in {"minimum", "theme-only", "dpi-only", "font-only"}:
        mark(f"mode: {sys.argv[1]}; Python: {sys.version}; executable: {sys.executable}")
        run_reduced(sys.argv[1])
        mark("result: completed")
        return
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
