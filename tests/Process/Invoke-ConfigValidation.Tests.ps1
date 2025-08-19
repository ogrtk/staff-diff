# PowerShell & SQLite データ同期システム
# Process/Invoke-ConfigValidation.psm1 ユニットテスト

# テストヘルパーを最初にインポート
using module "../TestHelpers/TestEnvironmentHelpers.psm1"
using module "../TestHelpers/MockHelpers.psm1"

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
        $script:TestEnv = Initialize-TestEnvironment
        
        # テスト用データの準備
        $script:ValidTestConfig = New-TestConfig
    }
    
    AfterAll {
        # テスト環境のクリーンアップ
        Clear-TestEnvironment
    }
    
    BeforeEach {
        # 基本的なモック化 - 共通設定
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Write-SystemLog { }
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Invoke-WithErrorHandling { 
            param($ScriptBlock, $Category, $Operation, $Context)
            & $ScriptBlock
        }
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Get-Sqlite3Path { return @{ Source = "/usr/bin/sqlite3" } }
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Get-DataSyncConfig { return $script:ValidTestConfig }
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Test-DataSyncConfig { }
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Test-Path { return $true }
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path {
            param($Path, $Parent)
            if ($Parent) { return Join-Path $script:TestEnv.ProjectRoot "test-data" }
            return $Path
        }

        # デフォルトのResolve-FilePath (個別テストでオーバーライド可能)
        Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath {
            param($ParameterPath, $ConfigKey, $Description)
            if (-not [string]::IsNullOrEmpty($ParameterPath)) {
                return $ParameterPath
            }
            $defaultTestDir = Join-Path $script:TestEnv.ProjectRoot "test-data" "default"
            switch ($ConfigKey) {
                "provided_data_file_path" { return Join-Path $defaultTestDir "provided.csv" }
                "current_data_file_path" { return Join-Path $defaultTestDir "current.csv" }
                "output_file_path" { return Join-Path $defaultTestDir "output.csv" }
                default { return Join-Path $defaultTestDir "file.csv" }
            }
        }
    }

    Context "Invoke-ConfigValidation 関数 - 基本動作" {
        
        It "有効なパラメータで正常に処理を完了する" {
            # Arrange - テスト環境パスを活用
            $testDbPath = Join-Path $script:TestEnv.ProjectRoot "database" "test.db"
            $testProvidedPath = Join-Path $script:TestEnv.ProjectRoot "test-data" "test-provided.csv"
            $testCurrentPath = Join-Path $script:TestEnv.ProjectRoot "test-data" "test-current.csv"
            $testOutputPath = Join-Path $script:TestEnv.ProjectRoot "test-data" "test-output.csv"
            
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
            $result = Invoke-ConfigValidation -DatabasePath $testDbPath -ProvidedDataFilePath $testProvidedPath -CurrentDataFilePath $testCurrentPath -OutputFilePath $testOutputPath -ConfigFilePath "some/config/filepath"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.DatabasePath | Should -Be $testDbPath
            $result.ProvidedDataFilePath | Should -Be $testProvidedPath
            $result.CurrentDataFilePath | Should -Be $testCurrentPath
            $result.OutputFilePath | Should -Be $testOutputPath
        }
        
        It "DatabasePathが未指定の場合、デフォルトパスを設定する" {
            # Act - BeforeEachの基本モックを活用
            $result = Invoke-ConfigValidation
            
            # Assert
            $expectedDbPath = Join-Path ( Find-ProjectRoot ) "database" "data-sync.db"
            $result.DatabasePath | Should -Be $expectedDbPath
        }
        
        It "設定ファイル読み込みが正常に実行される" {
            # Act - BeforeEachの基本モックを活用
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
        
        It "実ファイルを使ったパス解決テスト" {
            # Arrange - 実テストファイルを作成
            $testDataDir = Join-Path $script:TestEnv.ProjectRoot "test-data" "real-files"
            if (-not (Test-Path $testDataDir)) {
                New-Item -Path $testDataDir -ItemType Directory -Force | Out-Null
            }
            
            # 実テストCSVファイルを作成
            $realProvidedPath = Join-Path $testDataDir "real-provided.csv"
            $realCurrentPath = Join-Path $testDataDir "real-current.csv"
            $realOutputPath = Join-Path $testDataDir "real-output.csv"
            
            # New-TestCsvDataを使ってテストデータ作成
            New-TestCsvData -DataType "provided_data" -RecordCount 5 -OutputPath $realProvidedPath -IncludeHeader
            New-TestCsvData -DataType "current_data" -RecordCount 3 -OutputPath $realCurrentPath -IncludeHeader
            
            try {
                # Resolve-FilePathをモックして実ファイルパスを返す
                Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath {
                    param($ParameterPath, $ConfigKey, $Description)
                    switch ($ConfigKey) {
                        "provided_data_file_path" { return $realProvidedPath }
                        "current_data_file_path" { return $realCurrentPath }
                        "output_file_path" { return $realOutputPath }
                    }
                }
                
                # 実ファイルの存在を確認するためにTest-Pathをモックしない
                # Split-Pathのみモック
                Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path {
                    param($Path, $Parent)
                    if ($Parent) { return $testDataDir }
                    return $Path
                }
                
                # Act
                $result = Invoke-ConfigValidation
                
                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.ProvidedDataFilePath | Should -Be $realProvidedPath
                $result.CurrentDataFilePath | Should -Be $realCurrentPath
                $result.OutputFilePath | Should -Be $realOutputPath
                
                # 実ファイルが作成されていることを確認
                Test-Path $realProvidedPath | Should -Be $true
                Test-Path $realCurrentPath | Should -Be $true
                
            }
            finally {
                # クリーンアップ
                if (Test-Path $testDataDir) {
                    Remove-Item $testDataDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
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
            # Arrange - テスト環境パスを活用
            $configProvidedPath = Join-Path $script:TestEnv.ProjectRoot "config" "provided.csv"
            $configCurrentPath = Join-Path $script:TestEnv.ProjectRoot "config" "current.csv"
            $configOutputPath = Join-Path $script:TestEnv.ProjectRoot "config" "output.csv"
            
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
            # Arrange - テスト環境パスを活用
            $testDataDir = Join-Path $script:TestEnv.ProjectRoot "test-data"
            $testProvidedPath = Join-Path $testDataDir "file-check-provided.csv"
            $testCurrentPath = Join-Path $testDataDir "file-check-current.csv"
            $testOutputPath = Join-Path $testDataDir "file-check-output.csv"
            
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
                if ($Parent) { return $testDataDir }
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
            # Arrange - テスト環境パスを活用
            $testDbPath = Join-Path $script:TestEnv.ProjectRoot "database" "log-test.db"
            $testDataDir = Join-Path $script:TestEnv.ProjectRoot "test-data"
            $testProvidedPath = Join-Path $testDataDir "log-provided.csv"
            $testCurrentPath = Join-Path $testDataDir "log-current.csv"
            $testOutputPath = Join-Path $testDataDir "log-output.csv"
            
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath {
                param($ParameterPath, $ConfigKey, $Description)
                switch ($ConfigKey) {
                    "provided_data_file_path" { return $testProvidedPath }
                    "current_data_file_path" { return $testCurrentPath }
                    "output_file_path" { return $testOutputPath }
                }
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path { return $testDataDir }
            
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
            # Arrange - テスト環境パスを活用
            $existingDir = Join-Path $script:TestEnv.ProjectRoot "test-data" "existing"
            $existingProvidedPath = Join-Path $existingDir "provided.csv"
            $existingCurrentPath = Join-Path $existingDir "current.csv"
            $existingOutputPath = Join-Path $existingDir "output.csv"
            
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath { 
                param($ParameterPath, $ConfigKey, $Description)
                switch ($ConfigKey) {
                    "provided_data_file_path" { return $existingProvidedPath }
                    "current_data_file_path" { return $existingCurrentPath }
                    "output_file_path" { return $existingOutputPath }
                }
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Test-Path { 
                param($Path)
                return $Path -match "existing"
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path {
                param($Path, $Parent)
                if ($Parent) { return $existingDir }
                return $Path
            }
            
            # Act & Assert
            { Invoke-ConfigValidation } | Should -Not -Throw
        }
        
        It "提供データファイルが存在しない場合、エラーをスローする" {
            # Arrange - テスト環境パスを活用
            $testDataDir = Join-Path $script:TestEnv.ProjectRoot "test-data"
            $missingProvidedPath = Join-Path $testDataDir "missing" "provided.csv"
            $existingCurrentPath = Join-Path $testDataDir "existing" "current.csv"
            $existingOutputPath = Join-Path $testDataDir "existing" "output.csv"
            
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath { 
                param($ParameterPath, $ConfigKey, $Description)
                switch ($ConfigKey) {
                    "provided_data_file_path" { return $missingProvidedPath }
                    "current_data_file_path" { return $existingCurrentPath }
                    "output_file_path" { return $existingOutputPath }
                }
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Test-Path { 
                param($Path)
                return $Path -match "existing"
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path {
                param($Path, $Parent)
                if ($Parent -and $Path -match "existing") { return Join-Path $testDataDir "existing" }
                if ($Parent -and $Path -match "missing") { return Join-Path $testDataDir "missing" }
                return $Path
            }
            
            # Act & Assert
            { Invoke-ConfigValidation } | Should -Throw "*提供データファイルが見つかりません*"
        }
        
        It "現在データファイルが存在しない場合、エラーをスローする" {
            # Arrange - テスト環境パスを活用
            $testDataDir = Join-Path $script:TestEnv.ProjectRoot "test-data"
            $existingProvidedPath = Join-Path $testDataDir "existing" "provided.csv"
            $missingCurrentPath = Join-Path $testDataDir "missing" "current.csv"
            $existingOutputPath = Join-Path $testDataDir "existing" "output.csv"
            
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath { 
                param($ParameterPath, $ConfigKey, $Description)
                switch ($ConfigKey) {
                    "provided_data_file_path" { return $existingProvidedPath }
                    "current_data_file_path" { return $missingCurrentPath }
                    "output_file_path" { return $existingOutputPath }
                }
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Test-Path { 
                param($Path)
                return $Path -match "existing"
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path {
                param($Path, $Parent)
                if ($Parent -and $Path -match "existing") { return Join-Path $testDataDir "existing" }
                if ($Parent -and $Path -match "missing") { return Join-Path $testDataDir "missing" }
                return $Path
            }
            
            # Act & Assert
            { Invoke-ConfigValidation } | Should -Throw "*現在データファイルが見つかりません*"
        }
        
        It "出力ディレクトリが存在しない場合、エラーをスローする" {
            # Arrange - テスト環境パスを活用
            $testDataDir = Join-Path $script:TestEnv.ProjectRoot "test-data"
            $existingProvidedPath = Join-Path $testDataDir "existing" "provided.csv"
            $existingCurrentPath = Join-Path $testDataDir "existing" "current.csv"
            $missingDirPath = Join-Path $testDataDir "missing_dir"
            $missingOutputPath = Join-Path $missingDirPath "output.csv"
            
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath { 
                param($ParameterPath, $ConfigKey, $Description)
                switch ($ConfigKey) {
                    "provided_data_file_path" { return $existingProvidedPath }
                    "current_data_file_path" { return $existingCurrentPath }
                    "output_file_path" { return $missingOutputPath }
                }
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Test-Path { 
                param($Path)
                if ($Path -eq $missingDirPath) {
                    return $false
                }
                return $Path -match "existing"
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path {
                param($Path, $Parent)
                if ($Parent -and $Path -eq $missingOutputPath) {
                    return $missingDirPath
                }
                return Join-Path $testDataDir "existing"
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
        
        It "日本語データを含むファイルパスの処理" {
            # Arrange - 日本語データを含むテストファイル作成
            $japaneseTestDir = Join-Path $script:TestEnv.ProjectRoot "test-data" "japanese-test"
            if (-not (Test-Path $japaneseTestDir)) {
                New-Item -Path $japaneseTestDir -ItemType Directory -Force | Out-Null
            }
            
            $japaneseProvidedPath = Join-Path $japaneseTestDir "日本語-provided.csv"
            $japaneseCurrentPath = Join-Path $japaneseTestDir "日本語-current.csv"
            $japaneseOutputPath = Join-Path $japaneseTestDir "日本語-output.csv"
            
            try {
                # 日本語データを含むCSVファイル作成
                New-TestCsvData -DataType "provided_data" -RecordCount 3 -OutputPath $japaneseProvidedPath -IncludeJapanese -IncludeHeader
                New-TestCsvData -DataType "current_data" -RecordCount 2 -OutputPath $japaneseCurrentPath -IncludeJapanese -IncludeHeader
                
                Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath {
                    param($ParameterPath, $ConfigKey, $Description)
                    switch ($ConfigKey) {
                        "provided_data_file_path" { return $japaneseProvidedPath }
                        "current_data_file_path" { return $japaneseCurrentPath }
                        "output_file_path" { return $japaneseOutputPath }
                    }
                }
                Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path {
                    param($Path, $Parent)
                    if ($Parent) { return $japaneseTestDir }
                    return $Path
                }
                
                # Act
                $result = Invoke-ConfigValidation
                
                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.ProvidedDataFilePath | Should -Be $japaneseProvidedPath
                $result.CurrentDataFilePath | Should -Be $japaneseCurrentPath
                $result.OutputFilePath | Should -Be $japaneseOutputPath
                
                # 日本語ファイル名でも正常に処理されることを確認
                Test-Path $japaneseProvidedPath | Should -Be $true
                Test-Path $japaneseCurrentPath | Should -Be $true
                
            }
            finally {
                # クリーンアップ
                if (Test-Path $japaneseTestDir) {
                    Remove-Item $japaneseTestDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "複数のパラメータが同時に指定された場合の優先順位" {
            # Arrange - テスト環境パスを活用
            $paramDir = Join-Path $script:TestEnv.ProjectRoot "test-data" "param"
            $allPaths = @{
                DatabasePath         = Join-Path $paramDir "database.db"
                ProvidedDataFilePath = Join-Path $paramDir "provided.csv"
                CurrentDataFilePath  = Join-Path $paramDir "current.csv"
                OutputFilePath       = Join-Path $paramDir "output.csv"
                ConfigFilePath       = "some/config/filepath"
            }

            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath {
                param($ParameterPath, $ConfigKey, $Description)
                return $ParameterPath  # パラメータ値をそのまま返す
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path { return $paramDir }
            
            # Act
            $result = Invoke-ConfigValidation @allPaths
            
            # Assert
            $result.DatabasePath | Should -Be $allPaths.DatabasePath
            $result.ProvidedDataFilePath | Should -Be $allPaths.ProvidedDataFilePath
            $result.CurrentDataFilePath | Should -Be $allPaths.CurrentDataFilePath
            $result.OutputFilePath | Should -Be $allPaths.OutputFilePath
        }
        
        It "非常に長いファイルパスでも正常に処理される" {
            # Arrange - テスト環境パスを活用
            $longDirName = "very_long_directory_name" * 10
            $longDir = Join-Path $script:TestEnv.ProjectRoot $longDirName
            $longPath = Join-Path $longDir "file.csv"
            $defaultTestPath = Join-Path $script:TestEnv.ProjectRoot "test-data" "default.csv"
            
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Resolve-FilePath {
                param($ParameterPath, $ConfigKey, $Description)
                if (-not [string]::IsNullOrEmpty($ParameterPath)) {
                    return $ParameterPath
                }
                return $defaultTestPath
            }
            Mock -ModuleName "Invoke-ConfigValidation" -CommandName Split-Path {
                param($Path, $Parent)
                if ($Parent) { return $longDir }
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