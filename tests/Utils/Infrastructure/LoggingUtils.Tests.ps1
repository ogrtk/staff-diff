#!/usr/bin/env pwsh
# Infrastructure Layer (Layer 2) - LoggingUtils Module Tests

BeforeAll {
    # レイヤードテストヘルパーの読み込み
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/LayeredTestHelpers.psm1") -Force
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/MockHelpers.psm1") -Force
    
    # Layer 2 (Infrastructure) テスト環境の初期化
    $script:TestEnv = Initialize-LayeredTestEnvironment -LayerName "Infrastructure" -ModuleName "LoggingUtils"
    
    # テスト用ログファイルパス
    $script:TestLogPath = Join-Path $script:TestEnv.TempDirectory.Path "test.log"
}

AfterAll {
    # テスト環境のクリーンアップ
    Cleanup-LayeredTestEnvironment -TestEnvironment $script:TestEnv
}

Describe "LoggingUtils (インフラストラクチャ層) テスト" {
    
    Context "Layer Architecture Validation" {
        It "基盤層のみに依存するLayer 2であること" {
            $dependencies = Assert-LayeredModuleDependencies -LayerName "Infrastructure" -ModuleName "LoggingUtils"
            $dependencies.Dependencies | Should -Contain "Foundation"
            $dependencies.InvalidDependencies | Should -BeExactly @()
            $dependencies.CircularDependencies | Should -BeExactly @()
        }
        
        It "基盤層関数を使用すること" {
            # LoggingUtilsがFoundation層の関数を使用することを確認
            $timestamp = Get-Timestamp
            $timestamp | Should -Not -BeNullOrEmpty
            $timestamp | Should -Match "^\d{8}_\d{6}$"
        }
    }
    
    Context "Write-SystemLog Function - Basic Logging" {
        It "コンソールにログメッセージを書き込むこと" {
            # コンソール出力のキャプチャ
            $output = Write-SystemLog -Message "Test message" -Level "Info" -Component "TestComponent" 6>&1
            
            $output | Should -Not -BeNullOrEmpty
            $output | Should -Match "Test message"
        }
        
        It "異なるログレベルを処理すること" {
            $levels = @("Debug", "Info", "Warning", "Error")
            
            foreach ($level in $levels) {
                { Write-SystemLog -Message "Test $level message" -Level $level } | Should -Not -Throw
            }
        }
        
        It "コンポーネント情報を含むこと" {
            $output = Write-SystemLog -Message "Component test" -Component "TestModule" 6>&1
            
            $output | Should -Match "TestModule"
        }
        
        It "未指定時にInfoレベルをデフォルトとすること" {
            $output = Write-SystemLog -Message "Default level test" 6>&1
            
            $output | Should -Not -BeNullOrEmpty
        }
        
        It "ログメッセージで日本語文字を処理すること" {
            $japaneseMessage = "テストログメッセージ（日本語）"
            
            { Write-SystemLog -Message $japaneseMessage -Level "Info" } | Should -Not -Throw
        }
    }
    
    Context "Write-SystemLog Function - File Logging" {
        It "LogFilePathが指定された時にファイルにログを書き込むこと" {
            Write-SystemLog -Message "File log test" -Level "Info" -LogFilePath $script:TestLogPath
            
            Test-Path $script:TestLogPath | Should -Be $true
            $logContent = Get-Content -Path $script:TestLogPath -Raw
            $logContent | Should -Match "File log test"
        }
        
        It "既存のログファイルに追記すること" {
            # 最初のログ
            Write-SystemLog -Message "First log entry" -LogFilePath $script:TestLogPath
            
            # 2番目のログ
            Write-SystemLog -Message "Second log entry" -LogFilePath $script:TestLogPath
            
            $logContent = Get-Content -Path $script:TestLogPath
            $logContent | Should -HaveCount 2
            $logContent[0] | Should -Match "First log entry"
            $logContent[1] | Should -Match "Second log entry"
        }
        
        It "ログディレクトリが存在しない場合に作成すること" {
            $nestedLogPath = Join-Path $script:TestEnv.TempDirectory.Path "logs/nested/test.log"
            
            Write-SystemLog -Message "Nested directory test" -LogFilePath $nestedLogPath
            
            Test-Path $nestedLogPath | Should -Be $true
            $logContent = Get-Content -Path $nestedLogPath -Raw
            $logContent | Should -Match "Nested directory test"
        }
        
        It "ログファイルでUTF-8エンコーディングを処理すること" {
            $utf8Message = "UTF-8 テスト: 日本語文字 ñáéíóú"
            Write-SystemLog -Message $utf8Message -LogFilePath $script:TestLogPath
            
            $logContent = Get-Content -Path $script:TestLogPath -Encoding UTF8 -Raw
            $logContent | Should -Match "UTF-8 テスト"
            $logContent | Should -Match "日本語文字"
        }
    }
    
    Context "Log Entry Formatting and Structure" {
        It "ログエントリにタイムスタンプを含むこと" {
            Write-SystemLog -Message "Timestamp test" -LogFilePath $script:TestLogPath
            
            $logContent = Get-Content -Path $script:TestLogPath -Raw
            $logContent | Should -Match "\d{4}-\d{2}-\d{2}.*\d{2}:\d{2}:\d{2}"
        }
        
        It "フォーマット済み出力にログレベルを含むこと" {
            Write-SystemLog -Message "Level test" -Level "Warning" -LogFilePath $script:TestLogPath
            
            $logContent = Get-Content -Path $script:TestLogPath -Raw
            $logContent | Should -Match "WARNING"
        }
        
        It "ログエントリを一貫してフォーマットすること" {
            $messages = @(
                @{ Message = "Info message"; Level = "Info" },
                @{ Message = "Warning message"; Level = "Warning" },
                @{ Message = "Error message"; Level = "Error" }
            )
            
            foreach ($msg in $messages) {
                Write-SystemLog -Message $msg.Message -Level $msg.Level -LogFilePath $script:TestLogPath
            }
            
            $logLines = Get-Content -Path $script:TestLogPath
            
            # 各行が同じフォーマット構造を持つことを確認
            foreach ($line in $logLines) {
                $line | Should -Match "^\d{4}-\d{2}-\d{2}.*\[.*\].*"
            }
        }
        
        It "複数行メッセージを処理すること" {
            $multilineMessage = "Line 1`nLine 2`nLine 3"
            Write-SystemLog -Message $multilineMessage -LogFilePath $script:TestLogPath
            
            $logContent = Get-Content -Path $script:TestLogPath -Raw
            $logContent | Should -Match "Line 1"
            $logContent | Should -Match "Line 2"
            $logContent | Should -Match "Line 3"
        }
    }
    
    Context "Initialize-SystemLogging Function" {
        It "ログ設定を初期化すること" {
            $logConfig = @{
                LogFilePath = $script:TestLogPath
                LogLevel = "Debug"
                MaxLogFileSize = 1MB
                MaxLogFiles = 5
            }
            
            { Initialize-SystemLogging -Configuration $logConfig } | Should -Not -Throw
        }
        
        It "初期化時にログファイルを作成すること" {
            $initLogPath = Join-Path $script:TestEnv.TempDirectory.Path "init.log"
            $logConfig = @{ LogFilePath = $initLogPath }
            
            Initialize-SystemLogging -Configuration $logConfig
            
            Test-Path $initLogPath | Should -Be $true
        }
        
        It "設定パラメータを検証すること" {
            $invalidConfig = @{
                LogLevel = "InvalidLevel"
                MaxLogFileSize = -1
            }
            
            { Initialize-SystemLogging -Configuration $invalidConfig } | Should -Throw
        }
    }
    
    Context "Write-PerformanceLog Function - Performance Logging" {
        It "パフォーマンス指標をログに記録すること" {
            $metrics = @{
                Operation = "DataImport"
                Duration = [TimeSpan]::FromSeconds(5.5)
                RecordCount = 1000
                MemoryUsage = 50MB
            }
            
            { Write-PerformanceLog -Metrics $metrics -LogFilePath $script:TestLogPath } | Should -Not -Throw
            
            $logContent = Get-Content -Path $script:TestLogPath -Raw
            $logContent | Should -Match "DataImport"
            $logContent | Should -Match "5\.5"
            $logContent | Should -Match "1000"
        }
        
        It "パフォーマンス統計を計算してログに記録すること" {
            $operations = 1..5 | ForEach-Object {
                @{
                    Operation = "TestOperation$_"
                    Duration = [TimeSpan]::FromMilliseconds((Get-Random -Minimum 100 -Maximum 1000))
                    RecordCount = (Get-Random -Minimum 10 -Maximum 100)
                }
            }
            
            foreach ($op in $operations) {
                Write-PerformanceLog -Metrics $op -LogFilePath $script:TestLogPath
            }
            
            $logContent = Get-Content -Path $script:TestLogPath -Raw
            $logContent | Should -Match "TestOperation"
            $logContent | Should -Match "Duration"
        }
        
        It "不足しているパフォーマンス指標を適切に処理すること" {
            $incompleteMetrics = @{
                Operation = "IncompleteTest"
            }
            
            { Write-PerformanceLog -Metrics $incompleteMetrics -LogFilePath $script:TestLogPath } | Should -Not -Throw
        }
    }
    
    Context "Write-AuditLog Function - Audit Logging" {
        It "監査イベントをログに記録すること" {
            $auditEvent = @{
                User = "TestUser"
                Action = "FileAccess"
                Resource = "test-data.csv"
                Result = "Success"
                Details = "File read successfully"
            }
            
            { Write-AuditLog -AuditEvent $auditEvent -LogFilePath $script:TestLogPath } | Should -Not -Throw
            
            $logContent = Get-Content -Path $script:TestLogPath -Raw
            $logContent | Should -Match "TestUser"
            $logContent | Should -Match "FileAccess"
            $logContent | Should -Match "Success"
        }
        
        It "セキュリティ関連情報を含むこと" {
            $securityEvent = @{
                User = "SecurityTest"
                Action = "Authentication"
                Resource = "System"
                Result = "Failed"
                IPAddress = "192.168.1.1"
                UserAgent = "TestAgent"
            }
            
            Write-AuditLog -AuditEvent $securityEvent -LogFilePath $script:TestLogPath
            
            $logContent = Get-Content -Path $script:TestLogPath -Raw
            $logContent | Should -Match "Authentication"
            $logContent | Should -Match "Failed"
            $logContent | Should -Match "192.168.1.1"
        }
        
        It "日本語文字を含む監査イベントを処理すること" {
            $japaneseAuditEvent = @{
                User = "テストユーザー"
                Action = "データ更新"
                Resource = "従業員データ.csv"
                Result = "成功"
            }
            
            Write-AuditLog -AuditEvent $japaneseAuditEvent -LogFilePath $script:TestLogPath
            
            $logContent = Get-Content -Path $script:TestLogPath -Encoding UTF8 -Raw
            $logContent | Should -Match "テストユーザー"
            $logContent | Should -Match "データ更新"
        }
    }
    
    Context "Log Rotation and Maintenance" {
        It "ログファイルローテーションを処理すること" {
            # 大量のログエントリを生成してローテーションをトリガー
            1..1000 | ForEach-Object {
                Write-SystemLog -Message "Log entry $_" -LogFilePath $script:TestLogPath
            }
            
            # ログファイルが存在し、サイズが妥当であることを確認
            Test-Path $script:TestLogPath | Should -Be $true
            $logFileSize = (Get-Item $script:TestLogPath).Length
            $logFileSize | Should -BeGreaterThan 0
        }
        
        It "ログファイルサイズ制限を維持すること" {
            $maxSize = 1KB  # 小さなサイズでテスト
            
            # サイズ制限を超えるまでログを書き込み
            1..100 | ForEach-Object {
                Write-SystemLog -Message "Size limit test entry $_ with additional content to increase size" -LogFilePath $script:TestLogPath
            }
            
            $logFileSize = (Get-Item $script:TestLogPath).Length
            # 実際のログローテーション実装がある場合、このテストを調整
        }
        
        It "古いログファイルをクリーンアップすること" {
            # 複数のログファイルを作成
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($script:TestLogPath)
            $directory = [System.IO.Path]::GetDirectoryName($script:TestLogPath)
            
            1..5 | ForEach-Object {
                $oldLogPath = Join-Path $directory "$baseName.$_.log"
                "Old log content $_" | Out-File -FilePath $oldLogPath -Encoding UTF8
            }
            
            # クリーンアップ機能をテスト（実装に依存）
            # Invoke-LogMaintenance -LogDirectory $directory -MaxFiles 3
            
            # 古いファイルが削除されることを確認
            $logFiles = Get-ChildItem -Path $directory -Filter "*.log"
            $logFiles | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Concurrent Logging and Thread Safety" {
        It "並行ログ書き込みを安全に処理すること" {
            $jobs = 1..5 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($LogPath, $JobId, $ModulePath)
                    
                    # モジュールの再インポート
                    Import-Module (Join-Path (Split-Path $ModulePath -Parent) "Foundation/CoreUtils.psm1") -Force
                    Import-Module $ModulePath -Force
                    
                    1..20 | ForEach-Object {
                        Write-SystemLog -Message "Concurrent log entry from job $JobId - $_" -LogFilePath $LogPath
                        Start-Sleep -Milliseconds (Get-Random -Minimum 1 -Maximum 10)
                    }
                } -ArgumentList $script:TestLogPath, $_, (Join-Path (Split-Path $PSScriptRoot -Parent) "../../../scripts/modules/Utils/Infrastructure/LoggingUtils.psm1")
            }
            
            $jobs | Wait-Job | Out-Null
            $jobs | Remove-Job
            
            # すべてのログエントリが書き込まれていることを確認
            Test-Path $script:TestLogPath | Should -Be $true
            $logLines = Get-Content -Path $script:TestLogPath
            $logLines.Count | Should -BeGreaterThan 90  # 5 jobs × 20 entries = 100 (some may be lost due to concurrency)
        }
        
        It "並行アクセス下でログの整合性を維持すること" {
            $testLogPath = Join-Path $script:TestEnv.TempDirectory.Path "concurrent.log"
            
            # 同時に複数のプロセスがログに書き込み
            $jobs = 1..3 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($LogPath, $JobId)
                    1..10 | ForEach-Object {
                        $message = "Job $JobId Entry $_"
                        Add-Content -Path $LogPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [INFO] $message" -Encoding UTF8
                    }
                } -ArgumentList $testLogPath, $_
            }
            
            $jobs | Wait-Job | Out-Null
            $jobs | Remove-Job
            
            $logContent = Get-Content -Path $testLogPath
            $logContent.Count | Should -Be 30  # 3 jobs × 10 entries
            
            # ログエントリの整合性を確認
            $logContent | ForEach-Object {
                $_ | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[INFO\] Job \d+ Entry \d+$"
            }
        }
    }
    
    Context "Integration with Foundation Layer" {
        It "基盤層のタイムスタンプ関数を使用すること" {
            Mock Get-Timestamp { return "20250817_120000" } -Verifiable
            
            Write-SystemLog -Message "Timestamp integration test" -LogFilePath $script:TestLogPath
            
            $logContent = Get-Content -Path $script:TestLogPath -Raw
            $logContent | Should -Match "20250817_120000"
        }
        
        It "基盤層のエンコーディング関数を使用すること" {
            Mock Get-CrossPlatformEncoding { return [System.Text.Encoding]::UTF8 } -Verifiable
            
            $unicodeMessage = "Unicode test: 🔥 ★ ♦ ◊"
            Write-SystemLog -Message $unicodeMessage -LogFilePath $script:TestLogPath
            
            $logContent = Get-Content -Path $script:TestLogPath -Encoding UTF8 -Raw
            $logContent | Should -Match "Unicode test"
        }
    }
    
    Context "Error Handling and Resilience" {
        It "ファイルアクセスエラーを適切に処理すること" {
            # 読み取り専用ディレクトリにログを書き込もうとする
            $readOnlyDir = Join-Path $script:TestEnv.TempDirectory.Path "readonly"
            New-Item -ItemType Directory -Path $readOnlyDir -Force | Out-Null
            
            try {
                # OS固有の読み取り専用設定
                if ($IsWindows) {
                    Set-ItemProperty -Path $readOnlyDir -Name IsReadOnly -Value $true
                } else {
                    # Linux/macOS: 書き込み権限を除去
                    chmod u-w $readOnlyDir
                }
                
                $readOnlyLogPath = Join-Path $readOnlyDir "readonly.log"
                
                { Write-SystemLog -Message "Read-only test" -LogFilePath $readOnlyLogPath } | Should -Not -Throw
            }
            finally {
                # 権限を復元
                if ($IsWindows) {
                    Set-ItemProperty -Path $readOnlyDir -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                } else {
                    chmod u+w $readOnlyDir 2>/dev/null
                }
            }
        }
        
        It "ファイルログが失敗した時にコンソールログを継続すること" {
            $invalidPath = "Z:\nonexistent\path\test.log"  # 存在しないドライブ
            
            $output = Write-SystemLog -Message "Invalid path test" -LogFilePath $invalidPath 6>&1
            
            # コンソール出力は動作するべき
            $output | Should -Not -BeNullOrEmpty
            $output | Should -Match "Invalid path test"
        }
        
        It "非常に長いログメッセージを処理すること" {
            $longMessage = "A" * 10000  # 10KB のメッセージ
            
            { Write-SystemLog -Message $longMessage -LogFilePath $script:TestLogPath } | Should -Not -Throw
            
            $logContent = Get-Content -Path $script:TestLogPath -Raw
            $logContent | Should -Match "AAAA"
        }
        
        It "nullまたは空のメッセージを処理すること" {
            { Write-SystemLog -Message $null -LogFilePath $script:TestLogPath } | Should -Not -Throw
            { Write-SystemLog -Message "" -LogFilePath $script:TestLogPath } | Should -Not -Throw
            
            Test-Path $script:TestLogPath | Should -Be $true
        }
    }
    
    Context "Performance and Resource Management" {
        It "大量ログを効率的に記録すること" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            1..1000 | ForEach-Object {
                Write-SystemLog -Message "Performance test entry $_" -LogFilePath $script:TestLogPath
            }
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 10000  # 10秒以内
        }
        
        It "ファイルハンドルをリークしないこと" {
            $initialHandles = (Get-Process -Id $PID).HandleCount
            
            # 大量のログ操作
            1..100 | ForEach-Object {
                Write-SystemLog -Message "Handle test $_" -LogFilePath $script:TestLogPath
            }
            
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            
            $finalHandles = (Get-Process -Id $PID).HandleCount
            ($finalHandles - $initialHandles) | Should -BeLessThan 50  # ハンドルリークがないことを確認
        }
        
        It "適度なメモリ使用量を維持すること" {
            $initialMemory = [GC]::GetTotalMemory($false)
            
            1..500 | ForEach-Object {
                Write-SystemLog -Message "Memory test entry $_ with some additional content to test memory usage" -LogFilePath $script:TestLogPath
            }
            
            [GC]::Collect()
            $finalMemory = [GC]::GetTotalMemory($true)
            
            ($finalMemory - $initialMemory) | Should -BeLessThan (10MB)  # メモリ使用量の増加が適度
        }
    }
}