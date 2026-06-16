const vscode = require('vscode');
const path = require('path');
const { LanguageClient } = require('vscode-languageclient/node');

let client;

function activate(context) {


    // 1. Find the compiled standalone Rust binary relative to this extension file
    const serverModule = path.resolve(
        context.extensionPath, 
        '..', 
        '..', 
        'lsp', 
        'target', 
        'debug', 
        'lush-lsp'
    );

    // 2. Configure how to run the binary
    const serverOptions = {
        run: { command: serverModule },
        debug: { command: serverModule }
    };

    // 3. Tell VS Code which file types trigger our LSP engine
    const clientOptions = {
        documentSelector: [
            { scheme: 'file', language: 'lua' },
            { scheme: 'file', language: 'lush' },
            { scheme: 'file', language: 'plaintext' }
        ],
        synchronize: {
            fileEvents: vscode.workspace.createFileSystemWatcher('**/*')
        }
    };

    // 4. Create and boot the language client
    client = new LanguageClient(
        'lushLsp',
        'Lush Language Server',
        serverOptions,
        clientOptions
    );

    client.start();

}

function deactivate() {
    if (!client) {
        return undefined;
    }
    return client.stop();
}

module.exports = {
    activate,
    deactivate
};