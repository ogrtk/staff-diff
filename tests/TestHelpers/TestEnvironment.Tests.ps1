# TestEnvironmentクラスの動作確認テスト

using module "./TestEnvironmentHelpers.psm1"

Describe "TestEnvironmentクラス 動作確認テスト" {
    
    BeforeEach {
        # テスト用環境変数の設定
        $env:PESTER_TEST = $true
    }
    
    AfterEach {
        # 環境変数のクリーンアップ
        Remove-Item Env:PESTER_TEST -ErrorAction SilentlyContinue
    }
    
    Context "TestEnvironment基本機能" {
        
        It "TestEnvironmentオブジェクトが正常に作成される" {
            # Arrange & Act
            $testEnv = [TestEnvironment]::new("BasicTest")
            
            # Assert
            $testEnv | Should -Not -BeNullOrEmpty
            $testEnv.GetTestInstanceId() | Should -Match "BasicTest_\d{8}_\d{6}_\d{4}"
            $testEnv.GetTempDirectory() | Should -Exist
            
            # Cleanup
            $testEnv.Dispose()
        }
        
        It "一時ディレクトリが適切に構造化されている" {
            # Arrange & Act
            $testEnv = [TestEnvironment]::new("StructureTest")
            
            # Assert
            $tempDir = $testEnv.GetTempDirectory()
            Test-Path (Join-Path $tempDir "databases") | Should -Be $true
            Test-Path (Join-Path $tempDir "csv-data") | Should -Be $true
            Test-Path (Join-Path $tempDir "config") | Should -Be $true
            Test-Path (Join-Path $tempDir "logs") | Should -Be $true
            Test-Path (Join-Path $tempDir "provided-data-history") | Should -Be $true
            Test-Path (Join-Path $tempDir "current-data-history") | Should -Be $true
            Test-Path (Join-Path $tempDir "output-history") | Should -Be $true
            
            # Cleanup
            $testEnv.Dispose()
        }
        
        It "データベースが正常に作成される" {
            # Arrange
            $testEnv = [TestEnvironment]::new("DatabaseTest")
            
            # Act
            $dbPath = $testEnv.CreateDatabase("test_db")
            
            # Assert
            $dbPath | Should -Exist
            $dbPath | Should -Match ".*databases[\\/]test_db\.db$"
            $testEnv.GetDatabasePath() | Should -Be $dbPath
            
            # Cleanup
            $testEnv.Dispose()
        }
        
        It "CSVファイルが正常に作成される" {
            # Arrange
            $testEnv = [TestEnvironment]::new("CsvTest")
            
            # Act
            $csvPath = $testEnv.CreateCsvFile("provided_data", 5, @{
                IncludeHeader = $true
                IncludeJapanese = $false
            })
            
            # Assert
            $csvPath | Should -Exist
            $csvPath | Should -Match ".*csv-data[\\/]provided_data_5records\.csv$"
            
            # CSVファイルの内容確認
            $csvContent = Get-Content $csvPath
            $csvContent.Count | Should -BeGreaterThan 5  # ヘッダー + 5レコード
            $csvContent[0] | Should -Match "employee_id.*card_number.*name"  # ヘッダー確認
            
            # Cleanup
            $testEnv.Dispose()
        }
        
        It "設定ファイルが正常に作成される" {
            # Arrange
            $testEnv = [TestEnvironment]::new("ConfigTest")
            $customSettings = @{
                version = "2.0.0"
                description = "カスタムテスト設定"
            }
            
            # Act
            $configPath = $testEnv.CreateConfigFile($customSettings, "custom-config")
            
            # Assert
            $configPath | Should -Exist
            $configPath | Should -Match ".*config[\\/]custom-config\.json$"
            $testEnv.GetConfigPath() | Should -Be $configPath
            
            # 設定ファイルの内容確認
            $configContent = Get-Content $configPath -Raw | ConvertFrom-Json
            $configContent.version | Should -Be "2.0.0"
            $configContent.description | Should -Be "カスタムテスト設定"
            $configContent.file_paths.provided_data_file_path | Should -Match ".*csv-data[\\/]provided_data\.csv$"
            
            # Cleanup
            $testEnv.Dispose()
        }
        
        It "一時ファイルが正常に作成される" {
            # Arrange
            $testEnv = [TestEnvironment]::new("TempFileTest")
            $testContent = "テスト用コンテンツです"
            
            # Act
            $tempFilePath = $testEnv.CreateTempFile($testContent, ".txt", "temp_")
            
            # Assert
            $tempFilePath | Should -Exist
            Get-Content $tempFilePath -Raw | Should -Be "$testContent`r`n"
            
            # Cleanup
            $testEnv.Dispose()
        }
    }
    
    Context "TestEnvironment リソース管理" {
        
        It "Disposeメソッドが正常にクリーンアップを実行する" {
            # Arrange
            $testEnv = [TestEnvironment]::new("DisposeTest")
            $tempDir = $testEnv.GetTempDirectory()
            
            # いくつかのファイルを作成
            $dbPath = $testEnv.CreateDatabase("dispose_test")
            $csvPath = $testEnv.CreateCsvFile("provided_data", 3)
            $configPath = $testEnv.CreateConfigFile(@{}, "dispose-config")
            
            # すべてのファイルが存在することを確認
            Test-Path $tempDir | Should -Be $true
            Test-Path $dbPath | Should -Be $true
            Test-Path $csvPath | Should -Be $true
            Test-Path $configPath | Should -Be $true
            
            # Act
            $testEnv.Dispose()
            
            # Assert
            Test-Path $tempDir | Should -Be $false  # メインディレクトリが削除されている
            Test-Path $dbPath | Should -Be $false   # 作成したファイルも削除されている
            Test-Path $csvPath | Should -Be $false
            Test-Path $configPath | Should -Be $false
            
            # Dispose後の操作でエラーが発生することを確認
            { $testEnv.CreateDatabase("after_dispose") } | Should -Throw "*既に破棄されています*"
        }
        
        It "重複Disposeが安全に処理される" {
            # Arrange
            $testEnv = [TestEnvironment]::new("DoubleDisposeTest")
            
            # Act & Assert
            { $testEnv.Dispose() } | Should -Not -Throw
            { $testEnv.Dispose() } | Should -Not -Throw  # 2回目のDisposeも安全
        }
    }
    
    Context "後方互換性確認" {
        
        It "New-TestEnvironment関数が正常にTestEnvironmentオブジェクトを返す" {
            # Act
            $testEnv = New-TestEnvironment -TestName "BackwardCompatTest"
            
            # Assert
            $testEnv | Should -BeOfType [TestEnvironment]
            $testEnv.GetTestInstanceId() | Should -Match "BackwardCompatTest_\d{8}_\d{6}_\d{4}"
            
            # Cleanup
            $testEnv.Dispose()
        }
        
        It "既存のNew-TestCsvData関数が警告と共に動作する" {
            # Arrange
            $tempDir = [System.IO.Path]::GetTempPath()
            $testCsvPath = Join-Path $tempDir "legacy_test.csv"
            
            try {
                # Act
                $warningMessages = @()
                $data = New-TestCsvData -DataType "provided_data" -RecordCount 3 -OutputPath $testCsvPath -IncludeHeader -WarningAction SilentlyContinue -WarningVariable warningMessages
                
                # Assert
                $data | Should -Not -BeNullOrEmpty
                $data.Count | Should -Be 3
                Test-Path $testCsvPath | Should -Be $true
                $warningMessages | Should -Contain "*非推奨*"
            }
            finally {
                # Cleanup
                if (Test-Path $testCsvPath) {
                    Remove-Item $testCsvPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}