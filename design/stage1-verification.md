# 第1段階の実装・検証記録

日付: 2026-10-30（日本時間）

## 状態

バックアップ機能と隔離復元の実装、および合成データによる検証は完了。PC Chrome・iPhone Safariの実際の学習データの取得・バックアップは未実施。実データの件数・内容も未確認。

現行の保存形式、出題、採点、復習、進捗処理を移行していない。本番保存領域へ復元する機能はない。実装検証時点ではdocs・GitHubを変更せず、コミット・プッシュ・公開を行わず停止した。2026-10-30に利用者から第1段階の公開承認を受けたため、既存docs方式での公開を行う。Ollama・外部サービスの設定は変更せず、Pythonは使用していない。

## 実施した検証

| 検証 | 結果 |
| --- | --- |
| `dart analyze --fatal-infos` | 指摘なし |
| `flutter test --no-pub --reporter expanded` | 104件成功。既存75件＋追加29件（保存系24件・画面5件） |
| `dart tool/run_backup_browser_probe.dart` | 実Chromeで3項目成功。新規プロファイル・専用ループバックOrigin・合成データを使用 |
| `flutter build web --no-pub --release --base-href /quiz-app/` | 成功。生成先はbuild/webのみ |
| `git diff --check` | 差分の空白エラーなし |
| `git diff --name-only -- docs` | 変更なし |
| バックアップ既定名・重複保存名のGit除外 | 除外されることを確認 |

テストの内容:

- 4択・記述式・フラッシュカード、Unicode・改行・未知の追加項目・日時の原文保持。
- 未作成キー、空文字、空配列、保存済みnullの区別。
- SHA-256不一致、欠損JSON、未対応版、対象外キー、不正Base64の拒否。
- 領域別の件数、一周の順序と位置、履歴・進捗内の集計不整合。
- 存在しない参照を削除・修復せず警告すること。
- 取得中のデータ変化、読取失敗、隔離ストア作成失敗の検出。
- 別DBの書込後に接続を閉じ、再オープンして原文・音声・未作成キーの一致を確認。
- 元DB名・任意の名前を検証領域の削除対象にできないこと。
- 保存依頼とファイル再選択・復元検証を区別する画面。
- 再取得失敗時に古いバックアップの保存操作を有効にしないこと。
- 小さい画面で作成操作・診断へスクロールできること。

実Chromeの3項目:

1. 原文一致と、不在の元音声DBを新設しないこと。
2. 実IndexedDBで音声込み復元・再オープン・元データと対象外データの不変性・検証DB削除。
3. 未対応の音声ストアを黙って省略せず拒否し、元スキーマを保持すること。

Flutter標準Chromeテストは、SDK付属スナップショットの存在しないパス参照、ソース入口での読み込み停止により完走していない。SDKは修正していない。上記の独立したブラウザ試験で同じ製品コードの保存アダプターを検証した。標準Chromeテストの3件を成功件数に含めていない。

ビルドにはCupertinoIconsのフォント不足を示す警告が残る。ビルド自体は成功しているが、iPhoneのファイル選択・保存を含む実画面での影響は未確認。今回、無関係な依存追加やSDK変更では解消していない。

## 追加ファイル

- `lib/backup_main.dart`: AppStateを起動しない専用入口。
- `lib/models/quiz_backup.dart`: 原文・音声・メタデータ、SHA-256、厳密なバックアップ形式の読込。
- `lib/screens/backup_screen.dart`: 作成、保存依頼、ファイル再選択、診断、隔離復元の画面。
- `lib/services/backup_service.dart`: 読取専用インターフェースと2回取得・JSON往復の照合。
- `lib/services/backup_validation_service.dart`: 件数・構造・参照・整合性の診断。
- `lib/services/backup_sandbox_service.dart`: 別DBへ復元し、再読込・照合後に検証DBを削除。
- `lib/services/backup_browser.dart`: 条件付きWeb実装の入口。
- `lib/services/backup_browser_web.dart`: localStorage・音声DBの読取、ダウンロード操作。
- `lib/services/backup_browser_stub.dart`: Web以外で誤動作させない実装。
- `test/services/backup_service_test.dart`: 保存系24件。
- `test/screens/backup_screen_test.dart`: 画面5件。
- `test/browser/backup_browser_test.dart`: 標準Chrome試験用。現在の環境では未完走。
- `test/support/backup_fixtures.dart`: 架空の検証データ。
- `tool/backup_browser_probe.dart`: 描画エンジンを使わない実ブラウザ検証。
- `tool/run_backup_browser_probe.dart`: コンパイル、一時サーバー、新規Chromeプロファイル、結果回収。
- `design/stage1-backup.md`: 操作手順、保存形式、安全境界、制約。
- `design/implementation-plan.md`: 今後の同期時の挙動と難易度選択の前倒し。
- `design/stage1-verification.md`: この記録。

## 変更ファイル

- `lib/main.dart`: `?backup=1`なら既存の読込時移行より先に専用画面を開く。
- `lib/screens/home_screen.dart`: バックアップ画面への入口を追加。
- `pubspec.yaml`・`pubspec.lock`: 既存のcrypto 3.0.7を直接依存として宣言。既存パッケージ版は更新していない。
- `.gitignore`: 個人バックアップの既定名・重複保存名・専用退避フォルダを除外。
- `README.md`: 未公開機能の手順と計画へのリンク。

## 次に必要な操作と確認

localhostで公開サイトのデータを読むことはできない。各端末では、公開更新の反映と「バックアップ・復元検証」画面の表示を確認する必要がある。

PCとiPhoneの実データを保全するには、公開反映後に両端末の同じ利用領域で、書き出し→ファイル保存→再選択→隔離検証を実施する必要がある。通常起動の既存移行を避けるため、公開後の初回は`?backup=1`の専用入口を直接開く手順を推奨する。古いキャッシュが残った場合も、サイトデータを削除せずに更新方法を確認する。

iPhone Safariでの保存・再選択、実データの件数と注意事項、両端末それぞれのファイル検証は未完了。第2段階に進む前にこれらを確認し、別途実装承認を得る。
