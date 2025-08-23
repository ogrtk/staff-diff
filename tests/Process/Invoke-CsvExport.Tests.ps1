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
    $configPath = Join-Path (Get-Location) "config" "data-sync-config.json"
    Get-DataSyncConfig -ConfigPath $configPath | Out-Null
}

Describe "Invoke-CsvExport モジュール" {
    BeforeEach {
        # テスト用の一時ディレクトリとファイルパス
        $script:testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "InvokeCsvExportTest_$(Get-Random)"
        New-Item -Path $script:testDirectory -ItemType Directory -Force | Out-Null
        $script:testDbPath = Join-Path $testDirectory "test.db"
        $script:outputPath = Join-Path $testDirectory "output.csv"
        $script:historyPath = Join-Path $testDirectory "history"
        
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
        Reset-DataSyncConfig
    }
    Context "出力フィルタリング機能" {
        
        BeforeEach {
            # テスト用設定のモック
            Mock Get-DataSyncConfig {
                return @{
                    sync_rules       = @{
                        sync_action_labels = @{
                            mappings = @{
                                ADD    = @{ value = "1" }
                                UPDATE = @{ value = "2" }
                                DELETE = @{ value = "3" }
                                KEEP   = @{ value = "9" }
                            }
                        }
                    }
                    output_filtering = @{
                        enabled      = $true
                        sync_actions = @{
                            ADD    = @{ enabled = $true }
                            UPDATE = @{ enabled = $true }
                            DELETE = @{ enabled = $true }
                            KEEP   = @{ enabled = $true }
                        }
                    }
                }
            }
            
            Mock Invoke-SqliteCsvExport { return 5 }
        }
        
        It "全ての同期アクションが有効な場合、フィルタリングなしで出力される" {
            # Act
            Invoke-CsvExport -DatabasePath $testDbPath -OutputFilePath $outputPath
            
            # Assert
            Should -Invoke Invoke-SqliteCsvExport -Times 1 -ParameterFilter {
                $Query -like "*sync_action IN ('1', '2', '3', '9')*"
            }
            Should -Invoke Write-SystemLog -Times 1 -ParameterFilter {
                $Message -like "*出力フィルタリング適用: sync_action IN ('1', '2', '3', '9')*"
            }
        }
        
        It "ADDアクションのみ有効な場合、新規作成のみ出力される" {
            # Arrange
            Mock Get-DataSyncConfig {
                return @{
                    sync_rules       = @{
                        sync_action_labels = @{
                            mappings = @{
                                ADD    = @{ value = "1" }
                                UPDATE = @{ value = "2" }
                                DELETE = @{ value = "3" }
                                KEEP   = @{ value = "9" }
                            }
                        }
                    }
                    output_filtering = @{
                        enabled      = $true
                        sync_actions = @{
                            ADD    = @{ enabled = $true }
                            UPDATE = @{ enabled = $false }
                            DELETE = @{ enabled = $false }
                            KEEP   = @{ enabled = $false }
                        }
                    }
                }
            }
            
            # Act
            Invoke-CsvExport -DatabasePath $testDbPath -OutputFilePath $outputPath
            
            # Assert
            Should -Invoke Invoke-SqliteCsvExport -Times 1 -ParameterFilter {
                $Query -like "*sync_action IN ('1')*"
            }
        }
        
        It "KEEPアクションのみ無効な場合、変更なし以外が出力される" {
            # Arrange
            Mock Get-DataSyncConfig {
                return @{
                    sync_rules       = @{
                        sync_action_labels = @{
                            mappings = @{
                                ADD    = @{ value = "1" }
                                UPDATE = @{ value = "2" }
                                DELETE = @{ value = "3" }
                                KEEP   = @{ value = "9" }
                            }
                        }
                    }
                    output_filtering = @{
                        enabled      = $true
                        sync_actions = @{
                            ADD    = @{ enabled = $true }
                            UPDATE = @{ enabled = $true }
                            DELETE = @{ enabled = $true }
                            KEEP   = @{ enabled = $false }
                        }
                    }
                }
            }
            
            # Act
            Invoke-CsvExport -DatabasePath $testDbPath -OutputFilePath $outputPath
            
            # Assert
            Should -Invoke Invoke-SqliteCsvExport -Times 1 -ParameterFilter {
                $Query -like "*sync_action IN ('1', '2', '3')*"
            }
        }
        
        It "全ての同期アクションが無効な場合、空の結果が出力される" {
            # Arrange
            Mock Get-DataSyncConfig {
                return @{
                    sync_rules       = @{
                        sync_action_labels = @{
                            mappings = @{
                                ADD    = @{ value = "1" }
                                UPDATE = @{ value = "2" }
                                DELETE = @{ value = "3" }
                                KEEP   = @{ value = "9" }
                            }
                        }
                    }
                    output_filtering = @{
                        enabled      = $true
                        sync_actions = @{
                            ADD    = @{ enabled = $false }
                            UPDATE = @{ enabled = $false }
                            DELETE = @{ enabled = $false }
                            KEEP   = @{ enabled = $false }
                        }
                    }
                }
            }
            
            Mock Invoke-SqliteCsvExport { return 0 }
            
            # Act
            Invoke-CsvExport -DatabasePath $testDbPath -OutputFilePath $outputPath
            
            # Assert
            Should -Invoke Invoke-SqliteCsvExport -Times 1 -ParameterFilter {
                $Query -like "*1=0*"
            }
            Should -Invoke Write-SystemLog -Times 1 -ParameterFilter {
                $Message -eq "全ての同期アクションが無効化されています" -and $Level -eq "Warning"
            }
        }
        
        It "enabled設定がない場合、全レコードが出力される" {
            # Arrange
            Mock Get-DataSyncConfig {
                return @{
                    sync_rules = @{
                        sync_action_labels = @{
                            mappings = @{
                                ADD = @{ value = "1" }
                                UPDATE = @{ value = "2" }
                                DELETE = @{ value = "3" }
                                KEEP = @{ value = "9" }
                            }
                        }
                    }
                }
            }
            
            # Act
            Invoke-CsvExport -DatabasePath $testDbPath -OutputFilePath $outputPath
            
            # Assert
            Should -Invoke Invoke-SqliteCsvExport -Times 1 -ParameterFilter {
                $Query -like "*sync_action IN ('1', '2', '3', '9')*"
            }
        }
    }
    
    Context "履歴保存機能" {
        
        BeforeEach {
            Mock Get-DataSyncConfig {
                return @{
                    sync_rules = @{
                        sync_action_labels = @{
                            mappings = @{
                                ADD = @{ value = "1" }
                                UPDATE = @{ value = "2" }
                                DELETE = @{ value = "3" }
                                KEEP = @{ value = "9" }
                            }
                        }
                    }
                }
            }
            Mock Invoke-SqliteCsvExport { return 3 }
        }
        
        It "履歴ディレクトリが存在しない場合、作成される" {
            # Arrange
            Mock Test-Path { return $false }
            Mock New-Item {}
            
            # Act
            Invoke-CsvExport -DatabasePath $testDbPath -OutputFilePath $outputPath
            
            # Assert
            Should -Invoke New-Item -Times 1 -ParameterFilter {
                $ItemType -eq "Directory" -and $Path -eq $script:historyPath
            }
        }
        
        It "出力ファイルが履歴ディレクトリにコピーされる" {
            # Arrange
            Mock Test-Path { return $true }
            
            # Act
            Invoke-CsvExport -DatabasePath $testDbPath -OutputFilePath $outputPath
            
            # Assert
            Should -Invoke Copy-Item -Times 1 -ParameterFilter {
                $Path -eq $outputPath
            }
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
        
        It "実際のsync_resultデータで全アクション出力テスト" {
            # Arrange - sync_resultテーブルにテストデータを挿入
            $actionCounts = @{
                ADD = 5
                UPDATE = 3
                DELETE = 2
                KEEP = 4
            }
            $testEnv.PopulateSyncResultTable($script:integrationDbPath, $actionCounts, @{})
            
            # Act
            Invoke-CsvExport -DatabasePath $script:integrationDbPath -OutputFilePath $script:integrationOutputPath
            
            # Assert
            Test-Path $script:integrationOutputPath | Should -Be $true
            
            # CSVファイルの内容確認
            $csvContent = Import-Csv $script:integrationOutputPath
            $csvContent.Count | Should -Be 14  # 5+3+2+4 = 14件
            
            # 各アクションの件数確認
            ($csvContent | Where-Object { $_.sync_action -eq "1" }).Count | Should -Be 5  # ADD
            ($csvContent | Where-Object { $_.sync_action -eq "2" }).Count | Should -Be 3  # UPDATE
            ($csvContent | Where-Object { $_.sync_action -eq "3" }).Count | Should -Be 2  # DELETE
            ($csvContent | Where-Object { $_.sync_action -eq "9" }).Count | Should -Be 4  # KEEP
        }
        
        It "ADDアクションのみフィルタリングテスト" {
            # Arrange - フィルタリング設定でADDのみ有効
            $filterConfigPath = $testEnv.CreateConfigFile(@{
                sync_rules = @{
                    sync_action_labels = @{
                        mappings = @{
                            ADD    = @{ value = "1"; enabled = $true }
                            UPDATE = @{ value = "2"; enabled = $false }
                            DELETE = @{ value = "3"; enabled = $false }
                            KEEP   = @{ value = "9"; enabled = $false }
                        }
                    }
                }
            }, "add-only-config")
            
            Get-DataSyncConfig -ConfigPath $filterConfigPath | Out-Null
            
            # sync_resultテーブルにテストデータを挿入
            $actionCounts = @{
                ADD = 3
                UPDATE = 5
                DELETE = 2
                KEEP = 8
            }
            $testEnv.PopulateSyncResultTable($script:integrationDbPath, $actionCounts, @{})
            
            # Act
            Invoke-CsvExport -DatabasePath $script:integrationDbPath -OutputFilePath $script:integrationOutputPath
            
            # Assert
            Test-Path $script:integrationOutputPath | Should -Be $true
            
            # CSVファイルの内容確認 - ADDアクションのみ
            $csvContent = Import-Csv $script:integrationOutputPath
            $csvContent.Count | Should -Be 3  # ADDアクションのみ
            $csvContent | ForEach-Object { $_.sync_action | Should -Be "1" }
        }
        
        It "KEEPアクション除外フィルタリングテスト" {
            # Arrange - KEEP以外を有効
            $filterConfigPath = $testEnv.CreateConfigFile(@{
                sync_rules = @{
                    sync_action_labels = @{
                        mappings = @{
                            ADD    = @{ value = "1"; enabled = $true }
                            UPDATE = @{ value = "2"; enabled = $true }
                            DELETE = @{ value = "3"; enabled = $true }
                            KEEP   = @{ value = "9"; enabled = $false }
                        }
                    }
                }
            }, "no-keep-config")
            
            Get-DataSyncConfig -ConfigPath $filterConfigPath | Out-Null
            
            # sync_resultテーブルにテストデータを挿入
            $actionCounts = @{
                ADD = 2
                UPDATE = 3
                DELETE = 1
                KEEP = 10  # KEEPは多めにして除外されることを確認
            }
            $testEnv.PopulateSyncResultTable($script:integrationDbPath, $actionCounts, @{})
            
            # Act
            Invoke-CsvExport -DatabasePath $script:integrationDbPath -OutputFilePath $script:integrationOutputPath
            
            # Assert
            Test-Path $script:integrationOutputPath | Should -Be $true
            
            # CSVファイルの内容確認 - KEEP以外
            $csvContent = Import-Csv $script:integrationOutputPath
            $csvContent.Count | Should -Be 6  # 2+3+1 = 6件（KEEPの10件は除外）
            
            # KEEPアクション（"9"）が含まれていないことを確認
            $csvContent | Where-Object { $_.sync_action -eq "9" } | Should -BeNullOrEmpty
        }
        
        It "全アクション無効時の空出力テスト" {
            # Arrange - すべてのアクションを無効
            $emptyFilterConfigPath = $testEnv.CreateConfigFile(@{
                sync_rules = @{
                    sync_action_labels = @{
                        mappings = @{
                            ADD    = @{ value = "1"; enabled = $false }
                            UPDATE = @{ value = "2"; enabled = $false }
                            DELETE = @{ value = "3"; enabled = $false }
                            KEEP   = @{ value = "9"; enabled = $false }
                        }
                    }
                }
            }, "all-disabled-config")
            
            Get-DataSyncConfig -ConfigPath $emptyFilterConfigPath | Out-Null
            
            # sync_resultテーブルにテストデータを挿入
            $testEnv.PopulateSyncResultTable($script:integrationDbPath, @{ ADD = 5; UPDATE = 3; DELETE = 2; KEEP = 4 }, @{})
            
            # Act
            Invoke-CsvExport -DatabasePath $script:integrationDbPath -OutputFilePath $script:integrationOutputPath
            
            # Assert
            Test-Path $script:integrationOutputPath | Should -Be $true
            
            # CSVファイルの内容確認 - ヘッダーのみ（データなし）
            $csvLines = Get-Content $script:integrationOutputPath
            $csvLines.Count | Should -Be 1  # ヘッダー行のみ
        }
        
        It "履歴保存機能の実テスト" {
            # Arrange
            $actionCounts = @{
                ADD = 2
                UPDATE = 1
                DELETE = 1
                KEEP = 2
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