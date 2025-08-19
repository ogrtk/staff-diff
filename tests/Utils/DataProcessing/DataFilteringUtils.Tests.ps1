# PowerShell & SQLite データ同期システム
# Utils/DataProcessing/DataFilteringUtils.psm1 ユニットテスト

# テストヘルパーを最初にインポート
using module "../../TestHelpers/TestEnvironmentHelpers.psm1"
using module "../../TestHelpers/MockHelpers.psm1"

# 依存関係のモジュールをインポート（モック化準備のため）
using module "../../../scripts/modules/Utils/Foundation/CoreUtils.psm1"
using module "../../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1"
using module "../../../scripts/modules/Utils/Infrastructure/LoggingUtils.psm1"

# テスト対象モジュールを最後にインポート
using module "../../../scripts/modules/Utils/DataProcessing/DataFilteringUtils.psm1"

Describe "DataFilteringUtils モジュール" {
    
    BeforeAll {
        $script:ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.Parent.FullName

        # テスト環境の初期化
        $script:TestEnv = Initialize-TestEnvironment -CreateTempDatabase
        
        # テスト用データベースパス
        $script:TestDbPath = $script:TestEnv.TestDatabasePath
        
        # テスト用設定データ
        $script:TestConfig = New-TestConfig
    }
    
    AfterAll {
        # テスト環境のクリーンアップ
        Clear-TestEnvironment
    }
    
    BeforeEach {
        # 基本的なモック化 - 共通設定
        Mock -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog { }
        Mock -ModuleName "DataFilteringUtils" -CommandName Get-DataSyncConfig { return $script:TestConfig }
        Mock -ModuleName "DataFilteringUtils" -CommandName Invoke-SqliteCommand { return @() }
        Mock -ModuleName "DataFilteringUtils" -CommandName Get-CsvColumns {
            param($TableName)
            switch ($TableName) {
                "provided_data" { return @("employee_id", "card_number", "name", "department", "position") }
                "current_data" { return @("user_id", "card_number", "name", "department", "position") }
                default { return @("id", "name", "value") }
            }
        }
        Mock -ModuleName "DataFilteringUtils" -CommandName New-FilterWhereClause {
            param($TableName)
            switch ($TableName) {
                "provided_data" { return "employee_id NOT LIKE 'Z%'" }
                "current_data" { return "user_id NOT LIKE 'Z%'" }
                default { return "" }
            }
        }
        Mock -ModuleName "DataFilteringUtils" -CommandName New-CreateTempTableSql {
            param($BaseTableName, $TempTableName)
            return "CREATE TABLE $TempTableName (id INTEGER, name TEXT);"
        }
    }

    Context "New-TempTableName 関数 - 一時テーブル名生成" {
        
        It "基本的なテーブル名で一時テーブル名が生成される" {
            # Act
            $result = New-TempTableName -BaseTableName "provided_data"
            
            # Assert
            $result | Should -Be "provided_data_temp"
        }
        
        It "current_dataテーブルで一時テーブル名が生成される" {
            # Act
            $result = New-TempTableName -BaseTableName "current_data"
            
            # Assert
            $result | Should -Be "current_data_temp"
        }
        
        It "sync_resultテーブルで一時テーブル名が生成される" {
            # Act
            $result = New-TempTableName -BaseTableName "sync_result"
            
            # Assert
            $result | Should -Be "sync_result_temp"
        }
        
        It "カスタムテーブル名で一時テーブル名が生成される" {
            # Act
            $result = New-TempTableName -BaseTableName "custom_table"
            
            # Assert
            $result | Should -Be "custom_table_temp"
        }
        
        It "既に_tempサフィックスがあるテーブル名でも正常に処理される" {
            # Act
            $result = New-TempTableName -BaseTableName "existing_temp"
            
            # Assert
            $result | Should -Be "existing_temp_temp"
        }
        
        It "空文字列のテーブル名でも一時テーブル名が生成される" {
            # Act
            $result = New-TempTableName -BaseTableName ""
            
            # Assert
            $result | Should -Be "_temp"
        }
    }

    Context "Show-FilteringStatistics 関数 - フィルタリング統計表示" {
        
        It "フィルタあり結果で統計が正常に表示される" {
            # Act
            Show-FilteringStatistics -TableName "provided_data" -TotalCount 100 -FilteredCount 80 -WhereClause "employee_id NOT LIKE 'Z%'"
            
            # Assert
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データフィルタ処理結果: provided_data" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "総件数: 100" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "通過件数: 80" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "除外件数: 20" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "通過率: 80.0%" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "20 件のデータが除外されました" -and $Level -eq "Warning" } -Scope It
        }
        
        It "フィルタなし結果で統計が正常に表示される" {
            # Act
            Show-FilteringStatistics -TableName "current_data" -TotalCount 50 -FilteredCount 50 -WhereClause ""
            
            # Assert
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "適用フィルタ: なし（全件通過）" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "処理件数: 50" } -Scope It
        }
        
        It "全件除外の場合で統計が正常に表示される" {
            # Act
            Show-FilteringStatistics -TableName "test_data" -TotalCount 10 -FilteredCount 0 -WhereClause "id > 1000"
            
            # Assert
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "通過件数: 0" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "除外件数: 10" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "通過率: 0.0%" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "10 件のデータが除外されました" -and $Level -eq "Warning" } -Scope It
        }
        
        It "全件通過の場合で除外警告が表示されない" {
            # Act
            Show-FilteringStatistics -TableName "test_data" -TotalCount 25 -FilteredCount 25 -WhereClause "1=1"
            
            # Assert
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "通過件数: 25" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "除外件数: 0" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "通過率: 100.0%" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "データが除外されました" } -Times 0 -Scope It
        }
        
        It "データ件数が0の場合で統計が正常に表示される" {
            # Act
            Show-FilteringStatistics -TableName "empty_data" -TotalCount 0 -FilteredCount 0 -WhereClause "id > 0"
            
            # Assert
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "総件数: 0" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "通過件数: 0" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "通過率: 0%" } -Scope It
        }
        
        It "少数点を含む通過率が正しく計算される" {
            # Act
            Show-FilteringStatistics -TableName "decimal_test" -TotalCount 3 -FilteredCount 1 -WhereClause "id = 1"
            
            # Assert
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "通過率: 33.3%" } -Scope It
        }
    }

    Context "Save-ExcludedDataForKeep 関数 - 除外データ保存" {
        
        It "除外データが正常にKEEP用テーブルに保存される" {
            # Arrange
            Mock -ModuleName "DataFilteringUtils" -CommandName Invoke-SqliteCommand {
                param($DatabasePath, $Query)
                if ($Query -match "SELECT COUNT") {
                    return @(@{ count = 5 })
                }
                return @()
            }
            
            # Act
            Save-ExcludedDataForKeep -DatabasePath $script:TestDbPath -SourceTableName "current_data" -ExcludedTableName "current_data_excluded" -FilterConfigTableName "current_data"
            
            # Assert
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Invoke-SqliteCommand -Times 4 -Scope It  # DROP, CREATE, INSERT, COUNT
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "除外データ用テーブルを作成しました" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "除外データをKEEP用テーブルに保存しました.*5 件" } -Scope It
        }
        
        It "フィルタ条件がない場合、処理がスキップされる" {
            # Arrange
            Mock -ModuleName "DataFilteringUtils" -CommandName New-FilterWhereClause { return "" }
            
            # Act
            Save-ExcludedDataForKeep -DatabasePath $script:TestDbPath -SourceTableName "test_table" -ExcludedTableName "test_excluded" -FilterConfigTableName "test_table"
            
            # Assert
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "フィルタ条件がないため、除外データ保存をスキップします" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Invoke-SqliteCommand -Times 0 -Scope It
        }
        
        It "空白文字のみのフィルタ条件でも処理がスキップされる" {
            # Arrange
            Mock -ModuleName "DataFilteringUtils" -CommandName New-FilterWhereClause { return "   " }
            
            # Act
            Save-ExcludedDataForKeep -DatabasePath $script:TestDbPath -SourceTableName "test_table" -ExcludedTableName "test_excluded" -FilterConfigTableName "test_table"
            
            # Assert
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "フィルタ条件がないため、除外データ保存をスキップします" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Invoke-SqliteCommand -Times 0 -Scope It
        }
        
        It "除外データが0件の場合でも正常に処理される" {
            # Arrange
            Mock -ModuleName "DataFilteringUtils" -CommandName Invoke-SqliteCommand {
                param($DatabasePath, $Query)
                if ($Query -match "SELECT COUNT") {
                    return @(@{ count = 0 })
                }
                return @()
            }
            
            # Act
            Save-ExcludedDataForKeep -DatabasePath $script:TestDbPath -SourceTableName "provided_data" -ExcludedTableName "provided_excluded" -FilterConfigTableName "provided_data"
            
            # Assert
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "除外データをKEEP用テーブルに保存しました.*0 件" } -Scope It
        }
        
        It "複雑なフィルタ条件でも正常に処理される" {
            # Arrange
            Mock -ModuleName "DataFilteringUtils" -CommandName New-FilterWhereClause {
                return "(employee_id NOT LIKE 'Z%' AND department != 'テスト部')"
            }
            Mock -ModuleName "DataFilteringUtils" -CommandName Invoke-SqliteCommand {
                param($DatabasePath, $Query)
                if ($Query -match "SELECT COUNT") {
                    return @(@{ count = 3 })
                }
                if ($Query -match "INSERT INTO.*WHERE NOT") {
                    # 除外条件が正しく反転されていることを確認
                    $Query | Should -Match "NOT \(\(employee_id NOT LIKE 'Z%' AND department != 'テスト部'\)\)"
                }
                return @()
            }
            
            # Act
            Save-ExcludedDataForKeep -DatabasePath $script:TestDbPath -SourceTableName "provided_data" -ExcludedTableName "provided_excluded" -FilterConfigTableName "provided_data"
            
            # Assert
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Invoke-SqliteCommand -Times 4 -Scope It
        }
    }

    Context "エラーハンドリングとエッジケース" {
        
        It "SQLiteコマンド実行エラーが適切に処理される" {
            # Arrange
            Mock -ModuleName "DataFilteringUtils" -CommandName Invoke-SqliteCommand {
                throw "データベース接続エラー"
            }
            
            # Act & Assert
            { Save-ExcludedDataForKeep -DatabasePath $script:TestDbPath -SourceTableName "test_table" -ExcludedTableName "test_excluded" -FilterConfigTableName "test_table" } | Should -Throw "*データベース接続エラー*"
        }
        
        It "Get-CsvColumnsエラーが適切に処理される" {
            # Arrange
            Mock -ModuleName "DataFilteringUtils" -CommandName Get-CsvColumns {
                throw "カラム取得エラー"
            }
            
            # Act & Assert
            { Save-ExcludedDataForKeep -DatabasePath $script:TestDbPath -SourceTableName "test_table" -ExcludedTableName "test_excluded" -FilterConfigTableName "test_table" } | Should -Throw "*カラム取得エラー*"
        }
        
        It "負の数値での統計表示も正常に処理される" {
            # Act
            Show-FilteringStatistics -TableName "negative_test" -TotalCount -1 -FilteredCount -1 -WhereClause "invalid"
            
            # Assert
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "総件数: -1" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "通過件数: -1" } -Scope It
        }
        
        It "FilteredCountがTotalCountより大きい場合も処理される" {
            # Act
            Show-FilteringStatistics -TableName "overflow_test" -TotalCount 10 -FilteredCount 15 -WhereClause "test"
            
            # Assert
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "除外件数: -5" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "通過率: 150.0%" } -Scope It
        }
        
        It "非常に長いテーブル名でも正常に処理される" {
            # Arrange
            $longTableName = "very_long_table_name" * 10
            
            # Act
            $result = New-TempTableName -BaseTableName $longTableName
            
            # Assert
            $result | Should -Be "${longTableName}_temp"
            $result.Length | Should -BeGreaterThan 100
        }
        
        It "特殊文字を含むテーブル名でも正常に処理される" {
            # Arrange
            $specialTableName = "table-with_special!chars@123"
            
            # Act
            $result = New-TempTableName -BaseTableName $specialTableName
            
            # Assert
            $result | Should -Be "${specialTableName}_temp"
        }
    }

    Context "統合シナリオテスト" {
        
        It "provided_dataの除外データ保存シナリオ" {
            # Arrange
            Mock -ModuleName "DataFilteringUtils" -CommandName New-FilterWhereClause {
                param($TableName)
                if ($TableName -eq "provided_data") {
                    return "employee_id NOT LIKE 'Z%'"
                }
                return ""
            }
            Mock -ModuleName "DataFilteringUtils" -CommandName Get-CsvColumns {
                param($TableName)
                if ($TableName -eq "provided_data") {
                    return @("employee_id", "card_number", "name", "department")
                }
                return @()
            }
            Mock -ModuleName "DataFilteringUtils" -CommandName Invoke-SqliteCommand {
                param($DatabasePath, $Query)
                if ($Query -match "SELECT COUNT") {
                    return @(@{ count = 3 })
                }
                return @()
            }
            
            # Act
            $tempTableName = New-TempTableName -BaseTableName "provided_data"
            Save-ExcludedDataForKeep -DatabasePath $script:TestDbPath -SourceTableName "provided_data" -ExcludedTableName $tempTableName -FilterConfigTableName "provided_data"
            Show-FilteringStatistics -TableName "provided_data" -TotalCount 100 -FilteredCount 97 -WhereClause "employee_id NOT LIKE 'Z%'"
            
            # Assert
            $tempTableName | Should -Be "provided_data_temp"
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Invoke-SqliteCommand -Times 4 -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "除外データをKEEP用テーブルに保存しました.*3 件" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "3 件のデータが除外されました" } -Scope It
        }
        
        It "current_dataの除外データ保存シナリオ" {
            # Arrange
            Mock -ModuleName "DataFilteringUtils" -CommandName New-FilterWhereClause {
                param($TableName)
                if ($TableName -eq "current_data") {
                    return "user_id NOT LIKE 'Z%'"
                }
                return ""
            }
            Mock -ModuleName "DataFilteringUtils" -CommandName Get-CsvColumns {
                param($TableName)
                if ($TableName -eq "current_data") {
                    return @("user_id", "card_number", "name", "department")
                }
                return @()
            }
            Mock -ModuleName "DataFilteringUtils" -CommandName Invoke-SqliteCommand {
                param($DatabasePath, $Query)
                if ($Query -match "SELECT COUNT") {
                    return @(@{ count = 1 })
                }
                return @()
            }
            
            # Act
            $tempTableName = New-TempTableName -BaseTableName "current_data"
            Save-ExcludedDataForKeep -DatabasePath $script:TestDbPath -SourceTableName "current_data" -ExcludedTableName "${tempTableName}_excluded" -FilterConfigTableName "current_data"
            Show-FilteringStatistics -TableName "current_data" -TotalCount 50 -FilteredCount 49 -WhereClause "user_id NOT LIKE 'Z%'"
            
            # Assert
            $tempTableName | Should -Be "current_data_temp"
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Invoke-SqliteCommand -Times 4 -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "除外データをKEEP用テーブルに保存しました.*1 件" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "1 件のデータが除外されました" } -Scope It
        }
    }

    Context "パフォーマンステスト" {
        
        It "大量データでの統計表示が一定時間内に完了する" {
            # Arrange
            $largeCount = 100000
            $filteredCount = 99500
            
            # Act
            $startTime = Get-Date
            Show-FilteringStatistics -TableName "large_data" -TotalCount $largeCount -FilteredCount $filteredCount -WhereClause "id > 500"
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            
            # Assert
            $duration | Should -BeLessThan 1  # 1秒以内に完了すべき
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "総件数: 100000" } -Scope It
            Should -Invoke -ModuleName "DataFilteringUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "通過率: 99.5%" } -Scope It
        }
        
        It "複数の一時テーブル名生成が効率的に処理される" {
            # Arrange
            $tableNames = @()
            for ($i = 1; $i -le 1000; $i++) {
                $tableNames += "table_$i"
            }
            
            # Act
            $startTime = Get-Date
            $tempTableNames = foreach ($tableName in $tableNames) {
                New-TempTableName -BaseTableName $tableName
            }
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            
            # Assert
            $duration | Should -BeLessThan 2  # 2秒以内に完了すべき
            $tempTableNames.Count | Should -Be 1000
            $tempTableNames[0] | Should -Be "table_1_temp"
            $tempTableNames[999] | Should -Be "table_1000_temp"
        }
    }

    Context "関数のエクスポート確認" {
        
        It "必要な関数がエクスポートされている" {
            # Arrange
            $expectedFunctions = @(
                'New-TempTableName',
                'Show-FilteringStatistics',
                'Save-ExcludedDataForKeep'
            )
            
            # Act
            $module = Get-Module -Name DataFilteringUtils
            $exportedFunctions = $module.ExportedFunctions.Keys
            
            # Assert
            foreach ($func in $expectedFunctions) {
                $exportedFunctions | Should -Contain $func
            }
        }
    }
}