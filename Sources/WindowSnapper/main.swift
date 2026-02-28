import AppKit
import Foundation

// Simple file-based debug logger
func debugLog(_ message: String) {
    let line = "\(Date()): \(message)\n"
    let path = "/tmp/zoned-debug.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

debugLog("main.swift: starting")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon; lives in the menu bar only

let delegate = AppDelegate()
app.delegate = delegate
app.run()
