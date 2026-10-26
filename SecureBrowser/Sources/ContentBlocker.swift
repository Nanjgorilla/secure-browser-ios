import WebKit

/// バンドル済みの EasyList / EasyPrivacy ルールをコンパイルしてキャッシュする。
@MainActor
final class ContentBlocker {
    static let shared = ContentBlocker()
    private(set) var lists: [WKContentRuleList] = []
    private var loading: Task<Void, Never>?

    /// 全ページ共通の追加ルール（HTTPS昇格・サードパーティCookie遮断）
    private let extraRules = """
    [
      {"trigger":{"url-filter":"^http://"},"action":{"type":"make-https"}},
      {"trigger":{"url-filter":".*","load-type":["third-party"]},"action":{"type":"block-cookies"}}
    ]
    """

    func load() async {
        if let loading { await loading.value; return }
        let t = Task { await self.compileAll() }
        loading = t
        await t.value
    }

    private func compileAll() async {
        let store = WKContentRuleListStore.default()!
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        var sources: [(String, String)] = [("extra-v\(version)", extraRules)]
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Rules")
            ?? Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let s = try? String(contentsOf: url, encoding: .utf8) {
                sources.append((url.deletingPathExtension().lastPathComponent + "-v\(version)", s))
            }
        }
        var result: [WKContentRuleList] = []
        for (id, json) in sources {
            if let cached = try? await store.contentRuleList(forIdentifier: id) {
                result.append(cached); continue
            }
            do {
                if let list = try await store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) {
                    result.append(list)
                }
            } catch {
                // 失敗したリストはスキップ（ログ送信等は一切しない）
                print("rule compile failed: \(id) \(error)")
            }
        }
        lists = result
    }

    func apply(to controller: WKUserContentController) {
        for l in lists { controller.add(l) }
    }
}
