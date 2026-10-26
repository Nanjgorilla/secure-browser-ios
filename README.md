# セキュアブラウザ (iOS)

広告ゼロ・高セキュリティを目指した SwiftUI + WKWebView 製の iOS ブラウザです。
有料の Apple Developer アカウントなしで、無料の Apple ID と Sideloadly / AltStore でインストールできます。

## 主な機能
- タブ（通常 / プライベート）、アドレスバー（URL または検索。既定は DuckDuckGo 日本）、戻る・進む・再読み込み
- 広告・トラッカーブロック：EasyList / EasyPrivacy を WebKit コンテンツブロッカー形式に変換して同梱（1リスト15万件上限を守り自動分割）
- HTTP → HTTPS 自動昇格、サードパーティ Cookie 遮断
- プライベートタブは非永続データストア（終了すると何も残りません）
- ポップアップ遮断、ユーザー操作なしの `window.open` を無効化、`sendBeacon` 無効化、外部アプリ起動スキーム遮断
- テレメトリ・解析 SDK は一切なし

## IPA の入手
GitHub の **Actions → Build unsigned IPA → 最新の実行 → Artifacts** から `SecureBrowser-unsigned-ipa` をダウンロードし、zip を展開して `SecureBrowser.ipa` を取り出します。
（未署名の IPA です。Sideloadly / AltStore がお使いの Apple ID で再署名します。）

## Sideloadly でのインストール手順

### Windows
1. Apple 公式の **iTunes** と **iCloud**（Microsoft Store 版ではなく apple.com の Web インストーラ版）をインストールします。
2. https://sideloadly.io から Sideloadly をダウンロードしてインストールします。
3. iPhone を USB で接続し、iPhone 側で「このコンピュータを信頼」をタップします。
4. Sideloadly を起動し、上部のデバイス欄に iPhone が表示されることを確認します。
5. `SecureBrowser.ipa` を Sideloadly のウィンドウにドラッグ＆ドロップします。
6. 「Apple account」欄に Apple ID のメールアドレスを入力し **Start** をクリック。パスワード（と2ファクタ認証コード）を入力します。
   ※ 心配な場合はサイドロード専用の Apple ID を作成するのがおすすめです。
7. 「Done」と表示されれば完了です。

### Mac
1. https://sideloadly.io から Mac 版をダウンロードし、アプリケーションフォルダへ移動します。
2. 初回起動時、案内に従って **Mail プラグイン** を有効化します（メール.app → 設定 → 一般 → プラグインを管理 → Sideloadly にチェック → 再起動）。
3. iPhone を USB 接続し「このコンピュータを信頼」をタップします。
4. IPA をドラッグ＆ドロップし、Apple ID を入力して **Start** をクリックします。

### iPhone 側の設定（共通）
1. **設定 → 一般 → VPNとデバイス管理** を開き、自分の Apple ID の項目をタップして「信頼」します。
2. iOS 16 以降では **設定 → プライバシーとセキュリティ → デベロッパモード** をオンにして再起動します（項目はサイドロード後に表示されます）。
3. ホーム画面の「セキュアブラウザ」を起動します。初回のみ広告ブロックルールのコンパイルに数秒〜十数秒かかります。

## ⚠️ 7日ごとの再署名について
無料 Apple ID で署名したアプリは **7日で有効期限が切れ**、起動できなくなります（データは残ります）。
- 期限前に Sideloadly で同じ IPA を同じ Apple ID で再インストールすれば延長されます。
- Sideloadly の「Automatic refresh」や、**AltStore**（AltServer を PC/Mac で常駐させ同じ Wi-Fi に接続）を使うと自動更新できます。
- 無料 Apple ID ではサイドロードアプリは同時に **3個まで**、App ID は 7日間に 10個までです。

## AltStore を使う場合
AltServer を PC/Mac にインストールし、iPhone に AltStore を入れた後、iPhone で IPA を「ファイル」アプリに保存 → AltStore の **My Apps → ＋** から選択します。

## 開発者向け
```sh
python3 scripts/convert_easylist.py   # ルール再生成（CI でも毎回実行）
brew install xcodegen && xcodegen generate
open SecureBrowser.xcodeproj
```
CI（`.github/workflows/build.yml`）は macOS ランナーで `CODE_SIGNING_ALLOWED=NO` でビルドし、`Payload/SecureBrowser.app` を zip して `.ipa` にします。公開リポジトリなら macOS ランナーは無料です。

## 制限事項
- WKWebView の仕様上、YouTube 動画内広告など一部の広告は防げません。
- EasyList の要素隠しはドメイン非依存の汎用ルールのみ、正規表現ルールは未対応です。
