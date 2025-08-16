# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

PowerShellベースのデータ管理システムで、SQLiteを使用してCSVデータの同期を行います。外部CSVファイル（提供データと現在データ）を処理し、フィルタリング機能付きでデータ同期を実行し、自動履歴保存機能付きで結果を出力します。

## 主要なアーキテクチャ原則

### 設定ベースアーキテクチャ
- **単一の真実の源**: すべてのデータスキーマ、テーブル定義、処理ルールは `config/data-sync-config.json` で定義
- **動的生成**: SQL文、CSV処理、バリデーションは設定から自動生成
- **最小限のコード変更**: カラムやテーブルの追加は設定ファイルの更新のみで対応

### モジュラー構造
- **Utilsモジュール**: 共通操作用のコアユーティリティ（ファイル処理、ログ、SQL生成）
- **Processモジュール**: 特定操作のビジネスロジック（インポート、エクスポート、同期、検証）
- **エラーハンドリング**: 設定可能なリトライとクリーンアップポリシーを持つ統一エラーハンドリング

### 外部ファイル処理 + 履歴保存
- **柔軟なファイルパス**: パラメータまたは設定で任意の場所からファイルを処理
- **自動履歴**: 処理されたファイルは日本時間タイムスタンプ付きで `data/` に自動保存
- **デュアル出力**: 結果は指定パスと履歴ディレクトリの両方に出力

## 必須コマンド

### システムの実行
```bash
# パラメータ指定（設定ファイルを上書き）
pwsh ./scripts/main.ps1 -ProvidedDataFilePath "/path/to/provided.csv" -CurrentDataFilePath "/path/to/current.csv" -OutputFilePath "/path/to/output.csv"

# 設定ファイルの値を使用
pwsh ./scripts/main.ps1

# カスタム設定ファイルを指定
pwsh ./scripts/main.ps1 -ConfigFilePath "/path/to/custom-config.json"

# 設定ファイルとパラメータを組み合わせ
pwsh ./scripts/main.ps1 -ConfigFilePath "/path/to/custom-config.json" -OutputFilePath "/path/to/custom-output.csv"

# Windows用ショートカット
.\run.bat
```

### テスト実行
```bash
# 全テスト実行
pwsh ./tests/run-test.ps1

# 特定テストファイルの実行
pwsh ./tests/run-test.ps1 -TestPath "Utils\CommonUtils.Tests.ps1"

# カバレッジとHTMLレポート付き実行
pwsh ./tests/run-test.ps1 -OutputFormat "HTML" -ShowCoverage

# 統合テストのみ実行
pwsh ./tests/run-test.ps1 -TestPath "Integration\FullSystem.Tests.ps1"
```

### 開発ユーティリティ
```bash
# UTF-8テストファイル作成
pwsh ./tests/create-utf8-tests.ps1

# エンコーディング問題の修正
pwsh ./tests/encoding-fix.ps1
```

## コア設定システム

`config/data-sync-config.json` ファイルがシステム全体を駆動：

### テーブルスキーマ定義
テーブルはカラム仕様で定義され、以下を自動生成：
- 制約付きSQL CREATE文
- CSVインポート/エクスポートマッピング
- データバリデーションルール
- フィルタ設定

### データフィルタリング
GLOBパターンによるフィルタリング：
- `exclude`: マッチするデータを除外（`"Z*"` でZ始まりIDを除外）
- `include`: マッチするデータのみ処理
- テーブル別適用、詳細ログ付き

### ファイルパス解決
優先順位: コマンドパラメータ → 設定ファイル → デフォルト

### 設定ファイルの指定
- `-ConfigFilePath`パラメータで任意の設定ファイルを指定可能
- 指定されない場合は`config/data-sync-config.json`を使用
- 複数環境（開発、テスト、本番）で異なる設定ファイルを使い分け可能

## モジュール依存関係と読み込み順序（レイヤアーキテクチャ）

### ディレクトリ構造
```
scripts/modules/Utils/
├── Foundation/          # Layer 1: 基盤層
│   └── CoreUtils.psm1
├── Infrastructure/      # Layer 2: インフラ層
│   ├── ConfigurationUtils.psm1
│   ├── LoggingUtils.psm1
│   └── ErrorHandlingUtils.psm1
├── DataAccess/         # Layer 3: データアクセス層
│   ├── DatabaseUtils.psm1
│   └── FileSystemUtils.psm1
└── DataProcessing/     # Layer 4: データ処理層
    ├── CsvProcessingUtils.psm1
    └── DataFilteringUtils.psm1
```

### Layer 1: Foundation（基盤層）- 設定非依存
1. **Foundation/CoreUtils.psm1** - 最初に読み込み必須（SQLite基本操作、エンコーディング、基本ログ）

### Layer 2: Infrastructure（インフラ層）- 設定依存
2. **Infrastructure/ConfigurationUtils.psm1** - 設定管理専用（CoreUtilsに依存）
3. **Infrastructure/LoggingUtils.psm1** - 高度なログ機能（CoreUtils、ConfigurationUtilsに依存）
4. **Infrastructure/ErrorHandlingUtils.psm1** - 統一エラーハンドリング（CoreUtils、ConfigurationUtilsに依存）

### Layer 3: Data Access（データアクセス層）
5. **DataAccess/DatabaseUtils.psm1** - SQL生成、テーブル定義（Layer 1, 2に依存）
6. **DataAccess/FileSystemUtils.psm1** - ファイル操作、履歴管理（Layer 1, 2に依存）

### Layer 4: Data Processing（データ処理層）
7. **DataProcessing/CsvProcessingUtils.psm1** - CSV処理専用（Layer 1-3に依存）
8. **DataProcessing/DataFilteringUtils.psm1** - データフィルタ処理（Layer 1, 2に依存）

### レイヤアーキテクチャの利点
- **依存関係の明確化**: 下位レイヤのみに依存、循環依存を回避
- **責任分離の明確化**: 各レイヤが単一責任を持つ
- **テスト容易性**: 各レイヤを独立してテスト可能
- **保守性向上**: 変更の影響範囲が明確
- **ディレクトリ分離**: 機能別の物理的分離によりナビゲーションが容易

## データ処理フロー

1. **設定検証** - スキーマとファイルパスの検証
2. **データベース初期化** - 設定からの動的テーブル作成
3. **フィルタリング付きCSVインポート** - 外部ファイル → SQLite、履歴保存付き
4. **データ同期** - 設定可能ルールで比較・マージ
5. **デュアル出力** - ターゲット場所 + 自動履歴保存
6. **統計とレポート** - 日本時間タイムスタンプ付き詳細ログ

## 重要な実装ノート

### 日本時間の取り扱い
- 全タイムスタンプは.NET TimeZoneInfoでAsia/Tokyoタイムゾーンを使用
- ファイル命名: `YYYYMMDD_HHMMSS` 形式
- 設定で設定可能なタイムゾーン

### エラーハンドリングカテゴリ
- **System**: 設定/ロジックエラー（処理停止）
- **Data**: レコード単位の失敗（警告で継続）
- **External**: ファイル/DB アクセス（バックオフ付きリトライ）

### SQLite統合
- PowerShell SQLiteモジュールとsqlite3コマンドラインツールの両方を使用
- 設定ベースの動的SQL生成
- インデックスとトリガーの自動作成

### CSV処理の詳細
- BOMサポート付きUTF-8エンコーディング
- 設定可能な区切り文字とnull値処理
- ヘッダー行検出とマッピング

## テスト戦略

- **ユニットテスト**: モック付き個別モジュール関数
- **統合テスト**: テストデータでの完全システムワークフロー
- **パフォーマンステスト**: 大量データセット処理（1000+レコード）
- **エンコーディングテスト**: 日本語文字処理とUTF-8準拠

## ファイル構成ロジック

- `scripts/modules/Utils/`: 再利用可能ユーティリティ（ビジネスロジックなし）
- `scripts/modules/Process/`: ワークフロー統制とビジネスルール
- `data/`: 自動履歴保存（手動編集禁止）
- `test-data/`: 開発・テスト用サンプルファイル
- `tests/`: ヘルパーとフィクスチャ付き包括的テストスイート

## 設定拡張パターン

新しいデータフィールドを追加するには：
1. `config/data-sync-config.json` のテーブルカラム定義を更新
2. 必要に応じてフィルタリングルールを追加
3. 同期用カラムマッピングを更新
4. すべてのSQL、CSV処理、バリデーションが自動適応

## よくあるトラブルシューティング

- **ファイルエンコーディング**: UTF-8確保、`create-utf8-tests.ps1` で確認
- **パス解決**: 作業ディレクトリと相対パス処理の確認
- **データベースロック**: SQLite busyエラーは同時アクセスを示す
- **フィルタ結果**: 予期しない除外についてはログのフィルタリング統計を確認

## エラーハンドリング標準

### 統一エラーハンドリング関数の使用
```powershell
# 基本パターン
Invoke-WithErrorHandling -ScriptBlock {
    # 処理内容
} -Category System -Operation "処理名" -Context @{
    "ファイルパス" = $filePath
}

# 専用関数（推奨）
Invoke-FileOperationWithErrorHandling -FileOperation {
    # ファイル処理
} -FilePath $path -OperationType "操作種別"
```

## デバッグとメンテナンス

### ログファイルの確認
```bash
# システムログの確認
tail -f logs/data-sync-system.log

# PowerShellでログ確認
Get-Content logs/data-sync-system.log -Tail 20
```

### データベース直接確認
```bash
# SQLiteデータベースに接続
sqlite3 database/data-sync.db

# テーブル一覧表示
.tables

# スキーマ確認
.schema sync_result

# データ確認例
SELECT COUNT(*) FROM provided_data;
SELECT sync_action, COUNT(*) FROM sync_result GROUP BY sync_action;
```

### パフォーマンス最適化
- データ量が多い場合（10万件以上）は performance_settings の調整を検討
- sqlite_pragmas設定でWALモードとキャッシュサイズを最適化済み
- バッチサイズは設定で調整可能（デフォルト1000件）

## 重要な注意事項
- 何か変更を行う際は、必ず設定ベースアーキテクチャを維持すること
- 新機能追加時は config/data-sync-config.json での設定可能性を検討すること
- ハードコーディングは避け、動的生成を優先すること
- すべての変更には適切なログとエラーハンドリングを含めること
- **エラーハンドリングは統一関数を使用し、適切なカテゴリを選択すること**
- **レイヤアーキテクチャの依存関係を維持し、上位レイヤから下位レイヤへの依存のみ許可**

## クイック開発ワークフロー

### 新機能開発時の手順
1. 設定ファイル更新: `config/data-sync-config.json`
2. テスト作成: `tests/` ディレクトリに対応するテストファイル
3. 実装: レイヤアーキテクチャに従ってモジュール選択
4. テスト実行: `pwsh ./tests/run-test.ps1`
5. 統合テスト: `pwsh ./tests/run-test.ps1 -TestPath "Integration\FullSystem.Tests.ps1"`

### 設定変更のテスト
```bash
# 設定変更後の検証
pwsh ./scripts/main.ps1 -ProvidedDataFilePath "./test-data/provided.csv" -CurrentDataFilePath "./test-data/current.csv" -OutputFilePath "./test-data/test-output.csv"
```