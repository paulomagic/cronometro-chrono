#!/bin/bash

# Script para criar um app nativo usando Swift e WKWebView
# que mantém a janela sempre por cima

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HTML_FILE="$SCRIPT_DIR/cronometro-enhanced.html"

# Criar diretório temporário para o Swift app
mkdir -p "/tmp/ChronoHUD"

# Criar o código Swift
cat > "/tmp/ChronoHUD/main.swift" << 'SWIFT_CODE'
import Cocoa
import WebKit

class FloatingWindowController: NSWindowController {
    override func windowDidLoad() {
        super.windowDidLoad()
        
        if let window = window {
            window.level = .floating  // Always on top!
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Criar janela flutuante
        let windowRect = NSRect(x: 100, y: 100, width: 400, height: 650)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // Configurar sempre por cima
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.title = "CHRONO // HUD"
        window.isOpaque = false
        window.backgroundColor = .clear
        
        // Criar WebView
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        
        // Carregar HTML
        let htmlPath = ProcessInfo.processInfo.arguments[1]
        let url = URL(fileURLWithPath: htmlPath)
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        
        window.contentView?.addSubview(webView)
        window.makeKeyAndOrderFront(nil)
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
SWIFT_CODE

echo "✅ App Swift criado em /tmp/ChronoHUD/main.swift"
echo ""
echo "🔨 Para compilar e usar:"
echo "1. Abra o Terminal"
echo "2. Execute: swiftc /tmp/ChronoHUD/main.swift -o /tmp/ChronoHUD/ChronoHUD"
echo "3. Execute: /tmp/ChronoHUD/ChronoHUD '$HTML_FILE'"
echo ""
echo "O app ficará sempre por cima de todas as janelas!"
