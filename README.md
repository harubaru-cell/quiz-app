# Quiz Study

Flutter Webで動く、自分専用の4択クイズ学習アプリです。

## 役割

- ChatGPT: 授業プリントから4択クイズJSONを作成
- このアプリ: JSONを読み込み、デッキ管理、出題、復習、学習履歴保存を行う

## 主な機能

- JSONファイル追加
- デッキ一覧、問題数、正答率、挑戦回数、最終プレイ日の表示
- デッキ削除
- 出題数選択: 10問 / 20問 / 50問 / 全問
- 問題順シャッフル
- 回答後の正誤、正解、解説表示
- 次へボタンで手動進行
- 途中終了時も学習履歴を保存
- 結果画面から再挑戦、間違えた問題だけ再挑戦
- ブラウザ内保存

## 開発実行

Flutter SDKをインストールし、PATHに`flutter`を追加したうえで実行します。

```powershell
flutter pub get
flutter run -d chrome
```

## GitHub Pages公開: docsフォルダ方式

このリポジトリでは、GitHub Pagesで公開するビルド済みファイルを`docs/`に配置します。

すでに`build/web`の内容を`docs/`へコピー済みです。`docs/index.html`の`base href`は、GitHub Pagesのプロジェクトページでも動きやすいように`./`へ調整しています。

GitHub側の設定:

1. GitHubリポジトリを開く
2. `Settings`を開く
3. `Pages`を開く
4. `Build and deployment`の`Source`を`Deploy from a branch`にする
5. `Branch`を`main`、フォルダを`/docs`にする
6. `Save`する

次回以降、Flutter SDKが使える環境では次の流れで更新します。

```powershell
flutter build web --release --base-href "./"
Copy-Item -Path build\web\* -Destination docs -Recurse -Force
```

iPhoneではSafariで公開URLを開き、共有メニューから「ホーム画面に追加」を選びます。

## JSON形式

```json
{
  "subject": "",
  "title": "",
  "version": "1.0",
  "questions": [
    {
      "id": "",
      "type": "multiple_choice",
      "question": "",
      "choices": ["", "", "", ""],
      "answer": 0,
      "explanation": "",
      "tags": [],
      "difficulty": "normal"
    }
  ]
}
```

Ver.1では`type`は`multiple_choice`のみ対応しています。
