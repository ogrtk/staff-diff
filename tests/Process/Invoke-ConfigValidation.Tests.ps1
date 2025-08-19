# PowerShell & SQLite データ同期システム
# Process/Invoke-ConfigValidation.psm1 ユニットテスト

# テストヘルパーを最初にインポート
using module "../TestHelpers/LayeredTestHelpers.psm1"
using module "../TestHelpers/MockHelpers.psm1"
using module "../TestHelpers/TestDataGenerator.psm1"

# 依存関係のモジュールをインポート（モック化準備のため）
using module "../../scripts/modules/Utils/Foundation/CoreUtils.psm1"
using module "../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1" 
using module "../../scripts/modules/Utils/Infrastructure/LoggingUtils.psm1" 
using module "../../scripts/modules/Utils/Infrastructure/ErrorHandlingUtils.psm1"
using module "../../scripts/modules/Utils/DataAccess/DatabaseUtils.psm1" 
using module "../../scripts/modules/Utils/DataAccess/FileSystemUtils.psm1"

# テスト対象モジュールを最後にインポート
using module "../../scripts/modules/Process/Invoke-ConfigValidation.psm1" 

Describe "Invoke-ConfigValidation モジュール" {
    
    BeforeAll {
        $script:ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName

        # テスト環境の初期化
        $script:TestEnv = Initialize-TestEnvironment -ProjectRoot $script:ProjectRoot
        $script:OriginalErrorActionPreference = $ErrorActionPreference
        
        # テスト用データの準備
        $script:ValidTestConfig = New-TestConfig
        $script:TestConfigPath = New-TempTestFile -Content ($script:ValidTestConfig | ConvertTo-Json -Depth 10) -Extension ".json" -Prefix "config_validation_"
    }
    
    AfterAll {
        # テスト環境のクリーンアップ
        $ErrorActionPreference = $script:OriginalErrorActionPreference
        
        # 一時ファイルのクリーンアップ
        if ($script:TestConfigPath -and (Test-Path $script:TestConfigPath)) {
            Remove-Item $script:TestConfigPath -Force -ErrorAction SilentlyContinue
        }
    }
    
    BeforeEach {
        # 基本的なモック化
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Write-SystemLog { }
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Invoke-WithErrorHandling { 
            param($ScriptBlock, $Category, $Operation, $Context)
            & $ScriptBlock
        }
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Get-Sqlite3Path { return @{ Source = "/usr/bin/sqlite3" } }
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Get-DataSyncConfig { return $script:ValidTestConfig }
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Test-DataSyncConfig { }
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath { return "/test/file.csv" }
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Test-Path { return $true }
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Get-DataSyncConfig {
            return $script:ValidTestConfig
        }

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
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath {
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
            
            # Act
            $result = Invoke-ConfigValidation -DatabasePath $testDbPath -ProvidedDataFilePath $testProvidedPath -CurrentDataFilePath $testCurrentPath -OutputFilePath $testOutputPath -ConfigFilePath $script:TestConfigPath
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.DatabasePath | Should -Be $testDbPath
            $result.ProvidedDataFilePath | Should -Be $testProvidedPath
            $result.CurrentDataFilePath | Should -Be $testCurrentPath
            $result.OutputFilePath | Should -Be $testOutputPath
        }
        
        It "DatabasePathが未指定の場合、デフォルトパスを設定する" {
            # Act
            $result = Invoke-ConfigValidation
            
            # Assert
            $expectedDbPath = Join-Path ( Find-ProjectRoot ) "database" "data-sync.db"
            $result.DatabasePath | Should -Be $expectedDbPath
        }
        
        It "設定ファイル読み込みが正常に実行される" {
            # Act
            Invoke-ConfigValidation
            
            # Assert
            Should -Invoke -ModuleName "Invoke-ConfigValidation" -CommandName Get-DataSyncConfig -Exactly 1 -Scope It
            Should -Invoke -ModuleName "Invoke-ConfigValidation" -CommandName Test-DataSyncConfig -Exactly 1 -Scope It
        }
    }

    Context "Invoke-ConfigValidation 関数 - 外部依存関係検証" {
        
        It "SQLite3コマンドが利用可能な場合、成功メッセージをログ出力する" {
            # Act
            Invoke-ConfigValidation
            
            # Assert
            Should -Invoke -ModuleName "Invoke-ConfigValidation" -CommandName Write-SystemLog -ParameterFilter { $Message -match "SQLite3コマンドが利用可能です" } -Scope It
        }
        
        It "SQLite3コマンドが見つからない場合、エラーをスローする" {
            # Arrange
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName "Get-Sqlite3Path" {
                throw "sqlite3コマンドが見つかりません"
            }
            
            # Act & Assert
            { Invoke-ConfigValidation } | Should -Throw "*sqlite3コマンドが見つかりません*"
        }
    }

    Context "Invoke-ConfigValidation 関数 - ファイルパス解決" {
        
        It "パラメータで指定されたパスが優先される" {
            # Arrange
            $providedPath = "/param/provided.csv"
            $currentPath = "/param/current.csv"
            $outputPath = "/param/output.csv"
            
            # Resolve-FilePathをモック（パラメータで指定された値をそのまま返す）
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath {
                param($ParameterPath, $ConfigKey, $Description)
                return $ParameterPath
            }
            
            # Act
            $result = Invoke-ConfigValidation -ProvidedDataFilePath $providedPath -CurrentDataFilePath $currentPath -OutputFilePath $outputPath
            
            # Assert - 結果確認
            $result.ProvidedDataFilePath | Should -Be $providedPath
            $result.CurrentDataFilePath | Should -Be $currentPath
            $result.OutputFilePath | Should -Be $outputPath
            
            # Assert - Resolve-FilePathが適切なパラメータで呼び出されたことを確認
            Should -Invoke -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath -Times 3
            Should -Invoke -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath -ParameterFilter {
                $ConfigKey -eq "provided_data_file_path" -and $ParameterPath -eq $providedPath
            } -Times 1
            Should -Invoke -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath -ParameterFilter {
                $ConfigKey -eq "current_data_file_path" -and $ParameterPath -eq $currentPath
            } -Times 1
            Should -Invoke -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath -ParameterFilter {
                $ConfigKey -eq "output_file_path" -and $ParameterPath -eq $outputPath
            } -Times 1
        }
        
        It "パラメータが未指定の場合、設定ファイルから解決される" {
            # Arrange
            $configProvidedPath = "/config/provided.csv"
            $configCurrentPath = "/config/current.csv"
            $configOutputPath = "/config/output.csv"
            
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath {
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
            $result = Invoke-ConfigValidation
            
            # Assert
            $result.ProvidedDataFilePath | Should -Be $configProvidedPath
            $result.CurrentDataFilePath | Should -Be $configCurrentPath
            $result.OutputFilePath | Should -Be $configOutputPath
        }
    }

    Context "Invoke-ConfigValidation 関数 - ファイル存在チェック" {
        
        It "解決されたパスでファイル存在チェックが実行される" {
            # Arrange
            $testProvidedPath = "/test/provided.csv"
            $testCurrentPath = "/test/current.csv"
            $testOutputPath = "/test/output.csv"
            
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath {
                param($ParameterPath, $ConfigKey, $Description)
                switch ($ConfigKey) {
                    "provided_data_file_path" { return $testProvidedPath }
                    "current_data_file_path" { return $testCurrentPath }
                    "output_file_path" { return $testOutputPath }
                }
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path {
                param($Path, $Parent)
                if ($Parent) { return "/test" }
                return $Path
            }
            
            # Act
            $result = Invoke-ConfigValidation
            
            # Assert
            Should -Invoke Test-Path -ModuleName "Invoke-ConfigValidation" -Times 2 -Scope it 
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "ファイル存在チェックでエラーが発生した場合、例外をスローする" {
            # Arrange
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Test-Path { 
                throw "ファイルが見つかりません"
            }
            
            # Act & Assert
            { Invoke-ConfigValidation } | Should -Throw "*ファイルが見つかりません*"
        }
    }

    Context "Invoke-ConfigValidation 関数 - ログ出力" {
        
        It "処理パラメータが適切にログ出力される" {
            # Arrange
            $testDbPath = "/test/database.db"
            $testProvidedPath = "/test/provided.csv"
            $testCurrentPath = "/test/current.csv"
            $testOutputPath = "/test/output.csv"
            
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath {
                param($ParameterPath, $ConfigKey, $Description)
                switch ($ConfigKey) {
                    "provided_data_file_path" { return $testProvidedPath }
                    "current_data_file_path" { return $testCurrentPath }
                    "output_file_path" { return $testOutputPath }
                }
            }
            
            # Act
            Invoke-ConfigValidation -DatabasePath $testDbPath
            
            # Assert
            Should -Invoke -ModuleName "Invoke-ConfigValidation" -CommandName Write-SystemLog -Times 1 -Scope It
        }
        
        It "各処理段階で適切な進捗ログが出力される" {
            # Act
            Invoke-ConfigValidation
            
            # Assert
            Should -Invoke -ModuleName "Invoke-ConfigValidation" -CommandName Write-SystemLog -Times 4 -Scope It
        }
    }

    Context "ファイル存在チェック（Test-ResolvedFilePaths経由）" {
        
        It "すべてのファイルが存在する場合、正常に完了する" {
            # Arrange
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath { 
                param($ParameterPath, $ConfigKey, $Description)
                switch ($ConfigKey) {
                    "provided_data_file_path" { return "/existing/provided.csv" }
                    "current_data_file_path" { return "/existing/current.csv" }
                    "output_file_path" { return "/existing/output.csv" }
                }
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Test-Path { 
                param($Path)
                return $Path -match "existing"
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path {
                param($Path, $Parent)
                if ($Parent) { return "/existing" }
                return $Path
            }
            
            # Act & Assert
            { Invoke-ConfigValidation } | Should -Not -Throw
        }
        
        It "提供データファイルが存在しない場合、エラーをスローする" {
            # Arrange
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath { 
                param($ParameterPath, $ConfigKey, $Description)
                switch ($ConfigKey) {
                    "provided_data_file_path" { return "/missing/provided.csv" }
                    "current_data_file_path" { return "/existing/current.csv" }
                    "output_file_path" { return "/existing/output.csv" }
                }
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Test-Path { 
                param($Path)
                return $Path -match "existing"
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path {
                param($Path, $Parent)
                if ($Parent) { return "/existing" }
                return $Path
            }
            
            # Act & Assert
            { Invoke-ConfigValidation } | Should -Throw "*提供データファイルが見つかりません*"
        }
        
        It "現在データファイルが存在しない場合、エラーをスローする" {
            # Arrange
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath { 
                param($ParameterPath, $ConfigKey, $Description)
                switch ($ConfigKey) {
                    "provided_data_file_path" { return "/existing/provided.csv" }
                    "current_data_file_path" { return "/missing/current.csv" }
                    "output_file_path" { return "/existing/output.csv" }
                }
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Test-Path { 
                param($Path)
                return $Path -match "existing"
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path {
                param($Path, $Parent)
                if ($Parent) { return "/existing" }
                return $Path
            }
            
            # Act & Assert
            { Invoke-ConfigValidation } | Should -Throw "*現在データファイルが見つかりません*"
        }
        
        It "出力ディレクトリが存在しない場合、エラーをスローする" {
            # Arrange
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath { 
                param($ParameterPath, $ConfigKey, $Description)
                switch ($ConfigKey) {
                    "provided_data_file_path" { return "/existing/provided.csv" }
                    "current_data_file_path" { return "/existing/current.csv" }
                    "output_file_path" { return "/missing_dir/output.csv" }
                }
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Test-Path { 
                param($Path)
                if ($Path -eq "/missing_dir") {
                    return $false
                }
                return $Path -match "existing"
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path {
                param($Path, $Parent)
                if ($Parent -and $Path -eq "/missing_dir/output.csv") {
                    return "/missing_dir"
                }
                return "/existing"
            }
            
            # Act & Assert
            { Invoke-ConfigValidation } | Should -Throw "*出力ディレクトリが存在しません*"
        }
    }

    Context "関数のエクスポート確認" {
        
        It "Invoke-ConfigValidation 関数がエクスポートされている" {
            # Arrange
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Get-Module {
                return @{
                    ExportedFunctions = @{
                        Keys = @("Invoke-ConfigValidation")
                    }
                }
            }
            
            # Act
            $module = Get-Module -Name Invoke-ConfigValidation
            $exportedFunctions = $module.ExportedFunctions.Keys
            
            # Assert
            $exportedFunctions | Should -Contain "Invoke-ConfigValidation"
        }
    }

    Context "エラーハンドリングとエッジケース" {
        
        It "空のProjectRootパラメータでエラーをスローする" {
            # Arrange
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Find-ProjectRoot {
                throw "空のプロジェクトルートパス"
            }
            
            # Act & Assert
            { Invoke-ConfigValidation } | Should -Throw "*空のプロジェクトルートパス*"
        }
        
        It "無効なProjectRootパスでエラーをスローする" {
            # Arrange
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Find-ProjectRoot {
                throw "無効なプロジェクトルートパス"
            }
            
            # Act & Assert
            { Invoke-ConfigValidation } | Should -Throw "*無効なプロジェクトルートパス*"
        }
        
        It "設定検証でエラーが発生した場合、適切にエラーをスローする" {
            # Arrange
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Test-DataSyncConfig {
                throw "設定検証エラー"
            }
            
            # Act & Assert
            { Invoke-ConfigValidation } | Should -Throw "*設定検証エラー*"
        }
        
        It "複数のパラメータが同時に指定された場合の優先順位" {
            # Arrange
            $allPaths = @{
                DatabasePath         = "/param/database.db"
                ProvidedDataFilePath = "/param/provided.csv"
                CurrentDataFilePath  = "/param/current.csv"
                OutputFilePath       = "/param/output.csv"
                ConfigFilePath       = $script:TestConfigPath
            }

            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath {
                param($ParameterPath, $ConfigKey, $Description)
                return $ParameterPath  # パラメータ値をそのまま返す
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path { return "/param" }
            
            # Act
            $result = Invoke-ConfigValidation @allPaths
            
            # Assert
            $result.DatabasePath | Should -Be $allPaths.DatabasePath
            $result.ProvidedDataFilePath | Should -Be $allPaths.ProvidedDataFilePath
            $result.CurrentDataFilePath | Should -Be $allPaths.CurrentDataFilePath
            $result.OutputFilePath | Should -Be $allPaths.OutputFilePath
        }
        
        It "非常に長いファイルパスでも正常に処理される" {
            # Arrange
            $longPath = "/" + ("very_long_directory_name" * 10) + "/file.csv"
            
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath {
                param($ParameterPath, $ConfigKey, $Description)
                if (-not [string]::IsNullOrEmpty($ParameterPath)) {
                    return $ParameterPath
                }
                return "/test/default.csv"
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path {
                param($Path, $Parent)
                if ($Parent) { return "/" + ("very_long_directory_name" * 10) }
                return $Path
            }
            
            # Act
            $result = Invoke-ConfigValidation -ProvidedDataFilePath $longPath
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.ProvidedDataFilePath | Should -Be $longPath
        }
    }
}