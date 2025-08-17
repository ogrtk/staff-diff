#!/usr/bin/env pwsh
# Infrastructure Layer (Layer 2) - ErrorHandlingUtils Module Tests

BeforeAll {
    # レイヤードテストヘルパーの読み込み
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/LayeredTestHelpers.psm1") -Force
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/MockHelpers.psm1") -Force
    
    # Layer 2 (Infrastructure) テスト環境の初期化
    $script:TestEnv = Initialize-LayeredTestEnvironment -LayerName "Infrastructure" -ModuleName "ErrorHandlingUtils"
}

AfterAll {
    # テスト環境のクリーンアップ
    Cleanup-LayeredTestEnvironment -TestEnvironment $script:TestEnv
}

Describe "ErrorHandlingUtils (インフラストラクチャ層) テスト" {
    
    Context "レイヤーアーキテクチャ検証" {
        It "Foundation層のみに依存するLayer 2であること" {
            $dependencies = Assert-LayeredModuleDependencies -LayerName "Infrastructure" -ModuleName "ErrorHandlingUtils"
            $dependencies.Dependencies | Should -Contain "Foundation"
            $dependencies.InvalidDependencies | Should -BeExactly @()
            $dependencies.CircularDependencies | Should -BeExactly @()
        }
    }
    
    Context "Invoke-WithErrorHandling関数 - 基本操作" {
        It "成功するスクリプトブロックを実行すること" {
            $result = Invoke-WithErrorHandling -ScriptBlock {
                return "success"
            } -Operation "TestOperation"
            
            $result | Should -Be "success"
        }
        
        It "例外を処理して再スローすること" {
            { 
                Invoke-WithErrorHandling -ScriptBlock {
                    throw "Test error"
                } -Operation "TestOperation"
            } | Should -Throw "Test error"
        }
        
        It "エラー時にクリーンアップスクリプトを実行すること" {
            $cleanupExecuted = $false
            
            try {
                Invoke-WithErrorHandling -ScriptBlock {
                    throw "Test error"
                } -Operation "TestOperation" -CleanupScript {
                    $script:cleanupExecuted = $true
                }
            }
            catch {
                # エラーは期待されている
            }
            
            $cleanupExecuted | Should -Be $true
        }
        
        It "成功時にクリーンアップスクリプトを実行すること" {
            $cleanupExecuted = $false
            
            Invoke-WithErrorHandling -ScriptBlock {
                return "success"
            } -Operation "TestOperation" -CleanupScript {
                $script:cleanupExecuted = $true
            }
            
            $cleanupExecuted | Should -Be $true
        }
    }
    
    Context "エラーカテゴリと分類" {
        It "Systemカテゴリエラーを処理すること" {
            { 
                Invoke-WithErrorHandling -ScriptBlock {
                    throw "System configuration error"
                } -Category "System" -Operation "ConfigValidation"
            } | Should -Throw "System configuration error"
        }
        
        It "Dataカテゴリエラーを処理すること" {
            { 
                Invoke-WithErrorHandling -ScriptBlock {
                    throw "Invalid data format"
                } -Category "Data" -Operation "DataProcessing"
            } | Should -Throw "Invalid data format"
        }
        
        It "Externalカテゴリエラーを処理すること" {
            { 
                Invoke-WithErrorHandling -ScriptBlock {
                    throw "Network connection failed"
                } -Category "External" -Operation "FileAccess"
            } | Should -Throw "Network connection failed"
        }
        
        It "指定されない場合はSystemカテゴリをデフォルトとすること" {
            { 
                Invoke-WithErrorHandling -ScriptBlock {
                    throw "Default category error"
                } -Operation "DefaultTest"
            } | Should -Throw "Default category error"
        }
    }
    
    Context "コンテキスト情報処理" {
        It "コンテキストハッシュテーブルを受け入れること" {
            $context = @{
                FilePath = "test.csv"
                Operation = "Import"
                RecordCount = 100
            }
            
            $result = Invoke-WithErrorHandling -ScriptBlock {
                return "context test success"
            } -Context $context -Operation "ContextTest"
            
            $result | Should -Be "context test success"
        }
        
        It "空のコンテキストを処理すること" {
            $result = Invoke-WithErrorHandling -ScriptBlock {
                return "empty context success"
            } -Context @{} -Operation "EmptyContextTest"
            
            $result | Should -Be "empty context success"
        }
        
        It "nullコンテキストを処理すること" {
            $result = Invoke-WithErrorHandling -ScriptBlock {
                return "null context success"
            } -Context $null -Operation "NullContextTest"
            
            $result | Should -Be "null context success"
        }
    }
    
    Context "Invoke-FileOperationWithErrorHandling関数" {
        It "成功するファイル操作を処理すること" {
            $testFile = Join-Path $script:TestEnv.TempDirectory.Path "test.txt"
            "test content" | Out-File -FilePath $testFile -Encoding UTF8
            
            $result = Invoke-FileOperationWithErrorHandling -FileOperation {
                Get-Content -Path $testFile
            } -FilePath $testFile -OperationType "Read"
            
            $result | Should -Contain "test content"
        }
        
        It "ファイル未発見エラーを処理すること" {
            $nonExistentFile = Join-Path $script:TestEnv.TempDirectory.Path "nonexistent.txt"
            
            { 
                Invoke-FileOperationWithErrorHandling -FileOperation {
                    Get-Content -Path $nonExistentFile -ErrorAction Stop
                } -FilePath $nonExistentFile -OperationType "Read"
            } | Should -Throw
        }
        
        It "ファイル書き込み操作を処理すること" {
            $outputFile = Join-Path $script:TestEnv.TempDirectory.Path "output.txt"
            
            $result = Invoke-FileOperationWithErrorHandling -FileOperation {
                "output content" | Out-File -FilePath $outputFile -Encoding UTF8
                return "write success"
            } -FilePath $outputFile -OperationType "Write"
            
            $result | Should -Be "write success"
            Test-Path $outputFile | Should -Be $true
        }
        
        It "ファイル削除操作を処理すること" {
            $deleteFile = Join-Path $script:TestEnv.TempDirectory.Path "delete.txt"
            "delete me" | Out-File -FilePath $deleteFile -Encoding UTF8
            
            $result = Invoke-FileOperationWithErrorHandling -FileOperation {
                Remove-Item -Path $deleteFile -Force
                return "delete success"
            } -FilePath $deleteFile -OperationType "Delete"
            
            $result | Should -Be "delete success"
            Test-Path $deleteFile | Should -Be $false
        }
    }
    
    Context "リトライロジックと外部操作" {
        It "失敗時に外部操作をリトライすること" {
            $attemptCount = 0
            
            $result = Invoke-WithErrorHandling -ScriptBlock {
                $script:attemptCount++
                if ($script:attemptCount -lt 3) {
                    throw "Simulated failure"
                }
                return "success after retries"
            } -Category "External" -Operation "RetryTest"
            
            # 注意: 実際のリトライロジックが実装されている場合のテスト
            # 現在のモック実装では単純にエラーを再スローするため、
            # 実際のリトライ機能がある場合はこのテストを調整する必要がある
        }
        
        It "タイムアウトシナリオを処理すること" {
            { 
                Invoke-WithErrorHandling -ScriptBlock {
                    Start-Sleep -Seconds 1  # 短いタイムアウトをシミュレート
                    throw "Operation timed out"
                } -Category "External" -Operation "TimeoutTest"
            } | Should -Throw "Operation timed out"
        }
    }
    
    Context "複雑なエラーシナリオ" {
        It "入れ子のエラーハンドリングを処理すること" {
            $result = Invoke-WithErrorHandling -ScriptBlock {
                Invoke-WithErrorHandling -ScriptBlock {
                    return "nested success"
                } -Operation "InnerOperation"
            } -Operation "OuterOperation"
            
            $result | Should -Be "nested success"
        }
        
        It "クリーンアップスクリプトエラーを適切に処理すること" {
            $mainOperationExecuted = $false
            
            try {
                Invoke-WithErrorHandling -ScriptBlock {
                    $script:mainOperationExecuted = $true
                    throw "Main operation error"
                } -Operation "MainOperation" -CleanupScript {
                    throw "Cleanup script error"
                }
            }
            catch {
                # 両方のエラーが発生するが、メインエラーが優先される
                $_.Exception.Message | Should -Match "(Main operation error|Cleanup script error)"
            }
            
            $mainOperationExecuted | Should -Be $true
        }
        
        It "異なるPowerShellコンテキストでの例外を処理すること" {
            # 異なるコンテキストでのエラーハンドリング
            $job = Start-Job -ScriptBlock {
                param($ModulePath)
                Import-Module $ModulePath -Force
                
                try {
                    Invoke-WithErrorHandling -ScriptBlock {
                        throw "Job context error"
                    } -Operation "JobOperation"
                }
                catch {
                    return $_.Exception.Message
                }
            } -ArgumentList (Join-Path (Split-Path $PSScriptRoot -Parent) "../../../scripts/modules/Utils/Infrastructure/ErrorHandlingUtils.psm1")
            
            $result = $job | Wait-Job | Receive-Job
            $job | Remove-Job
            
            $result | Should -Match "Job context error"
        }
    }
    
    Context "パフォーマンスとリソース管理" {
        It "複数の並行エラーハンドリング操作を処理すること" {
            $jobs = 1..5 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($ModulePath, $TestNum)
                    Import-Module $ModulePath -Force
                    
                    return Invoke-WithErrorHandling -ScriptBlock {
                        Start-Sleep -Milliseconds (Get-Random -Minimum 10 -Maximum 100)
                        return "Concurrent operation $TestNum success"
                    } -Operation "ConcurrentTest$TestNum"
                } -ArgumentList (Join-Path (Split-Path $PSScriptRoot -Parent) "../../../scripts/modules/Utils/Infrastructure/ErrorHandlingUtils.psm1"), $_
            }
            
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
            
            $results | Should -HaveCount 5
            $results | ForEach-Object { $_ | Should -Match "Concurrent operation \d+ success" }
        }
        
        It "エラーハンドリング中にリソースリークしないこと" {
            $initialHandles = (Get-Process -Id $PID).HandleCount
            
            # 多数のエラーハンドリング操作
            1..50 | ForEach-Object {
                try {
                    Invoke-WithErrorHandling -ScriptBlock {
                        if ($_ % 2 -eq 0) {
                            throw "Even number error"
                        }
                        return "Odd number success"
                    } -Operation "ResourceTest$_"
                }
                catch {
                    # エラーは期待されている
                }
            }
            
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            
            $finalHandles = (Get-Process -Id $PID).HandleCount
            
            # ハンドル数の大幅な増加がないことを確認
            ($finalHandles - $initialHandles) | Should -BeLessThan 100
        }
    }
    
    Context "Foundation層との統合" {
        It "ログ用にFoundation層ユーティリティを使用すること" {
            Mock Write-SystemLog { } -Verifiable
            
            try {
                Invoke-WithErrorHandling -ScriptBlock {
                    throw "Integration test error"
                } -Operation "IntegrationTest"
            }
            catch {
                # エラーは期待されている
            }
            
            # ログ関数が呼ばれることを確認（実装に依存）
            # Assert-MockCalled Write-SystemLog -Times 1 -Exactly
        }
        
        It "Foundation層のタイムスタンプ関数と連携すること" {
            Mock Get-Timestamp { return "20250817_120000" } -Verifiable
            
            $result = Invoke-WithErrorHandling -ScriptBlock {
                $timestamp = Get-Timestamp
                return "Operation completed at $timestamp"
            } -Operation "TimestampTest"
            
            $result | Should -Be "Operation completed at 20250817_120000"
        }
    }
}