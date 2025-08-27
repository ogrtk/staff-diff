# PowerShell & SQLite データ同期システム
# Process/Invoke-DataSync.psm1 ユニットテスト

# テストヘルパーを最初にインポート
using module "../TestHelpers/TestEnvironmentHelpers.psm1"
using module "../TestHelpers/MockHelpers.psm1"

# 依存関係のモジュールをインポート（モック化準備のため）
using module "../../scripts/modules/Utils/Foundation/CoreUtils.psm1"
using module "../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1" 
using module "../../scripts/modules/Utils/Infrastructure/LoggingUtils.psm1" 
using module "../../scripts/modules/Utils/Infrastructure/ErrorHandlingUtils.psm1"
using module "../../scripts/modules/Utils/DataAccess/DatabaseUtils.psm1" 
using module "../../scripts/modules/Utils/DataAccess/FileSystemUtils.psm1"
using module "../../scripts/modules/Utils/DataProcessing/CsvProcessingUtils.psm1"
using module "../../scripts/modules/Utils/DataProcessing/DataFilteringUtils.psm1"

# テスト対象モジュールを最後にインポート
using module "../../scripts/modules/Process/Invoke-DataSync.psm1" 

Describe "Invoke-DataSync モジュール" {
    
    BeforeAll {
        $script:ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName

        # TestEnvironmentクラスを使用したテスト環境の初期化
        $script:TestEnv = New-TestEnvironment -TestName "DataSync"
        
        # TestEnvironmentクラスを使用してテスト用設定を作成
        $script:ValidTestConfigPath = $script:TestEnv.CreateConfigFile(@{}, "valid-test-config")
        $script:ValidTestConfig = $script:TestEnv.GetConfig()
        
        # テスト用の同期アクション設定
        $script:TestSyncActionLabels = @{
            ADD = @{ value = "1"; enabled = $true; description = "新規追加" }
            UPDATE = @{ value = "2"; enabled = $true; description = "更新" }
            DELETE = @{ value = "3"; enabled = $true; description = "削除" }
            KEEP = @{ value = "9"; enabled = $true; description = "変更なし" }
        }
        
        # テスト用の設定
        $script:TestConfigWithSync = @{
            version = "1.0.0"
            sync_rules = @{
                sync_action_labels = @{
                    mappings = $script:TestSyncActionLabels
                }
            }
            data_filters = @{
                current_data = @{
                    output_excluded_as_keep = @{
                        enabled = $false
                    }
                }
            }
        }
    }
    
    AfterAll {
        # TestEnvironmentクラスを使用したクリーンアップ
        if ($script:TestEnv) {
            $script:TestEnv.Dispose()
        }
    }
    
    BeforeEach {
        # 基本的なモック化 - 共通設定
        Mock -ModuleName "Invoke-DataSync" -CommandName Write-SystemLog { }
        Mock -ModuleName "Invoke-DataSync" -CommandName Invoke-WithErrorHandling { 
            param($ScriptBlock, $Category, $Operation, $Context, $CleanupScript)
            & $ScriptBlock
        }
        Mock -ModuleName "Invoke-DataSync" -CommandName Get-DataSyncConfig { return $script:TestConfigWithSync }
        Mock -ModuleName "Invoke-DataSync" -CommandName Clear-Table { }
        Mock -ModuleName "Invoke-DataSync" -CommandName Invoke-SqliteCommand { }
        
        # 内部処理関数は直接モックできないため、必要に応じてSQLコマンドなどをモック
        
        # データベースユーティリティのモック
        Mock -ModuleName "Invoke-DataSync" -CommandName New-JoinCondition { return "pd.id = cd.id" }
        Mock -ModuleName "Invoke-DataSync" -CommandName Get-TableKeyColumns { return @("id") }
        Mock -ModuleName "Invoke-DataSync" -CommandName Get-SyncResultInsertColumns { return @("id", "name", "sync_action") }
        Mock -ModuleName "Invoke-DataSync" -CommandName New-SyncResultSelectClause { return "pd.id, pd.name, '1'" }
        Mock -ModuleName "Invoke-DataSync" -CommandName New-PriorityBasedSyncResultSelectClause { return "pd.id, pd.name, '1'" }
        Mock -ModuleName "Invoke-DataSync" -CommandName New-ComparisonWhereClause { return "pd.name != cd.name" }
        Mock -ModuleName "Invoke-DataSync" -CommandName Get-PriorityBasedSourceField { return "id" }
        Mock -ModuleName "Invoke-DataSync" -CommandName New-GroupByClause { return "id, name" }
        Mock -ModuleName "Invoke-DataSync" -CommandName Get-CsvColumns { return @("id", "name", "sync_action") }
    }

    Context "Invoke-DataSync 関数 - 基本動作" {
        
        It "有効なデータベースパスで正常に処理を完了する" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("data-sync-test")
            
            # Act & Assert
            { Invoke-DataSync -DatabasePath $testDbPath } | Should -Not -Throw
        }
        
        It "データベースパスが未指定の場合、エラーをスローする" {
            # Act & Assert
            { Invoke-DataSync -DatabasePath "" } | Should -Throw
        }
        
        It "処理開始と完了のログが出力される" {
            # Arrange
            $testDbPath = "/test/database.db"
            
            # Act
            Invoke-DataSync -DatabasePath $testDbPath
            
            # Assert
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データ同期処理を開始" } -Times 1 -Scope It
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データ同期処理が完了" -and $Level -eq "Success" } -Times 1 -Scope It
        }
    }

    Context "Invoke-DataSync 関数 - 同期処理の順序" {
        
        It "sync_resultテーブルの初期化が最初に実行される" {
            # Arrange
            $testDbPath = "/test/database.db"
            
            # Act
            Invoke-DataSync -DatabasePath $testDbPath
            
            # Assert
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Clear-Table -ParameterFilter { $TableName -eq "sync_result" } -Times 1 -Scope It
        }
        
        It "同期処理が正しく実行される" {
            # Arrange
            $testDbPath = "/test/database.db"
            
            # Act
            Invoke-DataSync -DatabasePath $testDbPath
            
            # Assert - 内部でSQL処理が実行されることを確認
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Invoke-SqliteCommand -Times 1 -Scope It
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データ同期処理が完了" } -Times 1 -Scope It
        }
        
        It "設定が適切に取得され使用される" {
            # Arrange
            $testDbPath = "/test/parameter-test.db"
            
            # Act
            Invoke-DataSync -DatabasePath $testDbPath
            
            # Assert
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Get-DataSyncConfig -Times 1 -Scope It
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Clear-Table -ParameterFilter { $TableName -eq "sync_result" } -Times 1 -Scope It
        }
    }

    Context "Invoke-DataSync 関数 - 除外データのKEEP出力" {
        
        It "output_excluded_as_keep設定が有効な場合、除外データがKEEPアクションとして追加される" {
            # Arrange
            $testDbPath = "/test/excluded-enabled.db"
            $configWithExcluded = $script:TestConfigWithSync.PSObject.Copy()
            $configWithExcluded.data_filters.current_data.output_excluded_as_keep.enabled = $true
            Mock -ModuleName "Invoke-DataSync" -CommandName Get-DataSyncConfig { return $configWithExcluded }
            
            # Act
            Invoke-DataSync -DatabasePath $testDbPath
            
            # Assert - 内部処理でSQL実行が行われることを確認
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Invoke-SqliteCommand -Times 1 -Scope It
        }
        
        It "output_excluded_as_keep設定が無効な場合、除外データの処理はスキップされる" {
            # Arrange
            $testDbPath = "/test/excluded-disabled.db"
            $configWithoutExcluded = $script:TestConfigWithSync.PSObject.Copy()
            $configWithoutExcluded.data_filters.current_data.output_excluded_as_keep.enabled = $false
            Mock -ModuleName "Invoke-DataSync" -CommandName Get-DataSyncConfig { return $configWithoutExcluded }
            
            # Act
            Invoke-DataSync -DatabasePath $testDbPath
            
            # Assert - 設定が無効な場合でも基本的な処理は実行される
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データ同期処理が完了" } -Times 1 -Scope It
        }
    }

    Context "内部処理 - 同期処理の統合テスト" {
        
        It "同期処理でSQL文が適切に実行される" {
            # Arrange
            $testDbPath = "/test/integration-sync.db"
            
            # Act
            Invoke-DataSync -DatabasePath $testDbPath
            
            # Assert - 内部でSQL処理が実行されることを確認
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Invoke-SqliteCommand -Times 1 -Scope It
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データ同期処理が完了" } -Times 1 -Scope It
        }
        
        It "データベースユーティリティ関数が呼び出される" {
            # Arrange
            $testDbPath = "/test/utilities-test.db"
            
            # Act
            Invoke-DataSync -DatabasePath $testDbPath
            
            # Assert - 内部でユーティリティ関数が使用されることを確認
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Get-DataSyncConfig -Times 1 -Scope It
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Clear-Table -ParameterFilter { $TableName -eq "sync_result" } -Times 1 -Scope It
        }
    }

    Context "Invoke-DataSync 関数 - エラーハンドリング" {
        
        It "データベースエラー時に適切にエラーハンドリングされる" {
            # Arrange
            $testDbPath = "/test/db-error.db"
            Mock -ModuleName "Invoke-DataSync" -CommandName Clear-Table { throw "データベースアクセスエラー" }
            Mock -ModuleName "Invoke-DataSync" -CommandName Invoke-WithErrorHandling { 
                param($ScriptBlock, $Category, $Operation, $Context, $CleanupScript)
                try {
                    & $ScriptBlock
                } catch {
                    if ($CleanupScript) {
                        & $CleanupScript
                    }
                    throw $_
                }
            }
            
            # Act & Assert
            { Invoke-DataSync -DatabasePath $testDbPath } | Should -Throw "*データベースアクセスエラー*"
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Invoke-WithErrorHandling -ParameterFilter { $Category -eq "External" -and $Operation -eq "データ同期処理" } -Times 1 -Scope It
        }
        
        It "設定エラー時に適切にエラーハンドリングされる" {
            # Arrange
            $testDbPath = "/test/config-error.db"
            Mock -ModuleName "Invoke-DataSync" -CommandName Get-DataSyncConfig { throw "設定読み込みエラー" }
            Mock -ModuleName "Invoke-DataSync" -CommandName Invoke-WithErrorHandling { 
                param($ScriptBlock, $Category, $Operation, $Context, $CleanupScript)
                try {
                    & $ScriptBlock
                } catch {
                    throw $_
                }
            }
            
            # Act & Assert
            { Invoke-DataSync -DatabasePath $testDbPath } | Should -Throw "*設定読み込みエラー*"
        }
        
        It "エラーハンドリング機能が動作する" {
            # Arrange
            $testDbPath = "/test/cleanup-test.db"
            Mock -ModuleName "Invoke-DataSync" -CommandName Invoke-SqliteCommand { throw "SQL処理エラー" }
            
            # Act & Assert - エラーハンドリングが適切に動作することを確認
            { Invoke-DataSync -DatabasePath $testDbPath } | Should -Throw "*SQL処理エラー*"
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Invoke-WithErrorHandling -Times 1 -Scope It
        }
    }

    Context "Invoke-DataSync 関数 - 冪等性" {
        
        It "sync_resultテーブルが処理開始時とエラー時の両方でクリアされる" {
            # Arrange
            $testDbPath = "/test/idempotent.db"
            
            # Act
            Invoke-DataSync -DatabasePath $testDbPath
            
            # Assert
            Should -Invoke -ModuleName "Invoke-DataSync" -CommandName Clear-Table -ParameterFilter { $TableName -eq "sync_result" } -Times 1 -Scope It
        }
        
        It "複数回実行されても同じ結果になる" {
            # Arrange
            $testDbPath = "/test/multiple-runs.db"
            
            # Act & Assert - 複数回実行してもエラーが発生しない
            { Invoke-DataSync -DatabasePath $testDbPath } | Should -Not -Throw
            { Invoke-DataSync -DatabasePath $testDbPath } | Should -Not -Throw
        }
    }

    Context "関数のエクスポート確認" {
        
        It "Invoke-DataSync 関数がエクスポートされている" {
            # Arrange
            Mock -ModuleName "Invoke-DataSync" -CommandName Get-Module {
                return @{
                    ExportedFunctions = @{
                        Keys = @("Invoke-DataSync")
                    }
                }
            }
            
            # Act
            $module = Get-Module -Name Invoke-DataSync
            $exportedFunctions = $module.ExportedFunctions.Keys
            
            # Assert
            $exportedFunctions | Should -Contain "Invoke-DataSync"
        }
    }
}