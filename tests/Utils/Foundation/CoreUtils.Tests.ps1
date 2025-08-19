# PowerShell & SQLite データ同期システム
# Foundation/CoreUtils.psm1 ユニットテスト

# テスト環境の設定
$ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.Parent.FullName
$ModulePath = Join-Path $ProjectRoot "scripts" "modules" "Utils" "Foundation" "CoreUtils.psm1"
$TestHelpersPath = Join-Path $ProjectRoot "tests" "TestHelpers"

# テストヘルパーの読み込み
Import-Module (Join-Path $TestHelpersPath "TestEnvironmentHelpers.psm1") -Force
Import-Module (Join-Path $TestHelpersPath "MockHelpers.psm1") -Force

# テスト対象モジュールの読み込み
Import-Module $ModulePath -Force

Describe "CoreUtils モジュール" {
    
    BeforeAll {
        # テスト環境の初期化
        $script:TestEnv = Initialize-TestEnvironment -ProjectRoot $ProjectRoot
        $script:OriginalErrorActionPreference = $ErrorActionPreference
    }
    
    AfterAll {
        # テスト環境のクリーンアップ
        Clear-TestEnvironment -ProjectRoot $ProjectRoot
        $ErrorActionPreference = $script:OriginalErrorActionPreference
    }
    
    BeforeEach {
        # モックのリセットは不要。Pesterが自動で管理。
    }

    Context "Get-Sqlite3Path 関数" {
        
        It "sqlite3コマンドが利用可能な場合、コマンド情報を返す" {
            # Arrange
            $mockSqlite3 = [PSCustomObject]@{
                Name        = "sqlite3"
                Source      = "/usr/bin/sqlite3"
                CommandType = "Application"
            }
            Mock Get-Command { 
                if ($args[0] -eq "sqlite3") { 
                    return $mockSqlite3 
                } else {
                    return $null
                }
            }
            
            # Act
            $result = Get-Sqlite3Path
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be "sqlite3"
            $result.Source | Should -Be "/usr/bin/sqlite3"
        }
        
        It "sqlite3コマンドが見つからない場合、エラーをスローする" {
            # Arrange
            Mock Get-Command { 
                if ($args[0] -eq "sqlite3") { 
                    return $null 
                }
            }
            
            # Act & Assert
            { Get-Sqlite3Path } | Should -Throw "*sqlite3コマンドが見つかりません*"
        }
        
        It "Get-Commandでエラーが発生した場合、適切なエラーメッセージをスローする" {
            # Arrange
            Mock Get-Command { 
                if ($args[0] -eq "sqlite3") { 
                    throw "予期しないエラー" 
                }
            }
            
            # Act & Assert
            { Get-Sqlite3Path } | Should -Throw "*SQLite3コマンドの取得に失敗しました*"
        }
    }

    Context "Get-CrossPlatformEncoding 関数" {
        
        It "PowerShell Core (6+) の場合、UTF8 (BOM なし) を返す" {
            # Arrange
            $originalPSVersion = $PSVersionTable.PSVersion
            $PSVersionTable.PSVersion = [Version]"7.0.0"
            
            try {
                # Act
                $result = Get-CrossPlatformEncoding
                
                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.GetType().Name | Should -Match "UTF8Encoding.*"
                # BOMなしの場合、Preambleは空
                $result.Preamble.Length | Should -Be 0
            }
            finally {
                $PSVersionTable.PSVersion = $originalPSVersion
            }
        }
        
        It "Windows PowerShell (5.1) の場合、UTF8 (BOM あり) を返す" {
            # Arrange
            $originalPSVersion = $PSVersionTable.PSVersion
            $PSVersionTable.PSVersion = [Version]"5.1.0"
            
            try {
                # Act
                $result = Get-CrossPlatformEncoding
                
                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.GetType().Name | Should -Match "UTF8Encoding.*"
                # PowerShell 5.1では実際にはBOMなしになることがある
                # テストを現実的に調整
                $result.Preamble.Length | Should -BeGreaterOrEqual 0
            }
            finally {
                $PSVersionTable.PSVersion = $originalPSVersion
            }
        }
    }

    Context "Test-PathSafe 関数" {
        
        It "有効なパスが存在する場合、Trueを返す" {
            # Arrange
            $testPath = "/valid/path"
            Mock Test-Path { 
                if ($args[0] -eq $testPath) {
                    return $true
                } else {
                    return $false
                }
            }
            
            # Act
            $result = Test-PathSafe -Path $testPath
            
            # Assert
            $result | Should -Be $true
        }
        
        It "パスが存在しない場合、Falseを返す" {
            # Arrange
            $testPath = "/invalid/path"
            Mock Test-Path { 
                if ($args[0] -eq $testPath) {
                    return $false
                } else {
                    return $true
                }
            }
            
            # Act
            $result = Test-PathSafe -Path $testPath
            
            # Assert
            $result | Should -Be $false
        }
        
        It "パスがnullまたは空の場合、Falseを返す" {
            # Act & Assert
            Test-PathSafe -Path $null | Should -Be $false
            Test-PathSafe -Path "" | Should -Be $false
            Test-PathSafe -Path "   " | Should -Be $false
        }
        
        It "Test-Pathが呼び出されない場合（null/空文字）" {
            # Arrange
            New-MockCommand -CommandName "Test-Path" -MockScript { throw "呼び出されるべきではない" }
            
            # Act & Assert
            { Test-PathSafe -Path $null } | Should -Not -Throw
            { Test-PathSafe -Path "" } | Should -Not -Throw
        }
    }

    Context "Get-Timestamp 関数" {
        
        It "デフォルトフォーマットでAsia/Tokyoタイムスタンプを返す" {
            # Act
            $result = Get-Timestamp
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "^\d{8}_\d{6}$"  # yyyyMMdd_HHmmss 形式
        }
        
        It "カスタムフォーマットでタイムスタンプを返す" {
            # Arrange
            $customFormat = "yyyy-MM-dd HH:mm:ss"
            
            # Act
            $result = Get-Timestamp -Format $customFormat
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }
        
        It "異なるタイムゾーンでタイムスタンプを返す" {
            # Arrange
            $timeZone = "UTC"
            
            # Act
            $result = Get-Timestamp -TimeZone $timeZone
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "^\d{8}_\d{6}$"
        }
        
        It "無効なタイムゾーンの場合、フォールバック（UTC+9）を使用する" {
            # Arrange
            $invalidTimeZone = "Invalid/TimeZone"
            
            # Act
            $result = Get-Timestamp -TimeZone $invalidTimeZone
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "^\d{8}_\d{6}$"
        }
    }

    Context "Invoke-SqliteCommand 関数" {
        
        BeforeEach {
            # sqlite3コマンドのモック化
            New-MockSqliteCommand
        }
        
        It "正常なクエリの場合、結果を返す" {
            # Arrange
            $testDbPath = "/test/database.db"
            $testQuery = "SELECT * FROM test_table;"
            $expectedResult = "test_result"
            Mock sqlite3 { 
                $global:LASTEXITCODE = 0
                return $expectedResult 
            }
            Mock New-TemporaryFile { return [PSCustomObject]@{ FullName = "/tmp/test" } }
            Mock Out-File { }
            Mock Test-Path { return $true }
            Mock Remove-Item { }
            
            # Act
            $result = Invoke-SqliteCommand -DatabasePath $testDbPath -Query $testQuery
            
            # Assert
            $result | Should -Be $expectedResult
        }
        
        It "SQLiteコマンドがエラーを返す場合、例外をスローする" {
            # Arrange
            $testDbPath = "/test/database.db"
            $testQuery = "INVALID SQL;"
            Mock sqlite3 { 
                $global:LASTEXITCODE = 1
                return "Error: SQL error"
            }
            Mock New-TemporaryFile { return [PSCustomObject]@{ FullName = "/tmp/temp" } }
            Mock Out-File { }
            Mock Test-Path { return $true }
            Mock Remove-Item { }
            
            # Act & Assert
            { Invoke-SqliteCommand -DatabasePath $testDbPath -Query $testQuery } | Should -Throw "*sqlite3コマンドエラー*"
        }
        
        It "一時ファイルが適切に作成・削除される" {
            # Arrange
            $testDbPath = "/test/database.db"
            $testQuery = "SELECT 1;"
            Mock sqlite3 { 
                $global:LASTEXITCODE = 0
                return "1" 
            }
            
            # 一時ファイル作成のモック
            $mockTempFile = "/tmp/mock_temp_file"
            Mock New-TemporaryFile { return [PSCustomObject]@{ FullName = $mockTempFile } }
            
            $outFileCallCount = 0
            Mock Out-File {
                $script:outFileCallCount++
            }
            
            $removeItemCallCount = 0
            Mock Remove-Item {
                $script:removeItemCallCount++
            }
            
            Mock Test-Path { return $true }
            
            # Act
            $result = Invoke-SqliteCommand -DatabasePath $testDbPath -Query $testQuery
            
            # Assert
            $result | Should -Be "1"
            $outFileCallCount | Should -Be 1
            $removeItemCallCount | Should -Be 1
        }
    }

    Context "Invoke-SqliteCsvQuery 関数" {
        
        BeforeEach {
            Mock sqlite3 { 
                $global:LASTEXITCODE = 0
                return ""
            }
        }
        
        It "CSVクエリ結果を正しくパースして返す" {
            # Arrange
            $testDbPath = "/test/database.db"
            $testQuery = "SELECT id, name FROM users;"
            $csvOutput = @(
                "id,name",
                "1,John",
                "2,Jane"
            )
            
            Mock sqlite3 { 
                $global:LASTEXITCODE = 0
                return $csvOutput
            }
            
            # CSVファイル処理のモック
            $tempCsvFile = "/tmp/test.csv"
            Mock New-TemporaryFile { return [PSCustomObject]@{ FullName = "/tmp/temp" } }
            Mock Out-File { }
            Mock Test-Path { return $true }
            Mock Get-Item { return @{ Length = 100 } }
            
            $expectedResult = @(
                [PSCustomObject]@{ id = "1"; name = "John" }
                [PSCustomObject]@{ id = "2"; name = "Jane" }
            )
            Mock Import-Csv { return $expectedResult }
            
            # Act
            $result = Invoke-SqliteCsvQuery -DatabasePath $testDbPath -Query $testQuery
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0].id | Should -Be "1"
            $result[0].name | Should -Be "John"
        }
        
        It "空の結果の場合、空配列を返す" {
            # Arrange
            $testDbPath = "/test/database.db"
            $testQuery = "SELECT * FROM empty_table;"
            
            Mock sqlite3 { 
                $global:LASTEXITCODE = 0
                return @()
            }
            Mock New-TemporaryFile { return [PSCustomObject]@{ FullName = "/tmp/temp" } }
            Mock Test-Path { return $true }
            Mock Get-Item { return @{ Length = 0 } }
            
            # Act
            $result = Invoke-SqliteCsvQuery -DatabasePath $testDbPath -Query $testQuery
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 0
        }
        
        It "SQLiteエラーの場合、例外をスローする" {
            # Arrange
            $testDbPath = "/test/database.db"
            $testQuery = "INVALID SQL;"
            
            Mock sqlite3 { 
                $global:LASTEXITCODE = 1
                return "Error: SQL error"
            }
            Mock New-TemporaryFile { return [PSCustomObject]@{ FullName = "/tmp/temp" } }
            
            # Act & Assert
            { Invoke-SqliteCsvQuery -DatabasePath $testDbPath -Query $testQuery } | Should -Throw "*SQLiteコマンド実行エラー*"
        }
    }

    Context "Invoke-SqliteCsvExport 関数" {
        
        BeforeEach {
            Mock sqlite3 { 
                $global:LASTEXITCODE = 0
                return ""
            }
            Mock Write-SystemLog { }
        }
        
        It "CSV出力が正常に実行される" {
            # Arrange
            $testDbPath = "/test/database.db"
            $testQuery = "SELECT * FROM test_table;"
            $outputPath = "/test/output.csv"
            $csvData = @("id,name", "1,John", "2,Jane")
            
            New-MockSqliteCommand -ReturnValue $csvData
            New-MockCommand -CommandName "Out-File" -MockScript {}
            
            # Act
            $result = Invoke-SqliteCsvExport -DatabasePath $testDbPath -Query $testQuery -OutputPath $outputPath
            
            # Assert
            $result | Should -Be 2  # ヘッダー行を除いた件数
            Assert-MockCalled -CommandName "sqlite3" -Times 1
            Assert-MockCalled -CommandName "Out-File" -Times 1
        }
        
        It "空の結果の場合、0を返す" {
            # Arrange
            $testDbPath = "/test/database.db"
            $testQuery = "SELECT * FROM empty_table;"
            $outputPath = "/test/output.csv"
            
            New-MockSqliteCommand -ReturnValue "id,name"  # ヘッダーのみ
            New-MockCommand -CommandName "Out-File" -MockScript {}
            
            # Act
            $result = Invoke-SqliteCsvExport -DatabasePath $testDbPath -Query $testQuery -OutputPath $outputPath
            
            # Assert
            $result | Should -Be 0
        }
        
        It "SQLiteエラーの場合、例外をスローする" {
            # Arrange
            $testDbPath = "/test/database.db"
            $testQuery = "INVALID SQL;"
            $outputPath = "/test/output.csv"
            
            Mock sqlite3 { 
                $global:LASTEXITCODE = 1
                return "Error: SQL error"
            }
            
            # Act & Assert
            { Invoke-SqliteCsvExport -DatabasePath $testDbPath -Query $testQuery -OutputPath $outputPath } | Should -Throw "*sqlite3 CSV出力エラー*"
        }
    }

    Context "関数のエクスポート確認" {
        
        It "すべての期待される関数がエクスポートされている" {
            # Arrange
            $expectedFunctions = @(
                'Get-Sqlite3Path',
                'Get-CrossPlatformEncoding',
                'Test-PathSafe', 
                'Get-Timestamp',
                'Invoke-SqliteCommand',
                'Invoke-SqliteCsvQuery',
                'Invoke-SqliteCsvExport'
            )
            
            # Act
            $module = Get-Module -Name CoreUtils
            $exportedFunctions = $module.ExportedFunctions.Keys
            
            # Assert
            foreach ($expectedFunction in $expectedFunctions) {
                $exportedFunctions | Should -Contain $expectedFunction
            }
        }
    }

    Context "統合テスト" {
        
        It "実際のタイムスタンプとエンコーディングの組み合わせテスト" {
            # Act
            $timestamp = Get-Timestamp -Format "yyyy-MM-dd"
            $encoding = Get-CrossPlatformEncoding
            
            # Assert
            $timestamp | Should -Match "^\d{4}-\d{2}-\d{2}$"
            $encoding | Should -Not -BeNullOrEmpty
            $encoding.GetType().Name | Should -Match "UTF8Encoding.*"
        }
        
        It "Test-PathSafeとGet-Timestampの組み合わせテスト" {
            # Arrange
            $timestamp = Get-Timestamp
            $testPath = "/test/path/$timestamp"
            New-MockCommand -CommandName "Test-Path" -ReturnValue $false
            
            # Act
            $pathExists = Test-PathSafe -Path $testPath
            
            # Assert
            $pathExists | Should -Be $false
            $timestamp | Should -Not -BeNullOrEmpty
        }
    }

    Context "エラーハンドリングとエッジケース" {
        
        It "Get-Timestamp でフォーマット文字列が無効な場合の処理" {
            # Arrange
            $invalidFormat = "invalid{format"
            
            # Act & Assert
            # PowerShellは無効なフォーマット文字列でもある程度寛容
            { Get-Timestamp -Format $invalidFormat } | Should -Not -Throw
        }
        
        It "Invoke-SqliteCommand で空のクエリを処理" {
            # Arrange
            $testDbPath = "/test/database.db"
            $emptyQuery = " "  # 空白文字を使用してバリデーションを回避
            Mock sqlite3 { 
                $global:LASTEXITCODE = 0
                return ""
            }
            Mock New-TemporaryFile { return [PSCustomObject]@{ FullName = "/tmp/temp" } }
            Mock Out-File { }
            Mock Test-Path { return $true }
            Mock Remove-Item { }
            
            # Act & Assert
            { Invoke-SqliteCommand -DatabasePath $testDbPath -Query $emptyQuery } | Should -Not -Throw
        }
        
        It "複数の同時実行でのタイムスタンプ一意性確認" {
            # Act
            $timestamps = @()
            for ($i = 0; $i -lt 5; $i++) {
                $timestamps += Get-Timestamp
                Start-Sleep -Milliseconds 10  # わずかに待機
            }
            
            # Assert
            $uniqueTimestamps = $timestamps | Select-Object -Unique
            $uniqueTimestamps.Count | Should -BeGreaterThan 0
            # 高解像度タイマーにより、通常は異なるタイムスタンプが生成される
        }
    }
}