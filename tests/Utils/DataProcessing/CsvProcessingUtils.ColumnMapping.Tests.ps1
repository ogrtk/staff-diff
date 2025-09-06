# PowerShell & SQLite データ同期システム
# CsvProcessingUtils モジュールのカラムマッピング機能テスト

using module "..\..\..\scripts\modules\Utils\Foundation\CoreUtils.psm1"
using module "..\..\..\scripts\modules\Utils\Infrastructure\LoggingUtils.psm1"
using module "..\..\..\scripts\modules\Utils\Infrastructure\ConfigurationUtils.psm1"
using module "..\..\..\scripts\modules\Utils\DataAccess\DatabaseUtils.psm1"
using module "..\..\..\scripts\modules\Utils\DataProcessing\CsvProcessingUtils.psm1"

BeforeAll {
    # テスト用設定ファイルパス
    $script:TestConfigPath = Join-Path $PSScriptRoot "test-config-column-mapping.json"
    
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
                        name = "staff[name]"
                        type = "TEXT"
                        csv_include = $true
                    },
                    @{
                        name = "department[]"
                        type = "TEXT"
                        csv_include = $true
                    },
                    @{
                        name = "salary"
                        type = "REAL"
                        csv_include = $true
                    },
                    @{
                        name = "notes[memo]"
                        type = "TEXT"
                        csv_include = $false
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
}

AfterAll {
    # テスト用ファイルクリーンアップ
    if (Test-Path $script:TestConfigPath) {
        Remove-Item $script:TestConfigPath -Force
    }
    
    # 環境変数リセット
    Remove-Item Env:DATA_SYNC_CONFIG_PATH -ErrorAction SilentlyContinue
}

Describe "CSV・SQLカラム名マッピング機能テスト" {
    Context "Get-CsvToSqlColumnMapping関数" {
        It "CSVからSQLへの正しいマッピングが取得できる" {
            $mapping = Get-CsvToSqlColumnMapping -TableName "test_table"
            
            # 角括弧を含むカラムはエスケープされる
            $mapping["staff[name]"] | Should -Be '"staff[name]"'
            $mapping["department[]"] | Should -Be '"department[]"'
            
            # 通常のカラムはそのまま
            $mapping["id"] | Should -Be "id"
            $mapping["salary"] | Should -Be "salary"
            
            # csv_include = false のカラムは含まれない
            $mapping.ContainsKey("notes[memo]") | Should -Be $false
        }
        
        It "存在しないテーブル名でエラーが発生する" {
            { Get-CsvToSqlColumnMapping -TableName "non_existent_table" } | Should -Throw
        }
    }
    
    Context "Get-SqlToCsvColumnMapping関数" {
        It "SQLからCSVへの逆引きマッピングが取得できる" {
            $mapping = Get-SqlToCsvColumnMapping -TableName "test_table"
            
            # エスケープ済みからオリジナルへの逆引き
            $mapping['"staff[name]"'] | Should -Be "staff[name]"
            $mapping['"department[]"'] | Should -Be "department[]"
            
            # 通常のカラムはそのまま
            $mapping["id"] | Should -Be "id"
            $mapping["salary"] | Should -Be "salary"
        }
    }
    
    Context "マッピングの整合性テスト" {
        It "CSV→SQL→CSVの変換で元の名前に戻る" {
            $csvToSql = Get-CsvToSqlColumnMapping -TableName "test_table"
            $sqlToCsv = Get-SqlToCsvColumnMapping -TableName "test_table"
            
            foreach ($csvColumn in $csvToSql.Keys) {
                $sqlColumn = $csvToSql[$csvColumn]
                $backToCsv = $sqlToCsv[$sqlColumn]
                
                $backToCsv | Should -Be $csvColumn
            }
        }
    }
}

Describe "統合テスト" {
    Context "CSVとSQLでの実際の使用例" {
        BeforeAll {
            $script:TestDatabasePath = Join-Path $PSScriptRoot "test-column-mapping.db"
            $script:TestCsvPath = Join-Path $PSScriptRoot "test-column-mapping.csv"
            
            # テスト用CSVファイル作成（角括弧を含むヘッダー）
            $csvContent = @"
id,staff[name],department[],salary
1,田中太郎,営業[部],50000
2,佐藤花子,開発[],60000
3,鈴木一郎,人事[],55000
"@
            Set-Content -Path $script:TestCsvPath -Value $csvContent -Encoding UTF8
        }
        
        AfterAll {
            if (Test-Path $script:TestDatabasePath) {
                Remove-Item $script:TestDatabasePath -Force
            }
            if (Test-Path $script:TestCsvPath) {
                Remove-Item $script:TestCsvPath -Force
            }
        }
        
        It "角括弧を含むカラム名でCSVからSQLiteへのデータ流れが正常に動作する" {
            # 1. テーブル作成（エスケープ済みカラム名）
            $createSql = New-CreateTableSql -TableName "test_table"
            Invoke-SqliteCommand -DatabasePath $script:TestDatabasePath -Query $createSql
            
            # 2. CSVデータ読み込み（元のカラム名）
            $csvData = Import-CsvWithFormat -CsvPath $script:TestCsvPath -TableName "test_table"
            $csvData | Should -Not -BeNullOrEmpty
            $csvData.Count | Should -Be 3
            
            # 3. CSVからSQLへのマッピング確認
            $mapping = Get-CsvToSqlColumnMapping -TableName "test_table"
            
            # 4. データが正しく読み込まれていることを確認
            $firstRow = $csvData[0]
            $firstRow.id | Should -Be "1"
            $firstRow."staff[name]" | Should -Be "田中太郎"
            $firstRow."department[]" | Should -Be "営業[部]"
            $firstRow.salary | Should -Be "50000"
        }
    }
}