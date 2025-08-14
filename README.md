# PowerShell & SQLite データ管理システム

## 概要

PowerShellとSQLiteを使用した次世代データ管理・同期・出力システムです。
**設定ベースアーキテクチャ**により保守性を大幅に向上させ、**単一ファイルパス指定**による柔軟な運用と**履歴保存機能**による安全性を実現します。

## ⭐ 主要な特徴

### 🎯 単一ファイルパス指定
- **外部ファイル処理**: 任意の場所にあるCSVファイルを直接指定
- **履歴保存**: 処理ファイルを自動的にdata配下に日本時間タイムスタンプ付きで保存
- **設定ファイル管理**: パラメータまたは設定ファイルでファイルパスを管理

### 🚀 設定ベース保守性向上アーキテクチャ
- **項目追加時の修正箇所**: 複数ファイル → **1ファイルのみ**
- **動的SQL生成**: スキーマ変更に自動対応
- **設定検証機能**: 起動時に設定の整合性をチェック

### 🔍 データフィルタリング機能
- **柔軟な除外条件**: 正規表現パターンや特定値での除外/包含
- **設定可能**: Z始まり・Y始まりの職員番号などを設定で除外
- **詳細ログ**: 除外理由と統計情報を表示

### 📊 豊富なログ・レポート機能
- **統一ログシステム**: 日本時間でのレベル別ログ出力
- **同期統計**: ADD/UPDATE/DELETE/KEEPの件数表示
- **データベース情報**: テーブル別レコード数表示

## 必要な環境

- **PowerShell** 5.1 以上
- **SQLite3** コマンドラインツール（推奨）

## クイックスタート

### 1. ファイルの準備

テスト用のファイルを準備します：

```bash
# テスト用ディレクトリを作成
mkdir test-files

# 職員情報CSVファイルを作成
# ファイル例: test-files/current-staff.csv
```

### 2. 実行方法

#### A. パラメータ指定での実行

```powershell
# Windows PowerShell
.\scripts\main.ps1 -ProvidedDataFilePath "C:\data\provided.csv" -CurrentDataFilePath "C:\data\current.csv" -OutputFilePath "C:\output\result.csv"
```

```bash
# Linux/macOS
pwsh ./scripts/main.ps1 -ProvidedDataFilePath "/data/provided.csv" -CurrentDataFilePath "/data/current.csv" -OutputFilePath "/output/result.csv"
```

#### B. 設定ファイル指定での実行

1. **設定ファイルを編集**: `config/data-sync-config.json`

```json
{
  "file_paths": {
    "provided_data_file_path": "./test-data/provided.csv",
    "current_data_file_path": "./test-data/current.csv",
    "output_file_path": "./test-data/sync-result.csv"
  }
}
```

2. **実行**:

```powershell
# 設定ファイルの値で実行
.\scripts\main.ps1
```

### 3. 実行結果の確認

- **メイン出力**: 指定したパスにCSVファイルが出力
- **履歴保存**: `data/` 配下に日本時間タイムスタンプ付きで自動保存
  - `data/provided-data/` : 提供データの履歴
  - `data/current-data/` : 現在データの履歴
  - `data/output/` : 同期結果の履歴

## ファイル構成

```
ps-sqlite/
├── config/                   # 設定ファイル
│   └── data-sync-config.json # データ同期ツール設定
├── scripts/                  # PowerShellスクリプト
│   ├── main.ps1             # メインスクリプト（単一ファイルパス対応版）
│   └── modules/             # モジュール化されたスクリプト
│       ├── Process/         # 処理系モジュール
│       │   ├── Invoke-ConfigValidation.psm1  # 設定検証
│       │   ├── Invoke-CsvExport.psm1         # CSV出力処理
│       │   ├── Invoke-CsvImport.psm1         # CSV入力処理
│       │   ├── Invoke-DataSync.psm1          # データ同期処理
│       │   ├── Invoke-DatabaseInitialization.psm1 # データベース初期化
│       │   ├── Show-SyncResult.psm1          # 同期結果表示
│       │   ├── Show-SyncStatistics.psm1      # 同期統計表示
│       │   └── Test-DataConsistency.psm1     # データ整合性チェック
│       └── Utils/           # ユーティリティモジュール
│           ├── CommonUtils.psm1          # 共通ユーティリティ（日本時間・ファイルパス解決）
│           ├── ConfigUtils.psm1          # 設定読み込み・検証
│           ├── CsvUtils.psm1             # 設定ベースCSV処理（履歴保存対応）
│           ├── DataFilterUtils.psm1      # データフィルタリング
│           ├── ErrorHandlingUtils.psm1   # 統一エラーハンドリング
│           ├── FileUtils.psm1            # ファイル操作ユーティリティ
│           └── SqlUtils.psm1             # SQL生成・実行ユーティリティ
├── data/                    # 履歴保存ディレクトリ（自動生成）
│   ├── provided-data/       # 提供データ履歴（タイムスタンプ付き）
│   ├── current-data/        # 現在データ履歴（タイムスタンプ付き）
│   └── output/              # 同期結果履歴（タイムスタンプ付き）
├── database/                # SQLiteデータベース
│   └── data-sync.db         # メインデータベース
├── logs/                    # ログファイル（自動生成）
│   └── data-sync-system.log # 実行ログ（ローテーション対応）
├── tests/                   # テストスクリプト（Pester対応）
│   ├── main.Tests.ps1       # メインスクリプトテスト
│   ├── run-test.ps1         # テスト実行スクリプト
│   ├── create-utf8-tests.ps1 # UTF-8テスト作成
│   ├── encoding-fix.ps1     # エンコーディング修正
│   ├── Integration/         # 統合テスト
│   │   └── FullSystem.Tests.ps1 # システム全体テスト
│   ├── Process/             # 処理系モジュールテスト
│   │   └── ... (各モジュールのテスト)
│   ├── TestHelpers/         # テストヘルパー
│   │   ├── MockHelpers.psm1     # モック機能
│   │   └── TestDataGenerator.psm1 # テストデータ生成
│   └── Utils/               # ユーティリティモジュールテスト
│       └── ... (各ユーティリティのテスト)
├── test-data/               # テスト用データ（外部ファイル例）
│   ├── provided.csv         # 提供データサンプル
│   ├── current.csv          # 現在データサンプル
│   ├── large-provided.csv   # 大量データテスト用
│   ├── large-current.csv    # 大量データテスト用
│   └── sync-result.csv      # 同期結果サンプル
├── dependency.md            # 依存関係説明書
├── gemini.md               # Gemini関連ドキュメント
├── review.txt              # レビュー記録
├── test.db                 # テスト用データベース
├── package.json            # Node.js依存関係（開発用）
├── package-lock.json       # Node.js依存関係ロック
├── node_modules/           # Node.js依存関係（自動生成）
└── run.bat                 # Windows実行バッチ
```

## データ項目

**注意**: 以下は現在の設定例です。すべての項目は `config/data-sync-config.json` で変更可能です。

### 提供データ (provided_data) - 現在の設定
- `employee_id` (職員ID) - 必須、ユニーク
- `card_number` (カード番号)
- `name` (氏名) - 必須
- `department` (部署)
- `position` (役職)
- `email` (メールアドレス)
- `phone` (電話番号)
- `hire_date` (入社日)

### 現在データ (current_data) - 現在の設定
- `user_id` (利用者ID) - 必須、ユニーク
- `card_number` (カード番号)
- `name` (氏名) - 必須
- `department` (部署)
- `position` (役職)
- `email` (メールアドレス)
- `phone` (電話番号)
- `hire_date` (入社日)

### 同期結果 (sync_result) - 現在の設定
- `syokuin_no` (職員番号) - 必須
- `card_number` (カード番号)
- `name` (氏名) - 必須
- `department` (部署)
- `position` (役職)
- `email` (メールアドレス)
- `phone` (電話番号)
- `hire_date` (入社日)
- `sync_action` (同期アクション) - 必須 (ADD/UPDATE/DELETE/KEEP)

**設定ベースアーキテクチャ**: 項目の追加・変更・削除は設定ファイルのみで対応可能です。

## 設定ファイル

### ファイルパス設定

`config/data-sync-config.json` の `file_paths` セクション：

```json
{
  "file_paths": {
    "description": "ファイルパス設定",
    "provided_data_file_path": "./test-data/provided.csv",         // 提供データファイルパス
    "current_data_file_path": "./test-data/current.csv",           // 現在データファイルパス  
    "output_file_path": "./test-data/sync-result.csv",             // 出力ファイルパス
    "provided_data_history_directory": "./data/provided-data/",    // 提供データ履歴保存用
    "current_data_history_directory": "./data/current-data/",      // 現在データ履歴保存用
    "output_history_directory": "./data/output/",                 // 出力履歴保存用
    "timezone": "Asia/Tokyo"                                       // タイムゾーン設定
  }
}
```

### データフィルタリング設定

不要なデータを除外する設定：

```json
{
  "data_filters": {
    "provided_data": {
      "enabled": true,
      "rules": [
        {
          "field": "employee_id",
          "type": "exclude",
          "glob": "Z*",
          "description": "Z始まりの職員番号を除外"
        },
        {
          "field": "employee_id",
          "type": "exclude", 
          "glob": "Y*",
          "description": "Y始まりの職員番号を除外"
        }
      ]
    },
    "current_data": {
      "enabled": true,
      "rules": [
        {
          "field": "user_id",
          "type": "exclude",
          "glob": "Z*",
          "description": "Z始まりの利用者IDを除外"
        }
      ]
    }
  }
}
```

### フィルタタイプ

| タイプ | 説明 | 例 |
|--------|------|-----|
| `exclude` | GLOBパターンに一致するデータを除外 | `"Z*"` (Z始まり除外), `"TEMP"` (TEMP値除外) |
| `include` | GLOBパターンに一致するデータのみ処理 | `"E*"` (E始まりのみ), `"ACTIVE"` (ACTIVE値のみ) |

#### GLOBパターンの記法
- `*` : 0文字以上の任意の文字列
- `?` : 1文字の任意の文字
- `[abc]` : a, b, c のいずれか1文字
- `[!abc]` : a, b, c 以外の1文字

## 同期処理の仕様

| アクション | 説明 | 条件 |
|------------|------|------|
| **ADD** | 新規追加 | 提供データにあり、現在データにない |
| **UPDATE** | 更新 | 両方にあるが内容が異なる（提供データを優先） |
| **DELETE** | 削除 | 現在データにあり、提供データにない |
| **KEEP** | 保持 | 両方にあり、内容が同じ |

## 履歴保存機能

### 自動履歴保存

システムは以下のタイミングで自動的にファイルを履歴保存します：

1. **入力時**: 外部ファイル → `data/provided-data/`, `data/current-data/` にコピー
2. **出力時**: 同期結果 → `data/output/` に保存

### タイムスタンプ形式

```
元ファイル名_YYYYMMDD_HHMMSS.csv
例: provided_20250806_092046.csv
```

### 履歴ファイルの確認

```powershell
# 履歴ファイル一覧
Get-ChildItem -Path ".\data" -Recurse -Filter "*.csv"
```

## トラブルシューティング

### 一般的な問題

1. **ファイルが見つからない**
   ```
   提供データ ファイルが見つかりません: ./test.csv
   ```
   - ファイルパスを確認してください
   - 相対パスの場合、実行ディレクトリに注意

2. **CSVエンコーディング**
   - UTF-8 エンコーディングで保存してください
   - BOM付きUTF-8も対応

3. **フィルタリングで全件除外**
   ```
   フィルタリング完了: 元データ 10件 → 処理対象 0件
   ```
   - フィルタリング設定を確認してください

### データベースのリセット

```powershell
# データベースファイルを削除
Remove-Item ".\database\data-sync.db" -Force

# 再実行
.\scripts\main.ps1
```

## 項目追加方法

新しい項目（例：`salary`）を追加する場合：

1. **設定ファイルのみ修正**: `config/data-sync-config.json`
```json
{
  "name": "salary",
  "type": "INTEGER", 
  "constraints": "",
  "csv_include": true,
  "required": false,
  "description": "給与"
}
```

2. **自動対応**: すべてのSQL文、CSV処理、バリデーションが自動的に対応

## 開発・保守

### 設定ベースアーキテクチャの利点

- **保守性**: 項目変更時の修正箇所を最小化
- **拡張性**: 新しいテーブルや項目の追加が容易
- **一貫性**: 設定からすべてのコードを自動生成
- **検証**: 設定の整合性を自動チェック

### 共通ライブラリ

提供される主要機能：

#### ユーティリティモジュール (Utils/)
- **CommonUtils.psm1**: 統一ログシステム・日本時間タイムスタンプ生成
- **ConfigUtils.psm1**: 設定読み込み・検証
- **SqlUtils.psm1**: 動的SQL生成・実行
- **DataFilterUtils.psm1**: データフィルタリング
- **FileUtils.psm1**: ファイル操作・履歴保存
- **CsvUtils.psm1**: 設定ベースCSV処理
- **ErrorHandlingUtils.psm1**: 統一エラーハンドリング

#### 処理系モジュール (Process/)
- **Invoke-DatabaseInitialization.psm1**: データベース初期化
- **Invoke-DataSync.psm1**: データ同期処理
- **Invoke-CsvImport.psm1**: CSV入力処理
- **Invoke-CsvExport.psm1**: CSV出力処理
- **Show-SyncResult.psm1**: 同期結果表示
- **Show-SyncStatistics.psm1**: 同期統計表示
- **Test-DataConsistency.psm1**: データ整合性チェック
- **Invoke-ConfigValidation.psm1**: 設定検証

## ライセンス

このプロジェクトはMITライセンスの下で公開されています。