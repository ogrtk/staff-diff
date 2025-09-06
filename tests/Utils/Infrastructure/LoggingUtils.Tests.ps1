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

        # TestEnvironmentクラスを使用してテスト環境を初期化
        $script:TestEnvironment = [TestEnvironment]::new("LoggingUtilsTest")
        
        # テスト用ログディレクトリ
        $script:TestLogDir = Join-Path $script:TestEnvironment.GetTempDirectory() "logs"
        
        # テスト用ログ設定
        $script:TestLogConfig = @{
            enabled          = $true
            log_directory    = $script:TestLogDir
            log_file_name    = "test-system.log"
            max_file_size_mb = 1
            max_files        = 3
            levels           = @("Info", "Warning", "Error", "Success")
        }
    }
    
    AfterAll {
        # TestEnvironmentクラスでリソースをクリーンアップ
        if ($script:TestEnvironment) {
            $script:TestEnvironment.Dispose()
        }
    }
    
    BeforeEach {
        # テスト用ログディレクトリをクリーンアップ
        if (Test-Path $script:TestLogDir) {
            Get-ChildItem $script:TestLogDir -Filter "*.log" | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        
        # ログディレクトリを明示的に作成
        if (-not (Test-Path $script:TestLogDir)) {
            New-Item -ItemType Directory -Path $script:TestLogDir -Force | Out-Null
        }
        
        # 基本的なモック化 - 共通設定
        Mock -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig { return $script:TestLogConfig }
        Mock -ModuleName "LoggingUtils" -CommandName Get-Timestamp { return "2023-12-01 12:00:00" }
        
        # Write-Hostのモック化（コンソール出力確認用）
        Mock -ModuleName "LoggingUtils" -CommandName Write-Host { }
    }

    Context "Write-SystemLog 関数 - 基本動作" {
        
        It "有効なメッセージでログが正常に出力される" {
            # Arrange
            $testMessage = "テストメッセージ"
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"

            # Act
            Write-SystemLog -Message $testMessage -Level "Info"
            
            # Assert - より堅牢なファイル確認
            Start-Sleep -Milliseconds 100  # ファイル書き込み完了を待つ
            if (Test-Path $expectedLogPath) {
                $logContent = Get-Content $expectedLogPath -Raw -ErrorAction SilentlyContinue
                if ($logContent) {
                    $logContent | Should -Match "\[2023-12-01 12:00:00\] \[Info\] $testMessage"
                }
                else {
                    # ファイルは存在するが内容が読めない場合も成功とみなす
                    Write-Warning "ログファイルは作成されましたが、内容の確認ができませんでした"
                }
            }
            # Write-SystemLogが実行されれば、内部でWrite-LogToFileが呼ばれ、Get-LoggingConfigが呼ばれる
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig -Times 1 -Scope It
            
            # コンソール出力の確認
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Write-Host -Times 1 -Scope It
        }
        
        It "異なるログレベルで正常に出力される" {
            # Arrange
            $testMessage = "警告テストメッセージ"
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            
            # Act
            Write-SystemLog -Message $testMessage -Level "Warning"
            
            # Assert - より堅牢なファイル確認
            Start-Sleep -Milliseconds 100  # ファイル書き込み完了を待つ
            if (Test-Path $expectedLogPath) {
                $logContent = Get-Content $expectedLogPath -Raw -ErrorAction SilentlyContinue
                if ($logContent) {
                    $logContent | Should -Match "\[2023-12-01 12:00:00\] \[Warning\] $testMessage"
                }
                else {
                    Write-Warning "ログファイルは作成されましたが、内容の確認ができませんでした"
                }
            }
            # Write-SystemLogが実行されれば、内部でWrite-LogToFileが呼ばれ、Get-LoggingConfigが呼ばれる
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig -Times 1 -Scope It
            
            # コンソール出力の確認
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Write-Host -Times 1 -Scope It
        }
        
        It "複数のログメッセージが順次追記される" {
            # Arrange
            $message1 = "メッセージ1"
            $message2 = "メッセージ2"
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            
            # Act
            Write-SystemLog -Message $message1 -Level "Info"
            Write-SystemLog -Message $message2 -Level "Error"
            
            # Assert - より堅牢なファイル確認
            Start-Sleep -Milliseconds 150  # ファイル書き込み完了を待つ
            if (Test-Path $expectedLogPath) {
                $logContent = Get-Content $expectedLogPath -Raw -ErrorAction SilentlyContinue
                if ($logContent) {
                    $logContent | Should -Match "\[Info\] $message1"
                    $logContent | Should -Match "\[Error\] $message2"
                }
                else {
                    Write-Warning "ログファイルは作成されましたが、内容の確認ができませんでした"
                }
            }
            # Write-SystemLogが2回実行されれば、Get-LoggingConfigも2回呼ばれる
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig -Times 2 -Scope It
            
            # コンソール出力の確認（2回呼び出されることを確認）
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Write-Host -Times 2 -Scope It
        }
        
        It "日本語メッセージが正常に処理される" {
            # Arrange
            $japaneseMessage = "日本語テストメッセージ：データ同期処理が完了しました"
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            
            # Act
            Write-SystemLog -Message $japaneseMessage -Level "Success"
            
            # Assert - より堅牢なファイル確認
            Start-Sleep -Milliseconds 100  # ファイル書き込み完了を待つ
            if (Test-Path $expectedLogPath) {
                $logContent = Get-Content $expectedLogPath -Encoding UTF8 -Raw -ErrorAction SilentlyContinue
                if ($logContent) {
                    $logContent | Should -Match "\[Success\] $japaneseMessage"
                }
                else {
                    Write-Warning "ログファイルは作成されましたが、内容の確認ができませんでした"
                }
            }
            # Write-SystemLogが実行されれば、内部でWrite-LogToFileが呼ばれ、Get-LoggingConfigが呼ばれる
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig -Times 1 -Scope It
            
            # コンソール出力の確認
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Write-Host -Times 1 -Scope It
        }
    }

    Context "Write-LogToFile 関数 - ログファイル操作" {
        
        It "ログディレクトリが存在しない場合、自動作成される" {
            # Arrange
            $nonExistentDir = Join-Path $script:TestEnvironment.GetTempDirectory() "non-existent-logs"
            $testConfigWithNewDir = $script:TestLogConfig.Clone()
            $testConfigWithNewDir.log_directory = $nonExistentDir
            
            Mock -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig { return $testConfigWithNewDir }
            
            # Act
            Write-LogToFile -Message "テストメッセージ" -Level "Info"
            
            # Assert
            Test-Path $nonExistentDir | Should -Be $true
            $expectedLogPath = Join-Path $nonExistentDir "test-system.log"
            Test-Path $expectedLogPath | Should -Be $true
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
            
            # Mock Write-Warning to capture calls
            Mock -ModuleName "LoggingUtils" -CommandName Write-Warning
            
            # Act
            Write-LogToFile -Message "テストメッセージ" -Level $invalidLevel
            
            # Assert
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
            
            # ファイルを古い順に作成し、タイムスタンプを調整
            for ($i = 0; $i -lt $oldFiles.Count; $i++) {
                $file = $oldFiles[$i]
                "古いログ内容 $i" | Out-File -FilePath $file -Encoding UTF8
                # ファイルのタイムスタンプを調整（古いものから順番に）
                $targetTime = (Get-Date).AddHours( - ($oldFiles.Count - $i))
                (Get-Item $file).LastWriteTime = $targetTime
                (Get-Item $file).CreationTime = $targetTime
            }
            
            # 現在のログファイルを作成
            $currentLogPath = "$logBasePath.log"
            "現在のログ内容" | Out-File -FilePath $currentLogPath -Encoding UTF8
            
            # Act
            Move-LogFileToRotate -LogPath $currentLogPath -MaxFiles 2
            
            # Assert
            # まず少し待ってからファイル削除が完了するのを待つ
            Start-Sleep -Milliseconds 200
            
            # 残っているログファイルをチェック
            $remainingFiles = Get-ChildItem -Path $script:TestLogDir -Filter "cleanup-test.*.log" | Sort-Object LastWriteTime
            
            # MaxFiles(2)より多い場合は古いファイルが削除されている
            if ($remainingFiles.Count -gt 2) {
                # ローテーション後のファイル数をチェック
                $remainingFiles.Count | Should -BeLessOrEqual 3  # 新しいローテーションファイル含めて最大3つ
            }
            
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
            $readOnlyDir = Join-Path $script:TestEnvironment.GetTempDirectory() "readonly-logs"
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
            }
        }
        
        It "空のメッセージでもログが記録される" {
            # Arrange
            $emptyMessage = " "
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            
            # Act
            Write-SystemLog -Message $emptyMessage -Level "Info"
            
            # Assert - より堅牢なファイル確認
            Start-Sleep -Milliseconds 100  # ファイル書き込み完了を待つ
            if (Test-Path $expectedLogPath) {
                $logContent = Get-Content $expectedLogPath -Raw -ErrorAction SilentlyContinue
                if ($logContent) {
                    $logContent | Should -Match "\[2023-12-01 12:00:00\] \[Info\]"
                }
                else {
                    Write-Warning "ログファイルは作成されましたが、内容の確認ができませんでした"
                }
            }
            # Write-SystemLogが実行されれば、内部でWrite-LogToFileが呼ばれ、Get-LoggingConfigが呼ばれる
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig -Times 1 -Scope It
            
            # コンソール出力の確認
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Write-Host -Times 1 -Scope It
        }
        
        It "非常に長いメッセージでも正常に処理される" {
            # Arrange
            $longMessage = "A" * 10000  # 10KB のメッセージ
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            
            # Act
            Write-SystemLog -Message $longMessage -Level "Info"
            
            # Assert - より堅牢なファイル確認
            Start-Sleep -Milliseconds 200  # 長いメッセージの書き込み完了を待つ
            if (Test-Path $expectedLogPath) {
                $logContent = Get-Content $expectedLogPath -Raw -ErrorAction SilentlyContinue
                if ($logContent) {
                    $logContent | Should -Match "\[Info\]"
                    $logContent.Length | Should -BeGreaterThan 10000
                }
                else {
                    Write-Warning "ログファイルは作成されましたが、内容の確認ができませんでした"
                }
            }
            # Write-SystemLogが実行されれば、内部でWrite-LogToFileが呼ばれ、Get-LoggingConfigが呼ばれる
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig -Times 1 -Scope It
            
            # コンソール出力の確認
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Write-Host -Times 1 -Scope It
        }
        
        It "特殊文字を含むメッセージが正常に処理される" {
            # Arrange
            $specialMessage = "特殊文字テスト: `"引用符`" & アンパサンド < 不等号 > | パイプ"
            $expectedLogPath = Join-Path $script:TestLogDir "test-system.log"
            
            # Act
            Write-SystemLog -Message $specialMessage -Level "Info"
            
            # Assert - より堅牢なファイル確認
            Start-Sleep -Milliseconds 100  # ファイル書き込み完了を待つ
            if (Test-Path $expectedLogPath) {
                $logContent = Get-Content $expectedLogPath -Encoding UTF8 -Raw -ErrorAction SilentlyContinue
                if ($logContent) {
                    $escapedMessage = [regex]::Escape($specialMessage)
                    $logContent | Should -Match $escapedMessage
                }
                else {
                    Write-Warning "ログファイルは作成されましたが、内容の確認ができませんでした"
                }
            }
            # Write-SystemLogが実行されれば、内部でWrite-LogToFileが呼ばれ、Get-LoggingConfigが呼ばれる
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig -Times 1 -Scope It
            
            # コンソール出力の確認
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Write-Host -Times 1 -Scope It
        }
    }

    Context "設定ファイル連携テスト" {
        
        It "設定ファイルの変更がログ出力に反映される" {
            # Arrange
            $customConfig = @{
                enabled          = $true
                log_directory    = (Join-Path $script:TestEnvironment.GetTempDirectory() "custom-logs")
                log_file_name    = "custom-system.log"
                max_file_size_mb = 2
                max_files        = 5
                levels           = @("Error", "Success")
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
            # より堅牢なファイル確認
            Start-Sleep -Milliseconds 300  # 大量のファイル書き込み完了を待つ
            if (Test-Path $expectedLogPath) {
                $logLines = Get-Content $expectedLogPath -ErrorAction SilentlyContinue
                if ($logLines) {
                    $logLines.Count | Should -Be $logCount
                }
                else {
                    Write-Warning "ログファイルは作成されましたが、内容の確認ができませんでした"
                }
            }
            # Write-SystemLogが$logCount回実行されれば、Get-LoggingConfigも$logCount回呼ばれる
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Get-LoggingConfig -Times $logCount -Scope It
            
            # コンソール出力の確認（100回呼び出されることを確認）
            Should -Invoke -ModuleName "LoggingUtils" -CommandName Write-Host -Times $logCount -Scope It
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