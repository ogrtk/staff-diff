# PowerShell & SQLite データ同期システム
# フィルタ除外データのKEEP出力機能テスト

BeforeAll {
    # 統合テストヘルパーの読み込み
    Import-Module (Join-Path $PSScriptRoot "../TestHelpers/MockHelpers.psm1") -Force
    
    # 一時ディレクトリの作成
    $script:TestDir = New-MockTemporaryDirectory -Prefix "excluded-keep-test"
    $script:TestConfigPath = Join-Path $script:TestDir.Path "test-config.json"
    $script:TestDatabasePath = Join-Path $script:TestDir.Path "test.db"
    $script:TestProvidedPath = Join-Path $script:TestDir.Path "provided.csv"
    $script:TestCurrentPath = Join-Path $script:TestDir.Path "current.csv"
    $script:TestOutputPath = Join-Path $script:TestDir.Path "output.csv"
}

AfterAll {
    # テスト環境のクリーンアップ
    Remove-MockTemporaryDirectory -TempDirectory $script:TestDir
}

Describe "除外データKEEP出力機能" {
    BeforeAll {
        # テスト用設定とデータベースパス（スクリプトスコープの変数を使用）
        $testConfigPath = $script:TestConfigPath
        $testDatabasePath = $script:TestDatabasePath
        $testProvidedPath = $script:TestProvidedPath
        $testCurrentPath = $script:TestCurrentPath
        $testOutputPath = $script:TestOutputPath
        
        # テスト用設定ファイル作成
        $testConfig = @{
            "file_paths" = @{
                "provided_data_file_path" = $testProvidedPath
                "current_data_file_path"  = $testCurrentPath
                "output_file_path"        = $testOutputPath
                "timezone"                = "Asia/Tokyo"
            }
            "csv_format" = @{
                "provided_data" = @{
                    "encoding"    = "UTF-8"
                    "delimiter"   = ","
                    "has_header"  = $false
                    "null_values" = @("", "NULL")
                }
                "current_data"  = @{
                    "encoding"    = "UTF-8"
                    "delimiter"   = ","
                    "has_header"  = $true
                    "null_values" = @("", "NULL")
                }
                "output"        = @{
                    "encoding"       = "UTF-8"
                    "delimiter"      = ","
                    "include_header" = $true
                }
            }
            "tables"     = @{
                "provided_data" = @{
                    "columns" = @(
                        @{ "name" = "id"; "type" = "INTEGER"; "constraints" = "PRIMARY KEY AUTOINCREMENT"; "csv_include" = $false }
                        @{ "name" = "employee_id"; "type" = "TEXT"; "constraints" = "NOT NULL"; "csv_include" = $true; "required" = $true }
                        @{ "name" = "name"; "type" = "TEXT"; "constraints" = "NOT NULL"; "csv_include" = $true; "required" = $true }
                    )
                }
                "current_data"  = @{
                    "columns" = @(
                        @{ "name" = "id"; "type" = "INTEGER"; "constraints" = "PRIMARY KEY AUTOINCREMENT"; "csv_include" = $false }
                        @{ "name" = "user_id"; "type" = "TEXT"; "constraints" = "NOT NULL"; "csv_include" = $true; "required" = $true }
                        @{ "name" = "name"; "type" = "TEXT"; "constraints" = "NOT NULL"; "csv_include" = $true; "required" = $true }
                    )
                }
                "sync_result"   = @{
                    "columns" = @(
                        @{ "name" = "id"; "type" = "INTEGER"; "constraints" = "PRIMARY KEY AUTOINCREMENT"; "csv_include" = $false }
                        @{ "name" = "syokuin_no"; "type" = "TEXT"; "constraints" = "NOT NULL"; "csv_include" = $true; "required" = $true }
                        @{ "name" = "name"; "type" = "TEXT"; "constraints" = "NOT NULL"; "csv_include" = $true; "required" = $true }
                        @{ "name" = "sync_action"; "type" = "TEXT"; "constraints" = "NOT NULL"; "csv_include" = $true; "required" = $true }
                    )
                }
            }
            "sync_rules" = @{
                "key_columns"         = @{
                    "provided_data" = @("employee_id")
                    "current_data"  = @("user_id")
                    "sync_result"   = @("syokuin_no")
                }
                "column_mappings"     = @{
                    "mappings" = @{
                        "employee_id" = "user_id"
                        "name"        = "name"
                    }
                }
                "sync_result_mapping" = @{
                    "mappings" = @{
                        "syokuin_no" = @{
                            "sources" = @(
                                @{ "type" = "provided_data"; "field" = "employee_id"; "priority" = 1 }
                                @{ "type" = "current_data"; "field" = "user_id"; "priority" = 2 }
                            )
                        }
                        "name"       = @{
                            "sources" = @(
                                @{ "type" = "provided_data"; "field" = "name"; "priority" = 1 }
                                @{ "type" = "current_data"; "field" = "name"; "priority" = 2 }
                            )
                        }
                    }
                }
                "sync_action_labels"  = @{
                    "mappings" = @{
                        "ADD"    = @{ "value" = "1" }
                        "UPDATE" = @{ "value" = "2" }
                        "DELETE" = @{ "value" = "3" }
                        "KEEP"   = @{ "value" = "9" }
                    }
                }
            }
        }
        
        # 除外データKEEP出力無効時の設定
        $testConfigDisabled = $testConfig.Clone()
        $testConfigDisabled["data_filters"] = @{
            "current_data" = @{
                "enabled"                 = $true
                "rules"                   = @(
                    @{ "field" = "user_id"; "type" = "exclude"; "glob" = "Z*" }
                )
                "output_excluded_as_keep" = @{
                    "enabled" = $false
                }
            }
        }
        
        # 除外データKEEP出力有効時の設定
        $testConfigEnabled = $testConfig.Clone()
        $testConfigEnabled["data_filters"] = @{
            "current_data" = @{
                "enabled"                 = $true
                "rules"                   = @(
                    @{ "field" = "user_id"; "type" = "exclude"; "glob" = "Z*" }
                )
                "output_excluded_as_keep" = @{
                    "enabled" = $true
                }
            }
        }
        
        # テストデータ作成（provided_data.csv）
        $providedData = @"
E001,田中太郎
E002,佐藤花子
E003,鈴木次郎
"@
        
        # テストデータ作成（current_data.csv）
        $currentData = @"
user_id,name
E001,田中太郎
E002,佐藤花子 Updated
Z001,削除対象ユーザー
Z002,もう一人の削除対象
"@
        
        # テストファイル作成
        $providedData | Out-File -FilePath $testProvidedPath -Encoding UTF8 -NoNewline
        $currentData | Out-File -FilePath $testCurrentPath -Encoding UTF8 -NoNewline
    }
    
    Context "除外データKEEP出力が無効の場合" {
        It "フィルタ除外されたcurrent_dataは出力されない" {
            # 設定ファイル作成（無効）
            $testConfigDisabled | ConvertTo-Json -Depth 10 | Out-File -FilePath $testConfigPath -Encoding UTF8
            
            # システム実行
            & pwsh -Command "
                Set-Location '$PWD'
                . './scripts/modules/Utils/Foundation/CoreUtils.psm1'
                . './scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1'
                . './scripts/modules/Utils/Infrastructure/LoggingUtils.psm1'
                . './scripts/modules/Utils/Infrastructure/ErrorHandlingUtils.psm1'
                . './scripts/modules/Utils/DataAccess/DatabaseUtils.psm1'
                . './scripts/modules/Utils/DataAccess/FileSystemUtils.psm1'
                . './scripts/modules/Utils/DataProcessing/CsvProcessingUtils.psm1'
                . './scripts/modules/Utils/DataProcessing/DataFilteringUtils.psm1'
                . './scripts/modules/Process/Invoke-CsvImport.psm1'
                . './scripts/modules/Process/Invoke-DataSync.psm1'
                
                Set-DataSyncConfig -ConfigFilePath '$testConfigPath'
                Remove-Item -Path '$testDatabasePath' -ErrorAction SilentlyContinue
                Initialize-Database -DatabasePath '$testDatabasePath'
                Invoke-CsvImport -CsvFilePath '$testProvidedPath' -DatabasePath '$testDatabasePath' -TableName 'provided_data'
                Invoke-CsvImport -CsvFilePath '$testCurrentPath' -DatabasePath '$testDatabasePath' -TableName 'current_data'
                Invoke-DataSync -DatabasePath '$testDatabasePath'
            "
            
            # sync_resultから結果確認
            $results = Invoke-SqliteCommand -DatabasePath $testDatabasePath -Query "SELECT syokuin_no, sync_action FROM sync_result WHERE syokuin_no LIKE 'Z%'"
            
            # Z*データは除外されて出力されないことを確認
            $results | Should -BeNullOrEmpty
        }
    }
    
    Context "除外データKEEP出力が有効の場合" {
        It "フィルタ除外されたcurrent_dataがKEEPアクションで出力される" {
            # 設定ファイル作成（有効）
            $testConfigEnabled | ConvertTo-Json -Depth 10 | Out-File -FilePath $testConfigPath -Encoding UTF8
            
            # システム実行
            & pwsh -Command "
                Set-Location '$PWD'
                . './scripts/modules/Utils/Foundation/CoreUtils.psm1'
                . './scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1'
                . './scripts/modules/Utils/Infrastructure/LoggingUtils.psm1'
                . './scripts/modules/Utils/Infrastructure/ErrorHandlingUtils.psm1'
                . './scripts/modules/Utils/DataAccess/DatabaseUtils.psm1'
                . './scripts/modules/Utils/DataAccess/FileSystemUtils.psm1'
                . './scripts/modules/Utils/DataProcessing/CsvProcessingUtils.psm1'
                . './scripts/modules/Utils/DataProcessing/DataFilteringUtils.psm1'
                . './scripts/modules/Process/Invoke-CsvImport.psm1'
                . './scripts/modules/Process/Invoke-DataSync.psm1'
                
                Set-DataSyncConfig -ConfigFilePath '$testConfigPath'
                Remove-Item -Path '$testDatabasePath' -ErrorAction SilentlyContinue
                Initialize-Database -DatabasePath '$testDatabasePath'
                Invoke-CsvImport -CsvFilePath '$testProvidedPath' -DatabasePath '$testDatabasePath' -TableName 'provided_data'
                Invoke-CsvImport -CsvFilePath '$testCurrentPath' -DatabasePath '$testDatabasePath' -TableName 'current_data'
                Invoke-DataSync -DatabasePath '$testDatabasePath'
            "
            
            # sync_resultから結果確認
            $results = Invoke-SqliteCommand -DatabasePath $testDatabasePath -Query "SELECT syokuin_no, sync_action FROM sync_result WHERE syokuin_no LIKE 'Z%' ORDER BY syokuin_no"
            
            # Z*データがKEEPアクション（値=9）で出力されることを確認
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -Be 2
            $results[0].syokuin_no | Should -Be "Z001"
            $results[0].sync_action | Should -Be "9"
            $results[1].syokuin_no | Should -Be "Z002"
            $results[1].sync_action | Should -Be "9"
        }
    }
}