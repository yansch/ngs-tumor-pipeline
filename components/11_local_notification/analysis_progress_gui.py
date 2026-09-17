#!/usr/bin/env python3
import os
import tkinter as tk
from tkinter import ttk
import json
from pathlib import Path

# Use env var if set, otherwise fall back to hardcoded path
base_dir = Path(os.environ.get(
    "NOTIFICATION_DIR",
    "/mnt/pipelines/ngs-tumor-pipeline/components/11_local_notification"
))
ctrl_file = base_dir / ".analysis_gui_ctrl"
ctrl_file.write_text("")  # clear at start

root = tk.Tk()
root.title("NGS Tumor Pipeline progress")
root.resizable(False, False)

# Bigger window and fonts for 2560x1440
root.minsize(900, 280)
root.option_add("*Font", "Sans 20")

overall_var = tk.IntVar()
case_var = tk.IntVar()

main_frame = ttk.Frame(root, padding=25)
main_frame.grid(row=0, column=0, sticky="nsew")
root.columnconfigure(0, weight=1)
root.rowconfigure(0, weight=1)

# Overall progress
overall_title = ttk.Label(main_frame, text="Overall progress:")
overall_title.grid(row=0, column=0, sticky="w", pady=(0, 8))

overall_bar = ttk.Progressbar(
    main_frame,
    variable=overall_var,
    maximum=100,
    length=700,
    mode="determinate"
)
overall_bar.grid(row=0, column=1, padx=(15, 0), pady=(0, 8))

overall_label = ttk.Label(main_frame, text="", width=70, anchor="w")
overall_label.grid(row=1, column=0, columnspan=2, sticky="w", pady=(0, 20))

# Current case progress
case_title = ttk.Label(main_frame, text="Current case:")
case_title.grid(row=2, column=0, sticky="w", pady=(0, 8))

case_bar = ttk.Progressbar(
    main_frame,
    variable=case_var,
    maximum=100,
    length=700,
    mode="determinate"
)
case_bar.grid(row=2, column=1, padx=(15, 0), pady=(0, 8))

case_label = ttk.Label(main_frame, text="", width=70, anchor="w")
case_label.grid(row=3, column=0, columnspan=2, sticky="w")

def read_ctrl():
    try:
        lines = ctrl_file.read_text().splitlines()
    except Exception:
        lines = []
    ctrl_file.write_text("")  # clear after reading

    for line in lines:
        if not line.strip():
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue
        cmd = msg.get("cmd")
        if cmd == "overall":
            pct = int(msg["value"])
            text = msg.get("text", "")
            overall_var.set(pct)
            if text:
                overall_label.config(text=text)
        elif cmd == "case":
            pct = int(msg["value"])
            text = msg.get("text", "")
            case_var.set(pct)
            if text:
                case_label.config(text=text)
        elif cmd == "title":
            root.title(msg["value"])
        elif cmd == "close":
            root.destroy()
            return

    root.after(100, read_ctrl)

root.after(100, read_ctrl)
root.mainloop()