/// Native POSIX shell execution via embedded yash-rs.

/// Execute a shell string natively through yash.
/// Returns the exit status code.
pub async fn exec_str(input: &str) -> i32 {
    let input = input.to_string();
    tokio::task::spawn_blocking(move || {
        let system = unsafe { yash_env::system::real::RealSystem::new() };
        let system = std::rc::Rc::new(yash_env::system::Concurrent::new(system));
        let runner = std::rc::Rc::clone(&system);

        let task = async {
            let mut env = yash_env::Env::with_system(system);

            if let Err(e) = env.traps.enable_internal_disposition_for_sigchld(&env.system).await {
                eprintln!("lush: failed to enable SIGCHLD disposition: {}", e);
            }

            // Register all POSIX builtins (echo, cd, pwd, etc.)
            env.builtins.extend(yash_builtin::iter());

            // Inherit PATH from process environment (already augmented by init_engine)
            // and export it into yash's variable set
            env.init_variables();

            // Also explicitly set PATH in yash's env so external utils like echo, test, etc. are found
            if let Ok(path_val) = std::env::var("PATH") {
                use yash_env::variable::{Scope, Value};
                env.variables
                    .get_or_new("PATH", Scope::Global)
                    .assign(Value::scalar(path_val), None)
                    .ok();
            }

            let ref_env = std::cell::RefCell::new(&mut env);
            let mut lexer = yash_syntax::parser::lex::Lexer::from_memory(&input, yash_syntax::source::Source::Unknown);
            let _ = yash_semantics::read_eval_loop(&ref_env, &mut lexer).await;
            
            ref_env.into_inner().exit_status.0 as i32
        };

        runner.run_real(task)
    }).await.unwrap_or(1)
}

/// Execute a shell script file natively through yash.
/// Returns the exit status code.
pub async fn exec_file(path: &str) -> i32 {
    match std::fs::read_to_string(path) {
        Ok(contents) => exec_str(&contents).await,
        Err(e) => {
            eprintln!("lush: {}: {}", path, e);
            1
        }
    }
}
