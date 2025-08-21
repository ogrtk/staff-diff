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
    
    BeforeEach {
        # テスト用の一時ディレクトリとファイルパス
        $script:testDirectory = New-TemporaryDirectory
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
        if (Test-Path $script:testDirectory) {
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
}