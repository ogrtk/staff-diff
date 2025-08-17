#!/usr/bin/env pwsh
# DataAccess Layer (Layer 3) - FileSystemUtils Module Tests

BeforeAll {
    # レイヤードテストヘルパーの読み込み
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/LayeredTestHelpers.psm1") -Force
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/MockHelpers.psm1") -Force
    
    # Layer 3 (DataAccess) テスト環境の初期化
    $script:TestEnv = Initialize-LayeredTestEnvironment -LayerName "DataAccess" -ModuleName "FileSystemUtils"
    
    # テスト用パス
    $script:TestFilePath = Join-Path $script:TestEnv.TempDirectory.Path "test.csv"
    $script:TestHistoryDir = Join-Path $script:TestEnv.TempDirectory.Path "history"
    
    # モック設定の設定
    $script:TestEnv.ConfigurationMock = New-MockConfiguration
}

AfterAll {
    # テスト環境のクリーンアップ
    Cleanup-LayeredTestEnvironment -TestEnvironment $script:TestEnv
}

Describe "FileSystemUtils (データアクセス層) テスト" {
    
    Context "Layer Architecture Validation" {
        It "基盤層とインフラストラクチャ層に依存するLayer 3であること" {
            $dependencies = Assert-LayeredModuleDependencies -LayerName "DataAccess" -ModuleName "FileSystemUtils"
            $dependencies.Dependencies | Should -Contain "Foundation"
            $dependencies.Dependencies | Should -Contain "Infrastructure"
            $dependencies.InvalidDependencies | Should -BeExactly @()
            $dependencies.CircularDependencies | Should -BeExactly @()
        }
        
        It "下位層関数を使用すること" {
            # FileSystemUtilsが下位レイヤの関数を使用することを確認
            $timestamp = Get-Timestamp
            $timestamp | Should -Not -BeNullOrEmpty
        }
    }
        
    Context "Resolve-FilePath Function - Path Resolution" {
        It "should resolve absolute paths correctly" {
            $absolutePath = Join-Path $script:TestEnv.TempDirectory.Path "absolute.csv"
            
            $result = Resolve-FilePath -ParameterPath $absolutePath
            
            $result | Should -Be $absolutePath
        }
        
        It "should resolve relative paths from project root" {
            $relativePath = "test-data/relative.csv"
            
            $result = Resolve-FilePath -ParameterPath $relativePath
            
            $result | Should -Not -BeNullOrEmpty
            [System.IO.Path]::IsPathRooted($result) | Should -Be $true
        }
        
        It "should handle path with spaces" {
            $pathWithSpaces = Join-Path $script:TestEnv.TempDirectory.Path "path with spaces.csv"
            
            $result = Resolve-FilePath -ParameterPath $pathWithSpaces
            
            $result | Should -Be $pathWithSpaces
        }
        
        It "should handle Windows and Unix path separators" {
            $windowsPath = "test-data\windows\path.csv"
            $unixPath = "test-data/unix/path.csv"
            
            $windowsResult = Resolve-FilePath -ParameterPath $windowsPath
            $unixResult = Resolve-FilePath -ParameterPath $unixPath
            
            $windowsResult | Should -Not -BeNullOrEmpty
            $unixResult | Should -Not -BeNullOrEmpty
        }
        
        It "should handle path normalization" {
            $unnormalizedPath = "test-data/../test-data/./normalized.csv"
            
            $result = Resolve-FilePath -ParameterPath $unnormalizedPath
            
            $result | Should -Not -Match "\.\."
            $result | Should -Not -Match "\.\/"
        }
    }
    
    Context "New-HistoryFileName Function - Filename Generation" {
        It "should generate history filename with timestamp" {
            $baseFileName = "test.csv"
            
            $result = New-HistoryFileName -BaseFileName $baseFileName
            
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "test_\d{8}_\d{6}\.csv"
        }
        
        It "should handle custom extension" {
            $baseFileName = "test.csv"
            $customExtension = ".txt"
            
            $result = New-HistoryFileName -BaseFileName $baseFileName -Extension $customExtension
            
            $result | Should -Match "test_\d{8}_\d{6}\.txt"
        }
        
        It "should handle filename without extension" {
            $baseFileName = "testfile"
            
            $result = New-HistoryFileName -BaseFileName $baseFileName
            
            $result | Should -Match "testfile_\d{8}_\d{6}\.csv"
        }
    }
    
    Context "Copy-InputFileToHistory Function - File History Operations" {
        BeforeEach {
            # テスト用ファイルの作成
            "test content" | Out-File -FilePath $script:TestFilePath -Encoding UTF8
        }
        
        It "should copy file to history directory" {
            $result = Copy-InputFileToHistory -SourceFilePath $script:TestFilePath -HistoryDirectory $script:TestHistoryDir
            
            Test-Path $script:TestHistoryDir | Should -Be $true
            $historyFiles = Get-ChildItem -Path $script:TestHistoryDir -Filter "test_*.csv"
            $historyFiles.Count | Should -Be 1
        }
        
        It "should create history directory if it doesn't exist" {
            $newHistoryDir = Join-Path $script:TestEnv.TempDirectory.Path "new_history"
            
            Copy-InputFileToHistory -SourceFilePath $script:TestFilePath -HistoryDirectory $newHistoryDir
            
            Test-Path $newHistoryDir | Should -Be $true
        }
        
        It "should throw error if source file doesn't exist" {
            $nonExistentFile = Join-Path $script:TestEnv.TempDirectory.Path "nonexistent.csv"
            
            { Copy-InputFileToHistory -SourceFilePath $nonExistentFile -HistoryDirectory $script:TestHistoryDir } | Should -Throw "*ソースファイルが存在しません*"
        }
        
        It "should preserve file content during copy" {
            $originalContent = "テスト内容`n日本語文字"
            $originalContent | Out-File -FilePath $script:TestFilePath -Encoding UTF8
            
            Copy-InputFileToHistory -SourceFilePath $script:TestFilePath -HistoryDirectory $script:TestHistoryDir
            
            $historyFile = Get-ChildItem -Path $script:TestHistoryDir -Filter "test_*.csv" | Select-Object -First 1
            $copiedContent = Get-Content -Path $historyFile.FullName -Raw -Encoding UTF8
            $copiedContent.Trim() | Should -Be $originalContent.Trim()
        }
    }
    
    Context "Integration with Lower Layers" {
        It "should use Foundation layer timestamp functions" {
            # Get-Timestampの使用確認
            $fileName = New-HistoryFileName -BaseFileName "integration.csv"
            $fileName | Should -Match "\d{8}_\d{6}"
        }
        
        It "should use Foundation layer encoding functions" {
            "日本語テスト" | Out-File -FilePath $script:TestFilePath -Encoding UTF8
            
            # エンコーディング処理の確認（間接的に）
            Copy-InputFileToHistory -SourceFilePath $script:TestFilePath -HistoryDirectory $script:TestHistoryDir
            
            $historyFile = Get-ChildItem -Path $script:TestHistoryDir -Filter "test_*.csv" | Select-Object -First 1
            $content = Get-Content -Path $historyFile.FullName -Raw -Encoding UTF8
            $content | Should -Match "日本語テスト"
        }
        
        It "should use Infrastructure layer logging functions" {
            # ログ出力の確認（間接的に）
            { Copy-InputFileToHistory -SourceFilePath $script:TestFilePath -HistoryDirectory $script:TestHistoryDir } | Should -Not -Throw
        }
    }
}