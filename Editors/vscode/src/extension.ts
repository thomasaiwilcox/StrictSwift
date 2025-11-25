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
    
    // Store context for restart functionality
    extensionContext = context;
    
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
        vscode.commands.registerCommand('strictswift.fixAll', fixAllInCurrentFile),
        vscode.commands.registerCommand('strictswift.showProfile', showCurrentProfile),
        vscode.commands.registerCommand('strictswift.generateConfig', generateConfigFile)
    );
    
    // Watch for configuration changes
    context.subscriptions.push(
        vscode.workspace.onDidChangeConfiguration(e => {
            if (e.affectsConfiguration('strictswift')) {
                vscode.window.showInformationMessage(
                    'StrictSwift configuration changed. Restart the language server for changes to take effect.',
                    'Restart'
                ).then(selection => {
                    if (selection === 'Restart') {
                        restartServer();
                    }
                });
            }
        })
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
        const installAction = 'Show Installation Instructions';
        const settingsAction = 'Open Settings';
        const result = await vscode.window.showWarningMessage(
            'StrictSwift language server not found.',
            installAction,
            settingsAction
        );
        
        if (result === installAction) {
            const instructions = `# StrictSwift LSP Installation

## Option 1: Install via Homebrew (coming soon)
\`\`\`bash
brew install strictswift
\`\`\`

## Option 2: Build from source
\`\`\`bash
git clone https://github.com/thomasaiwilcox/StrictSwift.git
cd StrictSwift
swift build --product strictswift-lsp -c release
sudo cp .build/release/strictswift-lsp /usr/local/bin/
\`\`\`

## Option 3: Set path manually
1. Open VS Code Settings (Cmd+,)
2. Search for "strictswift.serverPath"
3. Set the full path to your strictswift-lsp binary
`;
            const doc = await vscode.workspace.openTextDocument({
                content: instructions,
                language: 'markdown'
            });
            await vscode.window.showTextDocument(doc);
        } else if (result === settingsAction) {
            await vscode.commands.executeCommand('workbench.action.openSettings', 'strictswift.serverPath');
        }
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

    // Build initialization options from VS Code settings
    const initializationOptions = {
        profile: config.get<string>('profile', 'criticalCore'),
        rules: {
            safety: {
                enabled: config.get<boolean>('rules.safety.enabled', true),
                severity: config.get<string>('rules.safety.severity', 'error')
            },
            concurrency: {
                enabled: config.get<boolean>('rules.concurrency.enabled', true),
                severity: config.get<string>('rules.concurrency.severity', 'error')
            },
            memory: {
                enabled: config.get<boolean>('rules.memory.enabled', true),
                severity: config.get<string>('rules.memory.severity', 'error')
            },
            architecture: {
                enabled: config.get<boolean>('rules.architecture.enabled', true),
                severity: config.get<string>('rules.architecture.severity', 'warning')
            },
            complexity: {
                enabled: config.get<boolean>('rules.complexity.enabled', true),
                severity: config.get<string>('rules.complexity.severity', 'warning')
            },
            performance: {
                enabled: config.get<boolean>('rules.performance.enabled', true),
                severity: config.get<string>('rules.performance.severity', 'hint')
            }
        },
        excludePaths: config.get<string[]>('excludePaths', []),
        includePaths: config.get<string[]>('includePaths', [])
    };

    // Client options
    const clientOptions: LanguageClientOptions = {
        documentSelector: [{ scheme: 'file', language: 'swift' }],
        synchronize: {
            fileEvents: vscode.workspace.createFileSystemWatcher('**/*.swift'),
            configurationSection: 'strictswift'
        },
        initializationOptions,
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

// Store extension context for restart
let extensionContext: vscode.ExtensionContext | undefined;

async function restartServer(): Promise<void> {
    if (client) {
        await client.stop();
        client = undefined;
    }
    
    if (extensionContext) {
        await startServer(extensionContext);
        vscode.window.showInformationMessage('StrictSwift language server restarted');
    } else {
        vscode.window.showErrorMessage('Cannot restart: extension context not available');
    }
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

async function showCurrentProfile(): Promise<void> {
    const config = vscode.workspace.getConfiguration('strictswift');
    const profile = config.get<string>('profile', 'criticalCore');
    
    const profileDescriptions: { [key: string]: string } = {
        'criticalCore': 'Critical Core - Essential safety rules only',
        'teamDefault': 'Team Default - Balanced rules for team projects',
        'legacy': 'Legacy - Lenient rules for existing codebases',
        'newProject': 'New Project - Strict rules for new development',
        'enterprise': 'Enterprise - Comprehensive coverage',
        'custom': 'Custom - Using individual rule settings'
    };
    
    const categories = ['safety', 'concurrency', 'memory', 'architecture', 'complexity', 'performance'];
    let details = `**Current Profile:** ${profileDescriptions[profile] || profile}\n\n`;
    details += '### Rule Categories\n\n';
    
    for (const cat of categories) {
        const enabled = config.get<boolean>(`rules.${cat}.enabled`, true);
        const severity = config.get<string>(`rules.${cat}.severity`, 'warning');
        const emoji = enabled ? '✅' : '❌';
        details += `${emoji} **${cat.charAt(0).toUpperCase() + cat.slice(1)}**: ${enabled ? severity : 'disabled'}\n`;
    }
    
    const doc = await vscode.workspace.openTextDocument({
        content: details,
        language: 'markdown'
    });
    await vscode.window.showTextDocument(doc, { preview: true });
}

async function generateConfigFile(): Promise<void> {
    const config = vscode.workspace.getConfiguration('strictswift');
    const profile = config.get<string>('profile', 'criticalCore');
    
    const configContent = `# StrictSwift Configuration
# Generated from VS Code settings

profile: ${profile}

rules:
  safety:
    enabled: ${config.get<boolean>('rules.safety.enabled', true)}
    severity: ${config.get<string>('rules.safety.severity', 'error')}
  
  concurrency:
    enabled: ${config.get<boolean>('rules.concurrency.enabled', true)}
    severity: ${config.get<string>('rules.concurrency.severity', 'error')}
  
  memory:
    enabled: ${config.get<boolean>('rules.memory.enabled', true)}
    severity: ${config.get<string>('rules.memory.severity', 'error')}
  
  architecture:
    enabled: ${config.get<boolean>('rules.architecture.enabled', true)}
    severity: ${config.get<string>('rules.architecture.severity', 'warning')}
  
  complexity:
    enabled: ${config.get<boolean>('rules.complexity.enabled', true)}
    severity: ${config.get<string>('rules.complexity.severity', 'warning')}
  
  performance:
    enabled: ${config.get<boolean>('rules.performance.enabled', true)}
    severity: ${config.get<string>('rules.performance.severity', 'hint')}

exclude:
${(config.get<string[]>('excludePaths', []) || []).map(p => `  - "${p}"`).join('\n')}

# Uncomment to include only specific paths
# include:
#   - "Sources/**"
#   - "Tests/**"
`;

    const workspaceFolders = vscode.workspace.workspaceFolders;
    if (!workspaceFolders || workspaceFolders.length === 0) {
        // No workspace, just show the content
        const doc = await vscode.workspace.openTextDocument({
            content: configContent,
            language: 'yaml'
        });
        await vscode.window.showTextDocument(doc);
        return;
    }

    const configPath = vscode.Uri.joinPath(workspaceFolders[0].uri, '.strictswift.yml');
    
    try {
        await vscode.workspace.fs.stat(configPath);
        // File exists, ask to overwrite
        const overwrite = await vscode.window.showWarningMessage(
            '.strictswift.yml already exists. Overwrite?',
            'Overwrite',
            'Cancel'
        );
        if (overwrite !== 'Overwrite') {
            return;
        }
    } catch {
        // File doesn't exist, proceed
    }

    await vscode.workspace.fs.writeFile(configPath, Buffer.from(configContent, 'utf8'));
    const doc = await vscode.workspace.openTextDocument(configPath);
    await vscode.window.showTextDocument(doc);
    vscode.window.showInformationMessage('Created .strictswift.yml configuration file');
}
