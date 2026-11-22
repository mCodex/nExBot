"""Install the profile and matching engine bundled with this release."""

from contextlib import contextmanager
from datetime import datetime
import hashlib
import locale
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import threading


PAYLOAD = Path(__file__).resolve().parent / "payload"
USER_DIRECTORIES = ("cavebot_configs", "nExBot_configs", "targetbot_configs", "storage", "private")
CLIENT_NAMES = ("otclient", "otcr", "opentibia")


def is_link(path):
    return path.is_symlink() or getattr(path, "is_junction", lambda: False)()


def client_roots(system, home, env):
    if system == "Windows":
        return [Path(env["APPDATA"])] if env.get("APPDATA") else []
    if system == "Darwin":
        return [home / "Library" / "Application Support"]
    xdg_data = Path(env.get("XDG_DATA_HOME") or ".")
    return [home / ".local" / "share", *([xdg_data] if xdg_data.is_absolute() else [])]


def detect_bot_folders(roots):
    folders = set()

    def scan(directory, remaining):
        try:
            entries = list(directory.iterdir())
        except OSError:
            return

        for entry in entries:
            if is_link(entry) or not entry.is_dir():
                continue
            if entry.name.casefold() == "bot":
                folders.add(entry.resolve())
            elif remaining:
                scan(entry, remaining - 1)

    for root in roots:
        try:
            clients = list(root.iterdir())
        except OSError:
            continue
        for client in clients:
            if any(name in client.name.casefold() for name in CLIENT_NAMES):
                if client.is_dir() and not is_link(client):
                    scan(client, 2)

    return sorted(folders, key=lambda path: str(path).casefold())


def run(command):
    try:
        result = subprocess.run(
            [str(argument) for argument in command],
            check=True,
            capture_output=True,
            text=True,
            errors="replace",
            timeout=45,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
    except subprocess.CalledProcessError as error:
        message = (error.stderr or error.stdout).strip()
        raise RuntimeError(message or str(error)) from error
    return result.stdout.strip()


def install_profile(source, bot_folder):
    if not bot_folder.is_dir() or bot_folder.name.casefold() != "bot":
        raise ValueError("Select the client's existing bot folder. / Selecione a pasta bot do cliente.")

    profile = bot_folder / "nExBot"
    if is_link(profile):
        raise ValueError("Select a profile without symbolic links. / Escolha um perfil sem links simbólicos.")
    if profile.exists() and not (profile / "_Loader.lua").is_file():
        raise ValueError("The nExBot folder already exists. / A pasta nExBot já existe.")

    # Stage beside the bot directory so replacement and backup use the same volume.
    with tempfile.TemporaryDirectory(prefix=".nexbot-install-", dir=bot_folder.parent) as workspace:
        staged = Path(workspace) / "nExBot"
        shutil.copytree(source, staged)
        backup = None

        if profile.exists():
            for name in USER_DIRECTORIES:
                current = profile / name
                if current.is_dir() and not is_link(current):
                    shutil.copytree(current, staged / name, symlinks=True, dirs_exist_ok=True)

            backup_root = bot_folder.parent / ".nexbot-backups"
            backup_root.mkdir(mode=0o700, exist_ok=True)
            if is_link(backup_root):
                raise ValueError("The backup directory is a symbolic link. / A pasta de backup é um link simbólico.")
            backup_dir = Path(tempfile.mkdtemp(
                prefix=datetime.now().strftime("%Y-%m-%d-%H%M%S-"),
                dir=backup_root,
            ))
            backup = backup_dir / "nExBot"
            profile.rename(backup)

        try:
            staged.rename(profile)
        except OSError:
            if backup is not None:
                backup.rename(profile)
            raise

    return profile, backup


def configure_startup(system, engine, profile):
    if system == "Windows":
        directory = Path(os.environ["LOCALAPPDATA"]) / "nExBot"
        directory.mkdir(exist_ok=True)
        digest = hashlib.sha256(engine.read_bytes()).hexdigest()[:16]
        executable = directory / f"nexbot-engine-{digest}.exe"
        if not executable.is_file() or hashlib.sha256(executable.read_bytes()).hexdigest()[:16] != digest:
            with tempfile.TemporaryDirectory(dir=directory) as workspace:
                staged = Path(workspace) / executable.name
                shutil.copyfile(engine, staged)
                staged.replace(executable)
        run([
            Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/powershell.exe",
            "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned",
            "-File", profile / "tools/windows/autostart.ps1", "-Engine", executable,
            "-ProfileDir", profile,
        ])
    elif system == "Darwin":
        run(["/bin/sh", profile / "tools/macos/install-autostart.sh", engine, profile])
    else:
        command = [sys.executable]
        if not getattr(sys, "frozen", False):
            command.append(__file__)
        run([*command, "--linux-autostart", engine, profile])


def verify_package(system):
    profile_source = PAYLOAD / "nExBot"
    engine = PAYLOAD / ("nexbot-engine.exe" if system == "Windows" else "nexbot-engine")
    version = run([engine, "--version"])
    if not version.startswith("nexbot-engine ") or not (profile_source / "_Loader.lua").is_file():
        raise ValueError("Invalid installer package. / Pacote de instalação inválido.")

    return profile_source, engine, version


@contextmanager
def installer_lock(path):
    with path.open("a+b") as handle:
        try:
            if os.name == "nt":
                import msvcrt

                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise RuntimeError("Another installer is open. / Há outro instalador aberto.") from error
        yield


def install(system, bot_folder):
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        raise PermissionError("Use your desktop account. / Use sua conta de usuário.")

    profile_source, engine, version = verify_package(system)
    if system == "Linux":
        run(["systemctl", "--user", "show", "--property=Version"])

    with installer_lock(Path.home() / ".nexbot-installer.lock"):
        profile, backup = install_profile(profile_source, bot_folder)
        try:
            configure_startup(system, engine, profile)
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            # Keep the installed profile and its backup available for a startup retry.
            message = "Automatic startup failed. / A inicialização automática falhou."
            raise RuntimeError(f"{message}\n{error}\n{backup or profile}") from error

    return version, backup


def window():
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk

    pt = (locale.getlocale()[0] or "").lower().startswith("pt")
    system = platform.system()
    root = tk.Tk()
    root.title("nExBot")
    root.resizable(True, False)

    frame = ttk.Frame(root, padding=24)
    frame.grid(sticky="nsew")
    root.columnconfigure(0, weight=1)
    frame.columnconfigure(0, weight=1)

    heading = "Instalar o nExBot" if pt else "Install nExBot"
    instructions = (
        "Feche o OTClient e selecione a pasta bot que ele usa."
        if pt else "Close OTClient and choose the bot folder it uses."
    )
    ttk.Label(frame, text=heading, font=("TkDefaultFont", 16, "bold")).grid(sticky="w")
    ttk.Label(frame, text=instructions).grid(sticky="w", pady=(10, 16))

    detected = detect_bot_folders(client_roots(system, Path.home(), os.environ))
    selected = tk.StringVar(value=str(detected[0]) if len(detected) == 1 else "")
    paths = ttk.Combobox(frame, textvariable=selected, values=[str(path) for path in detected],
                         state="readonly", width=53)
    paths.grid(row=2, column=0, sticky="ew")

    def browse():
        path = filedialog.askdirectory(parent=root, mustexist=True)
        if path:
            selected.set(path)
            update_button()

    browse_button = ttk.Button(frame, text="Procurar…" if pt else "Browse…", command=browse)
    browse_button.grid(row=2, column=1, padx=(8, 0))

    status = tk.StringVar()
    ttk.Label(frame, textvariable=status, wraplength=470).grid(columnspan=2, sticky="w", pady=(14, 8))

    def update_button(*_):
        install_button.configure(state="normal" if selected.get() else "disabled")

    def finish(result):
        paths.configure(state="readonly")
        browse_button.configure(state="normal")
        update_button()
        root.protocol("WM_DELETE_WINDOW", root.destroy)
        status.set("")

        if isinstance(result, Exception):
            messagebox.showerror(heading, str(result), parent=root)
            return

        version, backup = result
        message = (
            "Abra o OTClient, pressione Ctrl+B e ative o perfil nExBot."
            if pt else "Open OTClient, press Ctrl+B, and enable the nExBot profile."
        )
        if backup:
            message += f"\n\nBackup: {backup}"
        status.set(f"{version}\n\n{message}")
        install_button.configure(state="disabled")
        ttk.Button(frame, text="Fechar" if pt else "Close", command=root.destroy).grid(
            row=4, column=1, sticky="e"
        )

    def start():
        bot_folder = Path(selected.get()).resolve()
        confirm = (
            "O instalador prepara este perfil e configura o início automático para sua conta."
            if pt else "The installer sets up this profile and configures automatic startup for your account."
        )
        if not messagebox.askokcancel(heading, f"{confirm}\n\n{bot_folder}", parent=root):
            return

        paths.configure(state="disabled")
        browse_button.configure(state="disabled")
        install_button.configure(state="disabled")
        status.set("Instalando…" if pt else "Installing…")
        root.protocol("WM_DELETE_WINDOW", lambda: None)

        from queue import Empty, Queue

        completed = Queue()

        def work():
            try:
                completed.put(install(system, bot_folder))
            except (KeyError, OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
                completed.put(error)

        def poll():
            try:
                result = completed.get_nowait()
            except Empty:
                root.after(100, poll)
            else:
                finish(result)

        threading.Thread(target=work, daemon=True).start()
        root.after(100, poll)

    install_button = ttk.Button(frame, text="Instalar" if pt else "Install", command=start)
    install_button.grid(row=4, column=1, sticky="e")
    paths.bind("<<ComboboxSelected>>", update_button)
    update_button()
    root.mainloop()


if __name__ == "__main__":
    if sys.argv[1:] == ["--verify-package"]:
        verify_package(platform.system())
    elif platform.system() == "Linux" and len(sys.argv) == 4 and sys.argv[1] == "--linux-autostart":
        import runpy

        _, _, engine, profile = sys.argv
        script = PAYLOAD / "nExBot/tools/linux/install-autostart.py"
        sys.argv = [str(script), engine, profile]
        runpy.run_path(str(script), run_name="__main__")
    else:
        window()
