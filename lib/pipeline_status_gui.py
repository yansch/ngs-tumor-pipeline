#!/usr/bin/env python3
"""
NGS Tumor Pipeline Status Monitor
Standalone GUI for Technical Assistants to monitor pipeline execution on the Omen workstation.
Reads /tmp/ngs_pipeline_status.json asynchronously.
"""

import json
import os
import sys
import tkinter as tk
from tkinter import ttk
from pathlib import Path

STATUS_FILE = Path(os.environ.get("NGS_STATUS_FILE", "/tmp/ngs_pipeline_status.json"))

class PipelineStatusApp:
    def __init__(self, root):
        self.root = root
        self.root.title("🧬 NGS Tumor Pipeline Status")
        self.root.minsize(780, 420)
        self.root.resizable(True, True)

        # Style configuration
        self.style = ttk.Style()
        try:
            self.style.theme_use("clam")
        except Exception:
            pass

        # Configure custom styles
        self.root.option_add("*Font", "Sans 11")

        # Variables
        self.var_status_badge = tk.StringVar(value="Checking status...")
        self.var_notice = tk.StringVar(value="")
        self.var_overall_lbl = tk.StringVar(value="Overall Progress: 0%")
        self.var_case_lbl = tk.StringVar(value="Current Case: -")
        self.var_step_lbl = tk.StringVar(value="Current Step: -")
        self.var_meta_lbl = tk.StringVar(value="")
        self.var_overall_pct = tk.DoubleVar(value=0.0)
        self.var_case_pct = tk.DoubleVar(value=0.0)

        self._build_ui()
        self._poll_status()

    def _build_ui(self):
        # Outer container
        main_frame = ttk.Frame(self.root, padding=20)
        main_frame.pack(fill=tk.BOTH, expand=True)

        # Header banner frame
        self.header_frame = tk.Frame(main_frame, bg="#2b2b2b", padx=16, pady=12)
        self.header_frame.pack(fill=tk.X, pady=(0, 15))

        self.lbl_title = tk.Label(
            self.header_frame,
            text="🧬 NGS TUMOR PIPELINE",
            font=("Sans", 16, "bold"),
            fg="#ffffff",
            bg="#2b2b2b"
        )
        self.lbl_title.pack(side=tk.LEFT)

        self.lbl_badge = tk.Label(
            self.header_frame,
            textvariable=self.var_status_badge,
            font=("Sans", 11, "bold"),
            fg="#ffffff",
            bg="#555555",
            padx=10,
            pady=4
        )
        self.lbl_badge.pack(side=tk.RIGHT)

        # Notice Card
        self.notice_frame = tk.Frame(main_frame, bg="#e8f4f8", padx=14, pady=10, relief=tk.GROOVE, bd=1)
        self.notice_frame.pack(fill=tk.X, pady=(0, 15))

        self.lbl_notice = tk.Label(
            self.notice_frame,
            textvariable=self.var_notice,
            font=("Sans", 11),
            fg="#1a4968",
            bg="#e8f4f8",
            anchor="w",
            justify=tk.LEFT
        )
        self.lbl_notice.pack(fill=tk.X)

        # Progress Section
        prog_group = ttk.LabelFrame(main_frame, text=" Progress Details ", padding=15)
        prog_group.pack(fill=tk.BOTH, expand=True, pady=(0, 15))

        # 1. Overall Progress
        lbl_overall_title = ttk.Label(prog_group, textvariable=self.var_overall_lbl, font=("Sans", 11, "bold"))
        lbl_overall_title.pack(anchor="w", pady=(0, 4))

        self.bar_overall = ttk.Progressbar(
            prog_group,
            variable=self.var_overall_pct,
            maximum=100,
            mode="determinate"
        )
        self.bar_overall.pack(fill=tk.X, pady=(0, 12))

        # 2. Case & Step Progress
        lbl_case_title = ttk.Label(prog_group, textvariable=self.var_case_lbl, font=("Sans", 11, "bold"))
        lbl_case_title.pack(anchor="w", pady=(0, 4))

        self.bar_case = ttk.Progressbar(
            prog_group,
            variable=self.var_case_pct,
            maximum=100,
            mode="determinate"
        )
        self.bar_case.pack(fill=tk.X, pady=(0, 4))

        lbl_step = ttk.Label(prog_group, textvariable=self.var_step_lbl, foreground="#444444")
        lbl_step.pack(anchor="w")

        # Footer / Metadata
        footer_frame = ttk.Frame(main_frame)
        footer_frame.pack(fill=tk.X, side=tk.BOTTOM)

        lbl_meta = ttk.Label(footer_frame, textvariable=self.var_meta_lbl, font=("Sans", 9), foreground="#666666")
        lbl_meta.pack(side=tk.LEFT)

        btn_close = ttk.Button(footer_frame, text="Close Window", command=self.root.destroy)
        btn_close.pack(side=tk.RIGHT, padx=(8, 0))

        btn_refresh = ttk.Button(footer_frame, text="↻ Refresh", command=self._poll_status)
        btn_refresh.pack(side=tk.RIGHT)

    def _read_status_file(self):
        if not STATUS_FILE.exists():
            return None
        try:
            content = STATUS_FILE.read_text(encoding="utf-8").strip()
            if not content:
                return None
            return json.loads(content)
        except Exception:
            return None

    def _poll_status(self):
        data = self._read_status_file()

        if data is None or not data.get("running", False):
            # Idle / Inactive state
            self.lbl_badge.config(text="🟢 IDLE / BEREIT", bg="#2e7d32", fg="#ffffff")
            self.notice_frame.config(bg="#e8f5e9", relief=tk.GROOVE)
            self.lbl_notice.config(
                text="✅ Aktuell läuft keine Pipeline-Berechnung.\nDer Laptop kann normal verwendet oder heruntergefahren werden.",
                fg="#1b5e20",
                bg="#e8f5e9"
            )
            if data:
                total = data.get("total_cases", 0)
                msg = data.get("message", "Letzte Ausführung abgeschlossen.")
                last_update = data.get("last_update", "-")
                self.var_overall_lbl.set(f"Gesamtfortschritt: 100% ({total} Fälle)")
                self.var_case_lbl.set("Status: Abgeschlossen")
                self.var_step_lbl.set(f"Ergebnis: {msg}")
                self.var_meta_lbl.set(f"Letztes Update: {last_update}")
                self.var_overall_pct.set(100)
                self.var_case_pct.set(100)
            else:
                self.var_overall_lbl.set("Gesamtfortschritt: -")
                self.var_case_lbl.set("Status: Kein aktiver Durchlauf")
                self.var_step_lbl.set("Es liegen keine aktuellen Statusdaten vor.")
                self.var_meta_lbl.set("Statusdatei: nicht vorhanden")
                self.var_overall_pct.set(0)
                self.var_case_pct.set(0)
        else:
            # Active running state
            case_idx = data.get("case_index", 0)
            total_cases = data.get("total_cases", 0)
            case_label = data.get("case_label", "Unbekannt")
            step_name = data.get("step_name", "In Bearbeitung")
            overall_pct = data.get("overall_percent", 0)
            case_pct = data.get("case_percent", 0)
            last_update = data.get("last_update", "-")
            start_time = data.get("start_time", "-")
            pid = data.get("pid", "-")

            self.lbl_badge.config(text="🧬 IN ARBEIT (RUNNING)", bg="#d84315", fg="#ffffff")
            self.notice_frame.config(bg="#fff3e0", relief=tk.GROOVE)
            self.lbl_notice.config(
                text=f"⚠️ Pipeline läuft aktuell (PID: {pid})!\nBitte den Laptop NICHT ausschalten oder neustarten.",
                fg="#bf360c",
                bg="#fff3e0"
            )

            self.var_overall_lbl.set(f"Gesamtfortschritt: {overall_pct}% (Fall {case_idx} von {total_cases})")
            self.var_case_lbl.set(f"Aktueller Fall: {case_label} ({case_pct}%)")
            self.var_step_lbl.set(f"Schritt: {step_name}")
            self.var_meta_lbl.set(f"Start: {start_time}  |  Letztes Update: {last_update}")

            self.var_overall_pct.set(overall_pct)
            self.var_case_pct.set(case_pct)

        # Schedule next poll in 1 second
        self.root.after(1000, self._poll_status)

def main():
    root = tk.Tk()
    app = PipelineStatusApp(root)
    root.mainloop()

if __name__ == "__main__":
    main()
