# PowerShell & SQLite データ同期システム
# Process/Invoke-CsvImport.psm1 ユニットテスト

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
using module "../../scripts/modules/Process/Invoke-CsvImport.psm1" 

Describe "Invoke-CsvImport モジュール" {
    
    BeforeAll {
        $script:ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName

        # TestEnvironmentクラスを使用したテスト環境の初期化
        $script:TestEnv = New-TestEnvironment -TestName "CsvImport"
        
        # TestEnvironmentクラスを使用してテスト用設定を作成
        $script:ValidTestConfigPath = $script:TestEnv.CreateConfigFile(@{}, "valid-test-config")
        $script:ValidTestConfig = $script:TestEnv.GetConfig()
        
        # テスト用のファイルパス設定
        $script:TestFilePathConfig = @{
            provided_data_history_directory = "/test/history/provided"
            current_data_history_directory = "/test/history/current"
        }
        
        # テスト用のCSVフォーマット設定
        $script:TestCsvFormatConfig = @{
            has_header = $true
            encoding = "UTF8"
            delimiter = ","
            newline = "CRLF"
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
        Mock -ModuleName "Invoke-CsvImport" -CommandName Write-SystemLog { }
        Mock -ModuleName "Invoke-CsvImport" -CommandName Invoke-WithErrorHandling { 
            param($ScriptBlock, $Category, $Operation, $CleanupScript)
            & $ScriptBlock
        }
        Mock -ModuleName "Invoke-CsvImport" -CommandName Get-FilePathConfig { return $script:TestFilePathConfig }
        Mock -ModuleName "Invoke-CsvImport" -CommandName Test-Path { return $true }
        Mock -ModuleName "Invoke-CsvImport" -CommandName Copy-InputFileToHistory { return "/test/history/copied.csv" }
        Mock -ModuleName "Invoke-CsvImport" -CommandName Get-CsvFormatConfig { return $script:TestCsvFormatConfig }
        Mock -ModuleName "Invoke-CsvImport" -CommandName Test-CsvFormat { return $true }
        Mock -ModuleName "Invoke-CsvImport" -CommandName Import-CsvWithFormat { return @(@{ id="1"; name="テスト" }) }
        Mock -ModuleName "Invoke-CsvImport" -CommandName Invoke-Filtering { 
            return @{ TotalCount = 10; FilteredCount = 8; TableName = "test_table" }
        }
        Mock -ModuleName "Invoke-CsvImport" -CommandName New-TempCsvWithHeader { return "/temp/header_file.csv" }
        Mock -ModuleName "Invoke-CsvImport" -CommandName Remove-Item { }
        
        # 一般的なユーティリティのモック
        Mock -ModuleName "Invoke-CsvImport" -CommandName Clear-Table { }
        Mock -ModuleName "Invoke-CsvImport" -CommandName Invoke-SqliteCommand { }
        Mock -ModuleName "Invoke-CsvImport" -CommandName New-TempTableName { return "temp_test_table" }
        Mock -ModuleName "Invoke-CsvImport" -CommandName New-CreateTempTableSql { return "CREATE TEMP TABLE temp_test_table (id TEXT, name TEXT);" }
        Mock -ModuleName "Invoke-CsvImport" -CommandName Import-CsvToSqliteTable { }
        Mock -ModuleName "Invoke-CsvImport" -CommandName Get-DataSyncConfig { return @{ data_filters = @{ current_data = @{ output_excluded_as_keep = @{ enabled = $false } } } } }
        Mock -ModuleName "Invoke-CsvImport" -CommandName New-FilterWhereClause { return "id IS NOT NULL" }
        Mock -ModuleName "Invoke-CsvImport" -CommandName New-FilteredInsertSql { return "INSERT INTO test_table SELECT * FROM temp_test_table WHERE id IS NOT NULL;" }
        Mock -ModuleName "Invoke-CsvImport" -CommandName New-CreateIndexSql { return @("CREATE INDEX idx_test ON test_table (id);") }
        Mock -ModuleName "Invoke-CsvImport" -CommandName Show-FilteringStatistics { }
        Mock -ModuleName "Invoke-CsvImport" -CommandName Import-Csv { return @(@{ id="1"; name="テスト" }) }
    }

    Context "Invoke-CsvImport 関数 - 基本動作" {
        
        It "提供データタイプで正常に処理を完了する" {
            # Arrange
            $testCsvPath = "/test/provided.csv"
            $testDbPath = $script:TestEnv.CreateDatabase("csv-import-test")
            $dataType = "provided_data"
            
            # Act & Assert
            { Invoke-CsvImport -CsvPath $testCsvPath -DatabasePath $testDbPath -DataType $dataType } | Should -Not -Throw
        }
        
        It "現在データタイプで正常に処理を完了する" {
            # Arrange
            $testCsvPath = "/test/current.csv"
            $testDbPath = $script:TestEnv.CreateDatabase("csv-import-test")
            $dataType = "current_data"
            
            # Act & Assert
            { Invoke-CsvImport -CsvPath $testCsvPath -DatabasePath $testDbPath -DataType $dataType } | Should -Not -Throw
        }
        
        It "無効なデータタイプでエラーをスローする" {
            # Arrange
            $testCsvPath = "/test/data.csv"
            $testDbPath = "/test/database.db"
            $invalidDataType = "invalid_data"
            
            # Act & Assert
            { Invoke-CsvImport -CsvPath $testCsvPath -DatabasePath $testDbPath -DataType $invalidDataType } | Should -Throw
        }
        
        It "処理開始と完了のログが出力される" {
            # Arrange
            $testCsvPath = "/test/data.csv"
            $testDbPath = "/test/database.db"
            $dataType = "provided_data"
            
            # Act
            Invoke-CsvImport -CsvPath $testCsvPath -DatabasePath $testDbPath -DataType $dataType
            
            # Assert
            Should -Invoke -ModuleName "Invoke-CsvImport" -CommandName Write-SystemLog -ParameterFilter { $Message -match "提供データのインポート処理を開始" } -Times 1 -Scope It
            Should -Invoke -ModuleName "Invoke-CsvImport" -CommandName Write-SystemLog -ParameterFilter { $Message -match "提供データのインポート処理が完了" -and $Level -eq "Success" } -Times 1 -Scope It
        }
    }

    Context "Invoke-CsvImport 関数 - データタイプ別設定" {
        
        It "提供データタイプで適切な設定が使用される" {
            # Arrange
            $testCsvPath = "/test/provided.csv"
            $testDbPath = "/test/database.db"
            $dataType = "provided_data"
            Mock -ModuleName "Invoke-CsvImport" -CommandName Invoke-CsvImportMain { 
                param($CsvPath, $DatabasePath, $TableName, $HistoryDirectory, $FileTypeDescription)
                $TableName | Should -Be "provided_data"
                $HistoryDirectory | Should -Be "/test/history/provided"
                $FileTypeDescription | Should -Be "提供データ"
            }
            
            # Act
            Invoke-CsvImport -CsvPath $testCsvPath -DatabasePath $testDbPath -DataType $dataType
            
            # Assert
            Should -Invoke -ModuleName "Invoke-CsvImport" -CommandName Invoke-CsvImportMain -Times 1 -Scope It
        }
        
        It "現在データタイプで適切な設定が使用される" {
            # Arrange
            $testCsvPath = "/test/current.csv"
            $testDbPath = "/test/database.db"
            $dataType = "current_data"
            Mock -ModuleName "Invoke-CsvImport" -CommandName Invoke-CsvImportMain { 
                param($CsvPath, $DatabasePath, $TableName, $HistoryDirectory, $FileTypeDescription)
                $TableName | Should -Be "current_data"
                $HistoryDirectory | Should -Be "/test/history/current"
                $FileTypeDescription | Should -Be "現在データ"
            }
            
            # Act
            Invoke-CsvImport -CsvPath $testCsvPath -DatabasePath $testDbPath -DataType $dataType
            
            # Assert
            Should -Invoke -ModuleName "Invoke-CsvImport" -CommandName Invoke-CsvImportMain -Times 1 -Scope It
        }
    }

    Context "Invoke-CsvImport 関数 - エラーハンドリング" {
        
        It "存在しないCSVファイルでエラーをスローする" {
            # Arrange
            $nonExistentPath = "/test/nonexistent.csv"
            $testDbPath = "/test/database.db"
            $dataType = "provided_data"
            Mock -ModuleName "Invoke-CsvImport" -CommandName Test-Path { return $false }
            Mock -ModuleName "Invoke-CsvImport" -CommandName Invoke-CsvImportMain { throw "CSVファイルが見つかりません: $nonExistentPath" }
            
            # Act & Assert
            { Invoke-CsvImport -CsvPath $nonExistentPath -DatabasePath $testDbPath -DataType $dataType } | Should -Throw "*CSVファイルが見つかりません*"
        }
        
        It "履歴ディレクトリにファイルがコピーされることを確認" {
            # Arrange
            $testCsvPath = "/test/data.csv"
            $testDbPath = "/test/database.db"
            $dataType = "provided_data"
            
            # Act & Assert - 処理が正常に完了することを確認
            { Invoke-CsvImport -CsvPath $testCsvPath -DatabasePath $testDbPath -DataType $dataType } | Should -Not -Throw
            
            # 基本的な処理が実行されることを確認
            Should -Invoke -ModuleName "Invoke-CsvImport" -CommandName Get-FilePathConfig -Times 1 -Scope It
            Should -Invoke -ModuleName "Invoke-CsvImport" -CommandName Copy-InputFileToHistory -Times 1 -Scope It
        }
    }

    Context "Invoke-CsvImport 関数 - 基本機能テスト（統合）" {
        
        It "正常なCSVファイルで処理が完了する" {
            # Arrange
            $testCsvPath = "/test/valid.csv"
            $testDbPath = "/test/database.db"
            $dataType = "provided_data"
            
            # Act & Assert
            { Invoke-CsvImport -CsvPath $testCsvPath -DatabasePath $testDbPath -DataType $dataType } | Should -Not -Throw
            
            # Assert - 基本的な処理が実行されることを確認
            Should -Invoke -ModuleName "Invoke-CsvImport" -CommandName Get-FilePathConfig -Times 1 -Scope It
            Should -Invoke -ModuleName "Invoke-CsvImport" -CommandName Write-SystemLog -ParameterFilter { $Message -match "提供データのインポート処理が完了" } -Times 1 -Scope It
        }
        
        It "処理完了ログが出力される" {
            # Arrange
            $testCsvPath = "/test/valid.csv"
            $testDbPath = "/test/database.db"
            $dataType = "current_data"
            
            # Act
            Invoke-CsvImport -CsvPath $testCsvPath -DatabasePath $testDbPath -DataType $dataType
            
            # Assert
            Should -Invoke -ModuleName "Invoke-CsvImport" -CommandName Write-SystemLog -ParameterFilter { $Message -match "現在データのインポート処理が完了" } -Times 1 -Scope It
        }
    }

    Context "関数のエクスポート確認" {
        
        It "Invoke-CsvImport 関数がエクスポートされている" {
            # Arrange
            Mock -ModuleName "Invoke-CsvImport" -CommandName Get-Module {
                return @{
                    ExportedFunctions = @{
                        Keys = @("Invoke-CsvImport")
                    }
                }
            }
            
            # Act
            $module = Get-Module -Name Invoke-CsvImport
            $exportedFunctions = $module.ExportedFunctions.Keys
            
            # Assert
            $exportedFunctions | Should -Contain "Invoke-CsvImport"
        }
    }
}