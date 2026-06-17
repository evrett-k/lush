use mlua::{Lua, Result};
use std::fs::{self, OpenOptions};
use std::path::Path;
use std::env;

/// Initializes the Lush execution engine and registers all native shell commands.
pub fn init_engine() -> Result<Lua> {
    // Ensure PATH includes common tool locations that macOS shells have
    // but that may be missing when lush is spawned as a subprocess
    let mut path = env::var("PATH").unwrap_or_default();
    for extra in &[
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/sbin",
    ] {
        if !path.split(':').any(|p| p == *extra) {
            path.push(':');
            path.push_str(extra);
        }
    }
    // Add ~/.cargo/bin if it exists
    if let Some(home) = env::var_os("HOME") {
        let cargo_bin = Path::new(&home).join(".cargo/bin");
        if cargo_bin.exists() {
            let cargo_bin_str = cargo_bin.to_string_lossy();
            if !path.split(':').any(|p| p == cargo_bin_str.as_ref()) {
                path.push(':');
                path.push_str(&cargo_bin_str);
            }
        }
    }
    env::set_var("PATH", &path);
    env::set_var("SHELL", "lush");

    let lua = Lua::new();
    inject_builtins(&lua)?;
    load_config(&lua);
    Ok(lua)
}

/// Loads ~/.lush.lua if it exists.
fn load_config(lua: &Lua) {
    let config_path = env::var_os("HOME")
        .map(|h| Path::new(&h).join(".lush.lua"));
    if let Some(path) = config_path {
        if path.exists() {
            match fs::read_to_string(&path) {
                Ok(src) => {
                    if let Err(e) = lua.load(&src).exec() {
                        eprintln!("lush: error in ~/.lush.lua: {}", e);
                    }
                }
                Err(e) => eprintln!("lush: could not read ~/.lush.lua: {}", e),
            }
        }
    }
}

/// Pre-compiles an entire script or prompt block.
pub fn precompile(input: &str) -> String {
    let mut processed_lines = Vec::new();
    
    for line in input.lines() {
        let trimmed = line.trim();
        
        // 1. Pass empty lines and standard Lua/Shell comments straight through
        if trimmed.is_empty() || trimmed.starts_with("--") || trimmed.starts_with("#") {
            processed_lines.push(line.to_string());
            continue;
        }

        // 2. Identify and ignore lines that belong to standard Lua control structures or assignments
        if trimmed.starts_with("local") 
            || trimmed.starts_with("if") 
            || trimmed.starts_with("for") 
            || trimmed.starts_with("while")
            || trimmed.starts_with("function")
            || trimmed.starts_with("return")
            || trimmed.starts_with("end")
            || trimmed.starts_with("print")
            || trimmed.contains('=') // Handles standard assignments like x = 10
            || trimmed.contains('(') // Already a Lua call or expression
        {
            processed_lines.push(line.to_string());
            continue;
        }

        // 3. Process potential shell macros
        let parts: Vec<&str> = trimmed.split_whitespace().collect();
        let command = parts[0];
        let args = &parts[1..];

        let rewritten = match command {
            "exit" => "exit".to_string(),
            "pwd" => "pwd()".to_string(),
            "clear" => "clear()".to_string(),
            "whoami" => "whoami()".to_string(),
            "reload" => "reload()".to_string(),

            "ls" if args.is_empty() => "ls()".to_string(),
            "ls" if args.len() == 1 => format!("ls(\"{}\")", args[0]),
            "cd" if args.is_empty() => "cd()".to_string(),
            "cd" if args.len() == 1 => format!("cd(\"{}\")", args[0]),
            "cat" if args.len() == 1 => format!("cat(\"{}\")", args[0]),
            "mkdir" if args.len() == 1 => format!("mkdir(\"{}\")", args[0]),
            "touch" if args.len() == 1 => format!("touch(\"{}\")", args[0]),
            "rm" if args.len() == 1 => format!("rm(\"{}\")", args[0]),

            "mv" if args.len() == 2 => format!("mv(\"{}\", \"{}\")", args[0], args[1]),
            "cp" if args.len() == 2 => format!("cp(\"{}\", \"{}\")", args[0], args[1]),
            
            "echo" => format!("echo(\"{}\")", args.join(" ")),
            
            _ if args.is_empty() => format!("{}()", command),
            _ => line.to_string(),
        };

        processed_lines.push(rewritten);
    }

    processed_lines.join("\n")
}

/// Checks whether a binary exists somewhere on PATH.
#[allow(dead_code)]
pub fn is_executable_in_path(name: &str) -> bool {
    env::var_os("PATH")
        .map(|paths| {
            env::split_paths(&paths).any(|dir| dir.join(name).is_file())
        })
        .unwrap_or(false)
}

fn expand_vars(input: &str) -> String {
    let mut result = String::new();
    let mut i = 0;
    let bytes = input.as_bytes();
    while i < bytes.len() {
        if bytes[i] == b'$' {
            i += 1;
            let start = i;
            while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                i += 1;
            }
            let var_name = &input[start..i];
            if !var_name.is_empty() {
                if let Ok(val) = env::var(var_name) {
                    result.push_str(&val);
                }
            } else {
                result.push('$');
            }
        } else {
            result.push(bytes[i] as char);
            i += 1;
        }
    }
    result
}

fn expand_tilde(path: &str) -> String {
    let path = expand_vars(path);
    if path == "~" {
        env::var("HOME").unwrap_or_else(|_| "/".to_string())
    } else if let Some(rest) = path.strip_prefix("~/") {
        let home = env::var("HOME").unwrap_or_else(|_| "/".to_string());
        format!("{}/{}", home, rest)
    } else {
        path.to_string()
    }
}

fn inject_builtins(lua: &Lua) -> Result<()> {
    let globals = lua.globals();

    let mv_fn = lua.create_function(|_, (src, dest): (String, String)| {
        let src = expand_tilde(&src);
        let dest = expand_tilde(&dest);
        if let Err(e) = fs::rename(&src, &dest) { eprintln!("mv error: {}", e); }
        Ok(())
    })?;
    globals.set("mv", mv_fn)?;

    let cp_fn = lua.create_function(|_, (src, dest): (String, String)| {
        use std::io::{self, Write};
        let src = expand_tilde(&src);
        let dest = expand_tilde(&dest);
        if let Err(e) = fs::copy(&src, &dest) { 
            eprintln!("cp error: {}", e); 
        } else {
            println!("Copied: '{}' -> '{}'", src, dest);
            let _ = io::stdout().flush();
        }
        Ok(())
    })?;
    globals.set("cp", cp_fn)?;

    let ls_fn = lua.create_function(|_, target_dir: Option<String>| {
        let dir_path = target_dir
            .map(|d| expand_tilde(&d))
            .unwrap_or_else(|| ".".to_string());
        let path = Path::new(&dir_path);

        if let Ok(entries) = fs::read_dir(path) {
            for entry in entries.flatten() {
                let file_name = entry.file_name();
                let name_str = file_name.to_string_lossy();

                if entry.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                    print!("\x1b[1;34m{}/\x1b[0m  ", name_str);
                } else {
                    print!("{}  ", name_str);
                }
            }
            println!();
        } else { eprintln!("ls error: Cannot access '{}'", dir_path); }
        Ok(())
    })?;
    globals.set("ls", ls_fn)?;

    let cat_fn = lua.create_function(|_, file_name: String| {
        use std::io::{self, Write};
        let file_name = expand_tilde(&file_name);
        match fs::read_to_string(&file_name) {
            Ok(content) => {
                println!("{}", content.trim_end());
                let _ = io::stdout().flush();
            }
            Err(e) => eprintln!("cat error: {}", e),
        }
        Ok(())
    })?;
    globals.set("cat", cat_fn)?;

    let mkdir_fn = lua.create_function(|_, dir_name: String| {
        let dir_name = expand_tilde(&dir_name);
        if let Err(e) = fs::create_dir(&dir_name) { eprintln!("mkdir error: {}", e); }
        Ok(())
    })?;
    globals.set("mkdir", mkdir_fn)?;

    let touch_fn = lua.create_function(|_, file_name: String| {
        let file_name = expand_tilde(&file_name);
        if let Err(e) = OpenOptions::new().write(true).create(true).open(&file_name) {
            eprintln!("touch error: {}", e);
        }
        Ok(())
    })?;
    globals.set("touch", touch_fn)?;

    let rm_fn = lua.create_function(|_, target: String| {
        let target = expand_tilde(&target);
        let path = Path::new(&target);
        if path.is_dir() {
            if let Err(e) = fs::remove_dir(path) { eprintln!("rm error: {}", e); }
        } else if let Err(e) = fs::remove_file(path) { eprintln!("rm error: {}", e); }
        Ok(())
    })?;
    globals.set("rm", rm_fn)?;

    let cd_fn = lua.create_function(|_, target_dir: Option<String>| {
        let home = env::var("HOME").unwrap_or_else(|_| "/".to_string());
        let destination = target_dir
            .map(|d| expand_tilde(&d))
            .unwrap_or(home);
        if let Err(e) = env::set_current_dir(Path::new(&destination)) {
            eprintln!("cd error: {}", e);
        }
        Ok(())
    })?;
    globals.set("cd", cd_fn)?;

    let pwd_fn = lua.create_function(|_, (): ()| {
        if let Ok(current) = env::current_dir() {
            println!("{}", current.to_string_lossy());
        }
        Ok(())
    })?;
    globals.set("pwd", pwd_fn)?;

    let clear_fn = lua.create_function(|_, (): ()| {
        print!("\x1b[2J\x1b[1;1H");
        Ok(())
    })?;
    globals.set("clear", clear_fn)?;

    let whoami_fn = lua.create_function(|_, (): ()| {
        let user = env::var("USER")
            .or_else(|_| env::var("LOGNAME"))
            .unwrap_or_else(|_| {
                std::process::Command::new("id")
                    .arg("-un")
                    .output()
                    .ok()
                    .and_then(|o| String::from_utf8(o.stdout).ok())
                    .map(|s| s.trim().to_string())
                    .unwrap_or_else(|| "unknown".to_string())
            });
        println!("{}", user);
        Ok(())
    })?;
    globals.set("whoami", whoami_fn)?;

    let echo_fn = lua.create_function(|_, content: String| {
        println!("{}", expand_vars(&content));
        Ok(())
    })?;
    globals.set("echo", echo_fn)?;

    let reload_fn = lua.create_function(|lua, (): ()| {
        load_config(lua);
        println!("lush: config reloaded");
        Ok(())
    })?;
    globals.set("reload", reload_fn)?;

    let trap_fn = lua.create_function(|lua, (sig, callback): (String, mlua::Function)| {
        let globals = lua.globals();
        let traps: mlua::Table = globals.get("LUSH_TRAPS").or_else(|_| lua.create_table())?;
        traps.set(sig.to_uppercase(), callback)?;
        globals.set("LUSH_TRAPS", traps)?;
        Ok(())
    })?;
    globals.set("trap", trap_fn)?;

    let exec_fn = lua.create_function(|_, args: mlua::Variadic<String>| {
        let mut iter = args.into_iter();
        if let Some(cmd) = iter.next() {
            let rest: Vec<String> = iter.collect();
            match std::process::Command::new(&cmd).args(&rest).status() {
                Ok(status) => { return Ok(status.code().unwrap_or(0)); }
                Err(_) => {
                    eprintln!("lush: command not found: {}", cmd);
                    return Ok(127);
                }
            }
        }
        Ok(0)
    })?;
    globals.set("exec", exec_fn)?;

    let common_tools = [
        // Shells/Scripting
        "fish", "pwsh", "zsh", "bash", "sh", "dash",
        // Version Control
        "git", "svn", "cvs",
        // Compilers/Build
        "cargo", "rustc", "gcc", "clang", "make", "cmake", "ninja", "gmake",
        // Languages
        "python3", "python", "ruby", "node", "deno", "go", "java", "javac", "perl", "node",
        // Package Managers/Dev
        "brew", "npm", "yarn", "pnpm", "mvn", "gradle", "go", "gem", "pip",
        // Cloud/Container
        "docker", "kubectl", "helm", "terraform", "ansible", "aws", "gcloud", "az",
        // Editors/Pager/Viewer
        "vim", "nvim", "nano", "less", "more", "bat", "emacs",
        // Text/File Processing
        "grep", "find", "sed", "awk", "sort", "head", "tail", "wc", "cut", "tr", "xargs",
        "basename", "dirname", "cat", "tee", "uniq", "fmt", "fold", "join", "paste", "split",
        "base64", "hexdump", "od", "md5sum", "sha1sum", "sha256sum",
        // Filesystem/System
        "ls", "cd", "pwd", "mkdir", "touch", "rm", "mv", "cp", "ln", "du", "df",
        "chmod", "chown", "chgrp", "stat", "find", "locate", "updatedb",
        "mount", "umount", "chroot", "fdisk", "lsblk",
        // Processes/Monitoring
        "ps", "kill", "top", "htop", "glances", "pstree", "lsof", "free", "uptime", "w", "who", "last",
        // Networking
        "ssh", "ssh-keygen", "ssh-add", "scp", "rsync", "curl", "wget", "ping", "traceroute",
        "netstat", "ifconfig", "ip", "ss", "nmap", "dig", "nslookup", "host",
        // Terminal/Session
        "tmux", "screen", "clear", "watch", "history", "alias", "env", "export",
        // Misc
        "time", "ts", "nice", "renice", "nohup", "sleep", "yes", "true", "false",
        "jq", "yq", "fzf", "rg", "eza", "fd", "bat",
    ];
    for tool in common_tools {
        let tool_name = tool.to_string();
        let wrapper = lua.create_function(move |_, args: mlua::Variadic<String>| {
            let rest: Vec<String> = args.into_iter().collect();
            match std::process::Command::new(&tool_name).args(&rest).status() {
                Ok(_) => {}
                Err(_) => eprintln!("lush: command not found: {}", tool_name),
            }
            Ok(())
        })?;
        globals.set(tool, wrapper)?;
    }

    Ok(())
}
