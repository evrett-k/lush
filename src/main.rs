mod lush;
mod repl;
mod shell;

use std::env;
use std::fs;
use std::path::Path;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();

    let lua = lush::init_engine()?;

    if args.len() < 2 {
        repl::start_interactive(&lua).await?;
    } else {
        let script_path = &args[1];
        let path = Path::new(script_path);

        if path.is_file() {
            let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("");
            match ext {
                // .sh files — run natively through embedded yash
                "sh" => {
                    let code = shell::exec_file(script_path).await;
                    std::process::exit(code);
                }
                "fish" => {
                    let status = std::process::Command::new("fish").arg(script_path).status()?;
                    std::process::exit(status.code().unwrap_or(1));
                }
                "ps1" => {
                    let shell = if cfg!(windows) {
                        "powershell"
                    } else if std::process::Command::new("pwsh-preview").output().is_ok() {
                        "pwsh-preview"
                    } else {
                        "pwsh"
                    };
                    let status = std::process::Command::new(shell).arg(script_path).status()?;
                    std::process::exit(status.code().unwrap_or(1));
                }
                "cmd" | "bat" => {
                    let shell = if cfg!(windows) { "cmd.exe" } else { "/bin/sh" };
                    let args = if cfg!(windows) { ["/c", script_path] } else { ["-c", script_path] };
                    let status = std::process::Command::new(shell).args(args).status()?;
                    std::process::exit(status.code().unwrap_or(1));
                }
                // .lush and everything else — lush precompiler → Lua VM
                _ => {
                    let raw_script = fs::read_to_string(script_path)?;
                    let mut exit_code = 0;
                    for line in raw_script.lines() {
                        let trimmed = line.trim();
                        if trimmed.is_empty() || trimmed.starts_with("--") || trimmed.starts_with("#!") || trimmed.starts_with("#") {
                            continue;
                        }
                        let executable_lua = lush::precompile(trimmed);
                        if executable_lua == "exit" { break; }
                        if let Err(_) = lua.load(&executable_lua).exec() {
                            exit_code = shell::exec_str(trimmed).await;
                        } else {
                            exit_code = 0;
                        }
                    }
                    if exit_code != 0 { std::process::exit(exit_code); }
                }
            }
        } else {
            let inline_script = args[1..].join(" ");
            let executable_lua = lush::precompile(&inline_script);
            if let Err(_) = lua.load(&executable_lua).exec() {
                let code = shell::exec_str(&inline_script).await;
                std::process::exit(code);
            }
        }
    }

    Ok(())
}