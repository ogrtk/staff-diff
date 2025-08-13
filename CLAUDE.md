# PowerShell & SQLite データ管理システム

## プロジェクト概要

PowerShellとSQLiteを使用して、提供データと現在データの管理・同期・出力を行う次世代システムです。
**単一ファイルパス指定**による柔軟な運用、**履歴保存機能**による安全性、**設定ベースアーキテクチャ**による保守性を実現します。

**外部ファイル処理 + 履歴保存アーキテクチャ**により、任意の場所にあるファイルを処理しつつ、処理履歴をdata配下に自動保存します。

## 要件

### 基本機能
1. **単一ファイルパス指定による提供データ処理**
   - 外部に配置された単一の提供データCSVファイルを指定パスから読み込み
   - 読み込み時に自動的にdata/provided-data/配下に日本時間タイムスタンプ付きで履歴保存
   - データフィルタリング適用（Z始まり、Y始まりの職員番号除外等）

2. **単一ファイルパス指定による現在データ処理**
   - 外部に配置された単一の現在データCSVファイルを指定パスから読み込み
   - 読み込み時に自動的にdata/current-data/配下に日本時間タイムスタンプ付きで履歴保存
   - データフィルタリング適用

3. **データ比較と同期処理**
   - 現在データに存在しないレコードを追加（ADD）
   - 更新があったレコードの処理（UPDATE）- 提供データを優先
   - 現在データにしか存在しないレコードを削除（DELETE）
   - 変更のないレコードを保持（KEEP）

4. **デュアル出力機能**
   - 指定された外部パスへの出力
   - data/output/配下への日本時間タイムスタンプ付き履歴保存
   - 同期アクション（ADD/UPDATE/DELETE/KEEP）を含むCSV形式

5. **ファイルパス管理機能**
   - パラメータ指定による動的ファイルパス指定
   - 設定ファイル（config/data-sync-config.json）による静的ファイルパス管理
   - ファイルパス解決の優先順位: パラメータ → 設定ファイル

### 追加機能（重要）

#### 🎯 単一ファイルパス指定システム
- **外部ファイル直接処理**: dataディレクトリに依存しない柔軟なファイル配置
- **履歴保存機能**: 処理ファイルを自動的にdata配下にタイムスタンプ付きで保存
- **ファイルパス解決システム**: パラメータと設定ファイルの優先順位管理
- **デュアル出力**: 指定パス + 履歴保存の同時実行

#### 🚀 設定ベース保守性向上
- **config/data-sync-config.json による一元管理**
- **項目追加時の修正箇所を1ファイルに削減**
- **動的SQL生成**: テーブル定義から自動生成
- **動的CSV処理**: 設定ベースでヘッダー・バリデーション
- **設定検証機能**: 起動時の整合性チェック

#### 🔍 データフィルタリング機能
- **Z始まり・Y始まりの職員番号を除外**（設定可能）
- **正規表現パターンでの柔軟な除外/包含**
- **特定値での除外/包含**
- **テーブル別設定**: staff_info と staff_master で個別設定
- **詳細ログ**: 除外理由と統計情報の表示

#### ⏰ 日本時間対応機能
- **日本時間タイムスタンプ**: Asia/Tokyoタイムゾーンでの正確な時刻記録
- **履歴ファイル名**: YYYYMMDD_HHMMSS 形式での自動命名
- **タイムゾーン設定**: 設定ファイルでのタイムゾーン変更対応

#### 📊 強化されたログ・レポート機能
- **統一ログシステム**: 日本時間でのレベル別ログ出力
- **フィルタリング統計**: 除外件数・率の表示
- **同期統計**: ADD/UPDATE/DELETE/KEEPの件数表示
- **データベース情報**: テーブル別レコード数表示

### 技術要件
- PowerShell 5.1以上によるスクリプト作成
- SQLite データベースの使用
- CSV ファイルの読み書き（UTF-8対応）
- 動的SQL生成・実行
- 正規表現によるデータフィルタリング
- JSON設定ファイルの読み込み・検証
- .NET TimeZoneInfo による日本時間処理
- ファイルシステム操作（コピー、タイムスタンプ付きファイル生成）
- パラメータ解析とファイルパス解決機能

## データ項目

**重要**: 以下は現在の設定例です。すべてのデータ項目は `config/data-sync-config.json` で設定可能です。

### 提供データ (provided_data) テーブル - 設定例

| 項目名 | データ型 | 制約 | CSV含む | 必須 | 説明 |
|--------|----------|------|---------|------|------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | × | - | 内部ID |
| employee_id | TEXT | NOT NULL UNIQUE | ○ | ○ | 職員ID |
| card_number | TEXT | - | ○ | × | カード番号 |
| name | TEXT | NOT NULL | ○ | ○ | 氏名 |
| department | TEXT | - | ○ | × | 部署 |
| position | TEXT | - | ○ | × | 役職 |
| email | TEXT | - | ○ | × | メールアドレス |
| phone | TEXT | - | ○ | × | 電話番号 |
| hire_date | DATE | - | ○ | × | 入社日 |

### 現在データ (current_data) テーブル - 設定例

| 項目名 | データ型 | 制約 | CSV含む | 必須 | 説明 |
|--------|----------|------|---------|------|------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | × | - | 内部ID |
| user_id | TEXT | NOT NULL UNIQUE | ○ | ○ | 利用者ID |
| card_number | TEXT | - | ○ | × | カード番号 |
| name | TEXT | NOT NULL | ○ | ○ | 氏名 |
| department | TEXT | - | ○ | × | 部署 |
| position | TEXT | - | ○ | × | 役職 |
| email | TEXT | - | ○ | × | メールアドレス |
| phone | TEXT | - | ○ | × | 電話番号 |
| hire_date | DATE | - | ○ | × | 入社日 |

### 同期結果 (sync_result) テーブル - 設定例

| 項目名 | データ型 | 制約 | CSV含む | 必須 | 説明 |
|--------|----------|------|---------|------|------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | × | - | 内部ID |
| syokuin_no | TEXT | NOT NULL | ○ | ○ | 職員番号 |
| card_number | TEXT | - | ○ | × | カード番号 |
| name | TEXT | NOT NULL | ○ | ○ | 氏名 |
| department | TEXT | - | ○ | × | 部署 |
| position | TEXT | - | ○ | × | 役職 |
| email | TEXT | - | ○ | × | メールアドレス |
| phone | TEXT | - | ○ | × | 電話番号 |
| hire_date | DATE | - | ○ | × | 入社日 |
| sync_action | TEXT | NOT NULL | ○ | ○ | 同期アクション (ADD/UPDATE/DELETE/KEEP) |

### 項目の追加・変更方法

新しい項目の追加や既存項目の変更は `config/data-sync-config.json` の `tables` セクションで行います：

```json
{
  "tables": {
    "provided_data": {
      "columns": [
        {
          "name": "new_field",
          "type": "TEXT",
          "constraints": "",
          "csv_include": true,
          "required": false,
          "description": "新しい項目"
        }
      ]
    }
  }
}
```

設定変更後は自動的にSQL文、CSV処理、バリデーションがすべて対応されます。

## プロジェクト構成

```
ps-sqlite/
├── CLAUDE.md                 # プロジェクト概要・技術仕様（本ファイル）
├── README.md                 # 使用方法・機能説明
├── initialprompt.txt         # 全システム生成用プロンプト
├── originalprompt.txt        # オリジナルプロンプト
├── config/                   # 設定ファイル
│   └── data-sync-config.json # データ同期ツール設定
├── scripts/                  # PowerShellスクリプト
│   ├── main.ps1             # メインスクリプト（単一ファイルパス対応版）
│   ├── database.ps1         # 動的データベース操作
│   ├── sync-data.ps1        # 動的データ同期処理
│   └── utils/               # ユーティリティスクリプト
│       ├── common-utils.ps1     # 共通ユーティリティ（日本時間・ファイルパス解決）
│       ├── config-utils.ps1     # 設定読み込み・検証
│       ├── sql-utils.ps1        # SQL生成・実行ユーティリティ
│       ├── file-utils.ps1       # ファイル操作ユーティリティ
│       ├── data-filter-utils.ps1 # データフィルタリング
│       └── csv-utils.ps1        # 設定ベースCSV処理（履歴保存対応）
├── data/                    # 履歴保存ディレクトリ（自動生成）
│   ├── provided-data/       # 提供データ履歴（タイムスタンプ付き）
│   ├── current-data/        # 現在データ履歴（タイムスタンプ付き）
│   └── output/              # 同期結果履歴（タイムスタンプ付き）
├── database/                # SQLiteデータベース
│   └── data-sync.db         # メインデータベース
├── logs/                    # ログファイル（自動生成）
│   └── staff-management.log # 実行ログ
├── test-data/               # テスト用データ（外部ファイル例）
│   ├── provided.csv         # 提供データサンプル
│   ├── current.csv          # 現在データサンプル
│   ├── large-provided.csv   # 大量データテスト用
│   ├── large-current.csv    # 大量データテスト用
│   └── sync-result.csv      # 同期結果サンプル
├── package.json             # Node.js依存関係（開発用）
├── package-lock.json        # Node.js依存関係ロック
├── node_modules/            # Node.js依存関係（自動生成）
└── run.bat                  # Windows実行バッチ
```

## 実行フロー

1. **設定検証**: data-sync-config.json の整合性チェック
2. **ファイルパス解決**: パラメータまたは設定ファイルからファイルパスを解決
3. **データベースの動的初期化**: 設定からテーブル・インデックス・トリガーを生成
4. **提供データCSVの処理**:
   - 外部パスからファイル読み込み
   - data/provided-data/配下に日本時間タイムスタンプ付きで履歴保存
   - データフィルタリング適用
   - SQLiteデータベースに格納
5. **現在データCSVの処理**:
   - 外部パスからファイル読み込み
   - data/current-data/配下に日本時間タイムスタンプ付きで履歴保存
   - データフィルタリング適用
   - SQLiteデータベースに格納
6. **データ比較・同期処理**: 動的SQL生成による処理
7. **データ整合性チェック**: 重複レコード等の検証
8. **デュアル出力**:
   - 指定された外部パスへの出力
   - data/output/配下への日本時間タイムスタンプ付き履歴保存
9. **統計・レポート表示**: フィルタリング・同期結果の表示

## 使用方法

### A. パラメータ指定実行
```powershell
# Windows PowerShell
.\scripts\main.ps1 -ProvidedDataFilePath "C:\data\provided.csv" -CurrentDataFilePath "C:\data\current.csv" -OutputFilePath "C:\output\result.csv"

# Linux/macOS
pwsh ./scripts/main.ps1 -ProvidedDataFilePath "/data/provided.csv" -CurrentDataFilePath "/data/current.csv" -OutputFilePath "/output/result.csv"
```

### B. 設定ファイル指定実行
1. **設定ファイル編集**: `config/data-sync-config.json`
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

### 実行例（テスト用）
設定ファイルにテストパスを設定して実行:
```powershell
# テスト実行
.\scripts\main.ps1
```

## 設定管理

### data-sync-config.json の主要セクション

#### 1. file_paths
ファイルパス設定
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

#### 2. tables
テーブル定義（カラム、型、制約、CSV設定）
```json
{
  "tables": {
    "provided_data": {
      "description": "提供データテーブル",
      "columns": [
        {
          "name": "employee_id",
          "type": "TEXT",
          "constraints": "NOT NULL UNIQUE",
          "csv_include": true,
          "required": true,
          "description": "職員ID"
        }
      ]
    },
    "current_data": {
      "description": "現在データテーブル",
      "columns": [
        {
          "name": "user_id",
          "type": "TEXT",
          "constraints": "NOT NULL UNIQUE",
          "csv_include": true,
          "required": true,
          "description": "利用者ID"
        }
      ]
    }
  }
}
```

#### 3. sync_rules
同期処理ルール
```json
{
  "sync_rules": {
    "key_columns": {
      "description": "各テーブルのレコード比較キー",
      "provided_data": ["employee_id"],
      "current_data": ["user_id"],
      "sync_result": ["syokuin_no"]
    },
    "column_mappings": {
      "description": "テーブル間の比較項目対応付け（provided_dataの項目:current_dataの項目）",
      "mappings": {
        "employee_id": "user_id",
        "card_number": "card_number",
        "name": "name",
        "department": "department",
        "position": "position",
        "email": "email",
        "phone": "phone",
        "hire_date": "hire_date"
      }
    }
  }
}
```

**注意**: 比較カラムは `column_mappings` から自動生成されます。
- **provided_data比較カラム**: mappingsのキー部分 (employee_id, card_number, name, ...)
- **current_data比較カラム**: mappingsの値部分 (user_id, card_number, name, ...)

#### 4. data_filters
データフィルタリング設定
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

## データフィルタリング仕様

### フィルタタイプ

| タイプ | 説明 | 設定例 |
|--------|------|--------|
| exclude | GLOBパターンに一致するデータを除外 | `"Z*"` (Z始まり除外), `"TEMP"` (TEMP値除外) |
| include | GLOBパターンに一致するデータのみ処理 | `"E*"` (E始まりのみ), `"ACTIVE"` (ACTIVE値のみ) |

#### GLOBパターンの記法
- `*` : 0文字以上の任意の文字列
- `?` : 1文字の任意の文字
- `[abc]` : a, b, c のいずれか1文字
- `[!abc]` : a, b, c 以外の1文字

#### GLOBパターンの例
- `Z*` : Z始まり（前方一致）
- `*test*` : testを含む（部分一致）
- `???` : 3文字ちょうど
- `TEMP` : 完全一致

### 除外対象の例
- **Z始まりのID**: テストデータや一時的なデータ（employee_id、user_id）
- **Y始まりのID**: 退職者や無効なデータ（employee_id、user_id）
- **特定部署**: "TEST", "TEMP" 等のテスト部署
- **特定ステータス**: "INACTIVE", "DISABLED" 等

## アーキテクチャ上の重要な設計思想

### 単一ファイルパス + 履歴保存アーキテクチャ
1. **外部ファイル処理**: dataディレクトリに依存しない柔軟な運用
2. **履歴保存**: 処理履歴の自動保存による安全性確保
3. **デュアル出力**: 指定パス + 履歴保存の同時実行
4. **ファイルパス解決**: パラメータ優先の柔軟な設定管理

### 保守性向上の設計
1. **DRY原則**: 設定ファイルによる定義の一元化
2. **動的生成**: ハードコーディングの排除
3. **設定検証**: ランタイムエラーの事前防止
4. **統一ログ**: 日本時間での問題発生時の迅速な特定

### 拡張性の確保
1. **テーブル追加**: 設定ファイルへの追加のみ
2. **項目追加**: カラム定義の追加のみ
3. **フィルタ追加**: ルールの追加のみ
4. **新しいフィルタタイプ**: パターンマッチング関数の追加
5. **ファイルパス管理**: 設定ファイルでの一元管理

## 重要な注意事項

### ファイルパスの取り扱い
- 外部ファイルは単一ファイルパスで指定（ディレクトリではない）
- パラメータ指定が設定ファイルより優先される
- ファイル存在チェックは処理開始時に実行
- 相対パスの場合、実行ディレクトリからの相対位置

### データの取り扱い
- CSVファイルはUTF-8エンコーディングで保存
- フィルタリングで除外されたデータは処理対象外
- 同期処理では職員情報（staff_info）を優先
- data配下は履歴保存専用（処理対象ではない）

### 履歴保存機能
- 処理ファイルは自動的にdata配下にコピー保存される
- タイムスタンプは日本時間（Asia/Tokyo）で生成
- 履歴ファイルは元ファイル名_YYYYMMDD_HHMMSS.csv形式
- 履歴ディレクトリは自動生成される

### 設定変更時の注意
- 設定変更後は必ず検証機能でチェック
- 既存データベースとの互換性を考慮
- フィルタリング設定の変更は処理結果に大きく影響
- ファイルパス設定の変更は実行前に確認

### 性能に関する考慮
- 大量データ処理時はSQLite3コマンドラインツールの使用を推奨
- フィルタリング処理は全データ読み込み後に実行
- インデックスは設定ファイルで管理可能（現在は未設定）
- 履歴保存は処理性能に影響するが、安全性のため推奨

## エラーハンドリング標準化ガイドライン

### 概要
システム全体で統一されたエラーハンドリングパターンを提供し、保守性と信頼性を向上させます。

### エラーカテゴリ分類
| カテゴリ | 説明 | リトライ | 継続可否 | デフォルトレベル |
|----------|------|----------|----------|------------------|
| **System** | 設定ファイル不正、プログラムロジックエラー等 | ❌ | 中断 | Error |
| **Data** | 個別レコードのCSV不正、フィルタリング失敗等 | ❌ | 継続 | Warning |
| **External** | ファイルアクセス、DB接続、外部コマンド不在等 | ✅ | 中断 | Error |

### 統一エラーハンドリング関数

#### 基本パターン
```powershell
# 統合エラーハンドリング（リトライ・クリーンアップ対応）
Invoke-WithErrorHandling -ScriptBlock {
    # 処理内容
} -Category System -Operation "処理名" -Context @{
    "ファイルパス" = $filePath
} -CleanupScript { 
    # クリーンアップ処理 
}
```

#### 専用関数（推奨）
```powershell
# ファイル操作専用
Invoke-FileOperationWithErrorHandling -FileOperation {
    # ファイル処理
} -FilePath $path -OperationType "操作種別"

# データベース操作専用  
Invoke-DatabaseOperationWithErrorHandling -DatabaseOperation {
    # DB処理
} -DatabasePath $dbPath -OperationType "操作種別"

# 設定検証専用
Invoke-ConfigValidationWithErrorHandling -ValidationOperation {
    # 設定検証
} -ConfigSection "設定セクション"

# 外部コマンド実行専用
Invoke-ExternalCommandWithErrorHandling -CommandOperation {
    # コマンド実行
} -CommandName "sqlite3" -OperationType "操作種別"

# 安全な実行（エラーを例外として再スローしない）
Invoke-SafeOperation -Operation {
    # 処理内容
} -OperationName "操作名" -Category Data -DefaultReturn $null
```

### エラーハンドリング設定

#### config/data-sync-config.json
```json
{
  "error_handling": {
    "enabled": true,
    "log_stack_trace": true,
    "retry_settings": {
      "enabled": true,
      "max_attempts": 3,
      "delay_seconds": [1, 2, 5],
      "retryable_categories": ["External"]
    },
    "error_levels": {
      "System": "Error",
      "Data": "Warning",
      "External": "Error"
    },
    "continue_on_error": {
      "System": false,
      "Data": true,
      "External": false
    },
    "cleanup_on_error": true
  }
}
```

### 実装ガイドライン

#### ✅ 推奨パターン
```powershell
# 1. 適切なカテゴリの選択
Invoke-WithErrorHandling -Category Data -Operation "CSVファイル読み込み"

# 2. コンテキスト情報の提供
-Context @{
    "ファイルパス" = $csvPath
    "テーブル名" = $tableName
}

# 3. クリーンアップ処理の定義
-CleanupScript {
    if (Test-Path $tempFile) {
        Remove-Item $tempFile -Force
    }
}

# 4. 専用関数の使用（より具体的）
Invoke-FileOperationWithErrorHandling -FileOperation { 
    Copy-Item $source $destination 
} -FilePath $source -OperationType "ファイルコピー"
```

#### ❌ 避けるべきパターン
```powershell
# 1. 旧式のtry-catchの直接使用
try {
    # 処理
} catch {
    Write-Error "エラー: $($_.Exception.Message)"
    throw
}

# 2. エラー情報の不足
Invoke-WithErrorHandling { /* 処理 */ } # カテゴリ・操作名なし

# 3. 一律のエラー処理
catch { throw } # すべて同じ処理

# 4. ログとエラーハンドリングの混在
Write-SystemLog "エラー" -Level "Error"
throw $_.Exception
```

### エラー対応指針

#### 自動復旧可能エラー
- **リトライ対象**: External, System カテゴリ
- **最大試行回数**: 3回（設定可能）
- **遅延**: 1秒、2秒、5秒（設定可能）

#### 処理継続可能エラー
- **Data カテゴリ**: CSVフォーマット不正等
- **継続条件**: 部分的なデータ損失が許容される場合
- **ログレベル**: Warning

#### 即座中断エラー  
- **System, Configuration, External カテゴリ**
- **中断理由**: システム基盤の問題、設定不正
- **ログレベル**: Error

### デバッグとトラブルシューティング

#### ログ出力内容
- **エラーカテゴリ**: `[System] ファイル操作 でエラーが発生しました`
- **スタックトレース**: `log_stack_trace: true` で有効
- **コンテキスト情報**: ファイルパス、テーブル名等の関連情報
- **対処方法**: カテゴリ別の推奨対処法

#### エラー分析手順
1. **ログファイル確認**: `logs/staff-management.log`
2. **エラーカテゴリ特定**: System/Configuration/Data/External
3. **コンテキスト情報確認**: ファイルパス、設定等
4. **カテゴリ別対処**: 推奨対処法に従い修正

### 注意事項

#### 循環参照の回避
- `config-utils.ps1` では `error-handling-utils.ps1` を読み込まない
- 設定読み込み関数では旧式のtry-catchを使用

#### 性能への配慮
- エラーハンドリングは必要最小限に留める
- リトライは外部依存とシステムエラーのみ
- クリーンアップ処理は軽量に保つ

#### 後方互換性
- 既存の `Write-SystemLog` は継続使用可能
- 段階的な移行を推奨（クリティカルな箇所から優先）

# important-instruction-reminders
- 何か変更を行う際は、必ず設定ベースアーキテクチャを維持すること
- 新機能追加時は config/data-sync-config.json での設定可能性を検討すること
- ハードコーディングは避け、動的生成を優先すること
- すべての変更には適切なログとエラーハンドリングを含めること
- **エラーハンドリングは統一関数を使用し、適切なカテゴリを選択すること**
- **新規関数作成時は専用エラーハンドリング関数の使用を必須とすること**