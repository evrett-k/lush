use mlua::Lua;
use rustyline::error::ReadlineError;
use rustyline::Config;
use rustyline::Editor;
use rustyline::completion::{Completer, FilenameCompleter, Pair};
use rustyline::highlight::{CmdKind, Highlighter};
use rustyline::hint::{Hinter, HistoryHinter};
use rustyline::validate::Validator;
use rustyline::{Context, Helper, Result as ReadlineResult, CompletionType};
use crate::lush;
use std::env;
use std::borrow::Cow;
use std::collections::HashSet;
use std::fs;
use std::process::Command;
#[cfg(unix)]
use nix::sys::signal::{self, Signal};

#[cfg(unix)]
use std::sync::atomic::{AtomicBool, Ordering};
#[cfg(unix)]
use std::sync::Arc;
#[cfg(unix)]
use tokio::signal::unix::{signal, SignalKind};

fn path_binaries() -> HashSet<String> {
    let mut bins = HashSet::new();
    if let Some(path_var) = env::var_os("PATH") {
        for dir in env::split_paths(&path_var) {
            if let Ok(entries) = fs::read_dir(&dir) {
                for entry in entries.flatten() {
                    let p = entry.path();
                    if p.is_file() {
                        if let Some(name) = p.file_name() {
                            bins.insert(name.to_string_lossy().into_owned());
                        }
                    }
                }
            }
        }
    }
    bins
}

fn lush_builtins() -> HashSet<String> {
    ["ls","cd","cat","mv","cp","mkdir","touch","rm","pwd","clear","whoami","echo","exit","reload"]
        .iter().map(|s| s.to_string()).collect()
}

struct ShellHelper {
    file_completer: FilenameCompleter,
    hinter: HistoryHinter,
    known_commands: HashSet<String>,
}

impl ShellHelper {
    fn new() -> Self {
        let mut known = lush_builtins();
        known.extend(path_binaries());
        Self { file_completer: FilenameCompleter::new(), hinter: HistoryHinter {}, known_commands: known }
    }
    fn is_known(&self, word: &str) -> bool { self.known_commands.contains(word) }
    fn prefix_matches(&self, prefix: &str) -> bool {
        !prefix.is_empty() && self.known_commands.iter().any(|c| c.starts_with(prefix))
    }
}

impl Completer for ShellHelper {
    type Candidate = Pair;
    fn complete(&self, line: &str, pos: usize, ctx: &Context<'_>) -> ReadlineResult<(usize, Vec<Pair>)> {
        let before = &line[..pos];
        let words: Vec<&str> = before.split_whitespace().collect();
        if words.len() <= 1 && !before.ends_with(' ') {
            let prefix = words.first().copied().unwrap_or("");
            let mut matches: Vec<Pair> = self.known_commands.iter()
                .filter(|c| c.starts_with(prefix))
                .map(|c| Pair { display: c.clone(), replacement: c.clone() })
                .collect();
            matches.sort_by(|a, b| a.display.cmp(&b.display));
            if !matches.is_empty() { return Ok((pos - prefix.len(), matches)); }
        }
        self.file_completer.complete(line, pos, ctx)
    }
}

impl Hinter for ShellHelper {
    type Hint = String;
    fn hint(&self, line: &str, pos: usize, ctx: &Context<'_>) -> Option<String> {
        let before = &line[..pos];
        if !before.contains(' ') && !before.is_empty() {
            let mut matches: Vec<&String> = self.known_commands.iter()
                .filter(|c| c.starts_with(before) && c.as_str() != before)
                .collect();
            matches.sort();
            if let Some(top) = matches.first() {
                return Some(top[before.len()..].to_string());
            }
        }
        self.hinter.hint(line, pos, ctx)
    }
}

impl Highlighter for ShellHelper {
    fn highlight<'l>(&self, line: &'l str, _pos: usize) -> Cow<'l, str> {
        if line.is_empty() { return Cow::Borrowed(line); }
        let mut parts = line.splitn(2, ' ');
        let cmd = parts.next().unwrap_or("");
        let rest = parts.next();
        let colored_cmd = if self.is_known(cmd) {
            format!("\x1b[1;32m{}\x1b[0m", cmd)
        } else if self.prefix_matches(cmd) {
            format!("\x1b[1;33m{}\x1b[0m", cmd)
        } else {
            format!("\x1b[1;31m{}\x1b[0m", cmd)
        };
        if let Some(args) = rest {
            Cow::Owned(format!("{} {}", colored_cmd, args))
        } else {
            Cow::Owned(colored_cmd)
        }
    }
    fn highlight_hint<'h>(&self, hint: &'h str) -> Cow<'h, str> {
        Cow::Owned(format!("\x1b[90m{}\x1b[0m", hint))
    }
    fn highlight_char(&self, _line: &str, _pos: usize, _forced: CmdKind) -> bool { true }
}

impl Validator for ShellHelper {}
impl Helper for ShellHelper {}


fn build_prompt(last_exit_code: i32) -> String {
    let cwd = env::current_dir()
        .map(|p| {
            if let Some(home) = env::var_os("HOME") {
                let home = std::path::PathBuf::from(home);
                if let Ok(rel) = p.strip_prefix(&home) {
                    return format!("~/{}", rel.to_string_lossy());
                }
            }
            p.to_string_lossy().into_owned()
        })
        .unwrap_or_else(|_| "/".to_string());

    let branch = Command::new("git")
        .args(["rev-parse", "--abbrev-ref", "HEAD"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| format!(" \x1b[90m{}\x1b[0m", s.trim()));

    let prompt_char = if last_exit_code == 0 {
        "\x1b[1m$\x1b[0m"
    } else {
        "\x1b[1;31m$\x1b[0m"
    };

    format!(
        "\x1b[1;34m{}\x1b[0m{} {} ",
        cwd,
        branch.unwrap_or_default(),
        prompt_char
    )
}

fn get_starship_prompt(last_exit_code: i32) -> Option<(String, String)> {
    if !lush::is_executable_in_path("starship") {
        return None;
    }

    let output = Command::new("starship")
        .arg("prompt")
        .arg(format!("--status={}", last_exit_code))
        .env("STARSHIP_SHELL", "lush")
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    if stdout.is_empty() {
        return None;
    }

    let mut lines: Vec<String> = stdout.trim_end().lines().map(|s| s.to_string()).collect();
    if lines.is_empty() {
        return None;
    }

    let prompt_char = if last_exit_code == 0 {
        "\x1b[35m\u{276f}\x1b[0m "
    } else {
        "\x1b[31m\u{276f}\x1b[0m "
    };

    if lines.len() > 1 {
        let _ = lines.pop();
        Some((lines.join("\n"), prompt_char.to_string()))
    } else {
        Some(("".to_string(), prompt_char.to_string()))
    }
}

pub async fn start_interactive(lua: &Lua) -> mlua::Result<()> {
    if env::var("LANG").is_err() { env::set_var("LANG", "en_US.UTF-8"); }
    if env::var("LC_ALL").is_err() { env::set_var("LC_ALL", "en_US.UTF-8"); }

    #[cfg(unix)]
    let interrupt = {
        let interrupt = Arc::new(AtomicBool::new(false));
        let i_clone = Arc::clone(&interrupt);
        tokio::spawn(async move {
            let mut sigint = signal(SignalKind::interrupt()).expect("failed to bind sigint");
            loop {
                sigint.recv().await;
                i_clone.store(true, Ordering::SeqCst);
            }
        });
        Some(interrupt)
    };
    
    let config = Config::builder().completion_type(CompletionType::Circular).build();
    let mut rl = Editor::with_config(config).map_err(|e| {
        mlua::Error::RuntimeError(format!("Failed to initialize prompt: {}", e))
    })?;
    rl.set_helper(Some(ShellHelper::new()));

    let history_path = dirs_home().map(|h| h.join(".lush_history"));
    if let Some(ref path) = history_path { let _ = rl.load_history(path); }

    let mut last_exit_code = 0;

    loop {
        #[cfg(unix)]
        if let Some(ref interrupt) = interrupt {
            if interrupt.load(Ordering::SeqCst) {
                interrupt.store(false, Ordering::SeqCst);
                
                let mut trapped = false;
                let globals = lua.globals();
                if let Ok(traps) = globals.get::<mlua::Table>("LUSH_TRAPS") {
                    if let Ok(callback) = traps.get::<mlua::Function>("SIGINT") {
                        if let Err(e) = callback.call::<()>(()) {
                            eprintln!("lush: error in SIGINT trap: {}", e);
                        }
                        trapped = true;
                    }
                }

                if !trapped {
                    println!("\n^C detected");
                }
                continue;
            }
        }

        #[cfg(unix)]
        unsafe {
            let _ = signal::signal(Signal::SIGINT, signal::SigHandler::SigDfl);
            let _ = signal::signal(Signal::SIGTSTP, signal::SigHandler::SigDfl);
        }

        let use_starship = {
            let val = lua.globals().get::<mlua::Value>("use_starship").unwrap_or(mlua::Value::Nil);
            match val {
                mlua::Value::Boolean(b) => Some(b),
                mlua::Value::String(s) => s.to_str().ok().and_then(|str_val| {
                    let s_lower = str_val.to_lowercase();
                    if s_lower == "false" || s_lower == "0" { Some(false) }
                    else if s_lower == "true" || s_lower == "1" { Some(true) }
                    else { None }
                }),
                mlua::Value::Integer(i) => Some(i != 0),
                mlua::Value::Number(n) => Some(n != 0.0),
                _ => {
                    let env_starship = env::var("USE_STARSHIP").unwrap_or_default().to_lowercase();
                    match env_starship.as_str() {
                        "false" | "0" => Some(false),
                        "true" | "1" => Some(true),
                        _ => None,
                    }
                }
            }
        };

        let (prompt_str, header) = if use_starship != Some(false) {
            if let Some((h, p)) = get_starship_prompt(last_exit_code) {
                (p, Some(h))
            } else {
                (build_prompt(last_exit_code), None)
            }
        } else {
            (build_prompt(last_exit_code), None)
        };

        if let Some(h) = header {
            if !h.is_empty() { println!("{}", h); }
        }

        match rl.readline(&prompt_str) {
            Ok(line) => {
                let trimmed = line.trim();
                if trimmed.is_empty() { continue; }
                let _ = rl.add_history_entry(trimmed);
                let compiled_line = lush::precompile(trimmed);
                if compiled_line == "exit" { break; }
                match lua.load(&compiled_line).exec() {
                    Ok(_) => { last_exit_code = 0; }
                    Err(_) => { last_exit_code = crate::shell::exec_str(trimmed).await; }
                }
            }
            Err(ReadlineError::Interrupted) => {
                println!();
                last_exit_code = 130;
                continue;
            }
            Err(ReadlineError::Eof) => { break; }
            Err(err) => { eprintln!("Terminal Error: {:?}", err); break; }
        }
    }

    if let Some(ref path) = history_path { let _ = rl.save_history(path); }
    Ok(())
}

fn dirs_home() -> Option<std::path::PathBuf> {
    env::var_os("HOME").map(std::path::PathBuf::from)
}
