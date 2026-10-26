import SwiftUI
import WebKit

struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct BrowserView: View {
    @EnvironmentObject var store: TabStore
    @State private var showTabs = false
    var body: some View {
        Group {
            if !store.ready {
                VStack(spacing: 12) { ProgressView(); Text("広告ブロックルールを準備中…（初回のみ時間がかかります）").font(.footnote) }
            } else if let tab = store.current {
                TabPage(tab: tab, showTabs: $showTabs).id(tab.id)
            }
        }
        .task { await store.start() }
        .sheet(isPresented: $showTabs) { TabList().environmentObject(store) }
    }
}

struct TabPage: View {
    @EnvironmentObject var store: TabStore
    @ObservedObject var tab: BrowserTab
    @Binding var showTabs: Bool
    @State private var input = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if tab.isPrivate { Image(systemName: "eye.slash").foregroundColor(.purple) }
                Image(systemName: tab.urlString.hasPrefix("https://") ? "lock.fill" : "lock.open").foregroundColor(.secondary)
                TextField("検索またはURLを入力", text: $input)
                    .keyboardType(.webSearch).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .submitLabel(.go).focused($focused)
                    .onSubmit { tab.load(input: input) }
                Button { if tab.isLoading { tab.webView.stopLoading() } else { tab.webView.reload() } } label: {
                    Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                }.accessibilityLabel(tab.isLoading ? "停止" : "再読み込み")
            }
            .padding(8).background(Color(.secondarySystemBackground)).cornerRadius(10).padding(.horizontal, 8).padding(.top, 4)
            if tab.isLoading { ProgressView(value: tab.progress).progressViewStyle(.linear) }
            WebViewHost(webView: tab.webView)
            HStack {
                Button { tab.webView.goBack() } label: { Image(systemName: "chevron.backward") }.disabled(!tab.canGoBack).accessibilityLabel("戻る")
                Spacer()
                Button { tab.webView.goForward() } label: { Image(systemName: "chevron.forward") }.disabled(!tab.canGoForward).accessibilityLabel("進む")
                Spacer()
                Menu {
                    Button("新しいタブ") { store.newTab(isPrivate: false) }
                    Button("新しいプライベートタブ") { store.newTab(isPrivate: true) }
                    Button("このタブを閉じる", role: .destructive) { store.close(tab) }
                    Button("閲覧データを全て消去", role: .destructive) { Task { await store.clearAllData() } }
                } label: { Image(systemName: "plus.square.on.square") }
                Spacer()
                Button { showTabs = true } label: {
                    Text("\(store.tabs.count)").font(.caption.bold()).frame(width: 24, height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke())
                }.accessibilityLabel("タブ一覧")
            }.font(.title3).padding(.horizontal, 24).padding(.vertical, 8)
        }
        .onChange(of: tab.urlString) { v in if !focused { input = v } }
        .onAppear { input = tab.urlString; if tab.urlString.isEmpty { focused = true } }
    }
}

struct TabList: View {
    @EnvironmentObject var store: TabStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            List {
                ForEach(store.tabs) { t in
                    Button { store.currentID = t.id; dismiss() } label: {
                        HStack {
                            if t.isPrivate { Image(systemName: "eye.slash").foregroundColor(.purple) }
                            VStack(alignment: .leading) {
                                Text(t.title).lineLimit(1)
                                Text(t.urlString).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                            if t.id == store.currentID { Spacer(); Image(systemName: "checkmark") }
                        }
                    }
                }.onDelete { idx in idx.map { store.tabs[$0] }.forEach(store.close) }
            }
            .navigationTitle("タブ")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("プライベート") { store.newTab(isPrivate: true); dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("新規") { store.newTab(isPrivate: false); dismiss() } }
            }
        }
    }
}
