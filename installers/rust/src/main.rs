// Local TCP — Cross-platform Native Messaging Host installer (Rust)
// =============================================================================
// Installs the Node.js host (index.js) and registers it with Chromium-family
// browsers so the Local TCP extension can reach it.
//
// WHY a Node host (not a compiled binary): on macOS 15/26, Local Network
// Privacy keys LAN access to the executable's code identity. Routing through
// the system `node` (which macOS recognizes) is allowed to reach 192.168.x.x;
// a bare custom binary is silently denied. So Chrome must end up running
// `node index.js`, which is exactly what this installer wires up:
//   * macOS / Linux : manifest "path" -> index.js, whose shebang we rewrite to
//                     the absolute node path (so it never depends on $PATH).
//   * Windows       : manifest "path" -> run_bridge.bat, which calls node; the
//                     host is registered via HKCU registry keys.
//
// Usage:
//   localtcp-installer            # install (default)
//   localtcp-installer install
//   localtcp-installer uninstall
//
// The host's index.js and manifest template are embedded at compile time, so
// the resulting installer is a single self-contained binary.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const HOST_NAME: &str = "com.algoramming.localtcp";

// Embedded assets (resolved relative to this crate's Cargo.toml).
const INDEX_JS: &str = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../host/index.js"));
const MANIFEST_TMPL: &str =
    include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../host/com.algoramming.localtcp.json"));

fn main() {
    // Mode resolution: an explicit arg wins; otherwise infer from the executable's
    // own filename. This lets us ship the SAME compiled binary under two names —
    // `...installer.exe` installs, `...uninstaller.exe` uninstalls — so the bare
    // Windows .exe (launched with no args by a double-click) does the right thing.
    let action = env::args().nth(1).unwrap_or_else(default_action_from_exe_name);
    let result = match action.as_str() {
        "install" => install(),
        "uninstall" => uninstall(),
        "-h" | "--help" | "help" => {
            print_help();
            return;
        }
        other => Err(format!("unknown command '{other}'. Use: install | uninstall")),
    };
    if let Err(e) = result {
        eprintln!("\n[ERROR] {e}");
        eprintln!("If the problem persists, install Node.js manually from https://nodejs.org/ and re-run.");
        std::process::exit(1);
    }
}

fn default_action_from_exe_name() -> String {
    let name = env::current_exe()
        .ok()
        .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_lowercase()))
        .unwrap_or_default();
    if name.contains("uninstall") {
        "uninstall".to_string()
    } else {
        "install".to_string()
    }
}

fn print_help() {
    println!("Local TCP host installer\n");
    println!("  localtcp-installer            install (default)");
    println!("  localtcp-installer install    install and register the host");
    println!("  localtcp-installer uninstall  remove the host and all registrations");
}

// --- Install ---
fn install() -> Result<(), String> {
    banner("Local TCP Bridge — Installer");

    let node = find_node().ok_or_else(|| {
        format!(
            "Node.js was not found.\n  {}",
            node_install_hint()
        )
    })?;
    println!("[OK] Using Node at: {node}");

    let dir = install_dir();
    fs::create_dir_all(&dir).map_err(|e| format!("create {}: {e}", dir.display()))?;
    println!("[INFO] Install dir: {}", dir.display());

    // 1. Write index.js. On Unix, rewrite the shebang to the absolute node path
    //    so execution never depends on the (often minimal) inherited PATH.
    let index_path = dir.join("index.js");
    let index_contents = if cfg!(windows) {
        INDEX_JS.to_string()
    } else {
        patch_shebang(INDEX_JS, &node)
    };
    write_file(&index_path, &index_contents)?;
    make_executable(&index_path);
    println!("[INFO] Wrote {}", index_path.display());

    // 2. Determine the executable the manifest "path" should point at.
    let host_path: PathBuf = if cfg!(windows) {
        // Windows native messaging needs a launcher executable, not a .js.
        let bat = dir.join("run_bridge.bat");
        let contents = format!("@echo off\r\n\"{}\" \"%~dp0index.js\" %*\r\n", node);
        write_file(&bat, &contents)?;
        println!("[INFO] Wrote {}", bat.display());
        bat
    } else {
        index_path.clone()
    };

    // 3. Build the manifest with the absolute host path (JSON-escaped).
    let manifest = MANIFEST_TMPL.replace("HOST_PATH", &json_escape(&host_path.to_string_lossy()));
    let manifest_file = format!("{HOST_NAME}.json");

    // Keep a copy in the install dir (handy for debugging / Windows registry target).
    let local_manifest = dir.join(&manifest_file);
    write_file(&local_manifest, &manifest)?;

    if cfg!(windows) {
        register_windows(&local_manifest)?;
    } else {
        register_unix(&manifest_file, &manifest)?;
    }

    banner("✅ Installed");
    println!("Restart your browser completely, then use the Local TCP extension.");
    println!("Tip: the extension popup's bridge check should report version from index.js.");
    Ok(())
}

// --- Uninstall ---
fn uninstall() -> Result<(), String> {
    banner("Local TCP Bridge — Uninstaller");

    let manifest_file = format!("{HOST_NAME}.json");
    if cfg!(windows) {
        unregister_windows();
    } else {
        for d in browser_nm_dirs() {
            let f = d.join(&manifest_file);
            if f.exists() {
                let _ = fs::remove_file(&f);
                println!("[INFO] Removed {}", f.display());
            }
        }
    }

    let dir = install_dir();
    if dir.exists() {
        let _ = fs::remove_dir_all(&dir);
        println!("[INFO] Removed {}", dir.display());
    }

    banner("✅ Uninstalled");
    println!("Restart your browser to finish removing the host.");
    Ok(())
}

// --- Browser registration (macOS / Linux) ---
fn register_unix(manifest_file: &str, manifest: &str) -> Result<(), String> {
    let mut wrote = 0usize;
    for d in browser_nm_dirs() {
        // Write to a browser's host dir only if that browser's profile root
        // exists (so we don't litter dirs for browsers that aren't installed) —
        // except Chrome's, which we always create since it's the primary target.
        let is_primary = d.to_string_lossy().contains("Google/Chrome/")
            || d.to_string_lossy().contains("google-chrome/");
        let parent_exists = d.parent().map(|p| p.exists()).unwrap_or(false);
        if !is_primary && !parent_exists {
            continue;
        }
        if let Err(e) = fs::create_dir_all(&d) {
            eprintln!("[WARN] skip {}: {e}", d.display());
            continue;
        }
        let f = d.join(manifest_file);
        if write_file(&f, manifest).is_ok() {
            println!("[INFO] Registered: {}", f.display());
            wrote += 1;
        }
    }
    if wrote == 0 {
        return Err("could not register the host with any browser".to_string());
    }
    Ok(())
}

// --- Browser registration (Windows registry) ---
fn register_windows(manifest_path: &Path) -> Result<(), String> {
    let value = manifest_path.to_string_lossy().to_string();
    let mut ok = 0usize;
    for key in windows_reg_keys() {
        let status = Command::new("reg")
            .args(["add", &key, "/ve", "/t", "REG_SZ", "/d", &value, "/f"])
            .status();
        match status {
            Ok(s) if s.success() => {
                println!("[INFO] Registered: {key}");
                ok += 1;
            }
            _ => eprintln!("[WARN] could not write registry key: {key}"),
        }
    }
    if ok == 0 {
        return Err("failed to register the host in the Windows registry".to_string());
    }
    Ok(())
}

fn unregister_windows() {
    for key in windows_reg_keys() {
        let _ = Command::new("reg").args(["delete", &key, "/f"]).status();
        println!("[INFO] Removed registry key (if present): {key}");
    }
}

fn windows_reg_keys() -> Vec<String> {
    [
        r"HKCU\Software\Google\Chrome\NativeMessagingHosts",
        r"HKCU\Software\Microsoft\Edge\NativeMessagingHosts",
        r"HKCU\Software\BraveSoftware\Brave-Browser\NativeMessagingHosts",
        r"HKCU\Software\Chromium\NativeMessagingHosts",
    ]
    .iter()
    .map(|base| format!(r"{base}\{HOST_NAME}"))
    .collect()
}

// --- Platform paths ---
fn install_dir() -> PathBuf {
    let home = home_dir();
    if cfg!(target_os = "macos") {
        home.join("Library/Application Support/LocalTCP")
    } else if cfg!(windows) {
        PathBuf::from(env::var("APPDATA").unwrap_or_default())
            .join("Algoramming")
            .join("LocalTCP")
    } else {
        home.join(".local/lib/algoramming/localtcp")
    }
}

// Native-messaging host directories for Chromium-family browsers (Unix only).
fn browser_nm_dirs() -> Vec<PathBuf> {
    let home = home_dir();
    let mut v = Vec::new();
    if cfg!(target_os = "macos") {
        let base = home.join("Library/Application Support");
        v.push(base.join("Google/Chrome/NativeMessagingHosts"));
        v.push(base.join("Google/Chrome Beta/NativeMessagingHosts"));
        v.push(base.join("Google/Chrome Canary/NativeMessagingHosts"));
        v.push(base.join("Chromium/NativeMessagingHosts"));
        v.push(base.join("Microsoft Edge/NativeMessagingHosts"));
        v.push(base.join("BraveSoftware/Brave-Browser/NativeMessagingHosts"));
    } else if cfg!(target_os = "linux") {
        let c = home.join(".config");
        v.push(c.join("google-chrome/NativeMessagingHosts"));
        v.push(c.join("chromium/NativeMessagingHosts"));
        v.push(c.join("microsoft-edge/NativeMessagingHosts"));
        v.push(c.join("BraveSoftware/Brave-Browser/NativeMessagingHosts"));
    }
    v
}

fn home_dir() -> PathBuf {
    if cfg!(windows) {
        PathBuf::from(env::var("USERPROFILE").unwrap_or_default())
    } else {
        PathBuf::from(env::var("HOME").unwrap_or_default())
    }
}

// --- Node detection ---
fn find_node() -> Option<String> {
    // 1. Ask the system locator (`which` / `where`).
    let locator = if cfg!(windows) { "where" } else { "which" };
    if let Ok(out) = Command::new(locator).arg("node").output() {
        if out.status.success() {
            if let Ok(s) = String::from_utf8(out.stdout) {
                if let Some(line) = s.lines().next() {
                    let p = line.trim();
                    if !p.is_empty() && Path::new(p).exists() {
                        return Some(p.to_string());
                    }
                }
            }
        }
    }
    // 2. Fall back to common install locations.
    let candidates: &[&str] = if cfg!(windows) {
        &[
            r"C:\Program Files\nodejs\node.exe",
            r"C:\Program Files (x86)\nodejs\node.exe",
        ]
    } else {
        &[
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
            "/snap/bin/node",
        ]
    };
    candidates
        .iter()
        .find(|c| Path::new(c).exists())
        .map(|c| c.to_string())
}

fn node_install_hint() -> &'static str {
    if cfg!(target_os = "macos") {
        "Install it with Homebrew: `brew install node`, or from https://nodejs.org/"
    } else if cfg!(windows) {
        "Install it with `winget install OpenJS.NodeJS.LTS`, or from https://nodejs.org/"
    } else {
        "Install it via your package manager (e.g. `sudo apt install nodejs`), or from https://nodejs.org/"
    }
}

// --- Small utilities ---
fn patch_shebang(src: &str, node: &str) -> String {
    let rest = src.find('\n').map(|i| &src[i + 1..]).unwrap_or("");
    format!("#!{node}\n{rest}")
}

fn json_escape(s: &str) -> String {
    // Enough for filesystem paths embedded in JSON: backslashes and quotes.
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

fn write_file(path: &Path, contents: &str) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("create {}: {e}", parent.display()))?;
    }
    fs::write(path, contents).map_err(|e| format!("write {}: {e}", path.display()))
}

fn make_executable(path: &Path) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Ok(meta) = fs::metadata(path) {
            let mut perm = meta.permissions();
            perm.set_mode(0o755);
            let _ = fs::set_permissions(path, perm);
        }
    }
    #[cfg(not(unix))]
    {
        let _ = path;
    }
}

fn banner(title: &str) {
    println!("\n----------------------------------------------------");
    println!(" {title}");
    println!("----------------------------------------------------");
}
