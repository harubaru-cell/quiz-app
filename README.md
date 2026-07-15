# Quiz Study

Flutter Webで動く、自分専用のクイズ学習アプリです。

現在のアプリバージョン: **Ver.1.4**

## 役割

- ChatGPT: 授業プリントなどからクイズJSONや音声付きZIPを作成
- このアプリ: デッキの読み込み、出題、復習、学習履歴、音声の保存を行う

## 対応している問題形式

### 4択問題

`type`に`multiple_choice`を指定します。

### 記述式問題

`type`に`text_input`を指定します。

複数の正解候補を`answers`に登録できます。

### 音声付き問題

4択・記述式のどちらにも、任意で`audio`を追加できます。

```json
"audio": "audio/question-001.mp3"
```

音声付きのデッキは、`deck.json`と音声ファイルをZIPにまとめて読み込みます。

## 主な機能

- JSONファイルの追加
- 音声付きZIPファイルの追加
- 4択問題と記述式問題への対応
- 4択・記述式の両方で音声再生
- ZIP内音声のブラウザ内保存
- デッキ一覧、問題数、正答率、挑戦回数、最終プレイ日の表示
- デッキ削除
- デッキ削除時に保存済み音声も削除
- 出題数選択: 10問 / 20問 / 50問 / 全問
- 問題順シャッフル
- 回答後の正誤、正解、解説表示
- 記述式での複数正解候補
- 記述式で未入力のまま回答し、不正解・要復習として記録
- 次へボタンで手動進行
- 途中終了時も学習履歴を保存
- 結果画面から再挑戦
- 間違えた問題だけ再挑戦
- 問題ごとの未回答・正解・要復習の進捗保存
- 未回答・間違い・未習得の問題に絞った出題
- 固定した出題順で重複せず全問を一周
- 10問単位で進め、現在の区切りの残りから再開
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

ただし、長音などを含む別表記は、自動では正解になりません。

```text
へいじょうきょー
```

この表記も正解にしたい場合は、`answers`に追加してください。

## 開発実行

Flutter SDKをインストールし、PATHに`flutter`を追加したうえで実行します。

```powershell
flutter pub get
flutter run -d chrome --web-port 8081
```

開発中はポートを固定すると、ブラウザ内に保存したデッキや音声を継続して利用できます。

コードの問題を確認する場合は、次を実行します。

```powershell
flutter analyze
```

## JSONデッキ

音声を使用しないデッキは、JSONファイル単体で読み込めます。

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

## 音声付きZIPデッキ

音声付き問題では、JSONと音声ファイルをZIPにまとめます。

### ZIPの構成

```text
chinese-listening.zip
├─ deck.json
└─ audio
   ├─ question-001.mp3
   ├─ question-002.mp3
   └─ question-003.mp3
```

ZIP内のJSONファイル名は、必ず次の名前にします。

```text
deck.json
```

### 音声付き記述式問題

```json
{
  "id": "chinese-001",
  "type": "text_input",
  "question": "音声を聞いて、簡体字で書きなさい。",
  "audio": "audio/question-001.mp3",
  "answers": [
    "你好"
  ],
  "explanation": "你好は「こんにちは」という意味です。",
  "tags": [
    "中国語",
    "リスニング"
  ],
  "difficulty": "easy"
}
```

### 音声付き4択問題

```json
{
  "id": "chinese-002",
  "type": "multiple_choice",
  "question": "音声の内容として正しいものを選びなさい。",
  "audio": "audio/question-002.mp3",
  "choices": [
    "你好",
    "谢谢",
    "再见",
    "对不起"
  ],
  "answer": 0,
  "explanation": "音声では「你好」と発音しています。",
  "tags": [
    "中国語",
    "リスニング"
  ],
  "difficulty": "easy"
}
```

## 音声ファイルについて

ZIP内の音声は、デッキ読み込み時にブラウザ内へ保存されます。

そのため、読み込み後はZIPファイルを毎回選び直す必要はありません。

デッキを削除すると、そのデッキの学習履歴と保存済み音声も削除されます。

対応を想定している主な音声形式:

```text
.mp3
.m4a
.wav
.ogg
.aac
.webm
```

## デッキ全体のJSON例

```json
{
  "deckId": "sample-deck-001",
  "subject": "サンプル科目",
  "title": "サンプル問題デッキ",
  "version": "1.4",
  "questions": [
    {
      "id": "sample-001",
      "type": "multiple_choice",
      "question": "Ver.1.4で対応している問題形式はどれですか？",
      "choices": [
        "4択・記述式・音声付き問題",
        "4択問題のみ",
        "複数選択問題のみ",
        "並べ替え問題のみ"
      ],
      "answer": 0,
      "explanation": "Ver.1.4では、4択・記述式・音声付き問題に対応しています。",
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
    },
    {
      "id": "sample-003",
      "type": "text_input",
      "question": "音声を聞いて答えなさい。",
      "audio": "audio/question-003.mp3",
      "answers": [
        "你好"
      ],
      "explanation": "音声では「你好」と発音しています。",
      "tags": [
        "中国語",
        "リスニング"
      ],
      "difficulty": "easy"
    }
  ]
}
```

Ver.1.4では、`multiple_choice`と`text_input`に対応し、両方の問題形式へ任意で`audio`を追加できます。

## GitHub Pages公開: docsフォルダ方式

このリポジトリでは、GitHub Pagesで公開するビルド済みファイルを`docs/`に配置します。

公開URL:

```text
https://harubaru-cell.github.io/quiz-app/
```

GitHub側の設定:

1. GitHubリポジトリを開く
2. `Settings`を開く
3. `Pages`を開く
4. `Build and deployment`の`Source`を`Deploy from a branch`にする
5. `Branch`を`main`、フォルダを`/docs`にする
6. `Save`する

公開用ビルド:

```powershell
flutter build web --release --base-href "/quiz-app/"
Copy-Item -Path build\web\* -Destination docs -Recurse -Force
```

iPhoneではSafariで公開URLを開き、共有メニューから「ホーム画面に追加」を選びます。
