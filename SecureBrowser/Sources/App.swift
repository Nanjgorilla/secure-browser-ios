import SwiftUI

@main
struct SecureBrowserApp: App {
    @StateObject private var store = TabStore()
    var body: some Scene {
        WindowGroup { BrowserView().environmentObject(store) }
    }
}
