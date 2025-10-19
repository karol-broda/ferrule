import * as path from 'path';
import * as fs from 'fs';
import { workspace, ExtensionContext, window } from 'vscode';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
    TransportKind
} from 'vscode-languageclient/node';

let client: LanguageClient | undefined;

export function activate(context: ExtensionContext) {
    const config = workspace.getConfiguration('ferrule');
    let serverPath = config.get<string>('lspPath', '');

    if (!serverPath || serverPath === '') {
        // try to find ferrule-lsp in the workspace
        const workspaceFolders = workspace.workspaceFolders;
        if (workspaceFolders && workspaceFolders.length > 0) {
            const workspaceRoot = workspaceFolders[0].uri.fsPath;
            const possiblePaths = [
                path.join(workspaceRoot, 'zig-out', 'bin', 'ferrule-lsp'),
                path.join(workspaceRoot, 'zig-out', 'bin', 'ferrule-lsp.exe'),
            ];

            for (const possiblePath of possiblePaths) {
                if (fs.existsSync(possiblePath)) {
                    serverPath = possiblePath;
                    break;
                }
            }
        }

        // if still not found, try PATH
        if (!serverPath || serverPath === '') {
            serverPath = 'ferrule-lsp';
        }
    }

    const serverOptions: ServerOptions = {
        command: serverPath,
        transport: TransportKind.stdio,
    };

    const clientOptions: LanguageClientOptions = {
        documentSelector: [{ scheme: 'file', language: 'ferrule' }],
        synchronize: {
            fileEvents: workspace.createFileSystemWatcher('**/*.fe')
        }
    };

    client = new LanguageClient(
        'ferruleLsp',
        'Ferrule Language Server',
        serverOptions,
        clientOptions
    );

    // start the client, this will also launch the server
    client.start().catch((error) => {
        window.showErrorMessage(`Failed to start Ferrule LSP: ${error.message}`);
        console.error('Failed to start Ferrule LSP:', error);
    });
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    return client.stop();
}

