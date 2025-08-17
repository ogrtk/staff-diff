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
    
    Context "Save-WithHistory Function - Basic Operations" {
        It "should save content to specified output path" {
            $testContent = "test,content,header`nrow1,value1,data1`nrow2,value2,data2"
            
            $result = Save-WithHistory -Content $testContent -OutputPath $script:TestFilePath -HistoryDir $script:TestHistoryDir
            
            Test-Path $script:TestFilePath | Should -Be $true
            $savedContent = Get-Content -Path $script:TestFilePath -Raw
            $savedContent | Should -Be $testContent
            
            $result.OutputPath | Should -Be $script:TestFilePath
            $result.HistoryPath | Should -Not -BeNullOrEmpty
        }
        
        It "should create history directory if it doesn't exist" {
            $testContent = "history,test,content"
            
            $result = Save-WithHistory -Content $testContent -OutputPath $script:TestFilePath -HistoryDir $script:TestHistoryDir
            
            Test-Path $script:TestHistoryDir | Should -Be $true
            Test-Path $result.HistoryPath | Should -Be $true
        }
        
        It "should save copy to history directory with timestamp" {
            $testContent = "timestamped,content,test"
            
            $result = Save-WithHistory -Content $testContent -OutputPath $script:TestFilePath -HistoryDir $script:TestHistoryDir
            
            $historyFile = Split-Path $result.HistoryPath -Leaf
            $historyFile | Should -Match "\d{8}_\d{6}"  # タイムスタンプフォーマット
            
            $historyContent = Get-Content -Path $result.HistoryPath -Raw
            $historyContent | Should -Be $testContent
        }
        
        It "should handle Japanese content correctly" {
            $japaneseContent = "従業員ID,名前,部署`nE001,田中太郎,開発部`nE002,佐藤花子,営業部"
            
            $result = Save-WithHistory -Content $japaneseContent -OutputPath $script:TestFilePath -HistoryDir $script:TestHistoryDir
            
            $savedContent = Get-Content -Path $script:TestFilePath -Encoding UTF8 -Raw
            $savedContent | Should -Match "田中太郎"
            $savedContent | Should -Match "佐藤花子"
            
            $historyContent = Get-Content -Path $result.HistoryPath -Encoding UTF8 -Raw
            $historyContent | Should -Match "田中太郎"
        }
        
        It "should handle empty content" {
            $result = Save-WithHistory -Content "" -OutputPath $script:TestFilePath -HistoryDir $script:TestHistoryDir
            
            Test-Path $script:TestFilePath | Should -Be $true
            Test-Path $result.HistoryPath | Should -Be $true
            
            $savedContent = Get-Content -Path $script:TestFilePath -Raw
            $savedContent | Should -BeNullOrEmpty
        }
    }
    
    Context "Resolve-FilePath Function - Path Resolution" {
        It "should resolve absolute paths correctly" {
            $absolutePath = Join-Path $script:TestEnv.TempDirectory.Path "absolute.csv"
            
            $result = Resolve-FilePath -FilePath $absolutePath
            
            $result | Should -Be $absolutePath
        }
        
        It "should resolve relative paths from project root" {
            $relativePath = "test-data/relative.csv"
            
            $result = Resolve-FilePath -FilePath $relativePath
            
            $result | Should -Not -BeNullOrEmpty
            [System.IO.Path]::IsPathRooted($result) | Should -Be $true
        }
        
        It "should handle path with spaces" {
            $pathWithSpaces = Join-Path $script:TestEnv.TempDirectory.Path "path with spaces.csv"
            
            $result = Resolve-FilePath -FilePath $pathWithSpaces
            
            $result | Should -Be $pathWithSpaces
        }
        
        It "should handle Windows and Unix path separators" {
            $windowsPath = "test-data\windows\path.csv"
            $unixPath = "test-data/unix/path.csv"
            
            $windowsResult = Resolve-FilePath -FilePath $windowsPath
            $unixResult = Resolve-FilePath -FilePath $unixPath
            
            $windowsResult | Should -Not -BeNullOrEmpty
            $unixResult | Should -Not -BeNullOrEmpty
        }
        
        It "should handle path normalization" {
            $unnormalizedPath = "test-data/../test-data/./normalized.csv"
            
            $result = Resolve-FilePath -FilePath $unnormalizedPath
            
            $result | Should -Not -Match "\.\."
            $result | Should -Not -Match "\.\/"
        }
    }
    
    Context "Ensure-DirectoryExists Function - Directory Management" {
        It "should create directory if it doesn't exist" {
            $newDirPath = Join-Path $script:TestEnv.TempDirectory.Path "new/nested/directory"
            
            Ensure-DirectoryExists -DirectoryPath $newDirPath
            
            Test-Path $newDirPath | Should -Be $true
            (Get-Item $newDirPath).PSIsContainer | Should -Be $true
        }
        
        It "should not throw error if directory already exists" {
            New-Item -ItemType Directory -Path $script:TestHistoryDir -Force | Out-Null
            
            { Ensure-DirectoryExists -DirectoryPath $script:TestHistoryDir } | Should -Not -Throw
            
            Test-Path $script:TestHistoryDir | Should -Be $true
        }
        
        It "should handle path with Japanese characters" {
            $japaneseDirPath = Join-Path $script:TestEnv.TempDirectory.Path "日本語ディレクトリ"
            
            Ensure-DirectoryExists -DirectoryPath $japaneseDirPath
            
            Test-Path $japaneseDirPath | Should -Be $true
        }
        
        It "should handle very long directory paths" {
            $longDirName = "a" * 50  # 50文字のディレクトリ名
            $longDirPath = Join-Path $script:TestEnv.TempDirectory.Path $longDirName
            
            if ($longDirPath.Length -lt 260) {  # Windows MAX_PATH制限を考慮
                Ensure-DirectoryExists -DirectoryPath $longDirPath
                Test-Path $longDirPath | Should -Be $true
            } else {
                Set-TestInconclusive "Path too long for this platform"
            }
        }
        
        It "should handle UNC paths (Windows)" {
            if ($IsWindows) {
                # UNCパスのテストはローカル環境では制限的
                Set-TestInconclusive "UNC path testing requires network environment"
            } else {
                Set-TestInconclusive "UNC paths are Windows-specific"
            }
        }
    }
    
    Context "Copy-WithBackup Function - File Backup Operations" {
        BeforeEach {
            # テスト用ファイルの作成
            "original content" | Out-File -FilePath $script:TestFilePath -Encoding UTF8
        }
        
        It "should copy file to destination" {
            $destPath = Join-Path $script:TestEnv.TempDirectory.Path "destination.csv"
            
            $result = Copy-WithBackup -SourcePath $script:TestFilePath -DestinationPath $destPath
            
            Test-Path $destPath | Should -Be $true
            $destContent = Get-Content -Path $destPath -Raw
            $destContent | Should -Match "original content"
            
            $result.Success | Should -Be $true
            $result.DestinationPath | Should -Be $destPath
        }
        
        It "should create backup of existing destination file" {
            $destPath = Join-Path $script:TestEnv.TempDirectory.Path "existing.csv"
            "existing content" | Out-File -FilePath $destPath -Encoding UTF8
            
            $result = Copy-WithBackup -SourcePath $script:TestFilePath -DestinationPath $destPath -CreateBackup
            
            # 元のファイルが上書きされている
            $destContent = Get-Content -Path $destPath -Raw
            $destContent | Should -Match "original content"
            
            # バックアップファイルが作成されている
            Test-Path $result.BackupPath | Should -Be $true
            $backupContent = Get-Content -Path $result.BackupPath -Raw
            $backupContent | Should -Match "existing content"
        }
        
        It "should handle file permission errors gracefully" {
            $destPath = Join-Path $script:TestEnv.TempDirectory.Path "readonly.csv"
            "readonly content" | Out-File -FilePath $destPath -Encoding UTF8
            
            try {
                # OS固有の読み取り専用設定
                if ($IsWindows) {
                    Set-ItemProperty -Path $destPath -Name IsReadOnly -Value $true
                } else {
                    chmod u-w $destPath
                }
                
                $result = Copy-WithBackup -SourcePath $script:TestFilePath -DestinationPath $destPath
                
                # 読み取り専用ファイルでもコピーが試行される
                $result | Should -Not -BeNullOrEmpty
            }
            finally {
                # 権限を復元
                if ($IsWindows) {
                    Set-ItemProperty -Path $destPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                } else {
                    chmod u+w $destPath 2>/dev/null
                }
            }
        }
        
        It "should handle source file not found" {
            $nonExistentSource = Join-Path $script:TestEnv.TempDirectory.Path "nonexistent.csv"
            $destPath = Join-Path $script:TestEnv.TempDirectory.Path "dest.csv"
            
            $result = Copy-WithBackup -SourcePath $nonExistentSource -DestinationPath $destPath
            
            $result.Success | Should -Be $false
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Get-FileMetadata Function - File Information" {
        BeforeEach {
            $testContent = "metadata,test,content`nrow1,data1,value1`nrow2,data2,value2"
            $testContent | Out-File -FilePath $script:TestFilePath -Encoding UTF8
        }
        
        It "should return basic file metadata" {
            $metadata = Get-FileMetadata -FilePath $script:TestFilePath
            
            $metadata.FileName | Should -Be (Split-Path $script:TestFilePath -Leaf)
            $metadata.FilePath | Should -Be $script:TestFilePath
            $metadata.FileSize | Should -BeGreaterThan 0
            $metadata.CreationTime | Should -Not -BeNullOrEmpty
            $metadata.LastWriteTime | Should -Not -BeNullOrEmpty
        }
        
        It "should detect file encoding" {
            $metadata = Get-FileMetadata -FilePath $script:TestFilePath
            
            $metadata.Encoding | Should -Not -BeNullOrEmpty
            $metadata.Encoding | Should -Match "(UTF-8|Unicode)"
        }
        
        It "should count lines in text files" {
            $metadata = Get-FileMetadata -FilePath $script:TestFilePath
            
            $metadata.LineCount | Should -Be 3  # ヘッダー + 2データ行
        }
        
        It "should detect CSV structure" {
            $metadata = Get-FileMetadata -FilePath $script:TestFilePath
            
            $metadata.HasHeaders | Should -Not -BeNullOrEmpty
            $metadata.ColumnCount | Should -Be 3
            $metadata.Delimiter | Should -Be ","
        }
        
        It "should handle binary files" {
            $binaryPath = Join-Path $script:TestEnv.TempDirectory.Path "binary.dat"
            $binaryData = [byte[]](1..100)
            [System.IO.File]::WriteAllBytes($binaryPath, $binaryData)
            
            $metadata = Get-FileMetadata -FilePath $binaryPath
            
            $metadata.FileType | Should -Be "Binary"
            $metadata.LineCount | Should -Be 0
        }
        
        It "should handle very large files efficiently" {
            # 大きなファイルの作成（メモリ効率的に）
            $largeFilePath = Join-Path $script:TestEnv.TempDirectory.Path "large.csv"
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            # StreamWriterを使用してメモリ効率的に書き込み
            $writer = [System.IO.StreamWriter]::new($largeFilePath, $false, [System.Text.Encoding]::UTF8)
            try {
                $writer.WriteLine("header1,header2,header3")
                1..1000 | ForEach-Object {
                    $writer.WriteLine("data$_,value$_,content$_")
                }
            }
            finally {
                $writer.Dispose()
            }
            
            $metadata = Get-FileMetadata -FilePath $largeFilePath
            $stopwatch.Stop()
            
            $metadata.LineCount | Should -Be 1001  # ヘッダー + 1000行
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000  # 5秒以内
        }
    }
    
    Context "Archive-Files Function - File Archiving" {
        BeforeEach {
            # 複数のテストファイルを作成
            $script:TestFiles = @()
            1..3 | ForEach-Object {
                $filePath = Join-Path $script:TestEnv.TempDirectory.Path "test$_.csv"
                "test content $_" | Out-File -FilePath $filePath -Encoding UTF8
                $script:TestFiles += $filePath
            }
        }
        
        It "should create archive from multiple files" {
            $archivePath = Join-Path $script:TestEnv.TempDirectory.Path "archive.zip"
            
            $result = Archive-Files -FilePaths $script:TestFiles -ArchivePath $archivePath
            
            Test-Path $archivePath | Should -Be $true
            $result.Success | Should -Be $true
            $result.ArchivedFileCount | Should -Be 3
        }
        
        It "should include directory structure in archive" {
            $nestedDir = Join-Path $script:TestEnv.TempDirectory.Path "nested"
            New-Item -ItemType Directory -Path $nestedDir -Force | Out-Null
            
            $nestedFile = Join-Path $nestedDir "nested.csv"
            "nested content" | Out-File -FilePath $nestedFile -Encoding UTF8
            
            $archivePath = Join-Path $script:TestEnv.TempDirectory.Path "nested_archive.zip"
            $result = Archive-Files -FilePaths @($nestedFile) -ArchivePath $archivePath -PreserveStructure
            
            $result.Success | Should -Be $true
            Test-Path $archivePath | Should -Be $true
        }
        
        It "should handle compression settings" {
            $archivePath = Join-Path $script:TestEnv.TempDirectory.Path "compressed.zip"
            
            $result = Archive-Files -FilePaths $script:TestFiles -ArchivePath $archivePath -CompressionLevel "Maximum"
            
            $result.Success | Should -Be $true
            $result.CompressionRatio | Should -BeGreaterThan 0
        }
        
        It "should handle file access conflicts" {
            # ファイルをロックした状態でアーカイブを試行
            $lockFilePath = $script:TestFiles[0]
            $fileStream = [System.IO.File]::OpenRead($lockFilePath)
            
            try {
                $archivePath = Join-Path $script:TestEnv.TempDirectory.Path "locked_archive.zip"
                $result = Archive-Files -FilePaths $script:TestFiles -ArchivePath $archivePath
                
                # ロックされたファイルがある場合の処理
                $result.Errors | Should -Not -BeNullOrEmpty
            }
            finally {
                $fileStream.Dispose()
            }
        }
    }
    
    Context "Clean-TempFiles Function - Temporary File Management" {
        BeforeEach {
            # 一時ファイルの作成
            $script:TempFiles = @()
            1..5 | ForEach-Object {
                $tempPath = Join-Path $script:TestEnv.TempDirectory.Path "temp$_.tmp"
                "temporary content $_" | Out-File -FilePath $tempPath -Encoding UTF8
                $script:TempFiles += $tempPath
                
                # 古いファイルをシミュレート
                if ($_ -le 2) {
                    (Get-Item $tempPath).LastWriteTime = (Get-Date).AddDays(-2)
                }
            }
        }
        
        It "should clean up old temporary files" {
            $result = Clean-TempFiles -TempDirectory $script:TestEnv.TempDirectory.Path -OlderThanDays 1
            
            $result.CleanedFileCount | Should -BeGreaterOrEqual 2  # 2日以上古いファイル
            $result.Success | Should -Be $true
        }
        
        It "should preserve recent temporary files" {
            Clean-TempFiles -TempDirectory $script:TestEnv.TempDirectory.Path -OlderThanDays 1
            
            # 最近のファイル（temp3.tmp, temp4.tmp, temp5.tmp）は残る
            $remainingFiles = Get-ChildItem -Path $script:TestEnv.TempDirectory.Path -Filter "temp*.tmp"
            $remainingFiles.Count | Should -BeGreaterOrEqual 3
        }
        
        It "should handle pattern-based cleanup" {
            $result = Clean-TempFiles -TempDirectory $script:TestEnv.TempDirectory.Path -Pattern "*.tmp" -OlderThanDays 0
            
            # すべての.tmpファイルが削除される
            $result.CleanedFileCount | Should -Be 5
            
            $remainingTmpFiles = Get-ChildItem -Path $script:TestEnv.TempDirectory.Path -Filter "*.tmp"
            $remainingTmpFiles.Count | Should -Be 0
        }
        
        It "should calculate space freed" {
            $initialSize = (Get-ChildItem -Path $script:TestEnv.TempDirectory.Path -Recurse | Measure-Object -Property Length -Sum).Sum
            
            $result = Clean-TempFiles -TempDirectory $script:TestEnv.TempDirectory.Path -OlderThanDays 1
            
            $result.SpaceFreed | Should -BeGreaterThan 0
        }
    }
    
    Context "Error Handling and Edge Cases" {
        It "should handle permission denied errors" {
            $restrictedDir = Join-Path $script:TestEnv.TempDirectory.Path "restricted"
            New-Item -ItemType Directory -Path $restrictedDir -Force | Out-Null
            
            try {
                if ($IsWindows) {
                    # Windows: アクセス権限の変更は管理者権限が必要なため、テストを調整
                    Set-TestInconclusive "Permission testing requires administrative privileges on Windows"
                } else {
                    # Unix系: chmod でアクセス権限を変更
                    chmod 000 $restrictedDir
                    
                    $result = Ensure-DirectoryExists -DirectoryPath (Join-Path $restrictedDir "subdir")
                    $result.Success | Should -Be $false
                }
            }
            finally {
                if (-not $IsWindows) {
                    chmod 755 $restrictedDir -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "should handle disk space exhaustion gracefully" {
            # ディスク容量不足の完全なシミュレーションは困難
            # 代わりに大きなファイルでの処理をテスト
            $hugePath = Join-Path $script:TestEnv.TempDirectory.Path "huge.txt"
            
            try {
                # 利用可能な空き容量を確認
                $drive = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq (Split-Path $hugePath -Qualifier) }
                if ($drive -and $drive.FreeSpace -lt 100MB) {
                    Set-TestInconclusive "Insufficient disk space for testing"
                }
                
                # 大きなファイルの作成をテスト
                $largeContent = "x" * 1000000  # 1MB
                $result = Save-WithHistory -Content $largeContent -OutputPath $hugePath -HistoryDir $script:TestHistoryDir
                
                $result | Should -Not -BeNullOrEmpty
            }
            catch {
                # ディスク容量不足エラーが適切に処理されることを確認
                $_.Exception.Message | Should -Match "(disk|space|capacity)"
            }
        }
        
        It "should handle path length limitations" {
            if ($IsWindows) {
                # Windows MAX_PATH制限のテスト
                $longPath = Join-Path $script:TestEnv.TempDirectory.Path ("a" * 200)
                $longPath += ".csv"
                
                if ($longPath.Length -gt 260) {
                    $result = Save-WithHistory -Content "test" -OutputPath $longPath -HistoryDir $script:TestHistoryDir
                    # パスが長すぎる場合のエラーハンドリング
                    $result.Success | Should -Be $false
                }
            } else {
                Set-TestInconclusive "Path length testing is Windows-specific"
            }
        }
        
        It "should handle concurrent file access" {
            $concurrentPath = Join-Path $script:TestEnv.TempDirectory.Path "concurrent.csv"
            
            $jobs = 1..3 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($FilePath, $JobId)
                    
                    try {
                        # 同じファイルに同時書き込み
                        1..10 | ForEach-Object {
                            Add-Content -Path $FilePath -Value "Job $JobId Line $_" -Encoding UTF8
                            Start-Sleep -Milliseconds (Get-Random -Minimum 1 -Maximum 10)
                        }
                        return @{ Success = $true; JobId = $JobId }
                    }
                    catch {
                        return @{ Success = $false; JobId = $JobId; Error = $_.Exception.Message }
                    }
                } -ArgumentList $concurrentPath, $_
            }
            
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
            
            # すべてのジョブが完了することを確認
            $results | Should -HaveCount 3
            
            # ファイルが存在し、内容が書き込まれていることを確認
            Test-Path $concurrentPath | Should -Be $true
            $fileContent = Get-Content -Path $concurrentPath
            $fileContent.Count | Should -BeGreaterThan 0
        }
    }
    
    Context "Integration with Lower Layers" {
        It "should use Foundation layer timestamp functions" {
            Mock Get-Timestamp { return "20250817_120000" } -Verifiable
            
            $result = Save-WithHistory -Content "timestamp test" -OutputPath $script:TestFilePath -HistoryDir $script:TestHistoryDir
            
            $historyFileName = Split-Path $result.HistoryPath -Leaf
            $historyFileName | Should -Match "20250817_120000"
        }
        
        It "should use Foundation layer encoding functions" {
            Mock Get-CrossPlatformEncoding { return [System.Text.Encoding]::UTF8 } -Verifiable
            
            $unicodeContent = "Unicode: 🌟 田中太郎 🌟"
            $result = Save-WithHistory -Content $unicodeContent -OutputPath $script:TestFilePath -HistoryDir $script:TestHistoryDir
            
            $savedContent = Get-Content -Path $script:TestFilePath -Encoding UTF8 -Raw
            $savedContent | Should -Match "🌟"
        }
        
        It "should use Infrastructure layer error handling" {
            Mock Invoke-WithErrorHandling { 
                param($ScriptBlock)
                return & $ScriptBlock
            } -Verifiable
            
            $result = Save-WithHistory -Content "error handling test" -OutputPath $script:TestFilePath -HistoryDir $script:TestHistoryDir
            
            $result | Should -Not -BeNullOrEmpty
        }
    }
}