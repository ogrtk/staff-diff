# PowerShell & SQLite データ同期システム
# Process/Invoke-ConfigValidation.psm1 ユニットテスト

# テスト環境の設定
$ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName
$ModulePath = Join-Path $ProjectRoot "scripts" "modules" "Process" "Invoke-ConfigValidation.psm1"
$TestHelpersPath = Join-Path $ProjectRoot "tests" "TestHelpers"

# テストヘルパーの読み込み
Import-Module (Join-Path $TestHelpersPath "LayeredTestHelpers.psm1") -Force
Import-Module (Join-Path $TestHelpersPath "MockHelpers.psm1") -Force
Import-Module (Join-Path $TestHelpersPath "TestDataGenerator.psm1") -Force

# 依存モジュールの読み込み（レイヤアーキテクチャ順）
# Import-LayeredModules -ProjectRoot $ProjectRoot -TargetLayers @("Foundation", "Infrastructure")

# テスト対象モジュールの読み込み
Import-Module $ModulePath -Force

Describe "Invoke-ConfigValidation モジュール" {
    
    BeforeAll {
        # テスト環境の初期化
        $script:TestEnv = Initialize-TestEnvironment -ProjectRoot $ProjectRoot
        $script:OriginalErrorActionPreference = $ErrorActionPreference
        
        # テスト用データの準備
        $script:ValidTestConfig = New-TestConfig
        $script:TestConfigPath = New-TempTestFile -Content ($script:ValidTestConfig | ConvertTo-Json -Depth 10) -Extension ".json" -Prefix "config_validation_"
    }
    
    AfterAll {
        # テスト環境のクリーンアップ
        Clear-TestEnvironment -ProjectRoot $ProjectRoot
        $ErrorActionPreference = $script:OriginalErrorActionPreference
        Reset-AllMocks
        
        # 一時ファイルのクリーンアップ
        if (Test-Path $script:TestConfigPath) {
            Remove-Item $script:TestConfigPath -Force -ErrorAction SilentlyContinue
        }
    }
    
    BeforeEach {
        Reset-AllMocks
        Mock-LoggingSystem -CaptureMessages -SuppressOutput
        Mock-ErrorHandling -BypassErrorHandling
    }

    Context "Invoke-ConfigValidation 関数 - 基本動作" {
        
        It "有効なパラメータで正常に処理を完了する" {
            # Arrange
            $testProjectRoot = $script:TestEnv.ProjectRoot
            $testDbPath = Join-Path $testProjectRoot "database" "test.db"
            $testProvidedPath = Join-Path $testProjectRoot "test-data" "provided.csv"
            $testCurrentPath = Join-Path $testProjectRoot "test-data" "current.csv"
            $testOutputPath = Join-Path $testProjectRoot "test-data" "output.csv"
            
            # 外部依存関数のモック化
            Mock-Command -CommandName "Get-Sqlite3Path" -ReturnValue @{ Source = "/usr/bin/sqlite3" }
            Mock-Command -CommandName "Get-DataSyncConfig" -ReturnValue $script:ValidTestConfig
            Mock-Command -CommandName "Test-DataSyncConfig" -MockScript {}
            Mock-Command -CommandName "Resolve-FilePath" -MockScript {
                param($ParameterPath, $ConfigKey, $Description)
                if (-not [string]::IsNullOrEmpty($ParameterPath)) {
                    return $ParameterPath
                }
                switch ($ConfigKey) {
                    "provided_data_file_path" { return $testProvidedPath }
                    "current_data_file_path" { return $testCurrentPath }
                    "output_file_path" { return $testOutputPath }
                }
            }
            Mock-Command -CommandName "Test-ResolvedFilePaths" -MockScript {}
            
            # Act
            $result = Invoke-ConfigValidation -ProjectRoot $testProjectRoot -DatabasePath $testDbPath -ProvidedDataFilePath $testProvidedPath -CurrentDataFilePath $testCurrentPath -OutputFilePath $testOutputPath -ConfigFilePath $script:TestConfigPath
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.DatabasePath | Should -Be $testDbPath
            $result.ProvidedDataFilePath | Should -Be $testProvidedPath
            $result.CurrentDataFilePath | Should -Be $testCurrentPath
            $result.OutputFilePath | Should -Be $testOutputPath
        }
        
        It "DatabasePathが未指定の場合、デフォルトパスを設定する" {
            # Arrange
            $testProjectRoot = $script:TestEnv.ProjectRoot
            $expectedDbPath = Join-Path $testProjectRoot "database" "data-sync.db"
            
            Mock-Command -CommandName "Get-Sqlite3Path" -ReturnValue @{ Source = "/usr/bin/sqlite3" }
            Mock-Command -CommandName "Get-DataSyncConfig" -ReturnValue $script:ValidTestConfig
            Mock-Command -CommandName "Test-DataSyncConfig" -MockScript {}
            Mock-Command -CommandName "Resolve-FilePath" -ReturnValue "/test/file.csv"
            Mock-Command -CommandName "Test-ResolvedFilePaths" -MockScript {}
            
            # Act
            $result = Invoke-ConfigValidation -ProjectRoot $testProjectRoot
            
            # Assert
            $result.DatabasePath | Should -Be $expectedDbPath
        }
        
        It "設定ファイル読み込みが正常に実行される" {
            # Arrange
            $testProjectRoot = $script:TestEnv.ProjectRoot
            
            Mock-Command -CommandName "Get-Sqlite3Path" -ReturnValue @{ Source = "/usr/bin/sqlite3" }
            Mock-Command -CommandName "Test-DataSyncConfig" -MockScript {}
            Mock-Command -CommandName "Resolve-FilePath" -ReturnValue "/test/file.csv"
            Mock-Command -CommandName "Test-ResolvedFilePaths" -MockScript {}
            
            $getConfigCallCount = 0
            Mock-Command -CommandName "Get-DataSyncConfig" -MockScript {
                $script:getConfigCallCount++
                return $script:ValidTestConfig
            }
            
            # Act
            $result = Invoke-ConfigValidation -ProjectRoot $testProjectRoot
            
            # Assert
            $getConfigCallCount | Should -Be 1
            Assert-MockCalled -CommandName "Test-DataSyncConfig" -Times 1
        }
    }

    Context "Invoke-ConfigValidation 関数 - 外部依存関係検証" {
        
        It "SQLite3コマンドが利用可能な場合、成功メッセージをログ出力する" {
            # Arrange
            $testProjectRoot = $script:TestEnv.ProjectRoot
            $mockSqlite3 = @{ Source = "/usr/bin/sqlite3" }
            
            Mock-Command -CommandName "Get-Sqlite3Path" -ReturnValue $mockSqlite3
            Mock-Command -CommandName "Get-DataSyncConfig" -ReturnValue $script:ValidTestConfig
            Mock-Command -CommandName "Test-DataSyncConfig" -MockScript {}
            Mock-Command -CommandName "Resolve-FilePath" -ReturnValue "/test/file.csv"
            Mock-Command -CommandName "Test-ResolvedFilePaths" -MockScript {}
            
            # Act
            Invoke-ConfigValidation -ProjectRoot $testProjectRoot
            
            # Assert
            $logMessages = Get-CapturedLogMessages -Level "Success"
            ($logMessages | Where-Object { $_.Message -match "SQLite3コマンドが利用可能です" }) | Should -Not -BeNullOrEmpty
        }
        
        It "SQLite3コマンドが見つからない場合、エラーをスローする" {
            # Arrange
            $testProjectRoot = $script:TestEnv.ProjectRoot
            
            Mock-Command -CommandName "Get-Sqlite3Path" -MockScript {
                throw "sqlite3コマンドが見つかりません"
            }
            
            # Act & Assert
            { Invoke-ConfigValidation -ProjectRoot $testProjectRoot } | Should -Throw "*sqlite3コマンドが見つかりません*"
        }
    }

    Context "Invoke-ConfigValidation 関数 - ファイルパス解決" {
        
        It "パラメータで指定されたパスが優先される" {
            # Arrange
            $testProjectRoot = $script:TestEnv.ProjectRoot
            $providedPath = "/param/provided.csv"
            $currentPath = "/param/current.csv"
            $outputPath = "/param/output.csv"
            
            Mock-Command -CommandName "Get-Sqlite3Path" -ReturnValue @{ Source = "/usr/bin/sqlite3" }
            Mock-Command -CommandName "Get-DataSyncConfig" -ReturnValue $script:ValidTestConfig
            Mock-Command -CommandName "Test-DataSyncConfig" -MockScript {}
            Mock-Command -CommandName "Test-ResolvedFilePaths" -MockScript {}
            
            # Resolve-FilePathの呼び出しをモックして、パラメータが正しく渡されることを確認
            $resolveFilePathCalls = @()
            Mock-Command -CommandName "Resolve-FilePath" -MockScript {
                param($ParameterPath, $ConfigKey, $Description)
                $script:resolveFilePathCalls += @{
                    ParameterPath = $ParameterPath
                    ConfigKey     = $ConfigKey
                    Description   = $Description
                }
                return $ParameterPath  # パラメータで指定された値をそのまま返す
            }
            
            # Act
            $result = Invoke-ConfigValidation -ProjectRoot $testProjectRoot -ProvidedDataFilePath $providedPath -CurrentDataFilePath $currentPath -OutputFilePath $outputPath
            
            # Assert
            $result.ProvidedDataFilePath | Should -Be $providedPath
            $result.CurrentDataFilePath | Should -Be $currentPath
            $result.OutputFilePath | Should -Be $outputPath
            
            # Resolve-FilePathが適切なパラメータで呼び出されたことを確認
            $resolveFilePathCalls.Count | Should -Be 3
            $resolveFilePathCalls[0].ConfigKey | Should -Be "provided_data_file_path"
            $resolveFilePathCalls[1].ConfigKey | Should -Be "current_data_file_path"
            $resolveFilePathCalls[2].ConfigKey | Should -Be "output_file_path"
        }
        
        It "パラメータが未指定の場合、設定ファイルから解決される" {
            # Arrange
            $testProjectRoot = $script:TestEnv.ProjectRoot
            $configProvidedPath = "/config/provided.csv"
            $configCurrentPath = "/config/current.csv"
            $configOutputPath = "/config/output.csv"
            
            Mock-Command -CommandName "Get-Sqlite3Path" -ReturnValue @{ Source = "/usr/bin/sqlite3" }
            Mock-Command -CommandName "Get-DataSyncConfig" -ReturnValue $script:ValidTestConfig
            Mock-Command -CommandName "Test-DataSyncConfig" -MockScript {}
            Mock-Command -CommandName "Test-ResolvedFilePaths" -MockScript {}
            
            Mock-Command -CommandName "Resolve-FilePath" -MockScript {
                param($ParameterPath, $ConfigKey, $Description)
                if ([string]::IsNullOrEmpty($ParameterPath)) {
                    switch ($ConfigKey) {
                        "provided_data_file_path" { return $configProvidedPath }
                        "current_data_file_path" { return $configCurrentPath }
                        "output_file_path" { return $configOutputPath }
                    }
                }
                return $ParameterPath
            }
            
            # Act
            $result = Invoke-ConfigValidation -ProjectRoot $testProjectRoot
            
            # Assert
            $result.ProvidedDataFilePath | Should -Be $configProvidedPath
            $result.CurrentDataFilePath | Should -Be $configCurrentPath
            $result.OutputFilePath | Should -Be $configOutputPath
        }
    }

    Context "Invoke-ConfigValidation 関数 - ファイル存在チェック" {
        
        It "解決されたパスでファイル存在チェックが実行される" {
            # Arrange
            $testProjectRoot = $script:TestEnv.ProjectRoot
            $resolvedPaths = @{
                DatabasePath         = "/test/db.db"
                ProvidedDataFilePath = "/test/provided.csv"
                CurrentDataFilePath  = "/test/current.csv"
                OutputFilePath       = "/test/output.csv"
            }
            
            Mock-Command -CommandName "Get-Sqlite3Path" -ReturnValue @{ Source = "/usr/bin/sqlite3" }
            Mock-Command -CommandName "Get-DataSyncConfig" -ReturnValue $script:ValidTestConfig
            Mock-Command -CommandName "Test-DataSyncConfig" -MockScript {}
            Mock-Command -CommandName "Resolve-FilePath" -ReturnValue "/test/resolved.csv"
            
            $testResolvedFilePathsCalled = $false
            $capturedResolvedPaths = $null
            Mock-Command -CommandName "Test-ResolvedFilePaths" -MockScript {
                param($ResolvedPaths)
                $script:testResolvedFilePathsCalled = $true
                $script:capturedResolvedPaths = $ResolvedPaths
            }
            
            # Act
            Invoke-ConfigValidation -ProjectRoot $testProjectRoot
            
            # Assert
            $testResolvedFilePathsCalled | Should -Be $true
            $capturedResolvedPaths | Should -Not -BeNullOrEmpty
            $capturedResolvedPaths.Keys | Should -Contain "DatabasePath"
            $capturedResolvedPaths.Keys | Should -Contain "ProvidedDataFilePath"
            $capturedResolvedPaths.Keys | Should -Contain "CurrentDataFilePath"
            $capturedResolvedPaths.Keys | Should -Contain "OutputFilePath"
        }
        
        It "ファイル存在チェックでエラーが発生した場合、例外をスローする" {
            # Arrange
            $testProjectRoot = $script:TestEnv.ProjectRoot
            
            Mock-Command -CommandName "Get-Sqlite3Path" -ReturnValue @{ Source = "/usr/bin/sqlite3" }
            Mock-Command -CommandName "Get-DataSyncConfig" -ReturnValue $script:ValidTestConfig
            Mock-Command -CommandName "Test-DataSyncConfig" -MockScript {}
            Mock-Command -CommandName "Resolve-FilePath" -ReturnValue "/test/file.csv"
            Mock-Command -CommandName "Test-ResolvedFilePaths" -MockScript {
                throw "ファイルが見つかりません"
            }
            
            # Act & Assert
            { Invoke-ConfigValidation -ProjectRoot $testProjectRoot } | Should -Throw "*ファイルが見つかりません*"
        }
    }

    Context "Invoke-ConfigValidation 関数 - ログ出力" {
        
        It "処理パラメータが適切にログ出力される" {
            # Arrange
            $testProjectRoot = $script:TestEnv.ProjectRoot
            $testDbPath = "/test/database.db"
            $testProvidedPath = "/test/provided.csv"
            $testCurrentPath = "/test/current.csv"
            $testOutputPath = "/test/output.csv"
            
            Mock-Command -CommandName "Get-Sqlite3Path" -ReturnValue @{ Source = "/usr/bin/sqlite3" }
            Mock-Command -CommandName "Get-DataSyncConfig" -ReturnValue $script:ValidTestConfig
            Mock-Command -CommandName "Test-DataSyncConfig" -MockScript {}
            Mock-Command -CommandName "Resolve-FilePath" -MockScript {
                param($ParameterPath, $ConfigKey, $Description)
                switch ($ConfigKey) {
                    "provided_data_file_path" { return $testProvidedPath }
                    "current_data_file_path" { return $testCurrentPath }
                    "output_file_path" { return $testOutputPath }
                }
            }
            Mock-Command -CommandName "Test-ResolvedFilePaths" -MockScript {}
            
            # Act
            Invoke-ConfigValidation -ProjectRoot $testProjectRoot -DatabasePath $testDbPath
            
            # Assert
            $logMessages = Get-CapturedLogMessages -Level "Info"
            ($logMessages | Where-Object { $_.Message -match "Database Path: $testDbPath" }) | Should -Not -BeNullOrEmpty
            ($logMessages | Where-Object { $_.Message -match "Provided Data File: $testProvidedPath" }) | Should -Not -BeNullOrEmpty
            ($logMessages | Where-Object { $_.Message -match "Current Data File: $testCurrentPath" }) | Should -Not -BeNullOrEmpty
            ($logMessages | Where-Object { $_.Message -match "Output File: $testOutputPath" }) | Should -Not -BeNullOrEmpty
        }
        
        It "各処理段階で適切な進捗ログが出力される" {
            # Arrange
            $testProjectRoot = $script:TestEnv.ProjectRoot
            
            Mock-Command -CommandName "Get-Sqlite3Path" -ReturnValue @{ Source = "/usr/bin/sqlite3" }
            Mock-Command -CommandName "Get-DataSyncConfig" -ReturnValue $script:ValidTestConfig
            Mock-Command -CommandName "Test-DataSyncConfig" -MockScript {}
            Mock-Command -CommandName "Resolve-FilePath" -ReturnValue "/test/file.csv"
            Mock-Command -CommandName "Test-ResolvedFilePaths" -MockScript {}
            
            # Act
            Invoke-ConfigValidation -ProjectRoot $testProjectRoot
            
            # Assert
            $logMessages = Get-CapturedLogMessages -Level "Info"
            ($logMessages | Where-Object { $_.Message -match "外部依存関係を検証中" }) | Should -Not -BeNullOrEmpty
            ($logMessages | Where-Object { $_.Message -match "システム設定を検証中" }) | Should -Not -BeNullOrEmpty
            ($logMessages | Where-Object { $_.Message -match "ファイルパス解決処理を開始" }) | Should -Not -BeNullOrEmpty
            ($logMessages | Where-Object { $_.Message -match "入力ファイル・出力フォルダの存在チェック中" }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Test-ResolvedFilePaths 関数" {
        
        It "すべてのファイルが存在する場合、正常に完了する" {
            # Arrange
            $resolvedPaths = @{
                ProvidedDataFilePath = "/existing/provided.csv"
                CurrentDataFilePath  = "/existing/current.csv"
                OutputFilePath       = "/existing/output.csv"
            }
            
            Mock-Command -CommandName "Test-Path" -MockScript {
                param($Path)
                return $Path -match "existing"
            }
            
            # Act & Assert
            { Test-ResolvedFilePaths -ResolvedPaths $resolvedPaths } | Should -Not -Throw
        }
        
        It "提供データファイルが存在しない場合、エラーをスローする" {
            # Arrange
            $resolvedPaths = @{
                ProvidedDataFilePath = "/missing/provided.csv"
                CurrentDataFilePath  = "/existing/current.csv"
                OutputFilePath       = "/existing/output.csv"
            }
            
            Mock-Command -CommandName "Test-Path" -MockScript {
                param($Path)
                return $Path -match "existing"
            }
            
            # Act & Assert
            { Test-ResolvedFilePaths -ResolvedPaths $resolvedPaths } | Should -Throw "*提供データファイルが見つかりません*"
        }
        
        It "現在データファイルが存在しない場合、エラーをスローする" {
            # Arrange
            $resolvedPaths = @{
                ProvidedDataFilePath = "/existing/provided.csv"
                CurrentDataFilePath  = "/missing/current.csv"
                OutputFilePath       = "/existing/output.csv"
            }
            
            Mock-Command -CommandName "Test-Path" -MockScript {
                param($Path)
                return $Path -match "existing"
            }
            
            # Act & Assert
            { Test-ResolvedFilePaths -ResolvedPaths $resolvedPaths } | Should -Throw "*現在データファイルが見つかりません*"
        }
        
        It "出力ディレクトリが存在しない場合、エラーをスローする" {
            # Arrange
            $resolvedPaths = @{
                ProvidedDataFilePath = "/existing/provided.csv"
                CurrentDataFilePath  = "/existing/current.csv"
                OutputFilePath       = "/missing_dir/output.csv"
            }
            
            Mock-Command -CommandName "Test-Path" -MockScript {
                param($Path)
                if ($Path -eq "/missing_dir") {
                    return $false
                }
                return $Path -match "existing"
            }
            
            Mock-Command -CommandName "Split-Path" -MockScript {
                param($Path, $Parent)
                if ($Parent -and $Path -eq "/missing_dir/output.csv") {
                    return "/missing_dir"
                }
                return "/existing"
            }
            
            # Act & Assert
            { Test-ResolvedFilePaths -ResolvedPaths $resolvedPaths } | Should -Throw "*出力ディレクトリが存在しません*"
        }
    }

    Context "関数のエクスポート確認" {
        
        It "Invoke-ConfigValidation 関数がエクスポートされている" {
            # Act
            $module = Get-Module -Name Invoke-ConfigValidation
            $exportedFunctions = $module.ExportedFunctions.Keys
            
            # Assert
            $exportedFunctions | Should -Contain "Invoke-ConfigValidation"
        }
    }

    Context "エラーハンドリングとエッジケース" {
        
        It "空のProjectRootパラメータでエラーをスローする" {
            # Act & Assert
            { Invoke-ConfigValidation -ProjectRoot "" } | Should -Throw
        }
        
        It "無効なProjectRootパスでエラーをスローする" {
            # Act & Assert
            { Invoke-ConfigValidation -ProjectRoot "/nonexistent/path" } | Should -Throw
        }
        
        It "設定検証でエラーが発生した場合、適切にエラーをスローする" {
            # Arrange
            $testProjectRoot = $script:TestEnv.ProjectRoot
            
            Mock-Command -CommandName "Get-Sqlite3Path" -ReturnValue @{ Source = "/usr/bin/sqlite3" }
            Mock-Command -CommandName "Get-DataSyncConfig" -ReturnValue $script:ValidTestConfig
            Mock-Command -CommandName "Test-DataSyncConfig" -MockScript {
                throw "設定検証エラー"
            }
            
            # Act & Assert
            { Invoke-ConfigValidation -ProjectRoot $testProjectRoot } | Should -Throw "*設定検証エラー*"
        }
        
        It "複数のパラメータが同時に指定された場合の優先順位" {
            # Arrange
            $testProjectRoot = $script:TestEnv.ProjectRoot
            $allPaths = @{
                DatabasePath         = "/param/database.db"
                ProvidedDataFilePath = "/param/provided.csv"
                CurrentDataFilePath  = "/param/current.csv"
                OutputFilePath       = "/param/output.csv"
                ConfigFilePath       = $script:TestConfigPath
            }
            
            Mock-Command -CommandName "Get-Sqlite3Path" -ReturnValue @{ Source = "/usr/bin/sqlite3" }
            Mock-Command -CommandName "Get-DataSyncConfig" -ReturnValue $script:ValidTestConfig
            Mock-Command -CommandName "Test-DataSyncConfig" -MockScript {}
            Mock-Command -CommandName "Resolve-FilePath" -MockScript {
                param($ParameterPath, $ConfigKey, $Description)
                return $ParameterPath  # パラメータ値をそのまま返す
            }
            Mock-Command -CommandName "Test-ResolvedFilePaths" -MockScript {}
            
            # Act
            $result = Invoke-ConfigValidation -ProjectRoot $testProjectRoot @allPaths
            
            # Assert
            $result.DatabasePath | Should -Be $allPaths.DatabasePath
            $result.ProvidedDataFilePath | Should -Be $allPaths.ProvidedDataFilePath
            $result.CurrentDataFilePath | Should -Be $allPaths.CurrentDataFilePath
            $result.OutputFilePath | Should -Be $allPaths.OutputFilePath
        }
        
        It "非常に長いファイルパスでも正常に処理される" {
            # Arrange
            $testProjectRoot = $script:TestEnv.ProjectRoot
            $longPath = "/" + ("very_long_directory_name" * 10) + "/file.csv"
            
            Mock-Command -CommandName "Get-Sqlite3Path" -ReturnValue @{ Source = "/usr/bin/sqlite3" }
            Mock-Command -CommandName "Get-DataSyncConfig" -ReturnValue $script:ValidTestConfig
            Mock-Command -CommandName "Test-DataSyncConfig" -MockScript {}
            Mock-Command -CommandName "Resolve-FilePath" -ReturnValue $longPath
            Mock-Command -CommandName "Test-ResolvedFilePaths" -MockScript {}
            
            # Act
            $result = Invoke-ConfigValidation -ProjectRoot $testProjectRoot -ProvidedDataFilePath $longPath
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.ProvidedDataFilePath | Should -Be $longPath
        }
    }
}