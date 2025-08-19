# PowerShell & SQLite データ同期システム
# Utils/Infrastructure/LoggingUtils.psm1 ユニットテスト

# テストヘルパーを最初にインポート
using module "../../TestHelpers/TestEnvironmentHelpers.psm1"
using module "../../TestHelpers/MockHelpers.psm1"

# 依存関係のモジュールをインポート（モック化準備のため）
using module "../../../scripts/modules/Utils/Foundation/CoreUtils.psm1"
using module "../../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1"

# テスト対象モジュールを最後にインポート
using module "../../../scripts/modules/Utils/Infrastructure/LoggingUtils.psm1"

Describe "LoggingUtils モジュール" {
    
    BeforeAll {
        $script:ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.Parent.FullName

        # テスト環境の初期化
        $script:TestEnv = Initialize-TestEnvironment
        
        # テスト用ログディレクトリ
        $script:TestLogDir = Get-TestDataPath -SubPath "logs" -Temp
        if (-not (Test-Path $script:TestLogDir)) {
            New-Item -Path $script:TestLogDir -ItemType Directory -Force | Out-Null
        }
        
        # テスト用ログ設定
        $script:TestLogConfig = @{
            enabled = $true
            log_directory = $script:TestLogDir
            log_file_name = "test-system.log"
            max_file_size_mb = 1
            max_files = 3
            levels = @("Info", "Warning", "Error", "Success")
        }
    }
    
    AfterAll {
        # テスト環境のクリーンアップ
        Clear-TestEnvironment
        
        # テスト用ログディレクトリのクリーンアップ
        if (Test-Path $script:TestLogDir) {
            Remove-Item $script:TestLogDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    BeforeEach {
        # 基本的なモック化 - 共通設定
        Mock -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig { return $script:TestLogConfig }
        Mock -ModuleName "LoggingUtils" -CommandName Get-Timestamp { return "2023-12-01 12:00:00" }
        
        # テスト用ログディレクトリをクリーンアップ
        if (Test-Path $script:TestLogDir) {
            Get-ChildItem $script:TestLogDir -Filter "*.log" | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Write-SystemLog 関数 - 基本動作" {
        
        It "有効なメッセージでログが正常に出力される" {
            # Arrange
            $testMessage = "テストメッセージ"
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            
            # Act
            Write-SystemLog -Message $testMessage -Level "Info"
            
            # Assert
            Test-Path $expectedLogPath | Should -Be $true
            $logContent = Get-Content $expectedLogPath -Raw
            $logContent | Should -Match "\[2023-12-01 12:00:00\] \[Info\] $testMessage"
        }
        
        It "異なるログレベルで正常に出力される" {
            # Arrange
            $testMessage = "警告テストメッセージ"
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            
            # Act
            Write-SystemLog -Message $testMessage -Level "Warning"
            
            # Assert
            Test-Path $expectedLogPath | Should -Be $true
            $logContent = Get-Content $expectedLogPath -Raw
            $logContent | Should -Match "\[2023-12-01 12:00:00\] \[Warning\] $testMessage"
        }
        
        It "複数のログメッセージが順次追記される" {
            # Arrange
            $message1 = "メッセージ1"
            $message2 = "メッセージ2"
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            
            # Act
            Write-SystemLog -Message $message1 -Level "Info"
            Write-SystemLog -Message $message2 -Level "Error"
            
            # Assert
            Test-Path $expectedLogPath | Should -Be $true
            $logContent = Get-Content $expectedLogPath -Raw
            $logContent | Should -Match "\[Info\] $message1"
            $logContent | Should -Match "\[Error\] $message2"
        }
        
        It "日本語メッセージが正常に処理される" {
            # Arrange
            $japaneseMessage = "日本語テストメッセージ：データ同期処理が完了しました"
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            
            # Act
            Write-SystemLog -Message $japaneseMessage -Level "Success"
            
            # Assert
            Test-Path $expectedLogPath | Should -Be $true
            $logContent = Get-Content $expectedLogPath -Encoding UTF8 -Raw
            $logContent | Should -Match "\[Success\] $japaneseMessage"
        }
    }

    Context "Write-LogToFile 関数 - ログファイル操作" {
        
        It "ログディレクトリが存在しない場合、自動作成される" {
            # Arrange
            $nonExistentDir = Get-TestDataPath -SubPath "non-existent-logs" -Temp
            $testConfigWithNewDir = $script:TestLogConfig.Clone()
            $testConfigWithNewDir.log_directory = $nonExistentDir
            
            Mock -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig { return $testConfigWithNewDir }
            
            # Act
            Write-LogToFile -Message "テストメッセージ" -Level "Info"
            
            # Assert
            Test-Path $nonExistentDir | Should -Be $true
            $expectedLogPath = Join-Path $nonExistentDir "test-system.log"
            Test-Path $expectedLogPath | Should -Be $true
            
            # クリーンアップ
            Remove-Item $nonExistentDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        It "ログ設定が無効の場合、ログファイルが作成されない" {
            # Arrange
            $disabledConfig = $script:TestLogConfig.Clone()
            $disabledConfig.enabled = $false
            Mock -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig { return $disabledConfig }
            
            # Act
            Write-LogToFile -Message "テストメッセージ" -Level "Info"
            
            # Assert
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            Test-Path $expectedLogPath | Should -Be $false
        }
        
        It "無効なログレベルで警告が出力される" {
            # Arrange
            $invalidLevel = "InvalidLevel"
            
            # Act & Assert
            { Write-LogToFile -Message "テストメッセージ" -Level $invalidLevel } | Should -Not -Throw
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Write-Warning -Times 1 -Scope It
        }
    }

    Context "Move-LogFileToRotate 関数 - ログローテーション" {
        
        It "ログファイルが正常にローテーションされる" {
            # Arrange
            $testLogPath = Join-Path $script:TestLogDir "rotate-test.log"
            "テストログ内容" | Out-File -FilePath $testLogPath -Encoding UTF8
            
            Mock -ModuleName "LoggingUtils" -CommandName Get-Timestamp { return "20231201_120000" }
            
            # Act
            Move-LogFileToRotate -LogPath $testLogPath -MaxFiles 3
            
            # Assert
            Test-Path $testLogPath | Should -Be $false
            $rotatedLogPath = Join-Path $script:TestLogDir "rotate-test.20231201_120000.log"
            Test-Path $rotatedLogPath | Should -Be $true
            
            $rotatedContent = Get-Content $rotatedLogPath -Raw
            $rotatedContent | Should -Match "テストログ内容"
        }
        
        It "最大ファイル数を超える古いログファイルが削除される" {
            # Arrange
            $logBasePath = Join-Path $script:TestLogDir "cleanup-test"
            
            # 複数のローテーション済みログファイルを作成
            $oldFiles = @(
                "$logBasePath.20231130_100000.log",
                "$logBasePath.20231130_110000.log",
                "$logBasePath.20231130_120000.log",
                "$logBasePath.20231130_130000.log"
            )
            
            foreach ($file in $oldFiles) {
                "古いログ内容" | Out-File -FilePath $file -Encoding UTF8
                # ファイルのタイムスタンプを調整
                (Get-Item $file).LastWriteTime = (Get-Date).AddHours(-($oldFiles.IndexOf($file) + 1))
            }
            
            # 現在のログファイルを作成
            $currentLogPath = "$logBasePath.log"
            "現在のログ内容" | Out-File -FilePath $currentLogPath -Encoding UTF8
            
            # Act
            Move-LogFileToRotate -LogPath $currentLogPath -MaxFiles 2
            
            # Assert
            # 最新の2つのローテーション済みファイルと新しいローテーションファイルのみが残る
            $remainingFiles = Get-ChildItem -Path $script:TestLogDir -Filter "cleanup-test.*.log"
            $remainingFiles.Count | Should -BeLessOrEqual 3
            
            # 最も古いファイルが削除されていることを確認
            Test-Path $oldFiles[0] | Should -Be $false
        }
        
        It "ログファイルが存在しない場合でもエラーが発生しない" {
            # Arrange
            $nonExistentLogPath = Join-Path $script:TestLogDir "non-existent.log"
            
            # Act & Assert
            { Move-LogFileToRotate -LogPath $nonExistentLogPath -MaxFiles 3 } | Should -Not -Throw
        }
    }

    Context "ログファイルサイズ制限とローテーション統合テスト" {
        
        It "ファイルサイズ制限を超えた場合、自動でローテーションされる" {
            # Arrange
            $testConfigSmallSize = $script:TestLogConfig.Clone()
            $testConfigSmallSize.max_file_size_mb = 0.001  # 非常に小さなサイズ制限
            Mock -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig { return $testConfigSmallSize }
            
            $testLogPath = Join-Path $script:TestLogDir "test-system.log"
            
            # 大きなログファイルを作成
            $largeContent = "A" * 2000  # 2KB のコンテンツ
            $largeContent | Out-File -FilePath $testLogPath -Encoding UTF8
            
            Mock -ModuleName "LoggingUtils" -CommandName Get-Timestamp { return "20231201_120000" }
            
            # Act
            Write-LogToFile -Message "新しいログメッセージ" -Level "Info"
            
            # Assert
            # ローテーションされたファイルが存在することを確認
            $rotatedFiles = Get-ChildItem -Path $script:TestLogDir -Filter "test-system.*.log"
            $rotatedFiles.Count | Should -BeGreaterOrEqual 1
            
            # 新しいログファイルにメッセージが記録されていることを確認
            Test-Path $testLogPath | Should -Be $true
            $newLogContent = Get-Content $testLogPath -Raw
            $newLogContent | Should -Match "新しいログメッセージ"
        }
    }

    Context "エラーハンドリングとエッジケース" {
        
        It "書き込み権限がない場合でもエラーで停止しない" {
            # Arrange
            $readOnlyDir = Get-TestDataPath -SubPath "readonly-logs" -Temp
            New-Item -Path $readOnlyDir -ItemType Directory -Force | Out-Null
            
            $readOnlyConfig = $script:TestLogConfig.Clone()
            $readOnlyConfig.log_directory = $readOnlyDir
            Mock -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig { return $readOnlyConfig }
            
            # ディレクトリを読み取り専用に設定（Windows の場合）
            if ($IsWindows) {
                $acl = Get-Acl $readOnlyDir
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $env:USERNAME, "Write", "Deny"
                )
                $acl.SetAccessRule($accessRule)
                try {
                    Set-Acl $readOnlyDir $acl -ErrorAction SilentlyContinue
                }
                catch {
                    # 権限設定に失敗した場合はテストをスキップ
                    Set-ItResult -Skipped -Because "ディレクトリの読み取り専用設定に失敗しました"
                    return
                }
            }
            
            try {
                # Act & Assert
                { Write-LogToFile -Message "テストメッセージ" -Level "Info" } | Should -Not -Throw
            }
            finally {
                # クリーンアップ
                if ($IsWindows -and (Test-Path $readOnlyDir)) {
                    # 読み取り専用属性を削除
                    $acl = Get-Acl $readOnlyDir
                    $acl.Access | Where-Object { $_.IdentityReference -eq $env:USERNAME -and $_.AccessControlType -eq "Deny" } |
                    ForEach-Object { $acl.RemoveAccessRule($_) }
                    Set-Acl $readOnlyDir $acl -ErrorAction SilentlyContinue
                }
                Remove-Item $readOnlyDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        It "空のメッセージでもログが記録される" {
            # Arrange
            $emptyMessage = ""
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            
            # Act
            Write-SystemLog -Message $emptyMessage -Level "Info"
            
            # Assert
            Test-Path $expectedLogPath | Should -Be $true
            $logContent = Get-Content $expectedLogPath -Raw
            $logContent | Should -Match "\[2023-12-01 12:00:00\] \[Info\] $emptyMessage"
        }
        
        It "非常に長いメッセージでも正常に処理される" {
            # Arrange
            $longMessage = "A" * 10000  # 10KB のメッセージ
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            
            # Act
            Write-SystemLog -Message $longMessage -Level "Info"
            
            # Assert
            Test-Path $expectedLogPath | Should -Be $true
            $logContent = Get-Content $expectedLogPath -Raw
            $logContent | Should -Match "\[Info\]"
            $logContent.Length | Should -BeGreaterThan 10000
        }
        
        It "特殊文字を含むメッセージが正常に処理される" {
            # Arrange
            $specialMessage = "特殊文字テスト: `"引用符`" & アンパサンド < 不等号 > | パイプ"
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            
            # Act
            Write-SystemLog -Message $specialMessage -Level "Info"
            
            # Assert
            Test-Path $expectedLogPath | Should -Be $true
            $logContent = Get-Content $expectedLogPath -Encoding UTF8 -Raw
            $logContent | Should -Match [regex]::Escape($specialMessage)
        }
    }

    Context "設定ファイル連携テスト" {
        
        It "設定ファイルの変更がログ出力に反映される" {
            # Arrange
            $customConfig = @{
                enabled = $true
                log_directory = (Get-TestDataPath -SubPath "custom-logs" -Temp)
                log_file_name = "custom-system.log"
                max_file_size_mb = 2
                max_files = 5
                levels = @("Error", "Success")
            }
            
            if (-not (Test-Path $customConfig.log_directory)) {
                New-Item -Path $customConfig.log_directory -ItemType Directory -Force | Out-Null
            }
            
            Mock -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig { return $customConfig }
            
            # Act
            Write-LogToFile -Message "カスタム設定テスト" -Level "Error"
            
            # Assert
            $expectedLogPath = Join-Path $customConfig.log_directory "custom-system.log"
            Test-Path $expectedLogPath | Should -Be $true
            $logContent = Get-Content $expectedLogPath -Raw
            $logContent | Should -Match "カスタム設定テスト"
            
            # クリーンアップ
            Remove-Item $customConfig.log_directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "パフォーマンステスト" {
        
        It "大量のログ出力でも一定時間内に完了する" {
            # Arrange
            $logCount = 100
            $startTime = Get-Date
            
            # Act
            for ($i = 1; $i -le $logCount; $i++) {
                Write-SystemLog -Message "パフォーマンステスト ログ $i" -Level "Info"
            }
            
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            
            # Assert
            $duration | Should -BeLessThan 10  # 10秒以内に完了すべき
            
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            Test-Path $expectedLogPath | Should -Be $true
            $logLines = Get-Content $expectedLogPath
            $logLines.Count | Should -Be $logCount
        }
    }

    Context "関数のエクスポート確認" {
        
        It "必要な関数がエクスポートされている" {
            # Arrange
            $expectedFunctions = @(
                'Write-SystemLog',
                'Write-LogToFile',
                'Move-LogFileToRotate'
            )
            
            # Act
            $module = Get-Module -Name LoggingUtils
            $exportedFunctions = $module.ExportedFunctions.Keys
            
            # Assert
            foreach ($func in $expectedFunctions) {
                $exportedFunctions | Should -Contain $func
            }
        }
    }
}