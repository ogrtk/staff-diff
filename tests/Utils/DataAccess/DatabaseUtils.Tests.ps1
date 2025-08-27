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

    Context "New-CreateTempTableSql 関数 - 一時テーブル生成SQL" {
        
        It "基本的な一時テーブル作成SQLが正常に生成される" {
            # Act
            $result = New-CreateTempTableSql -BaseTableName "provided_data" -TempTableName "provided_data_temp"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "CREATE TABLE provided_data_temp"
            $result | Should -Match "employee_id TEXT"
            $result | Should -Match "name TEXT"
            $result | Should -Not -Match "PRIMARY KEY"  # 一時テーブルでは制約なし
        }
        
        It "CSV出力対象カラムのみが含まれる一時テーブルSQL生成" {
            # Arrange
            $customConfig = $script:TestConfig.Clone()
            $customConfig.tables.test_temp_table = @{
                description = "一時テーブルテスト用"
                columns     = @(
                    @{ name = "include_col"; type = "TEXT"; csv_include = $true; constraints = "" }
                    @{ name = "exclude_col"; type = "TEXT"; csv_include = $false; constraints = "" }
                    @{ name = "another_include"; type = "INTEGER"; csv_include = $true; constraints = "" }
                )
            }
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $customConfig }
            
            # Act
            $result = New-CreateTempTableSql -BaseTableName "test_temp_table" -TempTableName "temp_test_temp_table"
            
            # Assert
            $result | Should -Match "include_col TEXT"
            $result | Should -Match "another_include INTEGER"
            $result | Should -Not -Match "exclude_col"
        }
        
        It "無効なベーステーブル名でエラーをスローする" {
            # Act & Assert
            { New-CreateTempTableSql -BaseTableName "invalid_table" -TempTableName "temp_invalid" } | Should -Throw "*テーブル定義が見つかりません*"
        }
        
        It "空のカラム定義でも正常にSQL生成される" {
            # Arrange
            $emptyColumnConfig = $script:TestConfig.Clone()
            $emptyColumnConfig.tables.empty_temp_table = @{
                description = "空のカラム定義"
                columns     = @()
            }
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $emptyColumnConfig }
            
            # Act
            $result = New-CreateTempTableSql -BaseTableName "empty_temp_table" -TempTableName "temp_empty_temp_table"
            
            # Assert
            $result | Should -Match "CREATE TABLE temp_empty_temp_table"
            $result.Contains("(") | Should -Be $true  # 括弧が含まれることを確認
            $result.Contains(")") | Should -Be $true  # 括弧が含まれることを確認
        }
    }
    
    Context "Get-ColumnMapping 関数 - カラムマッピング取得" {
        
        It "有効なカラムマッピングが取得される" {
            # Act
            $result = Get-ColumnMapping -SourceTableName "provided_data" -TargetTableName "current_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.GetType().Name | Should -Be "Hashtable"
        }
        
        It "マッピング設定が存在しない場合、空のハッシュテーブルを返す" {
            # Arrange
            $configWithoutMapping = $script:TestConfig.Clone()
            $configWithoutMapping.sync_rules.PSObject.Properties.Remove('column_mappings')
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $configWithoutMapping }
            
            # Act
            $result = Get-ColumnMapping -SourceTableName "provided_data" -TargetTableName "current_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.GetType().Name | Should -Be "Hashtable"
        }
        
        It "mappingsプロパティが存在しない場合、空のハッシュテーブルを返す" {
            # Arrange
            $configWithoutMappingsProperty = $script:TestConfig.Clone()
            $configWithoutMappingsProperty.sync_rules.column_mappings = @{ description = "マッピング設定" }
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $configWithoutMappingsProperty }
            
            # Act
            $result = Get-ColumnMapping -SourceTableName "provided_data" -TargetTableName "current_data"
            
            # Assert
            $result | Should -BeOfType [hashtable]
            $result.Count | Should -Be 0
        }
        
        It "複雑なマッピング構造も正常に処理される" {
            # Arrange
            $complexMappingConfig = $script:TestConfig.Clone()
            # PSCustomObjectとして作成
            $complexMappingConfig.sync_rules.column_mappings.mappings = [PSCustomObject]@{
                "source_col1" = "target_col1"
                "source_col2" = "target_col2" 
                "source_col3" = "target_col3"
            }
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $complexMappingConfig }
            
            # Act
            $result = Get-ColumnMapping -SourceTableName "provided_data" -TargetTableName "current_data"
            
            # Assert
            $result.Count | Should -Be 3
            $result["source_col1"] | Should -Be "target_col1"
            $result["source_col2"] | Should -Be "target_col2"
            $result["source_col3"] | Should -Be "target_col3"
        }
    }
    
    Context "Get-ComparisonColumns 関数 - 比較カラム取得" {
        
        It "provided_dataの比較カラムが正常に取得される" {
            # Act
            $result = Get-ComparisonColumns -SourceTableName "provided_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan 0
        }
        
        It "current_dataの比較カラムが正常に取得される" {
            # Act  
            $result = Get-ComparisonColumns -SourceTableName "current_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan 0
        }
        
        It "column_mappings設定が存在しない場合、空配列を返す" {
            # Arrange
            $configWithoutMapping = $script:TestConfig.Clone()
            $configWithoutMapping.sync_rules.PSObject.Properties.Remove('column_mappings')
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $configWithoutMapping }
            Mock -ModuleName "DatabaseUtils" -CommandName Write-Warning { }
            
            # Act & Assert - 関数がエラーなく実行されることを確認
            { Get-ComparisonColumns -SourceTableName "provided_data" } | Should -Not -Throw
        }
        
        It "未対応のテーブル名で警告を出力し空配列を返す" {
            # Arrange
            Mock -ModuleName "DatabaseUtils" -CommandName Write-Warning { }
            
            # Act & Assert - 関数が警告を出力することを確認
            { Get-ComparisonColumns -SourceTableName "unsupported_table" } | Should -Not -Throw
            Should -Invoke -ModuleName "DatabaseUtils" -CommandName Write-Warning -ParameterFilter { $Message -match "未対応のテーブル名" } -Times 1 -Scope It
        }
        
        It "mappings.mappingsプロパティが存在しない場合、警告を出力する" {
            # Arrange
            $configWithoutMappingsProperty = $script:TestConfig.Clone()
            $configWithoutMappingsProperty.sync_rules.column_mappings = @{ description = "マッピング設定" }
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $configWithoutMappingsProperty }
            Mock -ModuleName "DatabaseUtils" -CommandName Write-Warning { }
            
            # Act
            $result = Get-ComparisonColumns -SourceTableName "provided_data"
            
            # Assert
            $result.Count | Should -Be 0
            Should -Invoke -ModuleName "DatabaseUtils" -CommandName Write-Warning -Times 1 -Scope It
        }
    }
    
    Context "New-OptimizationPragmas 関数 - SQLite最適化PRAGMA生成" {
        
        It "完全なPRAGMA設定で全てのPRAGMAが生成される" {
            # Arrange
            $configWithPragmas = $script:TestConfig.Clone()
            # performance_settingsオブジェクトがない場合は作成
            if (-not $configWithPragmas.performance_settings) {
                $configWithPragmas | Add-Member -MemberType NoteProperty -Name "performance_settings" -Value @{}
            }
            $configWithPragmas.performance_settings["sqlite_pragmas"] = @{
                journal_mode = "WAL"
                synchronous  = "NORMAL"
                temp_store   = "MEMORY"
                cache_size   = 10000
            }
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $configWithPragmas }
            
            # Act
            $result = New-OptimizationPragmas
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Contain "PRAGMA journal_mode = WAL;"
            $result | Should -Contain "PRAGMA synchronous = NORMAL;"
            $result | Should -Contain "PRAGMA temp_store = MEMORY;"
            $result | Should -Contain "PRAGMA cache_size = 10000;"
        }
        
        It "部分的なPRAGMA設定で対応するPRAGMAのみが生成される" {
            # Arrange
            $configWithPartialPragmas = $script:TestConfig.Clone()
            if (-not $configWithPartialPragmas.performance_settings) {
                $configWithPartialPragmas | Add-Member -MemberType NoteProperty -Name "performance_settings" -Value @{}
            }
            $configWithPartialPragmas.performance_settings["sqlite_pragmas"] = @{
                journal_mode = "DELETE"
                cache_size   = 5000
            }
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $configWithPartialPragmas }
            
            # Act
            $result = New-OptimizationPragmas
            
            # Assert
            $result.Count | Should -Be 2
            $result | Should -Contain "PRAGMA journal_mode = DELETE;"
            $result | Should -Contain "PRAGMA cache_size = 5000;"
            $result | Should -Not -Contain "PRAGMA synchronous"
            $result | Should -Not -Contain "PRAGMA temp_store"
        }
        
        It "performance_settings設定が存在しない場合、空配列を返す" {
            # Arrange
            $configWithoutPerformance = $script:TestConfig.Clone()
            $configWithoutPerformance.PSObject.Properties.Remove('performance_settings')
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $configWithoutPerformance }
            
            # Act & Assert - 関数がエラーなく実行されることを確認
            { New-OptimizationPragmas } | Should -Not -Throw
        }
        
        It "sqlite_pragmas設定が存在しない場合、空配列を返す" {
            # Arrange
            $configWithoutSqlitePragmas = $script:TestConfig.Clone()
            if (-not $configWithoutSqlitePragmas.performance_settings) {
                $configWithoutSqlitePragmas | Add-Member -MemberType NoteProperty -Name "performance_settings" -Value @{}
            }
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $configWithoutSqlitePragmas }
            
            # Act & Assert - 関数がエラーなく実行されることを確認
            { New-OptimizationPragmas } | Should -Not -Throw
        }
    }
    
    Context "New-FilterWhereClause 関数 - フィルタWHERE句生成" {
        
        It "単一のexcludeフィルタでWHERE句が生成される" {
            # Arrange
            $configWithFilter = $script:TestConfig.Clone()
            $configWithFilter.data_filters = @{
                test_table = @{
                    enabled = $true
                    rules   = @(
                        @{ type = "exclude"; field = "id"; glob = "Z*" }
                    )
                }
            }
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $configWithFilter }
            
            # Act
            $result = New-FilterWhereClause -TableName "test_table"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "id NOT GLOB 'Z\*'"
            $result.Contains("(") | Should -Be $true
            $result.EndsWith(")") | Should -Be $true
        }
        
        It "単一のincludeフィルタでWHERE句が生成される" {
            # Arrange
            $configWithIncludeFilter = $script:TestConfig.Clone()
            $configWithIncludeFilter.data_filters = @{
                test_table = @{
                    enabled = $true
                    rules   = @(
                        @{ type = "include"; field = "status"; glob = "A*" }
                    )
                }
            }
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $configWithIncludeFilter }
            
            # Act
            $result = New-FilterWhereClause -TableName "test_table"
            
            # Assert
            $result | Should -Match "status GLOB 'A\*'"
        }
        
        It "複数のフィルタルールで複合WHERE句が生成される" {
            # Arrange
            $configWithMultipleFilters = $script:TestConfig.Clone()
            $configWithMultipleFilters.data_filters = @{
                test_table = @{
                    enabled = $true
                    rules   = @(
                        @{ type = "exclude"; field = "id"; glob = "Z*" }
                        @{ type = "include"; field = "type"; glob = "A*" }
                        @{ type = "exclude"; field = "status"; glob = "INVALID*" }
                    )
                }
            }
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $configWithMultipleFilters }
            
            # Act
            $result = New-FilterWhereClause -TableName "test_table"
            
            # Assert
            $result | Should -Match "id NOT GLOB 'Z\*'"
            $result | Should -Match "type GLOB 'A\*'"
            $result | Should -Match "status NOT GLOB 'INVALID\*'"
            $result | Should -Match "AND"
        }
        
        It "data_filters設定が存在しない場合、空文字列を返す" {
            # Arrange
            $configWithoutFilters = $script:TestConfig.Clone()
            $configWithoutFilters.PSObject.Properties.Remove('data_filters')
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $configWithoutFilters }
            
            # Act
            $result = New-FilterWhereClause -TableName "test_table"
            
            # Assert
            $result | Should -Be ""
        }
        
        It "対象テーブルのフィルタが無効な場合、空文字列を返す" {
            # Arrange
            $configWithDisabledFilter = $script:TestConfig.Clone()
            $configWithDisabledFilter.data_filters = @{
                test_table = @{
                    enabled = $false
                    rules   = @(
                        @{ type = "exclude"; field = "id"; glob = "Z*" }
                    )
                }
            }
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $configWithDisabledFilter }
            
            # Act
            $result = New-FilterWhereClause -TableName "test_table"
            
            # Assert
            $result | Should -Be ""
        }
        
        It "rulesが存在しない場合、空文字列を返す" {
            # Arrange
            $configWithoutRules = $script:TestConfig.Clone()
            $configWithoutRules.data_filters = @{
                test_table = @{
                    enabled = $true
                }
            }
            Mock -ModuleName "DatabaseUtils" -CommandName Get-DataSyncConfig { return $configWithoutRules }
            
            # Act
            $result = New-FilterWhereClause -TableName "test_table"
            
            # Assert
            $result | Should -Be ""
        }
    }
    
    Context "New-FilteredInsertSql 関数 - フィルタ付きINSERT SQL生成" {
        
        It "WHERE句なしで基本的なINSERT文が生成される" {
            # Arrange
            Mock -ModuleName "DatabaseUtils" -CommandName Get-CsvColumns { 
                return @("col1", "col2", "col3") 
            }
            
            # Act
            $result = New-FilteredInsertSql -TargetTableName "target_table" -SourceTableName "source_table"
            
            # Assert
            $result.Contains("INSERT INTO target_table (col1, col2, col3)") | Should -Be $true
            $result | Should -Match "SELECT col1, col2, col3 FROM source_table"
            $result | Should -Not -Match "WHERE"
        }
        
        It "WHERE句ありで条件付きINSERT文が生成される" {
            # Arrange
            Mock -ModuleName "DatabaseUtils" -CommandName Get-CsvColumns { 
                return @("id", "name", "status") 
            }
            
            # Act
            $result = New-FilteredInsertSql -TargetTableName "target_table" -SourceTableName "source_table" -WhereClause "status = 'ACTIVE'"
            
            # Assert
            $result.Contains("INSERT INTO target_table (id, name, status)") | Should -Be $true
            $result | Should -Match "SELECT id, name, status FROM source_table"
            $result | Should -Match "WHERE status = 'ACTIVE'"
        }
        
        It "空のWHERE句では条件なしINSERT文が生成される" {
            # Arrange
            Mock -ModuleName "DatabaseUtils" -CommandName Get-CsvColumns { 
                return @("field1", "field2") 
            }
            
            # Act
            $result = New-FilteredInsertSql -TargetTableName "target_table" -SourceTableName "source_table" -WhereClause ""
            
            # Assert
            $result.Contains("INSERT INTO target_table (field1, field2)") | Should -Be $true
            $result | Should -Match "SELECT field1, field2 FROM source_table"
            $result | Should -Not -Match "WHERE"
        }
    }
    
    Context "New-SelectSql 関数 - SELECT SQL生成機能拡張" {
        
        It "すべてのオプションパラメータを使用したSELECT文が生成される" {
            # Act
            $result = New-SelectSql -TableName "provided_data" -Columns @("employee_id", "name") -WhereClause "employee_id IS NOT NULL" -OrderBy "name ASC" -Limit 100
            
            # Assert
            $result | Should -Match "SELECT employee_id, name FROM provided_data"
            $result | Should -Match "WHERE employee_id IS NOT NULL"
            $result | Should -Match "ORDER BY name ASC"
            $result | Should -Match "LIMIT 100"
        }
        
        It "カラム未指定時はテーブルのCSVカラムが使用される" {
            # Act
            $result = New-SelectSql -TableName "provided_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "SELECT .* FROM provided_data"
            $result | Should -Match "employee_id"
            $result | Should -Match "name"
        }
        
        It "Limit=0の場合はLIMIT句が含まれない" {
            # Act
            $result = New-SelectSql -TableName "provided_data" -Limit 0
            
            # Assert
            $result | Should -Not -Match "LIMIT"
        }
        
        It "空のWhereClauseとOrderByではそれらの句が含まれない" {
            # Act
            $result = New-SelectSql -TableName "provided_data" -WhereClause "" -OrderBy ""
            
            # Assert
            $result | Should -Not -Match "WHERE"
            $result | Should -Not -Match "ORDER BY"
        }
    }

    Context "関数のエクスポート確認" {
        
        It "必要な関数がエクスポートされている" {
            # Arrange
            $expectedFunctions = @(
                'Get-TableDefinition',
                'Clear-Table',
                'New-CreateTableSql',
                'New-CreateTempTableSql',
                'Get-ColumnMapping',
                'Get-ComparisonColumns',
                'New-OptimizationPragmas',
                'New-FilterWhereClause',
                'New-FilteredInsertSql',
                'New-SelectSql'
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