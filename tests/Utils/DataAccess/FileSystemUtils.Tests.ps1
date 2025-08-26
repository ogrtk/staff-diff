# PowerShell & SQLite データ同期システム
# Utils/DataAccess/FileSystemUtils.psm1 ユニットテスト

# テストヘルパーを最初にインポート
using module "../../TestHelpers/TestEnvironmentHelpers.psm1"
using module "../../TestHelpers/MockHelpers.psm1"

# 依存関係のモジュールをインポート（モック化準備のため）
using module "../../../scripts/modules/Utils/Foundation/CoreUtils.psm1"
using module "../../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1"
using module "../../../scripts/modules/Utils/Infrastructure/LoggingUtils.psm1"

# テスト対象モジュールを最後にインポート
using module "../../../scripts/modules/Utils/DataAccess/FileSystemUtils.psm1"

Describe "FileSystemUtils モジュール" {
    
    BeforeAll {
        $script:ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.Parent.FullName

        # TestEnvironmentクラスを使用してテスト環境を初期化
        $script:TestEnv = [TestEnvironment]::new("FileSystemUtils")
        
        # テスト用ディレクトリはTestEnvironmentの一時ディレクトリを使用
        $script:TestDataDir = $script:TestEnv.GetTempDirectory()
        
        # テスト用設定ファイルを作成
        $script:TestConfig = $script:TestEnv.GetConfig()
        if (-not $script:TestConfig) {
            $script:ConfigPath = $script:TestEnv.CreateConfigFile(@{}, "test-config")
            $script:TestConfig = $script:TestEnv.GetConfig()
        }
    }
    
    AfterAll {
        # TestEnvironmentオブジェクトのクリーンアップ（一時ディレクトリも自動的にクリーンアップされる）
        if ($script:TestEnv -and -not $script:TestEnv.IsDisposed) {
            $script:TestEnv.Dispose()
        }
    }
    
    BeforeEach {
        # 基本的なモック化 - 共通設定
        Mock -ModuleName "FileSystemUtils" -CommandName Write-SystemLog { }
        Mock -ModuleName "FileSystemUtils" -CommandName Get-Timestamp { return "20231201_120000" }
        Mock -ModuleName "FileSystemUtils" -CommandName Get-FilePathConfig {
            return @{
                provided_data_file_path = Join-Path $script:TestDataDir "config-provided.csv"
                current_data_file_path = Join-Path $script:TestDataDir "config-current.csv"
                output_file_path = Join-Path $script:TestDataDir "config-output.csv"
            }
        }
        
        # テスト用ディレクトリをクリーンアップ
        if (Test-Path $script:TestDataDir) {
            Get-ChildItem $script:TestDataDir | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "New-HistoryFileName 関数 - 履歴ファイル名生成" {
        
        It "基本的なファイル名でタイムスタンプ付きファイル名が生成される" {
            # Act
            $result = New-HistoryFileName -BaseFileName "test.csv"
            
            # Assert
            $result | Should -Be "test_20231201_120000.csv"
        }
        
        It "拡張子なしファイル名でデフォルト拡張子が使用される" {
            # Act
            $result = New-HistoryFileName -BaseFileName "test"
            
            # Assert
            $result | Should -Be "test_20231201_120000.csv"
        }
        
        It "カスタム拡張子が正常に使用される" {
            # Act
            $result = New-HistoryFileName -BaseFileName "test.txt" -Extension ".log"
            
            # Assert
            $result | Should -Be "test_20231201_120000.log"
        }
        
        It "複数の拡張子を含むファイル名で正常に処理される" {
            # Act
            $result = New-HistoryFileName -BaseFileName "test.backup.csv"
            
            # Assert
            $result | Should -Be "test.backup_20231201_120000.csv"
        }
        
        It "日本語ファイル名でも正常に処理される" {
            # Act
            $result = New-HistoryFileName -BaseFileName "テストファイル.csv"
            
            # Assert
            $result | Should -Be "テストファイル_20231201_120000.csv"
        }
        
        It "パス区切り文字を含むファイル名でベース名のみが使用される" {
            # Act
            $result = New-HistoryFileName -BaseFileName "folder/test.csv"
            
            # Assert
            $result | Should -Be "test_20231201_120000.csv"
        }
        
        It "特殊文字を含むファイル名でも正常に処理される" {
            # Act
            $result = New-HistoryFileName -BaseFileName "test-file_123.csv"
            
            # Assert
            $result | Should -Be "test-file_123_20231201_120000.csv"
        }
    }

    Context "Copy-InputFileToHistory 関数 - 履歴保存" {
        
        It "有効なファイルが履歴ディレクトリに正常にコピーされる" {
            # Arrange
            $sourceFile = Join-Path $script:TestDataDir "source.csv"
            $historyDir = Join-Path $script:TestDataDir "history"
            "テストデータ" | Out-File -FilePath $sourceFile -Encoding UTF8
            
            # Act
            $result = Copy-InputFileToHistory -SourceFilePath $sourceFile -HistoryDirectory $historyDir
            
            # Assert
            Test-Path $result | Should -Be $true
            $result | Should -Match "source_20231201_120000.csv$"
            $result | Should -Match ([regex]::Escape($historyDir))
            
            # ファイル内容の確認
            $content = Get-Content $result -Raw
            $content | Should -Match "テストデータ"
            
            # ログ出力の確認
            Should -Invoke -ModuleName "FileSystemUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "履歴ディレクトリを作成しました" } -Scope It
            Should -Invoke -ModuleName "FileSystemUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "ファイルを履歴に保存しました" } -Scope It
        }
        
        It "履歴ディレクトリが存在しない場合、自動作成される" {
            # Arrange
            $sourceFile = Join-Path $script:TestDataDir "source.csv"
            $historyDir = Join-Path $script:TestDataDir "non-existent-history"
            "テストデータ" | Out-File -FilePath $sourceFile -Encoding UTF8
            
            # Act
            $result = Copy-InputFileToHistory -SourceFilePath $sourceFile -HistoryDirectory $historyDir
            
            # Assert
            Test-Path $historyDir | Should -Be $true
            Test-Path $result | Should -Be $true
            Should -Invoke -ModuleName "FileSystemUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "履歴ディレクトリを作成しました" } -Scope It
        }
        
        It "履歴ディレクトリが既に存在する場合、作成ログが出力されない" {
            # Arrange
            $sourceFile = Join-Path $script:TestDataDir "source.csv"
            $historyDir = Join-Path $script:TestDataDir "existing-history"
            New-Item -Path $historyDir -ItemType Directory -Force | Out-Null
            "テストデータ" | Out-File -FilePath $sourceFile -Encoding UTF8
            
            # Act
            $result = Copy-InputFileToHistory -SourceFilePath $sourceFile -HistoryDirectory $historyDir
            
            # Assert
            Test-Path $result | Should -Be $true
            Should -Invoke -ModuleName "FileSystemUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "履歴ディレクトリを作成しました" } -Times 0 -Scope It
            Should -Invoke -ModuleName "FileSystemUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "ファイルを履歴に保存しました" } -Scope It
        }
        
        It "ソースファイルが存在しない場合、例外がスローされる" {
            # Arrange
            $nonExistentFile = Join-Path $script:TestDataDir "non-existent.csv"
            $historyDir = Join-Path $script:TestDataDir "history"
            
            # Act & Assert
            { Copy-InputFileToHistory -SourceFilePath $nonExistentFile -HistoryDirectory $historyDir } | Should -Throw "*ソースファイルが存在しません*"
        }
        
        It "大きなファイルでも正常にコピーされる" {
            # Arrange
            $sourceFile = Join-Path $script:TestDataDir "large-source.csv"
            $historyDir = Join-Path $script:TestDataDir "history"
            $largeContent = "A" * 10000  # 10KB のコンテンツ
            $largeContent | Out-File -FilePath $sourceFile -Encoding UTF8
            
            # Act
            $result = Copy-InputFileToHistory -SourceFilePath $sourceFile -HistoryDirectory $historyDir
            
            # Assert
            Test-Path $result | Should -Be $true
            $copiedContent = Get-Content $result -Raw
            $copiedContent.Length | Should -BeGreaterThan 9000  # 元のサイズとほぼ同じ
        }
        
        It "日本語を含むファイルでも正常にコピーされる" {
            # Arrange
            $sourceFile = Join-Path $script:TestDataDir "japanese-source.csv"
            $historyDir = Join-Path $script:TestDataDir "history"
            $japaneseContent = "氏名,部署,役職`n田中太郎,営業部,課長`n佐藤花子,開発部,主任"
            $japaneseContent | Out-File -FilePath $sourceFile -Encoding UTF8
            
            # Act
            $result = Copy-InputFileToHistory -SourceFilePath $sourceFile -HistoryDirectory $historyDir
            
            # Assert
            Test-Path $result | Should -Be $true
            $copiedContent = Get-Content $result -Encoding UTF8 -Raw
            $copiedContent | Should -Match "田中太郎"
            $copiedContent | Should -Match "佐藤花子"
        }
    }

    Context "Resolve-FilePath 関数 - ファイルパス解決" {
        
        It "パラメータが指定された場合、パラメータが優先される" {
            # Arrange
            $parameterPath = Join-Path $script:TestDataDir "parameter.csv"
            
            # Act
            $result = Resolve-FilePath -ParameterPath $parameterPath -ConfigKey "provided_data_file_path" -Description "テストファイル"
            
            # Assert
            $result | Should -Be $parameterPath
            Should -Invoke -ModuleName "FileSystemUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "パラメータ指定" } -Scope It
        }
        
        It "パラメータが未指定の場合、設定ファイルから取得される" {
            # Act
            $result = Resolve-FilePath -ConfigKey "provided_data_file_path" -Description "提供データファイル"
            
            # Assert
            $expectedPath = Join-Path $script:TestDataDir "config-provided.csv"
            $result | Should -Be $expectedPath
            Should -Invoke -ModuleName "FileSystemUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "設定ファイル" } -Scope It
        }
        
        It "パラメータも設定ファイルも無効な場合、例外がスローされる" {
            # Arrange
            Mock -ModuleName "FileSystemUtils" -CommandName Get-FilePathConfig {
                return @{
                    provided_data_file_path = ""
                    current_data_file_path = ""
                    output_file_path = ""
                }
            }
            
            # Act & Assert
            { Resolve-FilePath -ConfigKey "provided_data_file_path" -Description "テストファイル" } | Should -Throw "*パスが指定されていません*"
        }
        
        It "無効なConfigKeyが指定された場合、例外がスローされる" {
            # Act & Assert
            { Resolve-FilePath -ConfigKey "invalid_key" -Description "無効なファイル" } | Should -Throw "*パスが指定されていません*"
        }
        
        It "相対パスが絶対パスに変換される" {
            # Arrange
            $relativePath = "relative/path/file.csv"
            
            # Act
            $result = Resolve-FilePath -ParameterPath $relativePath -Description "相対パスファイル"
            
            # Assert
            [System.IO.Path]::IsPathRooted($result) | Should -Be $true
            $result | Should -Match ([regex]::Escape("relative"))
            $result | Should -Match ([regex]::Escape("file.csv"))
        }
        
        It "絶対パスがそのまま返される" {
            # Arrange
            if ($IsWindows) {
                $absolutePath = "C:\absolute\path\file.csv"
            }
            else {
                $absolutePath = "/absolute/path/file.csv"
            }
            
            # Act
            $result = Resolve-FilePath -ParameterPath $absolutePath -Description "絶対パスファイル"
            
            # Assert
            $result | Should -Be $absolutePath
        }
        
        It "空文字列パラメータの場合、設定ファイルから取得される" {
            # Act
            $result = Resolve-FilePath -ParameterPath "" -ConfigKey "current_data_file_path" -Description "現在データファイル"
            
            # Assert
            $expectedPath = Join-Path $script:TestDataDir "config-current.csv"
            $result | Should -Be $expectedPath
        }
        
        It "null パラメータの場合、設定ファイルから取得される" {
            # Act
            $result = Resolve-FilePath -ParameterPath $null -ConfigKey "output_file_path" -Description "出力ファイル"
            
            # Assert
            $expectedPath = Join-Path $script:TestDataDir "config-output.csv"
            $result | Should -Be $expectedPath
        }
    }

    Context "エラーハンドリングとエッジケース" {
        
        It "読み取り専用ディレクトリでも履歴保存が試行される" {
            # Arrange
            $sourceFile = Join-Path $script:TestDataDir "readonly-source.csv"
            $readonlyDir = Join-Path $script:TestDataDir "readonly-history"
            "テストデータ" | Out-File -FilePath $sourceFile -Encoding UTF8
            
            # 読み取り専用ディレクトリの作成試行（Windows環境でのみ）
            if ($IsWindows) {
                New-Item -Path $readonlyDir -ItemType Directory -Force | Out-Null
                try {
                    $acl = Get-Acl $readonlyDir
                    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $env:USERNAME, "Write", "Deny"
                    )
                    $acl.SetAccessRule($accessRule)
                    Set-Acl $readonlyDir $acl -ErrorAction SilentlyContinue
                    
                    # Act & Assert
                    { Copy-InputFileToHistory -SourceFilePath $sourceFile -HistoryDirectory $readonlyDir } | Should -Throw
                    
                    # クリーンアップ
                    $acl.Access | Where-Object { $_.IdentityReference -eq $env:USERNAME -and $_.AccessControlType -eq "Deny" } |
                    ForEach-Object { $acl.RemoveAccessRule($_) }
                    Set-Acl $readonlyDir $acl -ErrorAction SilentlyContinue
                }
                catch {
                    # 権限設定に失敗した場合はテストをスキップ
                    Set-ItResult -Skipped -Because "読み取り専用ディレクトリの設定に失敗しました"
                }
            }
            else {
                # Linux/Mac環境ではパーミッション制御が異なるため、基本テストのみ
                { Copy-InputFileToHistory -SourceFilePath $sourceFile -HistoryDirectory $readonlyDir } | Should -Not -Throw
            }
        }
        
        It "非常に長いパスでも正常に処理される" {
            # Arrange
            $longDirName = "very_long_directory_name" * 5  # 長いディレクトリ名
            $longPath = Join-Path $script:TestDataDir $longDirName
            if ($longPath.Length -lt 200) {
                $longPath = Join-Path $longPath ("sub" * 10)  # さらに長くする
            }
            
            # Act
            $result = Resolve-FilePath -ParameterPath $longPath -Description "長いパスファイル"
            
            # Assert
            $result | Should -Be $longPath
            $result.Length | Should -BeGreaterThan 100
        }
        
        It "特殊文字を含むパスでも正常に処理される" {
            # Arrange
            $specialPath = Join-Path $script:TestDataDir "special-chars!@#$%^&()_+={[}]|;'`",.csv"
            
            # Act
            $result = Resolve-FilePath -ParameterPath $specialPath -Description "特殊文字ファイル"
            
            # Assert
            $result | Should -Be $specialPath
        }
        
        It "空のファイルでも履歴保存が正常に動作する" {
            # Arrange
            $sourceFile = Join-Path $script:TestDataDir "empty-source.csv"
            $historyDir = Join-Path $script:TestDataDir "history"
            New-Item -Path $sourceFile -ItemType File -Force | Out-Null  # 空ファイル作成
            
            # Act
            $result = Copy-InputFileToHistory -SourceFilePath $sourceFile -HistoryDirectory $historyDir
            
            # Assert
            Test-Path $result | Should -Be $true
            (Get-Item $result).Length | Should -Be 0
        }
    }

    Context "設定ファイル連携テスト" {
        
        It "カスタム設定ファイルからファイルパスが正常に読み込まれる" {
            # Arrange
            $customConfig = @{
                provided_data_file_path = Join-Path $script:TestDataDir "custom-provided.csv"
                current_data_file_path = Join-Path $script:TestDataDir "custom-current.csv"
                output_file_path = Join-Path $script:TestDataDir "custom-output.csv"
            }
            Mock -ModuleName "FileSystemUtils" -CommandName Get-FilePathConfig { return $customConfig }
            
            # Act
            $providedPath = Resolve-FilePath -ConfigKey "provided_data_file_path" -Description "カスタム提供データ"
            $currentPath = Resolve-FilePath -ConfigKey "current_data_file_path" -Description "カスタム現在データ"
            $outputPath = Resolve-FilePath -ConfigKey "output_file_path" -Description "カスタム出力データ"
            
            # Assert
            $providedPath | Should -Be $customConfig.provided_data_file_path
            $currentPath | Should -Be $customConfig.current_data_file_path
            $outputPath | Should -Be $customConfig.output_file_path
        }
        
        It "複数のタイムスタンプで異なる履歴ファイル名が生成される" {
            # Arrange
            $sourceFile = Join-Path $script:TestDataDir "multi-source.csv"
            $historyDir = Join-Path $script:TestDataDir "multi-history"
            "テストデータ1" | Out-File -FilePath $sourceFile -Encoding UTF8
            
            # 最初のコピー
            $result1 = Copy-InputFileToHistory -SourceFilePath $sourceFile -HistoryDirectory $historyDir
            
            # タイムスタンプを変更
            Mock -ModuleName "FileSystemUtils" -CommandName Get-Timestamp { return "20231201_130000" }
            "テストデータ2" | Out-File -FilePath $sourceFile -Encoding UTF8
            
            # 2回目のコピー
            $result2 = Copy-InputFileToHistory -SourceFilePath $sourceFile -HistoryDirectory $historyDir
            
            # Assert
            $result1 | Should -Not -Be $result2
            Test-Path $result1 | Should -Be $true
            Test-Path $result2 | Should -Be $true
            
            $content1 = Get-Content $result1 -Raw
            $content2 = Get-Content $result2 -Raw
            $content1 | Should -Match "テストデータ1"
            $content2 | Should -Match "テストデータ2"
        }
    }

    Context "パフォーマンステスト" {
        
        It "複数ファイルの履歴保存が一定時間内に完了する" {
            # Arrange
            $fileCount = 10
            $historyDir = Join-Path $script:TestDataDir "performance-history"
            $sourceFiles = @()
            
            for ($i = 1; $i -le $fileCount; $i++) {
                $sourceFile = Join-Path $script:TestDataDir "perf-source-$i.csv"
                "パフォーマンステストデータ $i" | Out-File -FilePath $sourceFile -Encoding UTF8
                $sourceFiles += $sourceFile
            }
            
            # Act
            $startTime = Get-Date
            foreach ($sourceFile in $sourceFiles) {
                Copy-InputFileToHistory -SourceFilePath $sourceFile -HistoryDirectory $historyDir
            }
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            
            # Assert
            $duration | Should -BeLessThan 10  # 10秒以内に完了すべき
            
            # 全ファイルがコピーされていることを確認
            $historyFiles = Get-ChildItem $historyDir -Filter "*.csv"
            $historyFiles.Count | Should -Be $fileCount
        }
    }

    Context "関数のエクスポート確認" {
        
        It "必要な関数がエクスポートされている" {
            # Arrange
            $expectedFunctions = @(
                'New-HistoryFileName',
                'Copy-InputFileToHistory',
                'Resolve-FilePath'
            )
            
            # Act
            $module = Get-Module -Name FileSystemUtils
            $exportedFunctions = $module.ExportedFunctions.Keys
            
            # Assert
            foreach ($func in $expectedFunctions) {
                $exportedFunctions | Should -Contain $func
            }
        }
    }
}