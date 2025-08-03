# PowerShell & SQLite 職員データ管理システム

## プロジェクト概要

PowerShellとSQLiteを使用して、職員情報の管理・同期・出力を行う次世代システムです。
**単一ファイルパス指定**による柔軟な運用、**履歴保存機能**による安全性、**設定ベースアーキテクチャ**による保守性を実現します。

**外部ファイル処理 + 履歴保存アーキテクチャ**により、任意の場所にあるファイルを処理しつつ、処理履歴をdata配下に自動保存します。

## 要件

### 基本機能
1. **単一ファイルパス指定による職員情報処理**
   - 外部に配置された単一の職員情報CSVファイルを指定パスから読み込み
   - 読み込み時に自動的にdata/staff-info/配下に日本時間タイムスタンプ付きで履歴保存
   - データフィルタリング適用（Z始まり、Y始まりの職員番号除外等）

2. **単一ファイルパス指定による職員マスタデータ処理**
   - 外部に配置された単一の職員マスタCSVファイルを指定パスから読み込み
   - 読み込み時に自動的にdata/staff-master/配下に日本時間タイムスタンプ付きで履歴保存
   - データフィルタリング適用

3. **データ比較と同期処理**
   - 職員マスタデータに存在しないレコードを追加（ADD）
   - 更新があったレコードの処理（UPDATE）- 職員情報を優先
   - 職員マスタデータにしか存在しないレコードを削除（DELETE）
   - 変更のないレコードを保持（KEEP）

4. **デュアル出力機能**
   - 指定された外部パスへの出力
   - data/output/配下への日本時間タイムスタンプ付き履歴保存
   - 同期アクション（ADD/UPDATE/DELETE/KEEP）を含むCSV形式

5. **ファイルパス管理機能**
   - パラメータ指定による動的ファイルパス指定
   - 設定ファイル（config/schema-config.json）による静的ファイルパス管理
   - ファイルパス解決の優先順位: パラメータ → 設定ファイル

### 追加機能（重要）

#### 🎯 単一ファイルパス指定システム
- **外部ファイル直接処理**: dataディレクトリに依存しない柔軟なファイル配置
- **履歴保存機能**: 処理ファイルを自動的にdata配下にタイムスタンプ付きで保存
- **ファイルパス解決システム**: パラメータと設定ファイルの優先順位管理
- **デュアル出力**: 指定パス + 履歴保存の同時実行

#### 🚀 設定ベース保守性向上
- **config/schema-config.json による一元管理**
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

### 職員データテーブル共通項目

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
| created_at | DATETIME | DEFAULT CURRENT_TIMESTAMP | × | - | 作成日時 |
| updated_at | DATETIME | DEFAULT CURRENT_TIMESTAMP | × | - | 更新日時 |

### 同期結果テーブル追加項目

| 項目名 | データ型 | 制約 | 説明 |
|--------|----------|------|------|
| sync_action | TEXT | NOT NULL | 同期アクション (ADD/UPDATE/DELETE/KEEP) |

## プロジェクト構成

```
ps-sqlite/
├── CLAUDE.md                 # プロジェクト概要・技術仕様（本ファイル）
├── README.md                 # 使用方法・機能説明
├── initialprompt.txt         # 全システム生成用プロンプト
├── config/                   # 設定ファイル
│   └── schema-config.json    # スキーマ・フィルタリング・ファイルパス設定
├── scripts/                  # PowerShellスクリプト
│   ├── main.ps1             # メインスクリプト（単一ファイルパス対応版）
│   ├── common-utils.ps1     # 共通ユーティリティ（日本時間・ファイルパス解決）
│   ├── database.ps1         # 動的データベース操作
│   ├── csv-utils.ps1        # 設定ベースCSV処理（履歴保存対応）
│   └── sync-data.ps1        # 動的データ同期処理
├── sql/                     # SQLスクリプト
│   └── init-database.sql    # データベース初期化（参考用）
├── data/                    # 履歴保存ディレクトリ（自動生成）
│   ├── staff-info/          # 職員情報履歴（タイムスタンプ付き）
│   ├── staff-master/        # 職員マスタ履歴（タイムスタンプ付き）
│   └── output/              # 同期結果履歴（タイムスタンプ付き）
├── database/                # SQLiteデータベース
│   └── staff.db             # メインデータベース
├── test-data/               # テスト用データ（外部ファイル例）
│   ├── current-staff-info.csv
│   ├── master-staff-data.csv
│   └── sync-result.csv
├── samples/                 # サンプルデータ
│   ├── sample-staff-info.csv
│   └── sample-staff-master.csv
└── run.bat                  # Windows実行バッチ
```

## 実行フロー

1. **設定検証**: schema-config.json の整合性チェック
2. **ファイルパス解決**: パラメータまたは設定ファイルからファイルパスを解決
3. **データベースの動的初期化**: 設定からテーブル・インデックス・トリガーを生成
4. **職員情報CSVの処理**:
   - 外部パスからファイル読み込み
   - data/staff-info/配下に日本時間タイムスタンプ付きで履歴保存
   - データフィルタリング適用
   - SQLiteデータベースに格納
5. **職員マスタデータCSVの処理**:
   - 外部パスからファイル読み込み
   - data/staff-master/配下に日本時間タイムスタンプ付きで履歴保存
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
.\scripts\main.ps1 -StaffInfoFilePath "C:\data\current-staff.csv" -StaffMasterFilePath "C:\data\master-staff.csv" -OutputFilePath "C:\output\result.csv"

# Linux/macOS
pwsh ./scripts/main.ps1 -StaffInfoFilePath "/data/current-staff.csv" -StaffMasterFilePath "/data/master-staff.csv" -OutputFilePath "/output/result.csv"
```

### B. 設定ファイル指定実行
1. **設定ファイル編集**: `config/schema-config.json`
```json
{
  "file_paths": {
    "staff_info_file_path": "./test-data/current-staff.csv",
    "staff_master_file_path": "./test-data/master-staff.csv",
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

### schema-config.json の主要セクション

#### 1. file_paths
ファイルパス設定（新機能）
```json
{
  "file_paths": {
    "description": "ファイルパス設定",
    "staff_info_file_path": "",              // 職員情報ファイルパス
    "staff_master_file_path": "",            // 職員マスタファイルパス  
    "output_file_path": "",                  // 出力ファイルパス
    "staff_info_history_directory": "./data/staff-info/",    // 履歴保存用
    "staff_master_history_directory": "./data/staff-master/", // 履歴保存用
    "output_history_directory": "./data/output/",            // 履歴保存用
    "timezone": "Asia/Tokyo"                 // タイムゾーン設定
  }
}
```

#### 2. tables
テーブル定義（カラム、型、制約、CSV設定）
```json
{
  "tables": {
    "staff_info": {
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
    }
  }
}
```

#### 3. sync_rules
同期処理ルール
```json
{
  "sync_rules": {
    "comparison_columns": ["card_number", "name", "department", ...],
    "key_column": "employee_id"
  }
}
```

#### 4. data_filters
データフィルタリング設定
```json
{
  "data_filters": {
    "staff_info": {
      "enabled": true,
      "rules": [
        {
          "field": "employee_id",
          "type": "exclude_pattern",
          "pattern": "^Z.*",
          "description": "Z始まりの職員番号を除外"
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
| exclude_pattern | 正規表現に一致するデータを除外 | `"^Z.*"` (Z始まり除外) |
| include_pattern | 正規表現に一致するデータのみ処理 | `"^E.*"` (E始まりのみ) |
| exclude_value | 特定の値を除外 | `"TEMP"` (TEMP値除外) |
| include_value | 特定の値のみ処理 | `"ACTIVE"` (ACTIVE値のみ) |

### 除外対象の例
- **Z始まりの職員番号**: テストデータや一時的なデータ
- **Y始まりの職員番号**: 退職者や無効なデータ
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
- インデックスは主要な検索キー（employee_id）に設定済み
- 履歴保存は処理性能に影響するが、安全性のため推奨

# important-instruction-reminders
- 何か変更を行う際は、必ず設定ベースアーキテクチャを維持すること
- 新機能追加時は config/schema-config.json での設定可能性を検討すること
- ハードコーディングは避け、動的生成を優先すること
- すべての変更には適切なログとエラーハンドリングを含めること