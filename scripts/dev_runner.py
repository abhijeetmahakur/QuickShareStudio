#!/usr/bin/env python3
"""
QuickShare Studio - Intelligent Live Development Runner
======================================================
Watches project files and drives Flutter's interactive CLI:
- Triggers Hot Reload ('r') automatically upon saving Dart source files.
- Automatically falls back to Hot Restart ('R') when changes cannot be applied via hot reload
  (or when structural files like pubspec.yaml / assets are modified).
- Keeps the running application alive on compilation errors and displays clean error diagnostics.
- Provides interactive terminal commands ('r', 'R', 'h', 'q').
"""

import os
import sys
import time
import queue
import shutil
import threading
import subprocess
from pathlib import Path

# Ensure UTF-8 output streams on Windows
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# ANSI Color Codes for Windows Terminal / PowerShell / Modern Terminals
COLOR_RESET = "\033[0m"
COLOR_BOLD = "\033[1m"
COLOR_LIME = "\033[38;2;163;230;53m"      # QuickShare lime accent #A3E635
COLOR_GREEN = "\033[92m"
COLOR_YELLOW = "\033[93m"
COLOR_RED = "\033[91m"
COLOR_CYAN = "\033[96m"
COLOR_GRAY = "\033[90m"

# Enable Windows VT100 terminal mode if possible
if sys.platform == "win32":
    try:
        import ctypes
        kernel32 = ctypes.windll.kernel32
        hStdOut = kernel32.GetStdHandle(-11)
        mode = ctypes.c_ulong()
        kernel32.GetConsoleMode(hStdOut, ctypes.byref(mode))
        mode.value |= 0x0004  # ENABLE_VIRTUAL_TERMINAL_PROCESSING
        kernel32.SetConsoleMode(hStdOut, mode)
    except Exception:
        pass


class DevRunner:
    def __init__(self, project_root: Path, device: str = "chrome", web_port: int = 52835):
        self.project_root = project_root.resolve()
        self.device = device
        self.web_port = web_port
        self.process = None
        self.is_running = True
        self.last_reload_rejected = False
        self.last_reload_time = 0
        self.compile_error_lines = []
        self.in_compile_error = False
        self.input_queue = queue.Queue()

        # Watched directories and files
        self.watch_dirs = [
            self.project_root / "lib",
            self.project_root / "assets",
        ]
        self.watch_files = [
            self.project_root / "pubspec.yaml",
            self.project_root / "web" / "index.html",
        ]

        # File snapshot: path -> mtime
        self.file_snapshots = {}

    def log(self, prefix: str, message: str, color: str = COLOR_RESET):
        timestamp = time.strftime("%H:%M:%S")
        print(f"{COLOR_GRAY}[{timestamp}]{COLOR_RESET} {color}{prefix}{COLOR_RESET} {message}")

    def find_flutter(self) -> str:
        """Locates the flutter executable."""
        candidates = [
            shutil.which("flutter.bat"),
            shutil.which("flutter"),
            r"C:\flutter\bin\flutter.bat",
            r"C:\src\flutter\bin\flutter.bat",
            str(Path.home() / "flutter" / "bin" / "flutter.bat"),
        ]
        for c in candidates:
            if c and os.path.exists(c):
                return c
        return "flutter"

    def scan_watched_files(self) -> dict:
        """Scans watched directories and files, returning {abs_path: mtime}."""
        snapshot = {}
        for wdir in self.watch_dirs:
            if not wdir.exists():
                continue
            for root, dirs, files in os.walk(wdir):
                # Ignore hidden directories and build outputs
                dirs[:] = [d for d in dirs if not d.startswith(".") and d != "build"]
                for f in files:
                    if f.startswith("."):
                        continue
                    full_path = Path(root) / f
                    try:
                        snapshot[str(full_path)] = full_path.stat().st_mtime
                    except OSError:
                        pass

        for wfile in self.watch_files:
            if wfile.exists():
                try:
                    snapshot[str(wfile)] = wfile.stat().st_mtime
                except OSError:
                    pass

        return snapshot

    def detect_changes(self, old_snap: dict, new_snap: dict) -> list:
        """Returns list of changed Path objects."""
        changed = []
        # Check modified or added
        for path_str, mtime in new_snap.items():
            if path_str not in old_snap or mtime > old_snap[path_str]:
                changed.append(Path(path_str))
        # Check deleted
        for path_str in old_snap:
            if path_str not in new_snap:
                changed.append(Path(path_str))
        return changed

    def send_command(self, cmd: str):
        """Sends a single-character command ('r', 'R', 'q', etc.) to Flutter's stdin."""
        if not self.process or self.process.poll() is not None:
            return
        try:
            self.process.stdin.write(cmd + "\n")
            self.process.stdin.flush()
        except (BrokenPipeError, OSError):
            pass

    def file_watcher_loop(self):
        """Monitors filesystem changes and sends 'r' or 'R' accordingly."""
        self.file_snapshots = self.scan_watched_files()

        while self.is_running:
            time.sleep(0.25)
            if not self.is_running or not self.process or self.process.poll() is not None:
                continue

            current_snap = self.scan_watched_files()
            changed_files = self.detect_changes(self.file_snapshots, current_snap)

            if changed_files:
                # Debounce: wait 0.3s for editor writes to settle
                time.sleep(0.3)
                current_snap = self.scan_watched_files()
                self.file_snapshots = current_snap

                # Check if any changed file requires full restart or rebuild
                requires_restart = False
                changed_names = []
                for p in changed_files:
                    rel_p = str(p.relative_to(self.project_root) if p.is_relative_to(self.project_root) else p.name)
                    changed_names.append(rel_p)
                    # Structural files require hot restart
                    if p.name == "pubspec.yaml" or "assets" in p.parts or p.name == "index.html":
                        requires_restart = True

                summary = ", ".join(changed_names[:3])
                if len(changed_names) > 3:
                    summary += f" (+{len(changed_names) - 3} more)"

                if requires_restart or self.last_reload_rejected:
                    self.log(
                        f"[{COLOR_CYAN}AUTO RESTART{COLOR_RESET}]",
                        f"Structural change detected in {summary}. Performing Hot Restart...",
                        color=COLOR_CYAN,
                    )
                    self.last_reload_rejected = False
                    self.send_command("R")
                else:
                    self.log(
                        f"[{COLOR_LIME}AUTO RELOAD{COLOR_RESET}]",
                        f"Saved changes in {summary}. Performing Hot Reload...",
                        color=COLOR_LIME,
                    )
                    self.send_command("r")

                self.last_reload_time = time.time()

    def handle_stdout_line(self, line: str):
        """Processes Flutter output in real-time, catching reloads, restarts, and compile errors."""
        stripped = line.strip()

        # Check for reload rejection
        if "Hot reload was rejected" in line or "Please restart the application" in line or "Reload rejected" in line:
            self.last_reload_rejected = True
            print(f"\n{COLOR_YELLOW}+======================================================================+{COLOR_RESET}")
            print(f"{COLOR_YELLOW}| [RELOAD REJECTED] Flutter cannot hot-reload this structural change.  |{COLOR_RESET}")
            print(f"{COLOR_CYAN}| --> Automatically triggering Hot Restart ('R') now...                 |{COLOR_RESET}")
            print(f"{COLOR_YELLOW}+======================================================================+{COLOR_RESET}\n")
            self.send_command("R")
            return

        # Check for compilation errors
        is_error_start = (
            ": Error: " in line
            or "Failed to compile application." in line
            or "Error: " in line and not line.startswith("        ")
        )

        if is_error_start:
            self.in_compile_error = True
            self.compile_error_lines.append(stripped)
            return

        if self.in_compile_error:
            if stripped.startswith("lib/") or stripped.startswith("web/") or stripped.startswith("test/"):
                self.compile_error_lines.append(stripped)
                return
            elif "Failed to compile" in line or stripped == "^":
                self.compile_error_lines.append(stripped)
                return
            elif stripped == "" or "Try fixing the error" in line:
                # End of error block
                self.in_compile_error = False
                self._print_compile_error_banner(self.compile_error_lines)
                self.compile_error_lines = []
                return
            else:
                self.compile_error_lines.append(stripped)
                if len(self.compile_error_lines) > 25:
                    self.in_compile_error = False
                    self._print_compile_error_banner(self.compile_error_lines)
                    self.compile_error_lines = []
                return

        # Success messages
        if "Reloaded " in line and " libraries in " in line:
            self.last_reload_rejected = False
            print(f"\n{COLOR_GREEN}[OK] {stripped}{COLOR_RESET}")
            return
        if "Restarted application in " in line:
            self.last_reload_rejected = False
            print(f"\n{COLOR_CYAN}[OK] {stripped}{COLOR_RESET}")
            return

        # Normal line pass-through
        print(line, end="", flush=True)

    def _print_compile_error_banner(self, lines: list):
        """Displays a clean, unmistakable compile error box that reassures the dev the app stays running."""
        print(f"\n{COLOR_RED}{COLOR_BOLD}+----------------------------------------------------------------------+{COLOR_RESET}")
        print(f"{COLOR_RED}{COLOR_BOLD}|                      COMPILATION ERROR DETECTED                      |{COLOR_RESET}")
        print(f"{COLOR_RED}{COLOR_BOLD}+----------------------------------------------------------------------+{COLOR_RESET}")
        print(f"{COLOR_RED}|  QuickShare Studio remains RUNNING on the last working state.        |{COLOR_RESET}")
        print(f"{COLOR_RED}|  The running app was not terminated or closed.                       |{COLOR_RESET}")
        print(f"{COLOR_RED}{COLOR_BOLD}+----------------------------------------------------------------------+{COLOR_RESET}")
        for l in lines[:15]:
            # Print with slight indent
            print(f"{COLOR_YELLOW}  ! {l}{COLOR_RESET}")
        if len(lines) > 15:
            print(f"{COLOR_GRAY}  ... and {len(lines) - 15} more lines{COLOR_RESET}")
        print(f"{COLOR_RED}{COLOR_BOLD}+----------------------------------------------------------------------+{COLOR_RESET}")
        print(f"{COLOR_LIME}  Fix the syntax/type error in your editor and save to hot-reload!     {COLOR_RESET}")
        print(f"{COLOR_RED}{COLOR_BOLD}+----------------------------------------------------------------------+{COLOR_RESET}\n")

    def stdout_reader_loop(self):
        """Reads stdout from Flutter subprocess."""
        while self.is_running and self.process:
            line = self.process.stdout.readline()
            if not line:
                break
            self.handle_stdout_line(line)

    def user_input_loop(self):
        """Listens for user commands in terminal ('r', 'R', 'q', 'h')."""
        while self.is_running:
            try:
                user_cmd = input().strip()
                if not self.is_running:
                    break
                if user_cmd == "r":
                    self.log(f"[{COLOR_LIME}MANUAL RELOAD{COLOR_RESET}]", "Sending Hot Reload ('r')...", color=COLOR_LIME)
                    self.send_command("r")
                elif user_cmd == "R":
                    self.log(f"[{COLOR_CYAN}MANUAL RESTART{COLOR_RESET}]", "Sending Hot Restart ('R')...", color=COLOR_CYAN)
                    self.send_command("R")
                elif user_cmd == "q":
                    self.log(f"[{COLOR_YELLOW}QUIT{COLOR_RESET}]", "Stopping QuickShare Studio development runner...", color=COLOR_YELLOW)
                    self.stop()
                    break
                elif user_cmd == "h":
                    self.print_help()
                elif user_cmd:
                    self.send_command(user_cmd)
            except (EOFError, KeyboardInterrupt):
                self.stop()
                break

    def print_banner(self):
        print(f"""
{COLOR_LIME}{COLOR_BOLD}========================================================================
   QuickShare Studio - Live Development Runner (Hot Reload Active)
========================================================================{COLOR_RESET}
  Target Device   : {COLOR_CYAN}{self.device}{COLOR_RESET}
  Watching Folder : {COLOR_CYAN}{self.project_root / 'lib'}{COLOR_RESET}
  Hot Reload      : {COLOR_GREEN}AUTOMATIC on source file save (.dart){COLOR_RESET}
  Hot Restart     : {COLOR_YELLOW}AUTOMATIC on structural change / rejection{COLOR_RESET}
  Interactive Keys:
    [r] - Manual Hot Reload      [R] - Manual Hot Restart
    [h] - Show Help              [q] - Quit and close runner
========================================================================
""")

    def print_help(self):
        print(f"""
{COLOR_BOLD}QuickShare Studio Development Commands:{COLOR_RESET}
  {COLOR_LIME}r{COLOR_RESET} : Trigger Hot Reload (updates UI, build methods, styling)
  {COLOR_CYAN}R{COLOR_RESET} : Trigger Hot Restart (reinitializes app state, routes, models)
  {COLOR_YELLOW}c{COLOR_RESET} : Clear terminal screen
  {COLOR_RED}q{COLOR_RESET} : Terminate Flutter app and exit
  
{COLOR_BOLD}File Watcher Rules:{COLOR_RESET}
  - Saving any file in {COLOR_CYAN}lib/{COLOR_RESET} automatically triggers Hot Reload.
  - If a change alters class signatures or state variables and hot reload is rejected,
    the runner automatically promotes the reload to Hot Restart.
  - Saving {COLOR_CYAN}pubspec.yaml{COLOR_RESET} or assets automatically triggers Hot Restart.
  - If compilation fails, the app remains running on the previous good build.
""")

    def start(self):
        flutter_exe = self.find_flutter()
        self.print_banner()
        self.log("[START]", f"Starting Flutter development server using {flutter_exe}...", color=COLOR_CYAN)

        cmd = [flutter_exe, "run", "-d", self.device]
        if self.device in ("chrome", "edge", "web-server"):
            cmd.extend(["--web-port", str(self.web_port)])

        try:
            self.process = subprocess.Popen(
                cmd,
                cwd=str(self.project_root),
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                bufsize=1,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
        except Exception as e:
            self.log("[ERROR]", f"Failed to start Flutter: {e}", color=COLOR_RED)
            return 1

        # Spawn background threads for output, watcher, and user input
        t_out = threading.Thread(target=self.stdout_reader_loop, daemon=True)
        t_watch = threading.Thread(target=self.file_watcher_loop, daemon=True)
        t_in = threading.Thread(target=self.user_input_loop, daemon=True)

        t_out.start()
        t_watch.start()
        t_in.start()

        try:
            # Wait for flutter process to finish
            self.process.wait()
        except KeyboardInterrupt:
            self.log("[SHUTDOWN]", "Received interrupt, terminating...", color=COLOR_YELLOW)
            self.stop()

        return 0

    def stop(self):
        self.is_running = False
        if self.process and self.process.poll() is None:
            try:
                self.send_command("q")
                time.sleep(0.5)
                if self.process.poll() is None:
                    self.process.terminate()
            except Exception:
                pass


def main():
    import argparse

    parser = argparse.ArgumentParser(description="QuickShare Studio Live Dev Runner")
    parser.add_argument(
        "-d",
        "--device",
        default="chrome",
        help="Target device to run on (chrome, edge, windows). Default: chrome",
    )
    parser.add_argument(
        "-p",
        "--port",
        type=int,
        default=52835,
        help="Web port for Chrome / Edge. Default: 52835",
    )
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parent.parent
    runner = DevRunner(project_root=project_root, device=args.device, web_port=args.port)
    sys.exit(runner.start())


if __name__ == "__main__":
    main()
