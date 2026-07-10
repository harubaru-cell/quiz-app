# Quiz Study

Flutter Webで動く、自分専用のクイズ学習アプリです。

## 役割

- ChatGPT: 授業プリントなどからクイズJSONを作成
- このアプリ: JSONを読み込み、デッキ管理、出題、復習、学習履歴保存を行う

## 対応している問題形式

### 4択問題

`type`に`multiple_choice`を指定します。

### 記述式問題

`type`に`text_input`を指定します。

複数の正解候補を`answers`に登録できます。

## 主な機能

- JSONファイル追加
- 4択問題と記述式問題への対応
- デッキ一覧、問題数、正答率、挑戦回数、最終プレイ日の表示
- デッキ削除
- 出題数選択: 10問 / 20問 / 50問 / 全問
- 問題順シャッフル
- 回答後の正誤、正解、解説表示
- 記述式での複数正解候補
- 次へボタンで手動進行
- 途中終了時も学習履歴を保存
- 結果画面から再挑戦
- 間違えた問題だけ再挑戦
- ブラウザ内保存

## 記述式の正誤判定

記述式では、次の表記の違いを吸収して判定します。

- 前後の空白
- 文字の途中に入った空白
- 全角・半角の英数字や記号
- 英字の大文字・小文字
- ひらがな・カタカナ

たとえば、正解候補が次の場合、

```json
"answers": [
  "平城京",
  "へいじょうきょう"
]
```

以下は正解として扱われます。

```text
平城京
平 城 京
へいじょうきょう
ヘイジョウキョウ
```

ただし、長音などを含む別表記は自動では正解になりません。

```text
へいじょうきょー
```

この表記も正解にしたい場合は、`answers`に追加してください。

## 開発実行

Flutter SDKをインストールし、PATHに`flutter`を追加したうえで実行します。

```powershell
flutter pub get
flutter run -d chrome
```

コードの問題を確認する場合は、次を実行します。

```powershell
flutter analyze
```

## GitHub Pages公開: docsフォルダ方式

このリポジトリでは、GitHub Pagesで公開するビルド済みファイルを`docs/`に配置します。

`build/web`の内容を`docs/`へコピーし、`docs/index.html`の`base href`は、GitHub Pagesのプロジェクトページでも動きやすいように`./`へ調整します。

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

### 4択問題

```json
{
  "id": "sample-001",
  "type": "multiple_choice",
  "question": "正しい選択肢を選んでください。",
  "choices": [
    "選択肢1",
    "選択肢2",
    "選択肢3",
    "選択肢4"
  ],
  "answer": 0,
  "explanation": "正解の解説です。",
  "tags": [],
  "difficulty": "normal"
}
```

`answer`には、正解となる選択肢の番号を`0`から`3`で指定します。

```text
0 = 1番目
1 = 2番目
2 = 3番目
3 = 4番目
```

### 記述式問題

```json
{
  "id": "sample-002",
  "type": "text_input",
  "question": "710年に造営された都の名前を答えなさい。",
  "answers": [
    "平城京",
    "へいじょうきょう"
  ],
  "explanation": "710年に平城京が造営されました。",
  "tags": [
    "日本史",
    "奈良時代"
  ],
  "difficulty": "easy"
}
```

`answers`には、正解として認める回答を1つ以上指定します。

## デッキ全体のJSON例

```json
{
  "subject": "サンプル科目",
  "title": "サンプル問題デッキ",
  "version": "1.1",
  "questions": [
    {
      "id": "sample-001",
      "type": "multiple_choice",
      "question": "Ver.1.1で対応している問題形式はどれですか？",
      "choices": [
        "4択問題と記述式問題",
        "4択問題のみ",
        "複数選択問題のみ",
        "並べ替え問題のみ"
      ],
      "answer": 0,
      "explanation": "Ver.1.1では4択問題と記述式問題に対応しています。",
      "tags": [
        "仕様"
      ],
      "difficulty": "easy"
    },
    {
      "id": "sample-002",
      "type": "text_input",
      "question": "710年に造営された都の名前を答えなさい。",
      "answers": [
        "平城京",
        "へいじょうきょう"
      ],
      "explanation": "710年に平城京が造営されました。",
      "tags": [
        "日本史"
      ],
      "difficulty": "easy"
    }
  ]
}
```

Ver.1.1では、`multiple_choice`と`text_input`に対応しています。