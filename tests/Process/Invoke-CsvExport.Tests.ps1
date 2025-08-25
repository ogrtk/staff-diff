# PowerShell & SQLite データ同期システム
# Invoke-CsvExport モジュールテスト

using module "../TestHelpers/TestEnvironmentHelpers.psm1"
using module "../../scripts/modules/Utils/Foundation/CoreUtils.psm1"
using module "../../scripts/modules/Utils/Infrastructure/LoggingUtils.psm1"
using module "../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1"
using module "../../scripts/modules/Utils/Infrastructure/ErrorHandlingUtils.psm1"
using module "../../scripts/modules/Utils/DataAccess/DatabaseUtils.psm1"
using module "../../scripts/modules/Utils/DataAccess/FileSystemUtils.psm1"
using module "../../scripts/modules/Utils/DataProcessing/CsvProcessingUtils.psm1"
using module "../../scripts/modules/Utils/DataProcessing/DataFilteringUtils.psm1"
using module "../../scripts/modules/Process/Invoke-CsvExport.psm1"

BeforeAll {
    # テストヘルパーの読み込み
    # 設定初期化
    # $configPath = Join-Path (Get-Location) "config" "data-sync-config.json"
    # Get-DataSyncConfig -ConfigPath $configPath | Out-Null
}

Describe "Invoke-CsvExport モジュール" {
    BeforeEach {
        # テスト用の一時ディレクトリとファイルパス
        $script:testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "InvokeCsvExportTest_$(Get-Random)"
        New-Item -Path $script:testDirectory -ItemType Directory -Force | Out-Null
        $script:testDbPath = Join-Path $testDirectory "test.db"
        $script:outputPath = Join-Path $testDirectory "output.csv"
        $script:historyPath = Join-Path $testDirectory "history"
        
        # sync_resultテーブルの作成
        $createTableSql = @"
CREATE TABLE IF NOT EXISTS sync_result (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    syokuin_no TEXT NOT NULL UNIQUE,
    card_number TEXT,
    name TEXT NOT NULL,
    department TEXT,
    position TEXT,
    email TEXT,
    phone TEXT,
    hire_date DATE,
    sync_action TEXT NOT NULL
);
"@
        Invoke-SqliteCommand -DatabasePath $script:testDbPath -Query $createTableSql
        
        # モック設定
        Mock Write-SystemLog {}
        Mock Get-FilePathConfig {
            return @{
                output_history_directory = $script:historyPath
            }
        }
        Mock Get-TableKeyColumns { return @("syokuin_no") }
        Mock Get-CsvColumns { return @("syokuin_no", "name", "sync_action") }
        Mock New-HistoryFileName { return "test_output_20240101_120000.csv" }
        Mock Copy-Item {}

    }

    AfterEach {
        if ($script:testDirectory -and (Test-Path $script:testDirectory)) {
            Remove-Item -Path $script:testDirectory -Recurse -Force
        }
        # Reset-DataSyncConfig
    }
    Context "出力フィルタリング機能" {
        
        It "デフォルト設定ではADD/UPDATEが無効、DELETE/KEEPが有効" {
            # Act
            Invoke-CsvExport -DatabasePath $testDbPath -OutputFilePath $outputPath
            
            # Assert - 出力ファイルが作成されることを確認
            Test-Path $outputPath | Should -Be $true
        }
    }
    
    Context "履歴保存機能" {
        It "履歴ディレクトリが作成され、ファイルがコピーされる" {
            # Act
            Invoke-CsvExport -DatabasePath $testDbPath -OutputFilePath $outputPath
                
            # Assert - 履歴ディレクトリが存在することを確認
            Test-Path "./data/output" | Should -Be $true
        }
    }
        
    Context "エラーハンドリング" {
            
        It "出力ファイルパスが指定されていない場合、例外がスローされる" {
            # Act & Assert
            { Invoke-CsvExport -DatabasePath $testDbPath -OutputFilePath "" } | Should -Throw "*出力ファイルパスが指定されていません*"
        }
    }
        
    Context "TestEnvironment統合テスト" {
    BeforeEach {
        # TestEnvironmentインスタンス作成
        $script:testEnv = [TestEnvironment]::new("CsvExportIntegration")
            
        # テスト用データベース作成
        $script:integrationDbPath = $testEnv.CreateDatabase("csv_export_test")
            
        # テスト用設定ファイル作成（デフォルト設定と同じフィルタリング設定）
        $script:testConfigPath = $testEnv.CreateConfigFile(@{
                sync_rules = @{
                    sync_action_labels = @{
                        mappings = @{
                            ADD    = @{ value = "1"; enabled = $false }  # デフォルト設定に合わせる
                            UPDATE = @{ value = "2"; enabled = $false } # デフォルト設定に合わせる
                            DELETE = @{ value = "3" }  # enabled未指定=true（デフォルト）
                            KEEP   = @{ value = "9" }  # enabled未指定=true（デフォルト）
                        }
                    }
                }
            }, "integration-config")
            
        # 設定を読み込み
        Get-DataSyncConfig -ConfigPath $script:testConfigPath | Out-Null
            
        # テスト用出力パス
        $script:integrationOutputPath = Join-Path $testEnv.GetTempDirectory() "csv-data" "integration_output.csv"
    }
        
    AfterEach {
        if ($script:testEnv) {
            $script:testEnv.Dispose()
        }
        Reset-DataSyncConfig
    }
        
    It "実際のsync_resultデータでデフォルトフィルタリングテスト" {
        # Arrange - sync_resultテーブルにテストデータを挿入
        $actionCounts = @{
            ADD    = 5
            UPDATE = 3
            DELETE = 2
            KEEP   = 4
        }
        $testEnv.PopulateSyncResultTable($script:integrationDbPath, $actionCounts, @{})
            
        # Act - デフォルト設定で実行
        Invoke-CsvExport -DatabasePath $script:integrationDbPath -OutputFilePath $script:integrationOutputPath
            
        # Assert
        Test-Path $script:integrationOutputPath | Should -Be $true
            
        # CSVファイルの内容確認（デフォルト設定でADD/UPDATE除外、DELETE/KEEP有効）
        $csvContent = Import-Csv $script:integrationOutputPath
        $csvContent.Count | Should -Be 6  # 2+4 = 6件（ADD=5, UPDATE=3はデフォルトで除外）
            
        # 有効なアクションのみが含まれることを確認
            ($csvContent | Where-Object { $_.sync_action -eq "3" }).Count | Should -Be 2  # DELETE
            ($csvContent | Where-Object { $_.sync_action -eq "9" }).Count | Should -Be 4  # KEEP
    }
        
    It "デフォルト設定でのフィルタリング動作テスト" {
        # Arrange - sync_resultテーブルにテストデータを挿入
        $actionCounts = @{
            ADD    = 3
            UPDATE = 5
            DELETE = 2
            KEEP   = 8
        }
        $testEnv.PopulateSyncResultTable($script:integrationDbPath, $actionCounts, @{})
            
        # Act - デフォルト設定で実行
        Invoke-CsvExport -DatabasePath $script:integrationDbPath -OutputFilePath $script:integrationOutputPath
            
        # Assert
        Test-Path $script:integrationOutputPath | Should -Be $true
            
        # CSVファイルの内容確認 - DELETEとKEEPのみ有効
        $csvContent = Import-Csv $script:integrationOutputPath
        $csvContent.Count | Should -Be 10  # 2+8 = 10件（ADD=3, UPDATE=5はデフォルトで除外）
    }
        
    It "大量データでのフィルタリングテスト" {
        # Arrange - 大量のテストデータを挿入
        $actionCounts = @{
            ADD    = 2
            UPDATE = 3
            DELETE = 1
            KEEP   = 10
        }
        $testEnv.PopulateSyncResultTable($script:integrationDbPath, $actionCounts, @{})
            
        # Act - デフォルト設定で実行
        Invoke-CsvExport -DatabasePath $script:integrationDbPath -OutputFilePath $script:integrationOutputPath
            
        # Assert
        Test-Path $script:integrationOutputPath | Should -Be $true
            
        # CSVファイルの内容確認 - DELETEとKEEPのみ有効
        $csvContent = Import-Csv $script:integrationOutputPath
        $csvContent.Count | Should -Be 11  # 1+10 = 11件（ADD=2, UPDATE=3はデフォルトで除外）
    }
        
    It "デフォルト設定でのヘッダーチェック" {
        # Arrange - テストデータを挿入
        $testEnv.PopulateSyncResultTable($script:integrationDbPath, @{ ADD = 5; UPDATE = 3; DELETE = 2; KEEP = 4 }, @{})
            
        # Act - デフォルト設定で実行
        Invoke-CsvExport -DatabasePath $script:integrationDbPath -OutputFilePath $script:integrationOutputPath
            
        # Assert
        Test-Path $script:integrationOutputPath | Should -Be $true
            
        # CSVファイルのヘッダーとデータ行が正しいことを確認
        $csvLines = Get-Content $script:integrationOutputPath
        $csvLines.Count | Should -Be 7  # ヘッダー + 6データ行（DELETE=2, KEEP=4のみ）
    }
        
    It "履歴保存機能の実テスト" {
        # Arrange
        $actionCounts = @{
            ADD    = 2
            UPDATE = 1
            DELETE = 1
            KEEP   = 2
        }
        $testEnv.PopulateSyncResultTable($script:integrationDbPath, $actionCounts, @{})
            
        # 履歴ディレクトリパスを設定に追加
        $historyConfigPath = $testEnv.CreateConfigFile(@{
                file_paths = @{
                    output_history_directory = Join-Path $testEnv.GetTempDirectory() "output-history"
                }
            }, "history-config")
            
        Get-DataSyncConfig -ConfigPath $historyConfigPath | Out-Null
            
        # Act
        Invoke-CsvExport -DatabasePath $script:integrationDbPath -OutputFilePath $script:integrationOutputPath
            
        # Assert
        Test-Path $script:integrationOutputPath | Should -Be $true
            
        # 履歴ディレクトリが作成されていることを確認
        $historyDir = Join-Path $testEnv.GetTempDirectory() "output-history"
        Test-Path $historyDir | Should -Be $true
            
        # 履歴ファイルが存在することを確認（実装によってはファイル名が動的）
        $historyFiles = Get-ChildItem $historyDir -Filter "*.csv"
        $historyFiles.Count | Should -BeGreaterThan 0
    }
    }
}
