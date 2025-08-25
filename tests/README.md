● PowerShell & SQLite データ同期システム - 
  テストスクリプト使い方ガイド

  📋 テストスクリプト概要

  作成されたテストスイートは以下の3つのメインスク
  リプトで構成されています：

  🧪 主要テストスクリプト

  | スクリプト                       | 機能
    | 用途                |
  |-----------------------------|------------|----
  ---------------|
  | tests/run-test.ps1          | メインテスト実行
     | 全種類のテスト実行・レポート生成  |
  | tests/create-utf8-tests.ps1 | テストデータ生成
     | UTF-8対応テストファイル作成  |
  | tests/encoding-fix.ps1      |
  エンコーディング修正 |
  ファイルエンコーディング検出・修正 |

  ---
  🚀 メインテストスクリプト（run-test.ps1）

  基本的な使い方

  # 全テストを実行
  pwsh ./tests/run-test.ps1

  # 特定のテストタイプを実行
  pwsh ./tests/run-test.ps1 -TestType Unit
  pwsh ./tests/run-test.ps1 -TestType Integration
  pwsh ./tests/run-test.ps1 -TestType Process
  pwsh ./tests/run-test.ps1 -TestType Foundation

  # 特定のテストファイルを実行
  pwsh ./tests/run-test.ps1 -TestPath "Utils\Foundation\CoreUtils.Tests.ps1"

  パラメータ詳細

  | パラメータ           | 説明                |
  選択肢
                 | デフォルト   |
  |-----------------|-------------------|---------
  ------------------------------------------------
  ----|---------|
  | -TestPath       |
  特定のテストファイル/ディレクトリ | ファイルパス

        | ""      |
  | -TestType       | 実行するテストタイプ
  | All, Unit, Integration, Foundation,
  Infrastructure, Process | All     |
  | -OutputFormat   | 出力形式              |
  Console, NUnitXml, HTML, Text
              | Console |
  | -OutputPath     | 出力ファイルパス          |
  ファイルパス
                    | 自動生成    |
  | -ShowCoverage   | コードカバレッジ表示
  | スイッチ
                    | false   |
  | -Detailed       | 詳細出力              |
  スイッチ
                  | false   |
  | -SkipSlowTests  | 時間のかかるテストをスキップ
      | スイッチ
                        | false   |
  | -TimeoutMinutes | タイムアウト時間（分）
   | 数値
                   | 30      |

  テストタイプ別実行

  1. ユニットテスト

  # Foundation層のテスト（基盤機能）
  pwsh ./tests/run-test.ps1 -TestType Foundation

  # Infrastructure層のテスト（設定・エラーハンドリ
  ング）
  pwsh ./tests/run-test.ps1 -TestType
  Infrastructure

  # Process層のテスト（ビジネスロジック）
  pwsh ./tests/run-test.ps1 -TestType Process

  # すべてのユニットテスト
  pwsh ./tests/run-test.ps1 -TestType Unit

  2. 統合テスト

  # フルシステム統合テスト
  pwsh ./tests/run-test.ps1 -TestType Integration

  # 詳細出力付き統合テスト
  pwsh ./tests/run-test.ps1 -TestType Integration
  -Detailed

  出力形式とレポート生成

  1. HTMLレポート生成

  # HTMLレポート付きでテスト実行
  pwsh ./tests/run-test.ps1 -OutputFormat HTML

  # カスタムパスにHTMLレポート生成
  pwsh ./tests/run-test.ps1 -OutputFormat HTML
  -OutputPath "./reports/test-result.html"

  # コードカバレッジ付きHTMLレポート
  pwsh ./tests/run-test.ps1 -OutputFormat HTML
  -ShowCoverage

  2. XML形式での出力（CI/CD用）

  # NUnit XML形式で出力
  pwsh ./tests/run-test.ps1 -OutputFormat NUnitXml

  # カスタムパスにXML出力
  pwsh ./tests/run-test.ps1 -OutputFormat NUnitXml
   -OutputPath "./reports/TestResults.xml"

  3. テキストレポート

  # テキスト形式でレポート生成
  pwsh ./tests/run-test.ps1 -OutputFormat Text
  -OutputPath "./reports/test-summary.txt"

  コードカバレッジ

  # カバレッジ情報を表示
  pwsh ./tests/run-test.ps1 -ShowCoverage

  # カバレッジ付きHTMLレポート
  pwsh ./tests/run-test.ps1 -ShowCoverage
  -OutputFormat HTML

  # 特定層のカバレッジ確認
  pwsh ./tests/run-test.ps1 -TestType Foundation
  -ShowCoverage

  パフォーマンステスト

  # 時間のかかるテストをスキップ
  pwsh ./tests/run-test.ps1 -SkipSlowTests

  # タイムアウト時間を延長（大量データテスト用）
  pwsh ./tests/run-test.ps1 -TimeoutMinutes 60

  # パフォーマンステストのみ実行
  pwsh ./tests/run-test.ps1 -TestPath
  "Integration\FullSystem.Tests.ps1"
  -TimeoutMinutes 60

  ---
  🔧 テストデータ生成スクリプト（create-utf8-tests
  .ps1）

  基本的な使い方

  # 基本的なテストファイル生成
  pwsh ./tests/create-utf8-tests.ps1

  # 既存ファイルを上書きして生成
  pwsh ./tests/create-utf8-tests.ps1 -Overwrite

  # カスタムディレクトリに生成
  pwsh ./tests/create-utf8-tests.ps1
  -OutputDirectory "./custom-test-data"

  パラメータ詳細

  | パラメータ            | 説明           |
  デフォルト                |
  |------------------|--------------|-------------
  ---------|
  | -OutputDirectory | 出力ディレクトリ     |
  test-data/utf8-tests |
  | -Overwrite       | 既存ファイル上書き    |
  false                |
  | -IncludeJapanese | 日本語データを含む    |
  true                 |
  | -IncludeBOM      | UTF-8 BOMを含む | false
              |
  | -RecordCount     | 生成するレコード数    | 20
                    |

  用途別テストデータ生成

  1. 日本語テストデータ

  # 日本語を含むテストデータ生成
  pwsh ./tests/create-utf8-tests.ps1
  -IncludeJapanese

  # 日本語なしのテストデータ生成
  pwsh ./tests/create-utf8-tests.ps1
  -IncludeJapanese:$false

  2. エンコーディングテスト用

  # BOM付きUTF-8ファイル生成
  pwsh ./tests/create-utf8-tests.ps1 -IncludeBOM

  # BOM無しUTF-8ファイル生成（デフォルト）
  pwsh ./tests/create-utf8-tests.ps1

  3. 大量データテスト用

  # 1000件のテストデータ生成
  pwsh ./tests/create-utf8-tests.ps1 -RecordCount
  1000 -Overwrite

  # パフォーマンステスト用（10000件）
  pwsh ./tests/create-utf8-tests.ps1 -RecordCount
  10000 -OutputDirectory "./perf-test-data"

  4. フィルタリングテスト用

  # フィルタリング機能テスト用データ（Z*、Y*除外パ
  ターン含む）
  pwsh ./tests/create-utf8-tests.ps1

  # 生成されるファイル例：
  # - provided-data-with-filters.csv (Z*, 
  Y*パターン含む)
  # - current-data-with-filters.csv
  # - test-config-with-filters.json 
  (フィルタ設定付き)

  生成されるファイル一覧

  | ファイル名                   | 内容          |
   用途           |
  |-------------------------|-------------|-------
  -------|
  | provided-data-basic.csv | 基本提供データ     |
   基本テスト        |
  | current-data-basic.csv  | 基本現在データ     |
   基本テスト        |
  | *-with-filters.csv      |
  フィルタリング用データ |
  フィルタリング機能テスト |
  | large-*.csv             | 大量データ       |
  パフォーマンステスト   |
  | special-chars-data.csv  | 特殊文字データ     |
   エンコーディングテスト  |
  | error-test-data.csv     |
  不正フォーマットデータ |
  エラーハンドリングテスト |
  | encoding-*.csv          |
  エンコーディング検証用 | エンコーディングテスト
   |
  | test-config-*.json      | テスト用設定ファイル
    | 設定テスト        |

  ---
  🔍 エンコーディング修正スクリプト（encoding-fix.
  ps1）

  基本的な使い方

  # ファイルエンコーディング情報表示
  pwsh ./tests/encoding-fix.ps1 -TargetPath
  "file.csv" -ShowInfo

  # プロジェクト全体をUTF-8に変換（DryRun）
  pwsh ./tests/encoding-fix.ps1 -TargetEncoding
  UTF8 -Recursive -DryRun

  # 実際の変換実行
  pwsh ./tests/encoding-fix.ps1 -TargetEncoding
  UTF8 -Recursive -Backup

  パラメータ詳細

  | パラメータ           | 説明          | 選択肢

    | デフォルト                    |
  |-----------------|-------------|---------------
  ----------------------------------------|-------
  -------------------|
  | -TargetPath     | 対象パス        |
  ファイル/ディレクトリパス
                    | プロジェクトルート
        |
  | -TargetEncoding | 変換先エンコーディング |
  UTF8, UTF8BOM, ASCII, Unicode, UTF32
        | UTF8                     |
  | -SourceEncoding | 変換元エンコーディング |
  Auto, UTF8, UTF8BOM, ASCII, Unicode, UTF32,
  SHIFT_JIS | Auto                     |
  | -Recursive      | サブディレクトリも対象 |
  スイッチ
            | false                    |
  | -FileExtensions | 対象ファイル拡張子   |
  文字列配列
             | ps1,psm1,csv,json,txt,md |
  | -Backup         | バックアップ作成    |
  スイッチ
            | false                    |
  | -DryRun         | 実行せず予定表示    |
  スイッチ
            | false                    |
  | -Force          | 確認プロンプトスキップ |
  スイッチ
            | false                    |

  用途別使用例

  1. エンコーディング情報確認

  # 特定ファイルのエンコーディング確認
  pwsh ./tests/encoding-fix.ps1 -TargetPath
  "./test-data/sample.csv" -ShowInfo

  # 複数ファイルのエンコーディング確認
  Get-ChildItem "./test-data/*.csv" |
  ForEach-Object {
      pwsh ./tests/encoding-fix.ps1 -TargetPath
  $_.FullName -ShowInfo
  }

  2. UTF-8変換（BOM無し）

  # CSVファイルのみUTF-8に変換
  pwsh ./tests/encoding-fix.ps1 -TargetPath
  "./test-data" -TargetEncoding UTF8
  -FileExtensions @("*.csv") -DryRun

  # PowerShellファイルをUTF-8に変換（バックアップ
  付き）
  pwsh ./tests/encoding-fix.ps1 -TargetEncoding
  UTF8 -FileExtensions @("*.ps1", "*.psm1")
  -Backup -Recursive

  3. BOM付きUTF-8変換

  # PowerShellファイルをBOM付きUTF-8に変換
  pwsh ./tests/encoding-fix.ps1 -TargetEncoding
  UTF8BOM -FileExtensions @("*.ps1", "*.psm1")
  -Recursive

  4. Shift_JISからUTF-8への変換

  # Shift_JISファイルをUTF-8に変換
  pwsh ./tests/encoding-fix.ps1 -SourceEncoding
  SHIFT_JIS -TargetEncoding UTF8 -TargetPath
  "./legacy-data" -Backup

  ---
  🔬 テスト構造とヘルパー機能

  テストヘルパーモジュール

  1. LayeredTestHelpers.psm1

  # レイヤアーキテクチャ対応モジュール読み込み
  Import-LayeredModules -ProjectRoot $ProjectRoot
  -TargetLayers @("Foundation", "Infrastructure")

  # テスト環境初期化
  $testEnv = Initialize-TestEnvironment
  -ProjectRoot $ProjectRoot -CreateTempDatabase

  # テスト環境クリーンアップ
  Clear-TestEnvironment -ProjectRoot $ProjectRoot

  2. MockHelpers.psm1

  # SQLiteコマンドのモック化
  New-MockSqliteCommand -ReturnValue "test result"
  -ExitCode 0

  # ファイルシステムのモック化
  New-MockFileSystemOperations -FileExists
  @{"/test/file.csv" = $true} -FileContent
  @{"/test/file.csv" = "test,data"}

  # ログシステムのモック化
  New-MockLoggingSystem -CaptureMessages
  -SuppressOutput

  # モック呼び出し履歴の確認
  Assert-MockCalled -CommandName "sqlite3" -Times
  1

  3. TestDataGenerator.psm1

  # CSVテストデータ生成
  $testData = New-TestCsvData -DataType
  "provided_data" -RecordCount 10 -IncludeJapanese

  # 同期結果テストデータ生成
  $syncResults = New-SyncResultRecords -AddCount 3
   -UpdateCount 2 -DeleteCount 1 -KeepCount 4

  # テスト用設定ファイル生成
  $testConfig = New-TestConfig -CustomSettings @{
      data_filters = @{
          provided_data = @{ enabled = $true }
      }
  }

  カスタムテストの作成

  1. 新しいユニットテストファイル

  # tests/Utils/NewModule/NewModule.Tests.ps1

  # テストヘルパー読み込み
  Import-Module (Join-Path $TestHelpersPath
  "LayeredTestHelpers.psm1") -Force
  Import-Module (Join-Path $TestHelpersPath
  "MockHelpers.psm1") -Force

  Describe "NewModule テスト" {
      BeforeAll {
          $script:TestEnv =
  Initialize-TestEnvironment -ProjectRoot
  $ProjectRoot
      }

      AfterAll {
          Clear-TestEnvironment -ProjectRoot
  $ProjectRoot
          # モックのリセットは不要。Pesterが自動で管理。
      }

      Context "機能テスト" {
          It "正常ケース" {
              # テストロジック
          }
      }
  }

  2. 統合テストの拡張

  # tests/Integration/CustomIntegration.Tests.ps1

  Describe "カスタム統合テスト" {
      Context "特定シナリオ" {
          It "カスタムフローのテスト" {
              # カスタムテストデータ準備
              $customData = New-TestCsvData
  -DataType "mixed" -RecordCount 100

              # メインスクリプト実行
              $result = & pwsh $MainScriptPath
  -ProvidedDataFilePath $providedPath
  -CurrentDataFilePath $currentPath
  -OutputFilePath $outputPath

              # 結果検証
              $result | Should -Not -BeNullOrEmpty
          }
      }
  }

  ---
  🚀 CI/CD統合

  GitHub Actions例

  name: PowerShell Tests

  on: [push, pull_request]

  jobs:
    test:
      runs-on: ubuntu-latest
      steps:
      - uses: actions/checkout@v3

      - name: Install SQLite
        run: sudo apt-get install sqlite3

      - name: Run Tests
        run: |
          pwsh ./tests/run-test.ps1 -OutputFormat 
  NUnitXml -ShowCoverage

      - name: Publish Test Results
        uses: dorny/test-reporter@v1
        if: always()
        with:
          name: PowerShell Tests
          path: tests/TestResults.xml
          reporter: dotnet-nunit

  Azure DevOps例

  trigger:
  - main

  pool:
    vmImage: 'ubuntu-latest'

  steps:
  - task: PowerShell@2
    displayName: 'Run Tests'
    inputs:
      targetType: 'inline'
      script: |
        ./tests/run-test.ps1 -OutputFormat 
  NUnitXml -ShowCoverage

  - task: PublishTestResults@2
    displayName: 'Publish Test Results'
    inputs:
      testResultsFormat: 'NUnit'
      testResultsFiles: 'tests/TestResults.xml'

  ---
  🔧 トラブルシューティング

  よくあるエラーと対処法

  1. Pesterモジュールが見つからない

  # エラー: Module 'Pester' not found
  # 対処法: モジュールの手動インストール
  Install-Module -Name Pester -Force -Scope
  CurrentUser -AllowClobber

  2. SQLiteコマンドが見つからない

  # エラー: sqlite3コマンドが見つかりません
  # 対処法: SQLiteインストール

  # Windows (Chocolatey)
  choco install sqlite

  # Ubuntu/Debian
  sudo apt-get install sqlite3

  # macOS (Homebrew)
  brew install sqlite

  3. テストファイルのエンコーディングエラー

  # エラー: 文字化けやエンコーディングエラー
  # 対処法: エンコーディング修正
  pwsh ./tests/encoding-fix.ps1 -TargetPath
  "./test-data" -TargetEncoding UTF8
  -FileExtensions @("*.csv") -Backup

  4. 統合テストのタイムアウト

  # エラー: Test execution timeout
  # 対処法: タイムアウト時間延長
  pwsh ./tests/run-test.ps1 -TestType Integration
  -TimeoutMinutes 60

  5. 一時ファイルクリーンアップエラー

  # エラー: Cannot delete temp files
  # 対処法: 手動クリーンアップ
  Remove-Item $env:TEMP -Include "*test*" -Recurse
   -Force -ErrorAction SilentlyContinue

  デバッグテクニック

  1. 詳細出力での実行

  # 詳細ログ付きでテスト実行
  pwsh ./tests/run-test.ps1 -Detailed -TestPath
  "Utils\Foundation\CoreUtils.Tests.ps1"

  2. 特定テストの分離実行

  # 特定のテストのみ実行
  pwsh ./tests/run-test.ps1 -TestPath
  "Integration\FullSystem.Tests.ps1" -Detailed

  3. モック呼び出し履歴の確認

  # テスト内でモック履歴確認
  $mockHistory = Get-MockCallHistory -CommandName
  "sqlite3"
  Write-Host "SQLite呼び出し回数: 
  $($mockHistory.Count)"

  ---
  📊 テスト結果の分析

  カバレッジレポートの読み方

  # カバレッジ付きHTMLレポート生成
  pwsh ./tests/run-test.ps1 -ShowCoverage
  -OutputFormat HTML

  生成されるファイル

  - TestResults.html - テスト結果HTML
  - Coverage.xml - JaCoCo形式カバレッジ
  - TestResults.xml - NUnit形式テスト結果

  カバレッジ目標

  - Foundation層: 90%以上
  - Infrastructure層: 85%以上
  - Process層: 80%以上
  - 統合テスト: 70%以上

  パフォーマンス分析

  # パフォーマンステスト実行
  pwsh ./tests/run-test.ps1 -TestType Integration
  -TimeoutMinutes 60 | Tee-Object -FilePath
  "./perf-results.log"

  パフォーマンス目標

  - 小量データ（~100件）: 30秒以内
  - 中量データ（~1000件）: 2分以内
  - 大量データ（~10000件）: 10分以内

  ---
  🎯 テスト戦略とベストプラクティス

  1. テスト実行順序

  # 推奨実行順序
  # 1. Foundation層（基盤機能）
  pwsh ./tests/run-test.ps1 -TestType Foundation

  # 2. 
  Infrastructure層（設定・エラーハンドリング）
  pwsh ./tests/run-test.ps1 -TestType
  Infrastructure

  # 3. Process層（ビジネスロジック）
  pwsh ./tests/run-test.ps1 -TestType Process

  # 4. 統合テスト
  pwsh ./tests/run-test.ps1 -TestType Integration

  2. 開発時のテスト

  # 開発中は高速テストのみ
  pwsh ./tests/run-test.ps1 -SkipSlowTests

  # 変更した層のみテスト
  pwsh ./tests/run-test.ps1 -TestType Foundation

  # 特定ファイルのみテスト
  pwsh ./tests/run-test.ps1 -TestPath
  "Utils\Foundation\CoreUtils.Tests.ps1"

  3. リリース前テスト

  # 完全なテストスイート実行
  pwsh ./tests/run-test.ps1 -ShowCoverage
  -OutputFormat HTML -Detailed

  # パフォーマンステスト実行
  pwsh ./tests/run-test.ps1 -TestType Integration
  -TimeoutMinutes 60

  このテストスクリプト群により、PowerShell &
  SQLite データ同期システムの品質保証と継続的な改
  善が可能になります。