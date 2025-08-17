#!/usr/bin/env pwsh
# DataAccess Layer (Layer 3) - DatabaseUtils Module Tests

BeforeAll {
    # レイヤードテストヘルパーの読み込み
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/LayeredTestHelpers.psm1") -Force
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/MockHelpers.psm1") -Force
    
    # Layer 3 (DataAccess) テスト環境の初期化
    $script:TestEnv = Initialize-LayeredTestEnvironment -LayerName "DataAccess" -ModuleName "DatabaseUtils"
    
    # テスト用データベースパス
    $script:TestDatabasePath = Join-Path $script:TestEnv.TempDirectory.Path "test.db"
    
    # モック設定の設定
    $script:TestEnv.ConfigurationMock = New-MockConfiguration
}

AfterAll {
    # テスト環境のクリーンアップ
    Cleanup-LayeredTestEnvironment -TestEnvironment $script:TestEnv
}

Describe "DatabaseUtils (データアクセス層) テスト" {
    
    Context "Layer Architecture Validation" {
        It "should be Layer 3 with Foundation and Infrastructure dependencies" {
            $dependencies = Assert-LayeredModuleDependencies -LayerName "DataAccess" -ModuleName "DatabaseUtils"
            $dependencies.Dependencies | Should -Contain "Foundation"
            $dependencies.Dependencies | Should -Contain "Infrastructure"
            $dependencies.InvalidDependencies | Should -BeExactly @()
            $dependencies.CircularDependencies | Should -BeExactly @()
        }
        
        It "should use lower layer functions" {
            # DatabaseUtilsが下位レイヤの関数を使用することを確認
            $tableDef = Get-TableDefinition -TableName "provided_data"
            $tableDef | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Get-TableDefinition Function" {
        It "should return table definition for valid table name" {
            $tableDef = Get-TableDefinition -TableName "provided_data"
            
            $tableDef | Should -Not -BeNullOrEmpty
            $tableDef.columns | Should -Not -BeNullOrEmpty
            $tableDef.columns.employee_id | Should -Not -BeNullOrEmpty
        }
        
        It "should handle temporary table names (_temp suffix)" {
            $tempTableDef = Get-TableDefinition -TableName "provided_data_temp"
            $normalTableDef = Get-TableDefinition -TableName "provided_data"
            
            # 一時テーブルは元のテーブル定義を使用
            $tempTableDef.columns.employee_id | Should -Be $normalTableDef.columns.employee_id
        }
        
        It "should throw error for unknown table name" {
            { Get-TableDefinition -TableName "unknown_table" } | Should -Throw "*テーブル定義が見つかりません*"
        }
        
        It "should validate table column properties" {
            $tableDef = Get-TableDefinition -TableName "provided_data"
            
            # Primary keyの検証
            $tableDef.columns.employee_id.primary_key | Should -Be $true
            $tableDef.columns.employee_id.type | Should -Be "TEXT"
            
            # 必須フィールドの検証
            $tableDef.columns.name.nullable | Should -Be $false
            $tableDef.columns.name.type | Should -Be "TEXT"
        }
    }
    
    Context "Get-CsvColumns Function" {
        It "should return CSV column list for table" {
            $columns = Get-CsvColumns -TableName "provided_data"
            
            $columns | Should -Not -BeNullOrEmpty
            $columns | Should -Contain "employee_id"
            $columns | Should -Contain "name"
            $columns | Should -Contain "department"
        }
        
        It "should return columns in correct order" {
            $columns = Get-CsvColumns -TableName "provided_data"
            
            # employee_idが最初に来ることを確認（主キー）
            $columns[0] | Should -Be "employee_id"
            
            # 必須フィールドが含まれることを確認
            $columns | Should -Contain "name"
        }
        
        It "should handle tables with different column structures" {
            $providedColumns = Get-CsvColumns -TableName "provided_data"
            $currentColumns = Get-CsvColumns -TableName "current_data"
            
            # 両方のテーブルが同じ基本構造を持つことを確認
            $providedColumns | Should -Contain "employee_id"
            $currentColumns | Should -Contain "employee_id"
            
            # カラム数が妥当であることを確認
            $providedColumns.Count | Should -BeGreaterThan 2
            $currentColumns.Count | Should -BeGreaterThan 2
        }
    }
    
    Context "New-CreateTableSQL Function" {
        It "should generate valid CREATE TABLE SQL" {
            $sql = New-CreateTableSQL -TableName "test_table"
            
            $sql | Should -Not -BeNullOrEmpty
            $sql | Should -Match "CREATE TABLE.*test_table"
            $sql | Should -Match "employee_id.*TEXT.*PRIMARY KEY"
            $sql | Should -Match "name.*TEXT.*NOT NULL"
        }
        
        It "should handle IF NOT EXISTS option" {
            $sql = New-CreateTableSQL -TableName "test_table" -IfNotExists
            
            $sql | Should -Match "CREATE TABLE IF NOT EXISTS.*test_table"
        }
        
        It "should include all column definitions with proper constraints" {
            $sql = New-CreateTableSQL -TableName "provided_data"
            
            # 主キー制約
            $sql | Should -Match "employee_id.*PRIMARY KEY"
            
            # NOT NULL制約
            $sql | Should -Match "name.*NOT NULL"
            
            # カラムタイプ
            $sql | Should -Match "TEXT"
            
            # 適切なSQL構文
            $sql | Should -Match "\s*\(\s*"  # Opening parenthesis
            $sql | Should -Match "\s*\)\s*"  # Closing parenthesis
        }
        
        It "should generate different SQL for different tables" {
            $sql1 = New-CreateTableSQL -TableName "provided_data"
            $sql2 = New-CreateTableSQL -TableName "current_data"
            
            $sql1 | Should -Match "provided_data"
            $sql2 | Should -Match "current_data"
            
            # 基本構造は同じであるべき
            $sql1 | Should -Match "employee_id.*PRIMARY KEY"
            $sql2 | Should -Match "employee_id.*PRIMARY KEY"
        }
    }
    
    Context "New-InsertSQL Function" {
        It "should generate INSERT SQL with placeholders" {
            $sql = New-InsertSQL -TableName "test_table"
            
            $sql | Should -Not -BeNullOrEmpty
            $sql | Should -Match "INSERT INTO test_table"
            $sql | Should -Match "VALUES"
            $sql | Should -Match "\?"  # Placeholder
        }
        
        It "should include all table columns" {
            $sql = New-InsertSQL -TableName "provided_data"
            
            $sql | Should -Match "employee_id"
            $sql | Should -Match "name"
            $sql | Should -Match "department"
            
            # プレースホルダーの数がカラム数と一致
            $columns = Get-CsvColumns -TableName "provided_data"
            $placeholderCount = ($sql -split "\?").Count - 1
            $placeholderCount | Should -Be $columns.Count
        }
        
        It "should generate valid SQL syntax" {
            $sql = New-InsertSQL -TableName "provided_data"
            
            $sql | Should -Match "INSERT INTO.*\("
            $sql | Should -Match "\).*VALUES.*\("
            $sql | Should -Match "\)\s*$"
        }
    }
    
    Context "New-UpdateSQL Function" {
        It "should generate UPDATE SQL with WHERE clause" {
            $sql = New-UpdateSQL -TableName "test_table"
            
            $sql | Should -Not -BeNullOrEmpty
            $sql | Should -Match "UPDATE test_table"
            $sql | Should -Match "SET"
            $sql | Should -Match "WHERE"
            $sql | Should -Match "employee_id.*\?"  # Primary key in WHERE clause
        }
        
        It "should set all non-primary key columns" {
            $sql = New-UpdateSQL -TableName "provided_data"
            
            # 非主キーカラムがSET句に含まれる
            $sql | Should -Match "name.*=.*\?"
            $sql | Should -Match "department.*=.*\?"
            
            # 主キーはWHERE句のみ
            $whereClause = ($sql -split "WHERE")[1]
            $whereClause | Should -Match "employee_id.*=.*\?"
        }
        
        It "should handle tables with multiple primary keys" {
            # 複合主キーの場合のテスト（設定で複合キーが定義されている場合）
            $sql = New-UpdateSQL -TableName "provided_data"
            
            # 少なくとも1つの主キーがWHERE句にある
            $sql | Should -Match "WHERE.*employee_id.*=.*\?"
        }
    }
    
    Context "New-SelectSQL Function" {
        It "should generate SELECT SQL for all columns" {
            $sql = New-SelectSQL -TableName "test_table"
            
            $sql | Should -Not -BeNullOrEmpty
            $sql | Should -Match "SELECT.*FROM test_table"
        }
        
        It "should handle specific column selection" {
            $columns = @("employee_id", "name")
            $sql = New-SelectSQL -TableName "provided_data" -Columns $columns
            
            $sql | Should -Match "SELECT.*employee_id.*name.*FROM"
            $sql | Should -Not -Match "department"  # 指定されていないカラム
        }
        
        It "should add WHERE clause when provided" {
            $whereClause = "employee_id = ?"
            $sql = New-SelectSQL -TableName "provided_data" -WhereClause $whereClause
            
            $sql | Should -Match "WHERE.*employee_id.*=.*\?"
        }
        
        It "should add ORDER BY clause when provided" {
            $orderBy = "name ASC"
            $sql = New-SelectSQL -TableName "provided_data" -OrderBy $orderBy
            
            $sql | Should -Match "ORDER BY.*name.*ASC"
        }
        
        It "should combine WHERE and ORDER BY clauses" {
            $sql = New-SelectSQL -TableName "provided_data" -WhereClause "department = ?" -OrderBy "name ASC"
            
            $sql | Should -Match "WHERE.*department.*=.*\?"
            $sql | Should -Match "ORDER BY.*name.*ASC"
            
            # WHEREがORDER BYより前に来る
            $whereIndex = $sql.IndexOf("WHERE")
            $orderIndex = $sql.IndexOf("ORDER BY")
            $whereIndex | Should -BeLessThan $orderIndex
        }
    }
    
    Context "New-DeleteSQL Function" {
        It "should generate DELETE SQL with WHERE clause" {
            $sql = New-DeleteSQL -TableName "test_table"
            
            $sql | Should -Not -BeNullOrEmpty
            $sql | Should -Match "DELETE FROM test_table"
            $sql | Should -Match "WHERE"
            $sql | Should -Match "employee_id.*=.*\?"
        }
        
        It "should use primary key in WHERE clause" {
            $sql = New-DeleteSQL -TableName "provided_data"
            
            $sql | Should -Match "WHERE.*employee_id.*=.*\?"
        }
        
        It "should handle custom WHERE clause" {
            $customWhere = "department = ? AND position = ?"
            $sql = New-DeleteSQL -TableName "provided_data" -WhereClause $customWhere
            
            $sql | Should -Match "WHERE.*department.*=.*\?.*AND.*position.*=.*\?"
        }
    }
    
    Context "Database Schema Validation" {
        It "should validate column types against SQL standards" {
            $tableDef = Get-TableDefinition -TableName "provided_data"
            
            $validTypes = @("TEXT", "INTEGER", "REAL", "BLOB", "NUMERIC")
            foreach ($column in $tableDef.columns.Values) {
                $column.type | Should -BeIn $validTypes
            }
        }
        
        It "should ensure primary key constraints are defined" {
            $tableDef = Get-TableDefinition -TableName "provided_data"
            
            $primaryKeys = $tableDef.columns.Values | Where-Object { $_.primary_key -eq $true }
            $primaryKeys | Should -Not -BeNullOrEmpty
            $primaryKeys.Count | Should -BeGreaterOrEqual 1
        }
        
        It "should validate nullable constraints" {
            $tableDef = Get-TableDefinition -TableName "provided_data"
            
            # 主キーは非NULL
            $tableDef.columns.employee_id.nullable | Should -Not -Be $true
            
            # name フィールドは必須
            $tableDef.columns.name.nullable | Should -Be $false
        }
    }
    
    Context "SQL Generation Integration" {
        It "should generate complete CRUD operations for a table" {
            $tableName = "provided_data"
            
            $createSQL = New-CreateTableSQL -TableName $tableName
            $insertSQL = New-InsertSQL -TableName $tableName
            $selectSQL = New-SelectSQL -TableName $tableName
            $updateSQL = New-UpdateSQL -TableName $tableName
            $deleteSQL = New-DeleteSQL -TableName $tableName
            
            # すべてのSQL文が生成される
            $createSQL | Should -Not -BeNullOrEmpty
            $insertSQL | Should -Not -BeNullOrEmpty
            $selectSQL | Should -Not -BeNullOrEmpty
            $updateSQL | Should -Not -BeNullOrEmpty
            $deleteSQL | Should -Not -BeNullOrEmpty
            
            # すべてがテーブル名を含む
            @($createSQL, $insertSQL, $selectSQL, $updateSQL, $deleteSQL) | ForEach-Object {
                $_ | Should -Match $tableName
            }
        }
        
        It "should maintain consistency across different SQL operations" {
            $tableName = "provided_data"
            $columns = Get-CsvColumns -TableName $tableName
            
            $insertSQL = New-InsertSQL -TableName $tableName
            $selectSQL = New-SelectSQL -TableName $tableName
            
            # INSERT文とSELECT文で同じカラムが使われる
            foreach ($column in $columns) {
                $insertSQL | Should -Match $column
                $selectSQL | Should -Match $column
            }
        }
    }
    
    Context "Error Handling and Edge Cases" {
        It "should handle empty table definitions gracefully" {
            # 設定を一時的に空のテーブル定義に変更
            $originalConfig = $script:TestEnv.ConfigurationMock
            $script:TestEnv.ConfigurationMock = @{
                tables = @{
                    empty_table = @{
                        columns = @{}
                    }
                }
            }
            
            { Get-TableDefinition -TableName "empty_table" } | Should -Not -Throw
            
            # 元の設定を復元
            $script:TestEnv.ConfigurationMock = $originalConfig
        }
        
        It "should validate SQL injection prevention" {
            $maliciousTableName = "test'; DROP TABLE users; --"
            
            # テーブル名の検証は設定ベースなので、不正なテーブル名は拒否される
            { Get-TableDefinition -TableName $maliciousTableName } | Should -Throw
        }
        
        It "should handle very long table and column names" {
            $longName = "a" * 100  # 100文字のテーブル名
            
            { Get-TableDefinition -TableName $longName } | Should -Throw "*テーブル定義が見つかりません*"
        }
    }
    
    Context "Performance and Optimization" {
        It "should generate SQL efficiently for large schemas" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            1..100 | ForEach-Object {
                New-CreateTableSQL -TableName "provided_data" | Out-Null
                New-InsertSQL -TableName "provided_data" | Out-Null
                New-SelectSQL -TableName "provided_data" | Out-Null
            }
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000  # 5秒以内
        }
        
        It "should cache table definitions for repeated access" {
            # 複数回のアクセスで性能が向上することを確認
            $firstAccess = Measure-Command { Get-TableDefinition -TableName "provided_data" }
            $secondAccess = Measure-Command { Get-TableDefinition -TableName "provided_data" }
            $thirdAccess = Measure-Command { Get-TableDefinition -TableName "provided_data" }
            
            # 2回目以降のアクセスが1回目より速い（キャッシュ効果）
            $secondAccess.TotalMilliseconds | Should -BeLessOrEqual $firstAccess.TotalMilliseconds
            $thirdAccess.TotalMilliseconds | Should -BeLessOrEqual $firstAccess.TotalMilliseconds
        }
    }
}