import * as path from 'path';
import * as vscode from 'vscode';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
    TransportKind
} from 'vscode-languageclient/node';

let client: LanguageClient | undefined;

export async function activate(context: vscode.ExtensionContext) {
    console.log('StrictSwift extension is activating...');
    
    // Show activation message
    vscode.window.showInformationMessage('StrictSwift extension activated!');
    
    // Create output channel immediately
    const outputChannel = vscode.window.createOutputChannel('StrictSwift');
    outputChannel.appendLine('StrictSwift extension starting...');
    outputChannel.show();

    // Register commands
    context.subscriptions.push(
        vscode.commands.registerCommand('strictswift.restart', restartServer),
        vscode.commands.registerCommand('strictswift.analyze', analyzeCurrentFile),
        vscode.commands.registerCommand('strictswift.analyzeWorkspace', analyzeWorkspace),
        vscode.commands.registerCommand('strictswift.fixAll', fixAllInCurrentFile)
    );

    // Start the language server
    await startServer(context);
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    return client.stop();
}

async function startServer(context: vscode.ExtensionContext): Promise<void> {
    const config = vscode.workspace.getConfiguration('strictswift');
    
    if (!config.get<boolean>('enable', true)) {
        console.log('StrictSwift is disabled');
        return;
    }

    // Find the server executable
    let serverPath: string | undefined = config.get<string>('serverPath', '');
    if (!serverPath) {
        // Try to find in PATH or common locations
        serverPath = await findServerExecutable();
    }

    if (!serverPath) {
        vscode.window.showWarningMessage(
            'StrictSwift language server not found. Please install it or set the path in settings.'
        );
        return;
    }

    // Server options
    const serverOptions: ServerOptions = {
        run: {
            command: serverPath,
            transport: TransportKind.stdio
        },
        debug: {
            command: serverPath,
            transport: TransportKind.stdio
        }
    };

    // Client options
    const clientOptions: LanguageClientOptions = {
        documentSelector: [{ scheme: 'file', language: 'swift' }],
        synchronize: {
            fileEvents: vscode.workspace.createFileSystemWatcher('**/*.swift')
        },
        outputChannelName: 'StrictSwift',
        traceOutputChannel: vscode.window.createOutputChannel('StrictSwift Trace')
    };

    // Create and start the client
    client = new LanguageClient(
        'strictswift',
        'StrictSwift Language Server',
        serverOptions,
        clientOptions
    );

    try {
        await client.start();
        console.log('StrictSwift language server started successfully');
    } catch (error) {
        console.error('Failed to start StrictSwift language server:', error);
        vscode.window.showErrorMessage(`Failed to start StrictSwift: ${error}`);
    }
}

async function findServerExecutable(): Promise<string | undefined> {
    // Common locations to check
    const possiblePaths = [
        // From Swift build
        '.build/debug/strictswift-lsp',
        '.build/release/strictswift-lsp',
        // Installed globally
        '/usr/local/bin/strictswift-lsp',
        '/opt/homebrew/bin/strictswift-lsp',
        // In workspace
        'strictswift-lsp'
    ];

    // Check workspace folders first
    const workspaceFolders = vscode.workspace.workspaceFolders;
    if (workspaceFolders) {
        for (const folder of workspaceFolders) {
            for (const relativePath of possiblePaths) {
                const fullPath = path.join(folder.uri.fsPath, relativePath);
                if (await fileExists(fullPath)) {
                    return fullPath;
                }
            }
        }
    }

    // Check absolute paths
    for (const absolutePath of possiblePaths.filter(p => p.startsWith('/'))) {
        if (await fileExists(absolutePath)) {
            return absolutePath;
        }
    }

    // Try to find using 'which' command
    try {
        const { exec } = require('child_process');
        const result = await new Promise<string>((resolve, reject) => {
            exec('which strictswift-lsp', (error: Error | null, stdout: string) => {
                if (error) reject(error);
                else resolve(stdout.trim());
            });
        });
        if (result) return result;
    } catch {
        // Ignore errors
    }

    return undefined;
}

async function fileExists(filePath: string): Promise<boolean> {
    try {
        await vscode.workspace.fs.stat(vscode.Uri.file(filePath));
        return true;
    } catch {
        return false;
    }
}

async function restartServer(): Promise<void> {
    if (client) {
        await client.stop();
        client = undefined;
    }
    
    const context = await vscode.commands.executeCommand<vscode.ExtensionContext>(
        'strictswift.getContext'
    );
    
    // Just restart using workspace configuration
    await startServer({ subscriptions: [] } as unknown as vscode.ExtensionContext);
    vscode.window.showInformationMessage('StrictSwift language server restarted');
}

async function analyzeCurrentFile(): Promise<void> {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== 'swift') {
        vscode.window.showWarningMessage('Please open a Swift file to analyze');
        return;
    }

    // Trigger a save to get fresh diagnostics
    await editor.document.save();
    vscode.window.showInformationMessage('StrictSwift analysis triggered');
}

async function analyzeWorkspace(): Promise<void> {
    vscode.window.showInformationMessage('Analyzing workspace... (not yet implemented)');
    // TODO: Implement workspace analysis
}

async function fixAllInCurrentFile(): Promise<void> {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== 'swift') {
        vscode.window.showWarningMessage('Please open a Swift file to fix');
        return;
    }

    // Get all diagnostics for the current document
    const diagnostics = vscode.languages.getDiagnostics(editor.document.uri);
    const strictswiftDiagnostics = diagnostics.filter(
        d => d.source === 'strictswift'
    );

    if (strictswiftDiagnostics.length === 0) {
        vscode.window.showInformationMessage('No StrictSwift issues to fix');
        return;
    }

    // Request code actions for each diagnostic
    let fixCount = 0;
    for (const diagnostic of strictswiftDiagnostics) {
        const actions = await vscode.commands.executeCommand<vscode.CodeAction[]>(
            'vscode.executeCodeActionProvider',
            editor.document.uri,
            diagnostic.range,
            vscode.CodeActionKind.QuickFix
        );

        if (actions && actions.length > 0) {
            // Apply the first available fix
            const fix = actions.find(a => a.edit);
            if (fix?.edit) {
                await vscode.workspace.applyEdit(fix.edit);
                fixCount++;
            }
        }
    }

    vscode.window.showInformationMessage(`Applied ${fixCount} fixes`);
}
