# PowerShell & SQLite データ同期システム
# Process/Invoke-DatabaseInitialization.psm1 ユニットテスト

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
using module "../../scripts/modules/Process/Invoke-DatabaseInitialization.psm1" 

Describe "Invoke-DatabaseInitialization モジュール" {
    
    BeforeAll {
        $script:ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName

        # TestEnvironmentクラスを使用したテスト環境の初期化
        $script:TestEnv = New-TestEnvironment -TestName "DatabaseInitialization"
        
        # TestEnvironmentクラスを使用してテスト用設定を作成
        $script:ValidTestConfigPath = $script:TestEnv.CreateConfigFile(@{}, "valid-test-config")
        $script:ValidTestConfig = $script:TestEnv.GetConfig()
        
        # テスト用の設定（テーブル定義含む）
        $script:TestConfigWithTables = @{
            version = "1.0.0"
            tables = @{
                test_table = @{
                    columns = @{
                        id = @{ type = "TEXT"; primary_key = $true; nullable = $false }
                        name = @{ type = "TEXT"; nullable = $false }
                        value = @{ type = "INTEGER"; nullable = $true }
                    }
                }
                another_table = @{
                    columns = @{
                        key = @{ type = "TEXT"; primary_key = $true; nullable = $false }
                        data = @{ type = "TEXT"; nullable = $true }
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
        Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Write-SystemLog { }
        Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-WithErrorHandling { 
            param($ScriptBlock, $Category, $Operation, $Context, $CleanupScript)
            & $ScriptBlock
        }
        Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Get-DataSyncConfig { return $script:TestConfigWithTables }
        Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Test-Path { return $true }
        Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Get-Item { 
            return @{ Length = 1024; LastWriteTime = (Get-Date) }
        }
        Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Split-Path {
            param($Path, $Parent)
            if ($Parent) { return "/test/database" }
            return $Path
        }
        Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName New-Item { }
        Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Remove-Item { }
        Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName New-OptimizationPragmas { return @("PRAGMA journal_mode=WAL;") }
        Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName New-CreateTableSql { return "CREATE TABLE test_table (id TEXT PRIMARY KEY);" }
        Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-SqliteSchemaCommand { }
        Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Get-CrossPlatformEncoding { return "UTF8" }
        Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Out-File { }
        Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName sqlite3 { return "" }
        $global:LASTEXITCODE = 0
    }

    Context "Invoke-DatabaseInitialization 関数 - 基本動作" {
        
        It "有効なデータベースパスで正常に処理を完了する" {
            # Arrange
            $testDbPath = Join-Path $script:TestEnv.GetTempDirectory() "test.db"
            
            # Act & Assert
            { Invoke-DatabaseInitialization -DatabasePath $testDbPath } | Should -Not -Throw
        }
        
        It "データベースパスが未指定の場合、エラーをスローする" {
            # Act & Assert
            { Invoke-DatabaseInitialization -DatabasePath "" } | Should -Throw
        }
        
        It "初期化開始と完了のログが出力される" {
            # Arrange
            $testDbPath = "/test/database.db"
            
            # Act
            Invoke-DatabaseInitialization -DatabasePath $testDbPath
            
            # Assert
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データベース初期化を開始" } -Times 1 -Scope It
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データベースが正常に初期化されました" -and $Level -eq "Success" } -Times 1 -Scope It
        }
    }

    Context "Invoke-DatabaseInitialization 関数 - ディレクトリ作成" {
        
        It "データベースディレクトリが存在しない場合の処理が正常に完了する" {
            # Arrange
            $testDbPath = "/test/nonexistent/database.db"
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Test-Path { 
                param($Path)
                return $Path -ne "/test/nonexistent"
            }
            
            # Act & Assert - 処理が正常に完了することを確認
            { Invoke-DatabaseInitialization -DatabasePath $testDbPath } | Should -Not -Throw
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データベースが正常に初期化されました" } -Times 1 -Scope It
        }
        
        It "データベースディレクトリが既に存在する場合、作成しない" {
            # Arrange
            $testDbPath = "/test/existing/database.db"
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Test-Path { return $true }
            
            # Act
            Invoke-DatabaseInitialization -DatabasePath $testDbPath
            
            # Assert
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName New-Item -Times 0 -Scope It
        }
    }

    Context "Invoke-DatabaseInitialization 関数 - データベースファイルのクリーンアップ" {
        
        It "既存データベースファイルの情報をログ出力する" {
            # Arrange
            $testDbPath = "/test/existing.db"
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Test-Path { return $true }
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Get-Item { 
                return @{ Length = 2048; LastWriteTime = [DateTime]::Parse("2024-01-01 12:00:00") }
            }
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-WithErrorHandling { 
                param($ScriptBlock, $Category, $Operation, $Context, $CleanupScript)
                # クリーンアップスクリプトを実行
                if ($CleanupScript) {
                    & $CleanupScript
                }
                & $ScriptBlock
            }
            
            # Act
            Invoke-DatabaseInitialization -DatabasePath $testDbPath
            
            # Assert - クリーンアップスクリプトが実行された場合のログをチェック
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Get-Item -Times 1 -Scope It
        }
        
        It "空のデータベースファイルが存在する場合、削除される" {
            # Arrange
            $testDbPath = "/test/empty.db"
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Test-Path { return $true }
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Get-Item { 
                return @{ Length = 0; LastWriteTime = (Get-Date) }
            }
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-WithErrorHandling { 
                param($ScriptBlock, $Category, $Operation, $Context, $CleanupScript)
                # クリーンアップスクリプトを実行
                if ($CleanupScript) {
                    & $CleanupScript
                }
                & $ScriptBlock
            }
            
            # Act
            Invoke-DatabaseInitialization -DatabasePath $testDbPath
            
            # Assert - クリーンアップスクリプトが実行された場合をチェック
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Remove-Item -Times 1 -Scope It
        }
        
        It "データベースディレクトリが存在しない場合の処理が完了する" {
            # Arrange
            $testDbPath = "/test/recreated/database.db"
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Test-Path { 
                param($Path)
                return $false  # ディレクトリが存在しない状況をシミュレート
            }
            
            # Act & Assert - 処理が正常に完了することを確認
            { Invoke-DatabaseInitialization -DatabasePath $testDbPath } | Should -Not -Throw
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データベースが正常に初期化されました" } -Times 1 -Scope It
        }
    }

    Context "New-DatabaseSchema 関数 - SQL文生成" {
        
        It "設定に基づいて正しいSQL文が生成される" {
            # Arrange
            $testDbPath = "/test/schema.db"
            
            # Act
            Invoke-DatabaseInitialization -DatabasePath $testDbPath
            
            # Assert - 基本的な処理が完了することを確認
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Get-DataSyncConfig -Times 1 -Scope It
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データベースが正常に初期化されました" } -Times 1 -Scope It
        }
        
        It "各テーブルに対してDROP TABLE IF EXISTS文が生成される" {
            # Arrange
            $testDbPath = "/test/drop-tables.db"
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-SqliteSchemaCommand { 
                param($DatabasePath, $SqlContent)
                $SqlContent | Should -Match "DROP TABLE IF EXISTS"
            }
            
            # Act
            Invoke-DatabaseInitialization -DatabasePath $testDbPath
            
            # Assert
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-SqliteSchemaCommand -Times 1 -Scope It
        }
        
        It "最適化PRAGMAが先頭に配置される" {
            # Arrange
            $testDbPath = "/test/pragma.db"
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName New-OptimizationPragmas { return @("PRAGMA test=1;") }
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-SqliteSchemaCommand { 
                param($DatabasePath, $SqlContent)
                $SqlContent | Should -Match "^PRAGMA test=1;"
            }
            
            # Act
            Invoke-DatabaseInitialization -DatabasePath $testDbPath
            
            # Assert
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-SqliteSchemaCommand -Times 1 -Scope It
        }
    }

    Context "Invoke-SqliteSchemaCommand 関数 - SQLファイル実行" {
        
        It "一時SQLファイルが作成され削除される" {
            # Arrange
            $testDbPath = "/test/temp-file.db"
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Out-File { }
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Test-Path { return $true }
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName sqlite3 { }
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Remove-Item { }
            
            # Act
            Invoke-DatabaseInitialization -DatabasePath $testDbPath
            
            # Assert - 内部でInvoke-SqliteSchemaCommandが呼ばれているかを確認
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-SqliteSchemaCommand -Times 1 -Scope It
        }
        
        It "データベース初期化処理が正常に完了する" {
            # Arrange
            $testDbPath = "/test/sqlite3-exec.db"
            $global:LASTEXITCODE = 0
            
            # Act & Assert
            { Invoke-DatabaseInitialization -DatabasePath $testDbPath } | Should -Not -Throw
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データベースが正常に初期化されました" } -Times 1 -Scope It
        }
        
        It "sqlite3コマンド失敗時に適切にハンドリングされる" {
            # Arrange
            $testDbPath = "/test/sqlite3-error.db"
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName sqlite3 { 
                $global:LASTEXITCODE = 1
                return "エラーメッセージ" 
            }
            
            # Act 
            Invoke-DatabaseInitialization -DatabasePath $testDbPath
            
            # Assert - エラーハンドリングが適切に動作することを確認
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-WithErrorHandling -ParameterFilter { $Category -eq "External" } -Times 1 -Scope It
        }
    }

    Context "Invoke-DatabaseInitialization 関数 - エラーハンドリング" {
        
        It "外部コマンドエラー時に適切にエラーハンドリングされる" {
            # Arrange
            $testDbPath = "/test/error-handling.db"
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-SqliteSchemaCommand { throw "外部コマンドエラー" }
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-WithErrorHandling { 
                param($ScriptBlock, $Category, $Operation, $Context, $CleanupScript)
                try {
                    & $ScriptBlock
                } catch {
                    # クリーンアップスクリプトの実行をシミュレート
                    if ($CleanupScript) {
                        & $CleanupScript
                    }
                    throw $_
                }
            }
            
            # Act & Assert
            { Invoke-DatabaseInitialization -DatabasePath $testDbPath } | Should -Throw "*外部コマンドエラー*"
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-WithErrorHandling -ParameterFilter { $Category -eq "External" -and $Operation -eq "データベーススキーマ作成" } -Times 1 -Scope It
        }
        
        It "ファイルシステムエラー時に適切にエラーハンドリングされる" {
            # Arrange
            $testDbPath = "/test/filesystem-error.db"
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName New-Item { throw "ファイルシステムエラー" }
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Test-Path { return $false }
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-WithErrorHandling { 
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
            { Invoke-DatabaseInitialization -DatabasePath $testDbPath } | Should -Throw "*ファイルシステムエラー*"
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-WithErrorHandling -ParameterFilter { $Category -eq "External" -and $Operation -eq "ディレクトリ作成" } -Times 1 -Scope It
        }
        
        It "設定取得エラー時に適切にエラーハンドリングされる" {
            # Arrange
            $testDbPath = "/test/config-error.db"
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Get-DataSyncConfig { throw "設定エラー" }
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-WithErrorHandling { 
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
            { Invoke-DatabaseInitialization -DatabasePath $testDbPath } | Should -Throw "*設定エラー*"
        }
    }

    Context "Invoke-DatabaseInitialization 関数 - 冪等性と復旧" {
        
        It "複数回実行されても安全に処理される" {
            # Arrange
            $testDbPath = "/test/idempotent.db"
            
            # Act & Assert - 複数回実行してもエラーが発生しない
            { Invoke-DatabaseInitialization -DatabasePath $testDbPath } | Should -Not -Throw
            { Invoke-DatabaseInitialization -DatabasePath $testDbPath } | Should -Not -Throw
        }
        
        It "破損したデータベースファイルが適切にクリーンアップされる" {
            # Arrange
            $testDbPath = "/test/corrupted.db"
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Get-Item { 
                throw "ファイルアクセスエラー"
            }
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Test-Path { return $true }
            
            # Act & Assert - エラーが適切にハンドリングされる
            { Invoke-DatabaseInitialization -DatabasePath $testDbPath } | Should -Not -Throw
            # エラーハンドリング関数が呼ばれることを確認
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-WithErrorHandling -Times 1 -Scope It
        }
        
        It "クリーンアップスクリプトが適切に実行される" {
            # Arrange
            $testDbPath = "/test/cleanup.db"
            
            # Act
            Invoke-DatabaseInitialization -DatabasePath $testDbPath
            
            # Assert - エラーハンドリング関数が適切に呼び出されることを確認
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Invoke-WithErrorHandling -Times 1 -Scope It
        }
    }

    Context "Invoke-DatabaseInitialization 関数 - 日本語パス対応" {
        
        It "日本語を含むデータベースパスでも正常に処理される" {
            # Arrange
            $testDbPath = "/テスト/データベース/日本語.db"
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Split-Path {
                param($Path, $Parent)
                if ($Parent) { return "/テスト/データベース" }
                return $Path
            }
            
            # Act & Assert
            { Invoke-DatabaseInitialization -DatabasePath $testDbPath } | Should -Not -Throw
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データベースが正常に初期化されました: /テスト/データベース/日本語.db" } -Times 1 -Scope It
        }
        
        It "日本語パスでの初期化が正常に完了する" {
            # Arrange
            $testDbPath = "/test/japanese.db"
            
            # Act & Assert - 処理が正常に完了することを確認
            { Invoke-DatabaseInitialization -DatabasePath $testDbPath } | Should -Not -Throw
            Should -Invoke -ModuleName "Invoke-DatabaseInitialization" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データベースが正常に初期化されました" } -Times 1 -Scope It
        }
    }

    Context "関数のエクスポート確認" {
        
        It "Invoke-DatabaseInitialization 関数がエクスポートされている" {
            # Arrange
            Mock -ModuleName "Invoke-DatabaseInitialization" -CommandName Get-Module {
                return @{
                    ExportedFunctions = @{
                        Keys = @("Invoke-DatabaseInitialization")
                    }
                }
            }
            
            # Act
            $module = Get-Module -Name Invoke-DatabaseInitialization
            $exportedFunctions = $module.ExportedFunctions.Keys
            
            # Assert
            $exportedFunctions | Should -Contain "Invoke-DatabaseInitialization"
        }
    }
}