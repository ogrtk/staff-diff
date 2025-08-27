# PowerShell & SQLite データ同期システム
# Utils/DataAccess/DatabaseUtils.psm1 ユニットテスト

# テストヘルパーを最初にインポート
using module "../../TestHelpers/TestEnvironmentHelpers.psm1"
using module "../../TestHelpers/MockHelpers.psm1"

# 依存関係のモジュールをインポート（モック化準備のため）
using module "../../../scripts/modules/Utils/Foundation/CoreUtils.psm1"
using module "../../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1"
using module "../../../scripts/modules/Utils/Infrastructure/LoggingUtils.psm1"

# テスト対象モジュールを最後にインポート
using module "../../../scripts/modules/Utils/DataAccess/DatabaseUtils.psm1"

Describe "DatabaseUtils モジュール" {
    
    BeforeAll {
        $script:ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.Parent.FullName

        # TestEnvironmentクラスを使用してテスト環境を初期化
        $script:TestEnv = [TestEnvironment]::new("DatabaseUtils")
        
        # テスト用データベースを作成
        $script:TestDbPath = $script:TestEnv.CreateDatabase("test_database_utils")
        
        # テスト用設定ファイルを作成
        $script:TestConfig = $script:TestEnv.GetConfig()
        if (-not $script:TestConfig) {
            $script:ConfigPath = $script:TestEnv.CreateConfigFile(@{}, "test-config")
            $script:TestConfig = $script:TestEnv.GetConfig()
        }
    }
    
    AfterAll {
        # TestEnvironmentオブジェクトのクリーンアップ
        if ($script:TestEnv -and -not $script:TestEnv.IsDisposed) {
            $script:TestEnv.Dispose()
        }
    }
    
    BeforeEach {
        # テスト用設定にテストテーブル定義を追加
        $enhancedTestConfig = $script:TestConfig.Clone()
        
        # empty_tableの定義を追加
        $enhancedTestConfig.tables.empty_table = @{
            description       = "空のテーブル"
            columns           = @()
            table_constraints = @()
        }
        
        # custom_tableの定義を追加
        $enhancedTestConfig.tables.custom_table = @{
            description       = "カスタムテーブル"
            columns           = @(
                @{ name = "custom_id"; type = "INTEGER"; constraints = "PRIMARY KEY"; csv_include = $true; required = $true }
                @{ name = "custom_name"; type = "TEXT"; constraints = "NOT NULL"; csv_include = $true; required = $true }
                @{ name = "custom_data"; type = "BLOB"; constraints = ""; csv_include = $false; required = $false }
            )
            table_constraints = @(
                @{
                    name        = "uk_custom_name"
                    type        = "UNIQUE"
                    columns     = @("custom_name")
                    description = "カスタム名の一意制約"
                }
            )
        }
        
        # 基本的なモック化 - 共通設定
        Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $enhancedTestConfig }
        Mock -ModuleName "DatabaseUtils" -CommandName Write-SystemLog { }
        Mock -ModuleName "DatabaseUtils" -CommandName Invoke-SqliteCommand {
            param($DatabasePath, $Query)
            
            # モック用のシンプルな結果を返す
            if ($Query -match "SELECT name FROM sqlite_master") {
                return @(@{ name = "test_table" })
            }
            elseif ($Query -match "SELECT COUNT\(\*\)") {
                return @(@{ count = 5 })
            }
            elseif ($Query -match "DELETE FROM") {
                return @()
            }
            else {
                return @()
            }
        }
    }

    Context "Get-TableDefinition 関数 - 基本動作" {
        
        It "有効なテーブル名でテーブル定義が取得される" {
            # Act
            $result = Get-TableDefinition -TableName "provided_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.description | Should -Be "提供データテーブル"
            $result.columns | Should -Not -BeNullOrEmpty
            $result.columns.Count | Should -BeGreaterThan 0
        }
        
        It "一時テーブル名（_tempサフィックス）でベーステーブル定義が取得される" {
            # Act
            $result = Get-TableDefinition -TableName "provided_data_temp"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.description | Should -Be "提供データテーブル"
            $result.columns | Should -Not -BeNullOrEmpty
        }
        
        It "無効なテーブル名で例外がスローされる" {
            # Act & Assert
            { Get-TableDefinition -TableName "invalid_table" } | Should -Throw "*テーブル定義が見つかりません*"
        }
        
        It "複数のテーブル定義が設定から正常に取得される" {
            # Act
            $providedData = Get-TableDefinition -TableName "provided_data"
            $currentData = Get-TableDefinition -TableName "current_data"
            $syncResult = Get-TableDefinition -TableName "sync_result"
            
            # Assert
            $providedData.description | Should -Be "提供データテーブル"
            $currentData.description | Should -Be "現在データテーブル"
            $syncResult.description | Should -Be "同期結果テーブル"
        }
    }

    # Context "Get-CsvColumns 関数 - CSVカラム取得" {
        
    #     It "CSV出力対象カラムが正常に取得される" {
    #         # Act
    #         $result = Get-CsvColumns -TableName "provided_data"
            
    #         # Assert
    #         $result | Should -Not -BeNullOrEmpty
    #         $result | Should -Contain "employee_id"
    #         $result | Should -Contain "name"
    #         $result | Should -Not -Contain "id"  # csv_include=false のカラムは除外される
    #     }
        
    #     It "sync_resultテーブルのCSVカラムが正常に取得される" {
    #         # Act
    #         $result = Get-CsvColumns -TableName "sync_result"
            
    #         # Assert
    #         $result | Should -Not -BeNullOrEmpty
    #         $result | Should -Contain "syokuin_no"
    #         $result | Should -Contain "sync_action"
    #         $result | Should -Not -Contain "department"  # csv_include=false のカラムは除外される
    #     }
        
    #     It "一時テーブルでもCSVカラムが正常に取得される" {
    #         # Note: current_data_tempは一時テーブルなので、current_dataの定義を使用する
    #         # Act
    #         $result = Get-CsvColumns -TableName "current_data_temp"
            
    #         # Assert
    #         $result | Should -Not -BeNullOrEmpty
    #         $result.Count | Should -BeGreaterThan 0
    #         # current_dataテーブルの基本的なカラムが含まれていることを確認
    #         $result | Should -Contain "user_id"
    #         $result | Should -Contain "name"
    #     }
    # }


    Context "Clear-Table 関数 - テーブルクリア" {
        
        It "テーブルが存在する場合、正常にクリアされる" {
            # Arrange
            Mock -ModuleName "DatabaseUtils" -CommandName Invoke-SqliteCommand {
                param($DatabasePath, $Query)
                
                if ($Query -match "SELECT name FROM sqlite_master") {
                    return @(@{ name = "test_table" })
                }
                elseif ($Query -match "SELECT COUNT\(\*\)") {
                    return @(@{ count = 10 })
                }
                elseif ($Query -match "DELETE FROM") {
                    return @()
                }
                return @()
            }
            
            # Act
            Clear-Table -DatabasePath $script:TestDbPath -TableName "test_table" -ShowStatistics $true
            
            # Assert
            Should -Invoke -ModuleName "DatabaseUtils" -CommandName Invoke-SqliteCommand -Times 3 -Scope It
            Should -Invoke -ModuleName "DatabaseUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "テーブル 'test_table' をクリア中" } -Scope It
            Should -Invoke -ModuleName "DatabaseUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "クリアが完了しました" } -Scope It
        }
        
        It "テーブルが存在しない場合、スキップメッセージが出力される" {
            # Arrange
            Mock -ModuleName "DatabaseUtils" -CommandName Invoke-SqliteCommand {
                param($DatabasePath, $Query)
                
                if ($Query -match "SELECT name FROM sqlite_master") {
                    return @()  # テーブルが存在しない
                }
                return @()
            }
            
            # Act
            Clear-Table -DatabasePath $script:TestDbPath -TableName "non_existent_table"
            
            # Assert
            Should -Invoke -ModuleName "DatabaseUtils" -CommandName Invoke-SqliteCommand -Times 1 -Scope It  # 存在確認のみ
            Should -Invoke -ModuleName "DatabaseUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "存在しないため、スキップします" } -Scope It
        }
        
        It "ShowStatistics=falseの場合、カウント処理がスキップされる" {
            # Arrange
            Mock -ModuleName "DatabaseUtils" -CommandName Invoke-SqliteCommand {
                param($DatabasePath, $Query)
                
                if ($Query -match "SELECT name FROM sqlite_master") {
                    return @(@{ name = "test_table" })
                }
                elseif ($Query -match "DELETE FROM") {
                    return @()
                }
                return @()
            }
            
            # Act
            Clear-Table -DatabasePath $script:TestDbPath -TableName "test_table" -ShowStatistics $false
            
            # Assert
            Should -Invoke -ModuleName "DatabaseUtils" -CommandName Invoke-SqliteCommand -Times 2 -Scope It  # 存在確認とDELETEのみ
            Should -Invoke -ModuleName "DatabaseUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -notmatch "既存件数" } -Scope It
        }
    }

    Context "New-CreateTableSql 関数 - テーブル作成SQL生成" {
        
        It "基本的なテーブル作成SQLが正常に生成される" {
            # Act
            $result = New-CreateTableSql -TableName "provided_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "CREATE TABLE"
            $result | Should -Match "provided_data"
            $result | Should -Match "employee_id TEXT NOT NULL"
            $result | Should -Match "name TEXT NOT NULL"
            $result | Should -Match "card_number TEXT"
        }
        
        It "一時テーブルでも正常にSQL生成される" {
            # Act
            $result = New-CreateTableSql -TableName "current_data_temp"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "CREATE TABLE"
            $result | Should -Match "current_data_temp"
            $result | Should -Match "user_id TEXT NOT NULL"
        }
        
        It "PRIMARY KEY制約を含むテーブルでSQL生成される" {
            # Act
            $result = New-CreateTableSql -TableName "provided_data"
            
            # Assert
            $result | Should -Match "PRIMARY KEY AUTOINCREMENT"
        }
        
        It "UNIQUE制約がテーブル制約として正常に生成される" {
            # Act
            $result = New-CreateTableSql -TableName "provided_data"
            
            # Assert
            $result | Should -Match "CONSTRAINT uk_provided_employee_id UNIQUE"
            Should -Invoke -ModuleName "DatabaseUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "UNIQUE制約を追加" } -Scope It
        }
        
        It "複数のテーブル制約が正常に処理される" {
            # Act
            $result = New-CreateTableSql -TableName "sync_result"
            
            # Assert
            $result | Should -Match "CONSTRAINT uk_sync_result_syokuin_no UNIQUE"
        }
        
        It "無効なテーブル名で例外がスローされる" {
            # Act & Assert
            { New-CreateTableSql -TableName "invalid_table" } | Should -Throw "*テーブル定義が見つかりません*"
        }
    }

    Context "インデックス生成機能" {
        
        BeforeEach {
            # インデックス関連の関数が存在する場合のモック
            if (Get-Command "New-CreateIndexSql" -Module "DatabaseUtils" -ErrorAction SilentlyContinue) {
                Mock -ModuleName "DatabaseUtils" -CommandName Invoke-SqliteCommand { return @() }
            }
        }
        
        It "New-CreateIndexSql関数が存在する場合、インデックス作成SQLが生成される" {
            # Act
            $result = New-CreateIndexSql -TableName "provided_data"
                
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "CREATE INDEX"
            $result | Should -Match "idx_provided_employee_id"
        }
    }

    Context "エラーハンドリングとエッジケース" {
        
        It "SQLiteコマンド実行エラーが適切に処理される" {
            # Arrange
            Mock -ModuleName "DatabaseUtils" -CommandName Invoke-SqliteCommand {
                throw "データベース接続エラー"
            }
            
            # Act & Assert
            { Clear-Table -DatabasePath $script:TestDbPath -TableName "test_table" } | Should -Throw "*データベース接続エラー*"
        }
        
        It "設定ファイル読み込みエラーが適切に処理される" {
            # Arrange
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig {
                throw "設定ファイル読み込みエラー"
            }
            
            # Act & Assert
            { Get-TableDefinition -TableName "provided_data" } | Should -Throw "*設定ファイル読み込みエラー*"
        }
        
        It "空のテーブル定義から正常にSQL生成される" {
            # Note: empty_tableはBeforeEachで定義済み
            # Act
            $tableDefinition = Get-TableDefinition -TableName "empty_table"
            $sql = New-CreateTableSql -TableName "empty_table"
            
            # Assert
            $tableDefinition | Should -Not -BeNullOrEmpty
            $tableDefinition.columns.Count | Should -Be 0
            $sql | Should -Match "CREATE TABLE"
            $sql | Should -Match "empty_table"
        }
        
        It "制約なしテーブルでもSQL生成が正常に動作する" {
            # Arrange
            $noConstraintConfig = @{
                tables = @{
                    simple_table = @{
                        description       = "シンプルなテーブル"
                        columns           = @(
                            @{ name = "id"; type = "INTEGER"; constraints = ""; csv_include = $true; required = $false }
                            @{ name = "name"; type = "TEXT"; constraints = ""; csv_include = $true; required = $true }
                        )
                        table_constraints = @()
                    }
                }
            }
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $noConstraintConfig }
            
            # Act
            $result = New-CreateTableSql -TableName "simple_table"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "CREATE TABLE"
            $result | Should -Match "simple_table"
            $result | Should -Match "id INTEGER"
            $result | Should -Match "name TEXT"
        }
    }

    Context "パフォーマンステスト" {
        
        It "大きなテーブル定義でも一定時間内にSQL生成される" {
            # Arrange
            $largeTableConfig = @{
                tables = @{
                    large_table = @{
                        description       = "大きなテーブル"
                        columns           = @()
                        table_constraints = @()
                    }
                }
            }
            
            # 100個のカラムを生成
            for ($i = 1; $i -le 100; $i++) {
                $largeTableConfig.tables.large_table.columns += @{
                    name        = "column_$i"
                    type        = "TEXT"
                    constraints = ""
                    csv_include = ($i % 2 -eq 0)  # 偶数番目のみCSV出力
                    required    = ($i % 10 -eq 0)    # 10の倍数のみ必須
                }
            }
            
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $largeTableConfig }
            
            # Act
            $startTime = Get-Date
            $result = New-CreateTableSql -TableName "large_table"
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            
            # Assert
            $duration | Should -BeLessThan 5  # 5秒以内に完了すべき
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "CREATE TABLE"
        }
    }

    Context "設定ファイル連携テスト" {
        
        It "カスタム設定ファイルからテーブル定義が正常に読み込まれる" {
            # Note: custom_tableはBeforeEachで定義済み
            # Act
            $tableDefinition = Get-TableDefinition -TableName "custom_table"
            $sql = New-CreateTableSql -TableName "custom_table"
            
            # Assert
            $tableDefinition.description | Should -Be "カスタムテーブル"
            $tableDefinition.columns.Count | Should -Be 3
            $tableDefinition.columns[0].name | Should -Be "custom_id"
            $tableDefinition.columns[1].name | Should -Be "custom_name"
            $tableDefinition.columns[2].name | Should -Be "custom_data"
            $sql | Should -Match "custom_table"
            $sql | Should -Match "CONSTRAINT uk_custom_name UNIQUE"
        }
    }

    Context "関数のエクスポート確認" {
        
        It "必要な関数がエクスポートされている" {
            # Arrange
            $expectedFunctions = @(
                'Get-TableDefinition',
                'Clear-Table',
                'New-CreateTableSql'
            )
            
            # Act
            $module = Get-Module -Name DatabaseUtils
            $exportedFunctions = $module.ExportedFunctions.Keys
            
            # Assert
            foreach ($func in $expectedFunctions) {
                $exportedFunctions | Should -Contain $func
            }
        }
    }
}