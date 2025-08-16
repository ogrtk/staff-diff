# PowerShell & SQLite データ管理システム

## 概要

PowerShellとSQLiteを使用したCSVデータ同期システムです。外部CSVファイル（提供データと現在データ）を処理し、設定ベースの柔軟なフィルタリング機能とデータ同期を実行し、自動履歴保存機能付きで結果を出力します。

## 主要機能

- **外部ファイル処理**: 任意の場所のCSVファイルを直接指定
- **自動履歴保存**: 処理ファイルを日本時間タイムスタンプ付きで自動保存
- **設定ベースアーキテクチャ**: データスキーマやフィルタを設定ファイルで管理
- **データフィルタリング**: GLOBパターンによる柔軟な除外/包含ルール
- **統一ログシステム**: 日本時間でのレベル別ログ出力

## 必要環境

- **PowerShell** 5.1 以上
- **SQLite3** コマンドラインツール（推奨）

## クイックスタート

### 1. 基本実行

```bash
# パラメータ指定での実行
pwsh ./scripts/main.ps1 -ProvidedDataFilePath "/path/to/provided.csv" -CurrentDataFilePath "/path/to/current.csv" -OutputFilePath "/path/to/output.csv"

# 設定ファイルの値を使用
pwsh ./scripts/main.ps1

# カスタム設定ファイルを指定
pwsh ./scripts/main.ps1 -ConfigFilePath "/path/to/custom-config.json"

# Windows用ショートカット
.\run.bat
```

### 2. 設定ファイルでの実行

1. 設定ファイルを編集: `config/data-sync-config.json`

```json
{
  "file_paths": {
    "provided_data_file_path": "./test-data/provided.csv",
    "current_data_file_path": "./test-data/current.csv", 
    "output_file_path": "./test-data/sync-result.csv"
  }
}
```

2. 実行:

```bash
pwsh ./scripts/main.ps1
```

### 3. 実行結果

- **メイン出力**: 指定パスにCSVファイルが出力
- **履歴保存**: `data/` 配下に日本時間タイムスタンプ付きで自動保存
  - `data/provided-data/`: 提供データの履歴
  - `data/current-data/`: 現在データの履歴  
  - `data/output/`: 同期結果の履歴

## データ同期の仕様

| アクション | 説明 | 条件 |
|------------|------|------|
| **ADD** | 新規追加 | 提供データにあり、現在データにない |
| **UPDATE** | 更新 | 両方にあるが内容が異なる（提供データを優先） |
| **DELETE** | 削除 | 現在データにあり、提供データにない |
| **KEEP** | 保持 | 両方にあり、内容が同じ |

## データフィルタリング

`config/data-sync-config.json` でGLOBパターンによるフィルタリングを設定可能：

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
        }
      ]
    }
  }
}
```

### フィルタタイプ

| タイプ | 説明 | 例 |
|--------|------|-----|
| `exclude` | GLOBパターンに一致するデータを除外 | `"Z*"` (Z始まり除外) |
| `include` | GLOBパターンに一致するデータのみ処理 | `"E*"` (E始まりのみ) |

## テスト実行

```bash
# 全テスト実行
pwsh ./tests/run-test.ps1

# 特定テストファイルの実行
pwsh ./tests/run-test.ps1 -TestPath "Utils\CommonUtils.Tests.ps1"

# カバレッジレポート付き実行
pwsh ./tests/run-test.ps1 -OutputFormat "HTML" -ShowCoverage

# 統合テストのみ実行
pwsh ./tests/run-test.ps1 -TestPath "Integration\FullSystem.Tests.ps1"
```

## トラブルシューティング

### ファイルが見つからない

```
提供データ ファイルが見つかりません: ./test.csv
```

- ファイルパスを確認してください
- 相対パスの場合、実行ディレクトリに注意

### CSVエンコーディング問題

- UTF-8エンコーディングで保存してください
- BOM付きUTF-8も対応しています

### フィルタリングで全件除外

```
フィルタリング完了: 元データ 10件 → 処理対象 0件
```

- `config/data-sync-config.json` のフィルタリング設定を確認してください

### データベースのリセット

```bash
# データベースファイルを削除
Remove-Item ".\database\data-sync.db" -Force

# 再実行
pwsh ./scripts/main.ps1
```

## ログとデバッグ

```bash
# システムログの確認
Get-Content logs/data-sync-system.log -Tail 20

# データベース直接確認
sqlite3 database/data-sync.db
.tables
SELECT COUNT(*) FROM provided_data;
```

## 設定ファイル詳細解説

### ファイルパス設定 (`file_paths`)

```json
{
  "file_paths": {
    "provided_data_file_path": "./test-data/provided.csv",
    "current_data_file_path": "./test-data/current.csv",
    "output_file_path": "./test-data/sync-result.csv",
    "provided_data_history_directory": "./data/provided-data/",
    "current_data_history_directory": "./data/current-data/",
    "output_history_directory": "./data/output/",
    "timezone": "Asia/Tokyo"
  }
}
```

| 設定項目 | 説明 | 例 |
|----------|------|-----|
| `provided_data_file_path` | 提供データCSVファイルのパス | `"./data/staff-provided.csv"` |
| `current_data_file_path` | 現在データCSVファイルのパス | `"./data/staff-current.csv"` |
| `output_file_path` | 同期結果出力先パス | `"./output/sync-result.csv"` |
| `*_history_directory` | 各データの履歴保存ディレクトリ | `"./history/provided/"` |
| `timezone` | タイムスタンプ生成用タイムゾーン | `"Asia/Tokyo"`, `"UTC"` |

### CSVフォーマット設定 (`csv_format`)

```json
{
  "csv_format": {
    "provided_data": {
      "encoding": "UTF-8",
      "delimiter": ",",
      "newline": "LF",
      "has_header": false,
      "null_values": ["", "NULL", "null"]
    }
  }
}
```

| 設定項目 | 説明 | 選択肢 |
|----------|------|--------|
| `encoding` | ファイルエンコーディング | `"UTF-8"`, `"Shift_JIS"` |
| `delimiter` | フィールド区切り文字 | `","`, `"\t"`, `";"` |
| `newline` | 改行コード | `"LF"`, `"CRLF"`, `"CR"` |
| `has_header` | ヘッダー行の有無 | `true`, `false` |
| `null_values` | NULL値として扱う文字列 | `["", "NULL", "N/A"]` |

### テーブル定義 (`tables`)

```json
{
  "tables": {
    "provided_data": {
      "columns": [
        {
          "name": "employee_id",
          "type": "TEXT",
          "constraints": "NOT NULL",
          "csv_include": true,
          "required": true,
          "description": "職員ID"
        }
      ]
    }
  }
}
```

#### カラム設定項目

| 設定項目 | 説明 | 例 |
|----------|------|-----|
| `name` | カラム名 | `"employee_id"` |
| `type` | SQLiteデータ型 | `"TEXT"`, `"INTEGER"`, `"DATE"` |
| `constraints` | SQL制約 | `"NOT NULL"`, `"UNIQUE"` |
| `csv_include` | CSV入出力対象 | `true`, `false` |
| `required` | 必須項目（バリデーション用） | `true`, `false` |
| `description` | 項目説明 | `"職員番号"` |

### 同期ルール設定 (`sync_rules`)

#### キーカラム設定 (`key_columns`)

```json
{
  "key_columns": {
    "provided_data": ["employee_id"],
    "current_data": ["user_id"]
  }
}
```

各テーブルのレコード識別に使用するキーカラムを指定します。

#### カラムマッピング (`column_mappings`)

```json
{
  "column_mappings": {
    "mappings": {
      "employee_id": "user_id",
      "name": "name"
    }
  }
}
```

提供データと現在データの対応関係を定義します。

#### 同期結果マッピング (`sync_result_mapping`)

```json
{
  "sync_result_mapping": {
    "mappings": {
      "syokuin_no": {
        "sources": [
          {
            "type": "provided_data",
            "field": "employee_id",
            "priority": 1
          },
          {
            "type": "current_data", 
            "field": "user_id",
            "priority": 2
          }
        ]
      }
    }
  }
}
```

出力項目のデータソース優先順位を設定します。

### データフィルタリング設定 (`data_filters`)

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
        }
      ]
    }
  }
}
```

#### フィルタ設定項目

| 設定項目 | 説明 | 例 |
|----------|------|-----|
| `enabled` | フィルタ機能の有効/無効 | `true`, `false` |
| `field` | フィルタ対象フィールド名 | `"employee_id"` |
| `type` | フィルタタイプ | `"exclude"`, `"include"` |
| `glob` | GLOBパターン | `"Z*"`, `"TEMP_*"`, `"[0-9]*"` |
| `description` | フィルタ説明 | `"テストデータを除外"` |

### パフォーマンス設定 (`performance_settings`)

```json
{
  "performance_settings": {
    "batch_size": 1000,
    "auto_optimization": true,
    "sqlite_pragmas": {
      "journal_mode": "WAL",
      "cache_size": 10000
    }
  }
}
```

| 設定項目 | 説明 | 推奨値 |
|----------|------|--------|
| `batch_size` | 一括処理件数 | `1000`（小さなファイル）, `5000`（大きなファイル） |
| `auto_optimization` | 自動最適化 | `true` |
| `sqlite_pragmas` | SQLite最適化設定 | デフォルト値を推奨 |

### エラーハンドリング設定 (`error_handling`)

```json
{
  "error_handling": {
    "retry_settings": {
      "enabled": true,
      "max_attempts": 3,
      "delay_seconds": [1, 2, 5]
    },
    "continue_on_error": {
      "System": false,
      "Data": true,
      "External": false
    }
  }
}
```

#### エラーカテゴリ

| カテゴリ | 説明 | 推奨設定 |
|----------|------|----------|
| `System` | 設定エラー、ロジックエラー | 処理停止 (`false`) |
| `Data` | データ不整合、バリデーションエラー | 処理継続 (`true`) |
| `External` | ファイル/DB アクセスエラー | リトライ後停止 |

### ログ設定 (`logging`)

```json
{
  "logging": {
    "log_directory": "./logs/",
    "log_file_name": "data-sync-system.log",
    "max_file_size_mb": 10,
    "max_files": 5,
    "levels": ["Info", "Warning", "Error", "Success"]
  }
}
```

| 設定項目 | 説明 | 推奨値 |
|----------|------|--------|
| `log_directory` | ログファイル保存先 | `"./logs/"` |
| `max_file_size_mb` | ログファイル最大サイズ（MB） | `10` |
| `max_files` | ログファイル保持数 | `5` |
| `levels` | 出力ログレベル | すべて有効 |

## 設定の拡張

新しいデータフィールドを追加するには `config/data-sync-config.json` のテーブルカラム定義を更新するだけで、すべてのSQL、CSV処理、バリデーションが自動適応します。

## 開発者向け情報

詳細なアーキテクチャ、モジュール構造、開発ワークフローについては `CLAUDE.md` を参照してください。

## ライセンス

このプロジェクトはMITライセンスの下で公開されています。