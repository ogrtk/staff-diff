# PowerShell & SQLite データ同期システム
# DatabaseUtils モジュールのカラム名エスケープ機能テスト

using module "..\..\..\scripts\modules\Utils\Foundation\CoreUtils.psm1"
using module "..\..\..\scripts\modules\Utils\Infrastructure\LoggingUtils.psm1"
using module "..\..\..\scripts\modules\Utils\Infrastructure\ConfigurationUtils.psm1"
using module "..\..\..\scripts\modules\Utils\DataAccess\DatabaseUtils.psm1"

BeforeAll {
    # テスト用設定ファイルパス
    $script:TestConfigPath = Join-Path $PSScriptRoot "test-config-column-escape.json"
    
    # テスト用設定ファイル作成
    $testConfig = @{
        tables = @{
            test_table = @{
                columns = @(
                    @{
                        name = "id"
                        type = "INTEGER"
                        csv_include = $true
                        constraints = "PRIMARY KEY"
                    },
                    @{
                        name = "name[bracket]"
                        type = "TEXT"
                        csv_include = $true
                    },
                    @{
                        name = "value[]"
                        type = "REAL"
                        csv_include = $true
                    },
                    @{
                        name = "normal_column"
                        type = "TEXT"
                        csv_include = $true
                    }
                )
            }
        }
        csv_format = @{
            test_table = @{
                encoding = "UTF-8"
                delimiter = ","
                has_header = $true
                null_values = @("")
            }
        }
    }
    
    $testConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $script:TestConfigPath -Encoding UTF8
    
    # テスト用設定を使用
    $env:DATA_SYNC_CONFIG_PATH = $script:TestConfigPath
    
    # 設定キャッシュをリセット
    Reset-DataSyncConfig
}

AfterAll {
    # テスト用ファイルクリーンアップ
    if (Test-Path $script:TestConfigPath) {
        Remove-Item $script:TestConfigPath -Force
    }
    
    # 環境変数リセット
    Remove-Item Env:DATA_SYNC_CONFIG_PATH -ErrorAction SilentlyContinue
}

Describe "SQL識別子エスケープ機能テスト" {
    Context "Protect-SqliteIdentifier関数" {
        It "角括弧を含むカラム名が正しくエスケープされる" {
            $result = Protect-SqliteIdentifier -Identifier "name[bracket]"
            $result | Should -Be '"name[bracket]"'
        }
        
        It "空の角括弧を含むカラム名が正しくエスケープされる" {
            $result = Protect-SqliteIdentifier -Identifier "value[]"
            $result | Should -Be '"value[]"'
        }
        
        It "角括弧を含まないカラム名はそのまま返される" {
            $result = Protect-SqliteIdentifier -Identifier "normal_column"
            $result | Should -Be "normal_column"
        }
        
        It "二重引用符を含むカラム名が正しくエスケープされる" {
            $result = Protect-SqliteIdentifier -Identifier 'column"with"quotes'
            $result | Should -Be '"column""with""quotes"'
        }
        
        It "角括弧と二重引用符の両方を含むカラム名が正しくエスケープされる" {
            $result = Protect-SqliteIdentifier -Identifier 'column[with]"quotes'
            $result | Should -Be '"column[with]""quotes"'
        }
    }
    
    Context "CREATE TABLE文生成テスト" {
        It "角括弧を含むカラム名でCREATE TABLE文が正しく生成される" {
            $sql = New-CreateTableSql -TableName "test_table"
            
            $sql | Should -Match '"name\[bracket\]"'
            $sql | Should -Match '"value\[\]"'
            $sql | Should -Match 'normal_column'
        }
    }
    
    Context "SELECT文生成テスト" {
        It "角括弧を含むカラム名でSELECT文が正しく生成される" {
            $columns = @("id", "name[bracket]", "value[]", "normal_column")
            $sql = New-SelectSql -TableName "test_table" -Columns $columns
            
            $sql | Should -Match 'SELECT'
            $sql | Should -Match '"name\[bracket\]"'
            $sql | Should -Match '"value\[\]"'
            $sql | Should -Match 'normal_column'
        }
    }
    
    Context "INSERT文生成テスト" {
        It "角括弧を含むカラム名でINSERT文が正しく生成される" {
            $sql = New-FilteredInsertSql -TargetTableName "test_table" -SourceTableName "test_table_temp"
            
            $sql | Should -Match 'INSERT INTO test_table'
            $sql | Should -Match '"name\[bracket\]"'
            $sql | Should -Match '"value\[\]"'
            $sql | Should -Match 'normal_column'
        }
    }
}

Describe "実際のSQLite実行テスト" {
    BeforeAll {
        $script:TestDatabasePath = Join-Path $PSScriptRoot "test-column-escape.db"
    }
    
    AfterAll {
        if (Test-Path $script:TestDatabasePath) {
            Remove-Item $script:TestDatabasePath -Force
        }
    }
    
    Context "SQLite実行テスト" {
        It "角括弧を含むカラム名でテーブル作成・データ挿入・検索ができる" {
            # テーブル作成
            $createSql = New-CreateTableSql -TableName "test_table"
            Invoke-SqliteCommand -DatabasePath $script:TestDatabasePath -Query $createSql
            
            # データ挿入（手動で準備）
            $insertSql = 'INSERT INTO test_table (id, "name[bracket]", "value[]", normal_column) VALUES (1, ''test[value]'', 10.5, ''normal'')'
            Invoke-SqliteCommand -DatabasePath $script:TestDatabasePath -Query $insertSql
            
            # データ検索（CSV形式でオブジェクトとして取得）
            $selectSql = 'SELECT id, "name[bracket]", "value[]", normal_column FROM test_table WHERE id = 1'
            $result = Invoke-SqliteCsvQuery -DatabasePath $script:TestDatabasePath -Query $selectSql
            
            $result | Should -Not -BeNullOrEmpty
            $result[0].id | Should -Be 1
            $result[0]."name[bracket]" | Should -Be "test[value]"
            $result[0]."value[]" | Should -Be 10.5
            $result[0].normal_column | Should -Be "normal"
        }
    }
}