# TestEnvironment統合テスト単体実行用

using module "./TestEnvironmentHelpers.psm1"
using module "../../scripts/modules/Utils/Foundation/CoreUtils.psm1"
using module "../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1"

Describe "TestEnvironment統合テスト（単体）" {
    BeforeAll {
        # 全テストの開始前に設定をリセット
        Reset-DataSyncConfig
    }
    
    BeforeEach {
        # 設定をリセット
        Reset-DataSyncConfig
        
        # TestEnvironmentインスタンス作成
        $script:testEnv = [TestEnvironment]::new("CsvExportIntegration")
        
        # テスト用データベース作成
        $script:integrationDbPath = $testEnv.CreateDatabase("csv_export_test")
        
        # テスト用設定ファイル作成（フィルタリング設定含む）
        $script:testConfigPath = $testEnv.CreateConfigFile(@{
            sync_rules = @{
                sync_action_labels = @{
                    mappings = @{
                        ADD    = @{ value = "1"; enabled = $true }
                        UPDATE = @{ value = "2"; enabled = $true }
                        DELETE = @{ value = "3"; enabled = $true }
                        KEEP   = @{ value = "9"; enabled = $true }
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
    
    AfterAll {
        # 全テスト終了後に設定をリセット
        Reset-DataSyncConfig
    }
    
    It "sync_resultテーブル作成とデータ挿入テスト" {
        # Arrange
        $actionCounts = @{
            ADD = 5
            UPDATE = 3
            DELETE = 2
            KEEP = 4
        }
        
        # Act
        $testEnv.PopulateSyncResultTable($script:integrationDbPath, $actionCounts, @{})
        
        # Assert
        # データベースにテーブルが作成されていることを確認
        $tableExists = Invoke-SqliteCommand -DatabasePath $script:integrationDbPath -Query "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_result';"
        $tableExists | Should -Not -BeNullOrEmpty
        
        # データが正しく挿入されていることを確認
        $recordCount = Invoke-SqliteCommand -DatabasePath $script:integrationDbPath -Query "SELECT COUNT(*) FROM sync_result;"
        $recordCount | Should -Be 14  # 5+3+2+4
        
        # 各アクションの件数確認
        $addCount = Invoke-SqliteCommand -DatabasePath $script:integrationDbPath -Query "SELECT COUNT(*) FROM sync_result WHERE sync_action = '1';"
        $addCount | Should -Be 5
        
        $updateCount = Invoke-SqliteCommand -DatabasePath $script:integrationDbPath -Query "SELECT COUNT(*) FROM sync_result WHERE sync_action = '2';"
        $updateCount | Should -Be 3
        
        $deleteCount = Invoke-SqliteCommand -DatabasePath $script:integrationDbPath -Query "SELECT COUNT(*) FROM sync_result WHERE sync_action = '3';"
        $deleteCount | Should -Be 2
        
        $keepCount = Invoke-SqliteCommand -DatabasePath $script:integrationDbPath -Query "SELECT COUNT(*) FROM sync_result WHERE sync_action = '9';"
        $keepCount | Should -Be 4
    }
    
    It "TestEnvironmentのクリーンアップテスト" {
        # Arrange
        $tempDir = $testEnv.GetTempDirectory()
        $dbPath = $testEnv.CreateDatabase("cleanup_test")
        $csvPath = $testEnv.CreateCsvFile("provided_data", 5, @{})
        
        # 作成したファイルが存在することを確認
        Test-Path $tempDir | Should -Be $true
        Test-Path $dbPath | Should -Be $true
        Test-Path $csvPath | Should -Be $true
        
        # Act
        $testEnv.Dispose()
        
        # Assert
        Test-Path $tempDir | Should -Be $false
        Test-Path $dbPath | Should -Be $false
        Test-Path $csvPath | Should -Be $false
    }
}