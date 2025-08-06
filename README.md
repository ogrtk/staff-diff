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
│   ├── main.ps1             # メインスクリプト
│   ├── common-utils.ps1     # 共通ユーティリティ
│   ├── config-utils.ps1     # 設定読み込み・検証
│   ├── sql-utils.ps1        # SQL生成・実行ユーティリティ
│   ├── file-utils.ps1       # ファイル操作ユーティリティ
│   ├── data-filter-utils.ps1 # データフィルタリング
│   ├── database.ps1         # データベース操作
│   ├── csv-utils.ps1        # CSV処理
│   └── sync-data.ps1        # データ同期処理
├── data/                    # 履歴保存ディレクトリ
│   ├── provided-data/       # 提供データ履歴
│   ├── current-data/        # 現在データ履歴
│   └── output/              # 同期結果履歴
├── database/                # SQLiteデータベース
│   └── data-sync.db         # メインデータベース
├── logs/                    # ログファイル
│   └── staff-management.log # 実行ログ
└── test-data/               # テスト用データ
    ├── provided.csv         # 提供データサンプル
    ├── current.csv          # 現在データサンプル
    └── sync-result.csv      # 同期結果サンプル
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
          "type": "exclude_pattern",
          "pattern": "^Z.*",
          "description": "Z始まりの職員番号を除外"
        },
        {
          "field": "employee_id",
          "type": "exclude_pattern", 
          "pattern": "^Y.*",
          "description": "Y始まりの職員番号を除外"
        }
      ]
    },
    "current_data": {
      "enabled": true,
      "rules": [
        {
          "field": "user_id",
          "type": "exclude_pattern",
          "pattern": "^Z.*",
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
| `exclude_pattern` | 正規表現に一致するデータを除外 | `"^Z.*"` (Z始まり除外) |
| `include_pattern` | 正規表現に一致するデータのみ処理 | `"^E.*"` (E始まりのみ) |
| `exclude_value` | 特定の値を除外 | `"TEMP"` (TEMP値除外) |
| `include_value` | 特定の値のみ処理 | `"ACTIVE"` (ACTIVE値のみ) |

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
- **config-utils.ps1**: 設定読み込み・検証
- **sql-utils.ps1**: 動的SQL生成・実行
- **data-filter-utils.ps1**: データフィルタリング
- **file-utils.ps1**: ファイル操作・履歴保存
- **common-utils.ps1**: 統一ログシステム・日本時間タイムスタンプ生成
- **csv-utils.ps1**: 設定ベースCSV処理
- **database.ps1**: データベース操作
- **sync-data.ps1**: データ同期処理

## ライセンス

このプロジェクトはMITライセンスの下で公開されています。