BeforeAll {
    # Mock Invoke-WithErrorHandling function to avoid dependency issues
    function Global:Invoke-WithErrorHandling {
        param(
            [scriptblock]$ScriptBlock,
            [string]$Category = "System",
            [string]$Operation = "Operation",
            [hashtable]$Context = @{},
            [scriptblock]$CleanupScript = {}
        )
        
        try {
            return & $ScriptBlock
        } catch {
            Write-Warning "Mock error handling: $($_.Exception.Message)"
            throw
        }
    }
    
    # モジュールをインポート
    Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts/modules/Utils/CommonUtils.psm1') -Force
}

Describe "Get-CrossPlatformEncoding" {
    It "should return UTF8 encoding for PowerShell Core (version 6+)" {
        # Mock $PSVersionTable for testing PowerShell Core behavior
        Mock -ModuleName CommonUtils -CommandName Get-Variable -ParameterFilter { $Name -eq 'PSVersionTable' } -MockWith {
            return [PSCustomObject]@{
                PSVersion = [Version]'6.0.0'
            }
        }
        $encoding = Get-CrossPlatformEncoding
        $encoding.EncodingName | Should -Be "Unicode (UTF-8)"
        $encoding.Preamble.Length | Should -Be 0 # No BOM for PowerShell Core
    }

    It "should return UTF8 encoding with BOM for Windows PowerShell (version < 6)" {
        # Mock $PSVersionTable for testing Windows PowerShell behavior
        Mock -ModuleName CommonUtils -CommandName Get-Variable -ParameterFilter { $Name -eq 'PSVersionTable' } -MockWith {
            return [PSCustomObject]@{
                PSVersion = [Version]'5.1.0'
            }
        }
        $encoding = Get-CrossPlatformEncoding
        $encoding.EncodingName | Should -Be "Unicode (UTF-8)"
        # Explicitly create a UTF8 encoding with BOM to compare against
        $expectedEncodingWithBOM = [System.Text.UTF8Encoding]::new($true)
        $encoding.Preamble.Length | Should -Be $expectedEncodingWithBOM.Preamble.Length
    }
}

Describe "Get-Sqlite3Path" {
    It "should return the sqlite3 command path if found" {
        Mock -ModuleName CommonUtils -CommandName Get-Command -ParameterFilter { $Name -eq 'sqlite3' } -MockWith {
            return [PSCustomObject]@{
                Name = 'sqlite3'
                Source = '/usr/bin/sqlite3'
            }
        }
        $path = Get-Sqlite3Path
        $path.Name | Should -Be 'sqlite3'
        $path.Source | Should -Be '/usr/bin/sqlite3'
    }

    It "should throw an error if sqlite3 command is not found" {
        Mock -ModuleName CommonUtils -CommandName Get-Command -ParameterFilter { $Name -eq 'sqlite3' } -MockWith {
            return $null
        }
        {
            Get-Sqlite3Path
        } | Should -Throw "SQLite3コマンドの取得に失敗しました: sqlite3コマンドが見つかりません。sqlite3をインストールしてPATHに追加してください。"
    }
}

Describe "Clear-Table" {
    Context "Table exists" {
        It "should clear the table and log statistics when ShowStatistics is true" {
            # Mock Invoke-SqliteCommand for table existence check
            Mock -ModuleName CommonUtils -CommandName Invoke-SqliteCommand -ParameterFilter { $Query -like 'SELECT name FROM sqlite_master%' } -MockWith {
                return @{ name = 'test_table' }
            } -Verifiable

            # Mock Invoke-SqliteCommand for count query
            Mock -ModuleName CommonUtils -CommandName Invoke-SqliteCommand -ParameterFilter { $Query -like 'SELECT COUNT(*)%' } -MockWith {
                return @( @{ count = 10 } )
            } -Verifiable

            # Mock Invoke-SqliteCommand for delete query
            Mock -ModuleName CommonUtils -CommandName Invoke-SqliteCommand -ParameterFilter { $Query -like 'DELETE FROM%' } -MockWith {
                # Do nothing, just verify it's called
            } -Verifiable

            # Mock Write-SystemLog
            Mock -ModuleName CommonUtils -CommandName Write-SystemLog -MockWith {
                # Capture logs for assertion
            } -Verifiable

            Clear-Table -DatabasePath "test.db" -TableName "test_table" -ShowStatistics:$true

            Assert-MockCalled Invoke-SqliteCommand -ParameterFilter { $Query -like 'SELECT name FROM sqlite_master%' } -Times 1
            Assert-MockCalled Invoke-SqliteCommand -ParameterFilter { $Query -like 'SELECT COUNT(*)%' } -Times 1
            Assert-MockCalled Invoke-SqliteCommand -ParameterFilter { $Query -like 'DELETE FROM%' } -Times 1
            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like 'テーブル ''test_table'' をクリア中（既存件数: 10）%' -and $Level -eq 'Info' } -Times 1
            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like 'テーブル ''test_table'' のクリアが完了しました%' -and $Level -eq 'Success' } -Times 1
        }

        It "should clear the table and log without statistics when ShowStatistics is false" {
            # Mock Invoke-SqliteCommand for table existence check
            Mock -ModuleName CommonUtils -CommandName Invoke-SqliteCommand -ParameterFilter { $Query -like 'SELECT name FROM sqlite_master%' } -MockWith {
                return @{ name = 'test_table' }
            } -Verifiable

            # Mock Invoke-SqliteCommand for delete query
            Mock -ModuleName CommonUtils -CommandName Invoke-SqliteCommand -ParameterFilter { $Query -like 'DELETE FROM%' } -MockWith {
                # Do nothing, just verify it's called
            } -Verifiable

            # Mock Write-SystemLog
            Mock -ModuleName CommonUtils -CommandName Write-SystemLog -MockWith {
                # Capture logs for assertion
            } -Verifiable

            Clear-Table -DatabasePath "test.db" -TableName "test_table" -ShowStatistics:$false

            Assert-MockCalled Invoke-SqliteCommand -ParameterFilter { $Query -like 'SELECT name FROM sqlite_master%' } -Times 1
            Assert-MockCalled Invoke-SqliteCommand -ParameterFilter { $Query -like 'SELECT COUNT(*)%' } -Times 0 # Should not be called
            Assert-MockCalled Invoke-SqliteCommand -ParameterFilter { $Query -like 'DELETE FROM%' } -Times 1
            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like 'テーブル ''test_table'' をクリア中...' -and $Level -eq 'Info' } -Times 1
            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like 'テーブル ''test_table'' のクリアが完了しました%' -and $Level -eq 'Success' } -Times 1
        }
    }

    Context "Table does not exist" {
        It "should skip clearing the table and log a message" {
            # Mock Invoke-SqliteCommand for table existence check to return empty
            Mock -ModuleName CommonUtils -CommandName Invoke-SqliteCommand -ParameterFilter { $Query -like 'SELECT name FROM sqlite_master%' } -MockWith {
                return @()
            } -Verifiable

            # Mock Invoke-SqliteCommand for delete query (should not be called)
            Mock -ModuleName CommonUtils -CommandName Invoke-SqliteCommand -ParameterFilter { $Query -like 'DELETE FROM%' } -MockWith {
                # This mock should not be called
            } -Verifiable

            # Mock Write-SystemLog
            Mock -ModuleName CommonUtils -CommandName Write-SystemLog -MockWith {
                # Capture logs for assertion
            } -Verifiable

            Clear-Table -DatabasePath "test.db" -TableName "non_existent_table"

            Assert-MockCalled Invoke-SqliteCommand -ParameterFilter { $Query -like 'SELECT name FROM sqlite_master%' } -Times 1
            Assert-MockCalled Invoke-SqliteCommand -ParameterFilter { $Query -like 'DELETE FROM%' } -Times 0 # Should not be called
            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like 'テーブル ''non_existent_table'' は存在しないため、スキップします%' -and $Level -eq 'Info' } -Times 1
        }
    }
}

Describe "Invoke-SqliteCsvExport" {
    BeforeAll {
        # Mock external dependencies
        Mock -ModuleName CommonUtils -CommandName Get-CrossPlatformEncoding -MockWith {
            return [System.Text.Encoding]::UTF8
        }
        Mock -ModuleName CommonUtils -CommandName Write-SystemLog -MockWith {}
    }

    Context "正常なCSV出力" {
        It "SQLite3コマンドでCSVを出力し、件数を返す" {
            # Mock sqlite3 command execution
            Mock -ModuleName CommonUtils -CommandName & -MockWith {
                return @("header1,header2", "value1,value2", "value3,value4")
            }
            
            # Mock Out-File
            Mock -ModuleName CommonUtils -CommandName Out-File -MockWith {}

            $result = Invoke-SqliteCsvExport -DatabasePath "test.db" -Query "SELECT * FROM test" -OutputPath "output.csv"

            $result | Should -Be 2  # ヘッダー行を除いた件数
            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like '*CSV出力完了*' -and $Level -eq 'Success' } -Times 1
        }
    }

    Context "エラーハンドリング" {
        It "SQLite3コマンドエラー時に適切な例外を投げる" {
            # Mock sqlite3 command failure
            $global:LASTEXITCODE = 1
            Mock -ModuleName CommonUtils -CommandName & -MockWith {
                return "SQL error: syntax error"
            }

            { Invoke-SqliteCsvExport -DatabasePath "test.db" -Query "INVALID SQL" -OutputPath "output.csv" } |
                Should -Throw "*SQLite CSV出力の実行に失敗しました*"
        }
    }
}

# Commenting out tests for internal script: functions for now.
# Their functionality should be tested indirectly through public functions that use them.
# Describe "Get-MinimalLoggingConfig" {
#     It "should return the default logging configuration" {
#         $config = Get-MinimalLoggingConfig
#         $config.enabled | Should -Be $true
#         $config.log_directory | Should -Be "./logs/"
#         $config.log_file_name | Should -Be "data-sync-system.log"
#         $config.max_file_size_mb | Should -Be 10
#         $config.max_files | Should -Be 5
#         $config.levels | Should -Be @("Info", "Warning", "Error", "Success")
#     }
# }

# Describe "Get-MinimalJapanTimestamp" {
#     It "should return a timestamp in the specified format" {
#         $timestamp = Get-MinimalJapanTimestamp -Format "yyyy-MM-dd HH:mm:ss"
#         $timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
#     }

#     It "should return a timestamp approximately in Japan time (UTC+9)" {
#         $timestamp = Get-MinimalJapanTimestamp -Format "HH"
#         $currentUtcHour = (Get-Date).ToUniversalTime().Hour
#         $expectedJapanHour = ($currentUtcHour + 9) % 24
        
#         # Allow for a small time difference due to execution time
#         [int]$actualJapanHour = $timestamp
#         ($actualJapanHour -eq $expectedJapanHour -or $actualJapanHour -eq (($expectedJapanHour + 1) % 24)) | Should -Be $true
#     }
# }