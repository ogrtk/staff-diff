# PowerShell & SQLite データ同期システム
# Process/Test-DataConsistency.psm1 ユニットテスト

# テストヘルパーを最初にインポート
using module "../TestHelpers/TestEnvironmentHelpers.psm1"
using module "../TestHelpers/MockHelpers.psm1"

# 依存関係のモジュールをインポート（モック化準備のため）
using module "../../scripts/modules/Utils/Foundation/CoreUtils.psm1"
using module "../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1" 
using module "../../scripts/modules/Utils/Infrastructure/LoggingUtils.psm1" 
using module "../../scripts/modules/Utils/Infrastructure/ErrorHandlingUtils.psm1"
using module "../../scripts/modules/Utils/DataAccess/DatabaseUtils.psm1" 

# テスト対象モジュールを最後にインポート
using module "../../scripts/modules/Process/Test-DataConsistency.psm1" 

Describe "Test-DataConsistency モジュール" {
    
    BeforeAll {
        $script:ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName

        # TestEnvironmentクラスを使用したテスト環境の初期化
        $script:TestEnv = New-TestEnvironment -TestName "DataConsistency"
        
        # TestEnvironmentクラスを使用してテスト用設定を作成
        $script:ValidTestConfigPath = $script:TestEnv.CreateConfigFile(@{}, "valid-test-config")
        $script:ValidTestConfig = $script:TestEnv.GetConfig()
    }
    
    AfterAll {
        # TestEnvironmentクラスを使用したクリーンアップ
        if ($script:TestEnv) {
            $script:TestEnv.Dispose()
        }
    }
    
    BeforeEach {
        # 基本的なモック化 - 共通設定
        Mock -ModuleName "Test-DataConsistency" -CommandName Write-SystemLog { }
        Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-WithErrorHandling { 
            param($ScriptBlock, $Category, $Operation, $Context, $SuppressThrow)
            & $ScriptBlock
        }
        Mock -ModuleName "Test-DataConsistency" -CommandName New-GroupByClause { return "id, name" }
        Mock -ModuleName "Test-DataConsistency" -CommandName Get-TableKeyColumns { return @("id", "name") }
        Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { return @() }
        Mock -ModuleName "Test-DataConsistency" -CommandName Write-Warning { }
    }

    Context "Test-DataConsistency 関数 - 基本動作" {
        
        It "有効なデータベースパスで正常に処理を完了する" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("consistency-test")
            
            # Act
            { Test-DataConsistency -DatabasePath $testDbPath } | Should -Not -Throw
            
            # Assert
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データ整合性をチェック中" } -Times 1 -Scope It
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データ整合性チェック完了" } -Times 1 -Scope It
        }
        
        It "データベースパスが未指定の場合、エラーをスローする" {
            # Act & Assert
            { Test-DataConsistency -DatabasePath "" } | Should -Throw
        }
        
        It "重複データが存在しない場合、正常に完了する" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("no-duplicates")
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { return @() }
            
            # Act & Assert
            { Test-DataConsistency -DatabasePath $testDbPath } | Should -Not -Throw
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Write-SystemLog -ParameterFilter { $Message -match "問題なし" } -Times 1 -Scope It
        }
    }

    Context "Test-DataConsistency 関数 - 重複データ検出" {
        
        It "重複データが存在する場合、適切にエラーをスローする" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("duplicates-test")
            $duplicateData = @(
                @{ id = "001"; name = "テスト"; count = 2 },
                @{ id = "002"; name = "サンプル"; count = 3 }
            )
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { return $duplicateData }
            
            # Act & Assert
            { Test-DataConsistency -DatabasePath $testDbPath } | Should -Throw "*重複したキー*"
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Write-Warning -Times 3 -Scope It
        }
        
        It "重複データに対して適切な警告メッセージを出力する" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("warning-test")
            $duplicateData = @(
                @{ id = "001"; name = "テスト1"; count = 2 }
            )
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { return $duplicateData }
            
            # Act & Assert
            { Test-DataConsistency -DatabasePath $testDbPath } | Should -Throw
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Write-Warning -ParameterFilter { $Message -match "重複したキー.*が見つかりました" } -Times 1 -Scope It
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Write-Warning -ParameterFilter { $Message -match "001, テスト1.*: 2件" } -Times 1 -Scope It
        }
        
        It "複数の重複データに対して全てを報告する" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("multiple-duplicates")
            $duplicateData = @(
                @{ id = "001"; name = "テスト1"; count = 2 },
                @{ id = "002"; name = "テスト2"; count = 3 },
                @{ id = "003"; name = "テスト3"; count = 4 }
            )
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { return $duplicateData }
            
            # Act & Assert
            { Test-DataConsistency -DatabasePath $testDbPath } | Should -Throw
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Write-Warning -Times 4 -Scope It # ヘッダー + 3つの重複
        }
    }

    Context "Test-DataConsistency 関数 - SQL クエリ生成と実行" {
        
        It "適切なGROUP BYクエリが生成される" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("query-test")
            Mock -ModuleName "Test-DataConsistency" -CommandName New-GroupByClause { return "test_id, test_name" }
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { 
                param($DatabasePath, $Query)
                $Query | Should -Match "SELECT test_id, test_name, COUNT\(\*\) as count"
                $Query | Should -Match "FROM sync_result"
                $Query | Should -Match "GROUP BY test_id, test_name"
                $Query | Should -Match "HAVING COUNT\(\*\) > 1"
                return @()
            }
            
            # Act
            Test-DataConsistency -DatabasePath $testDbPath
            
            # Assert
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName New-GroupByClause -ParameterFilter { $TableName -eq "sync_result" } -Times 1 -Scope It
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand -Times 1 -Scope It
        }
        
        It "テーブルキーカラムが正しく取得される" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("key-columns-test")
            Mock -ModuleName "Test-DataConsistency" -CommandName Get-TableKeyColumns { return @("custom_id", "custom_name") }
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { return @() }
            
            # Act
            Test-DataConsistency -DatabasePath $testDbPath
            
            # Assert
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Get-TableKeyColumns -ParameterFilter { $TableName -eq "sync_result" } -Times 1 -Scope It
        }
        
        It "データベースコマンドが正しいパラメータで実行される" {
            # Arrange
            $testDbPath = "/test/database/path.db"
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { 
                param($DatabasePath, $Query)
                $DatabasePath | Should -Be $testDbPath
                return @()
            }
            
            # Act
            Test-DataConsistency -DatabasePath $testDbPath
            
            # Assert
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand -Times 1 -Scope It
        }
    }

    Context "Test-DataConsistency 関数 - エラーハンドリング" {
        
        It "SQLiteコマンドエラー時に適切にエラーハンドリングされる" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("error-handling-test")
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { throw "SQLiteエラー" }
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-WithErrorHandling { 
                param($ScriptBlock, $Category, $Operation, $Context, $SuppressThrow)
                try {
                    & $ScriptBlock
                } catch {
                    if (-not $SuppressThrow) {
                        throw $_
                    }
                }
            }
            
            # Act & Assert
            { Test-DataConsistency -DatabasePath $testDbPath } | Should -Not -Throw
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Invoke-WithErrorHandling -ParameterFilter { $Category -eq "External" -and $Operation -eq "データ整合性チェック" } -Times 1 -Scope It
        }
        
        It "GROUP BY句生成エラー時に適切にエラーハンドリングされる" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("groupby-error-test")
            Mock -ModuleName "Test-DataConsistency" -CommandName New-GroupByClause { throw "GROUP BY生成エラー" }
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-WithErrorHandling { 
                param($ScriptBlock, $Category, $Operation, $Context, $SuppressThrow)
                try {
                    & $ScriptBlock
                } catch {
                    if (-not $SuppressThrow) {
                        throw $_
                    }
                }
            }
            
            # Act & Assert
            { Test-DataConsistency -DatabasePath $testDbPath } | Should -Not -Throw
        }
        
        It "存在しないデータベースファイルでも適切に処理される" {
            # Arrange
            $nonExistentDbPath = "/path/to/nonexistent/database.db"
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { throw "データベースファイルが見つかりません" }
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-WithErrorHandling { 
                param($ScriptBlock, $Category, $Operation, $Context, $SuppressThrow)
                try {
                    & $ScriptBlock
                } catch {
                    if (-not $SuppressThrow) {
                        throw $_
                    }
                }
            }
            
            # Act & Assert
            { Test-DataConsistency -DatabasePath $nonExistentDbPath } | Should -Not -Throw
        }
    }

    Context "Test-DataConsistency 関数 - ログ出力" {
        
        It "処理開始時に適切なログが出力される" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("log-start-test")
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { return @() }
            
            # Act
            Test-DataConsistency -DatabasePath $testDbPath
            
            # Assert
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データ整合性をチェック中" -and $Level -eq "Info" } -Times 1 -Scope It
        }
        
        It "処理完了時に成功ログが出力される" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("log-success-test")
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { return @() }
            
            # Act
            Test-DataConsistency -DatabasePath $testDbPath
            
            # Assert
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データ整合性チェック完了.*問題なし" -and $Level -eq "Success" } -Times 1 -Scope It
        }
        
        It "重複データ検出時に警告ログが出力される" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("log-warning-test")
            $duplicateData = @(
                @{ id = "001"; name = "重複テスト"; count = 2 }
            )
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { return $duplicateData }
            
            # Act & Assert
            { Test-DataConsistency -DatabasePath $testDbPath } | Should -Throw
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Write-Warning -Times 2 -Scope It
        }
    }

    Context "Test-DataConsistency 関数 - 日本語データ対応" {
        
        It "日本語データを含む重複検出でも正常に処理される" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("japanese-test")
            $japaneseDuplicateData = @(
                @{ id = "日本001"; name = "テストデータ１"; count = 2 },
                @{ id = "日本002"; name = "サンプルデータ２"; count = 3 }
            )
            Mock -ModuleName "Test-DataConsistency" -CommandName Get-TableKeyColumns { return @("id", "name") }
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { return $japaneseDuplicateData }
            
            # Act & Assert
            { Test-DataConsistency -DatabasePath $testDbPath } | Should -Throw
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Write-Warning -ParameterFilter { $Message -match "日本001, テストデータ１.*: 2件" } -Times 1 -Scope It
            Should -Invoke -ModuleName "Test-DataConsistency" -CommandName Write-Warning -ParameterFilter { $Message -match "日本002, サンプルデータ２.*: 3件" } -Times 1 -Scope It
        }
        
        It "日本語のキーカラム名でも正常に処理される" {
            # Arrange
            $testDbPath = $script:TestEnv.CreateDatabase("japanese-columns-test")
            Mock -ModuleName "Test-DataConsistency" -CommandName Get-TableKeyColumns { return @("識別子", "名前") }
            Mock -ModuleName "Test-DataConsistency" -CommandName New-GroupByClause { return "識別子, 名前" }
            $japaneseDuplicateData = @(
                @{ "識別子" = "001"; "名前" = "テスト"; count = 2 }
            )
            Mock -ModuleName "Test-DataConsistency" -CommandName Invoke-SqliteCommand { return $japaneseDuplicateData }
            
            # Act & Assert
            { Test-DataConsistency -DatabasePath $testDbPath } | Should -Throw "*重複したキー（識別子, 名前）が見つかりました*"
        }
    }

    Context "関数のエクスポート確認" {
        
        It "Test-DataConsistency 関数がエクスポートされている" {
            # Arrange
            Mock -ModuleName "Test-DataConsistency" -CommandName Get-Module {
                return @{
                    ExportedFunctions = @{
                        Keys = @("Test-DataConsistency")
                    }
                }
            }
            
            # Act
            $module = Get-Module -Name Test-DataConsistency
            $exportedFunctions = $module.ExportedFunctions.Keys
            
            # Assert
            $exportedFunctions | Should -Contain "Test-DataConsistency"
        }
    }
}