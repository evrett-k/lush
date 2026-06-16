use mlua::Lua;
use std::sync::Arc;
use tokio::sync::Mutex;
use tower_lsp::jsonrpc::Result;
use tower_lsp::lsp_types::*; // This handles standard types, but tower_lsp has specific sub-exports we need:
use tower_lsp::lsp_types::notification::PublishDiagnostics;
use tower_lsp::{Client, LanguageServer, LspService, Server};

// Explicitly pull in the missing types that Rust couldn't map out of the wildcard export
use tower_lsp::lsp_types::{
    CompletionItem, CompletionItemKind, CompletionResponse, CompletionOptions,
    Diagnostic, DiagnosticSeverity, Documentation, MessageType, Position, Range,
    TextDocumentSyncCapability, TextDocumentSyncKind, Url,
};

struct Backend {
    client: Client,
    document_content: Arc<Mutex<String>>,
}

#[tower_lsp::async_trait]
impl LanguageServer for Backend {
    async fn initialize(&self, _: InitializeParams) -> Result<InitializeResult> {
        Ok(InitializeResult {
            capabilities: ServerCapabilities {
                text_document_sync: Some(TextDocumentSyncCapability::Kind(
                    TextDocumentSyncKind::FULL,
                )),
                ..ServerCapabilities::default()
            },
            ..InitializeResult::default()
        })
    }

    async fn shutdown(&self) -> Result<()> {
        Ok(())
    }

    async fn did_open(&self, params: DidOpenTextDocumentParams) {
        self.validate_document(params.text_document.uri, params.text_document.text).await;
    }

    async fn did_change(&self, mut params: DidChangeTextDocumentParams) {
        if let Some(change) = params.content_changes.pop() {
            self.validate_document(params.text_document.uri, change.text).await;
        }
    }
}

impl Backend {
    async fn validate_document(&self, uri: Url, text: String) {
        let mut diagnostics = Vec::new();
        
        // 1. Map custom syntax locally
        let compiled = lush::lush::precompile(&text);

        // 2. Safely compute the syntax error inside an isolated context block
        let parse_result = tokio::task::block_in_place(|| {
            let lua = Lua::new();
            lua.load(&compiled).into_function().map(|_| ()).map_err(|e| e.to_string())
        });

        // 3. Process the error string if one occurred
        if let Err(error_msg) = parse_result {
            let mut line_number = 0;

            if let Some(pos) = error_msg.find("]:") {
                let sub = &error_msg[pos + 2..];
                if let Some(end_pos) = sub.find(':') {
                    if let Ok(num) = sub[..end_pos].parse::<u32>() {
                        line_number = num.saturating_sub(1);
                    }
                }
            }

            diagnostics.push(Diagnostic {
                range: Range {
                    start: Position::new(line_number, 0),
                    end: Position::new(line_number, 100),
                },
                severity: Some(DiagnosticSeverity::ERROR),
                code: None,
                code_description: None,
                source: Some("Lush LSP".to_string()),
                message: error_msg,
                related_information: None,
                tags: None,
                data: None,
            });
        }

        // 4. Send back to editor window
        let _ = self.client.publish_diagnostics(uri, diagnostics, None).await;
    }
}

#[tokio::main]
async fn main() {
    let stdin = tokio::io::stdin();
    let stdout = tokio::io::stdout();

    let (service, socket) = LspService::new(|client| Backend {
        client,
        document_content: Arc::new(Mutex::new(String::new())),
    });

    Server::new(stdin, stdout, socket).serve(service).await;
}