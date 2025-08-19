# PowerShell & SQLite データ同期システム
# Infrastructure/ErrorHandlingUtils.psm1 ユニットテスト

# テスト環境の設定
$ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.Parent.FullName
$ModulePath = Join-Path $ProjectRoot "scripts" "modules" "Utils" "Infrastructure" "ErrorHandlingUtils.psm1"
$TestHelpersPath = Join-Path $ProjectRoot "tests" "TestHelpers"

# 依存モジュールの読み込み
Import-Module (Join-Path $ProjectRoot "scripts" "modules" "Utils" "Foundation" "CoreUtils.psm1") -Force
Import-Module (Join-Path $ProjectRoot "scripts" "modules" "Utils" "Infrastructure" "ConfigurationUtils.psm1") -Force

# テストヘルパーの読み込み
Import-Module (Join-Path $TestHelpersPath "TestEnvironmentHelpers.psm1") -Force
Import-Module (Join-Path $TestHelpersPath "MockHelpers.psm1") -Force

# テスト対象モジュールの読み込み
Import-Module $ModulePath -Force

Describe "ErrorHandlingUtils モジュール" {
    
    BeforeAll {
        # テスト環境の初期化
        $script:TestEnv = Initialize-TestEnvironment -ProjectRoot $ProjectRoot
        $script:OriginalErrorActionPreference = $ErrorActionPreference
        
        # テスト用エラーハンドリング設定
        $script:DefaultErrorConfig = @{
            enabled = $true
            log_stack_trace = $true
            retry_settings = @{
                enabled = $true
                max_attempts = 3
                delay_seconds = @(1, 2, 5)
                retryable_categories = @("External")
            }
            error_levels = @{
                System = "Error"
                Data = "Warning"
                External = "Error"
            }
            continue_on_error = @{
                System = $false
                Data = $true
                External = $false
            }
            cleanup_on_error = $true
        }
    }
    
    AfterAll {
        # テスト環境のクリーンアップ
        Clear-TestEnvironment -ProjectRoot $ProjectRoot
        $ErrorActionPreference = $script:OriginalErrorActionPreference
    }
    
    BeforeEach {
        # モックのリセットは不要。Pesterが自動で管理。
        New-MockLoggingSystem -CaptureMessages -SuppressOutput
    }

    Context "Get-ErrorHandlingConfig 関数" {
        
        It "設定が存在する場合、その設定を返す" {
            # Arrange
            $testConfig = @{ error_handling = $script:DefaultErrorConfig }
            Mock-ConfigurationSystem -MockConfig $testConfig
            
            # Act
            $result = Get-ErrorHandlingConfig
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.enabled | Should -Be $true
            $result.retry_settings.max_attempts | Should -Be 3
            $result.error_levels.System | Should -Be "Error"
        }
        
        It "error_handling設定が存在しない場合、デフォルト設定を生成する" {
            # Arrange
            $configWithoutErrorHandling = @{ version = "1.0.0" }
            Mock-ConfigurationSystem -MockConfig $configWithoutErrorHandling
            
            # Act
            $result = Get-ErrorHandlingConfig
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.enabled | Should -Be $true
            $result.retry_settings.enabled | Should -Be $true
            $result.retry_settings.max_attempts | Should -Be 3
            $result.continue_on_error.System | Should -Be $false
            $result.continue_on_error.Data | Should -Be $true
        }
        
        It "設定取得でエラーが発生した場合、最低限のフォールバック設定を返す" {
            # Arrange
            New-MockCommand -CommandName "Get-DataSyncConfig" -MockScript {
                throw "設定取得エラー"
            }
            
            # Act
            $result = Get-ErrorHandlingConfig
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.enabled | Should -Be $true
            $result.retry_settings.enabled | Should -Be $false
            $result.cleanup_on_error | Should -Be $false
        }
    }

    Context "Invoke-WithErrorHandling 関数 - 基本動作" {
        
        It "正常なスクリプトブロックの場合、結果を返す" {
            # Arrange
            New-MockErrorHandling -ErrorConfig $script:DefaultErrorConfig
            $testScript = { return "成功" }
            
            # Act
            $result = Invoke-WithErrorHandling -ScriptBlock $testScript -Category System -Operation "テスト操作"
            
            # Assert
            $result | Should -Be "成功"
        }
        
        It "エラーハンドリングが無効の場合、直接実行する" {
            # Arrange
            $disabledErrorConfig = @{ enabled = $false }
            New-MockErrorHandling -ErrorConfig $disabledErrorConfig
            $testScript = { return "直接実行" }
            
            # Act
            $result = Invoke-WithErrorHandling -ScriptBlock $testScript -Category System -Operation "テスト操作"
            
            # Assert
            $result | Should -Be "直接実行"
        }
        
        It "スクリプトブロックでエラーが発生した場合、例外を再スローする" {
            # Arrange
            New-MockErrorHandling -ErrorConfig $script:DefaultErrorConfig
            $errorScript = { throw "テストエラー" }
            
            # Act & Assert
            { Invoke-WithErrorHandling -ScriptBlock $errorScript -Category System -Operation "エラーテスト" } | Should -Throw "*テストエラー*"
        }
        
        It "SuppressThrowスイッチが有効な場合、エラーでもnullを返す" {
            # Arrange
            New-MockErrorHandling -ErrorConfig $script:DefaultErrorConfig
            $errorScript = { throw "テストエラー" }
            
            # Act
            $result = Invoke-WithErrorHandling -ScriptBlock $errorScript -Category System -Operation "エラーテスト" -SuppressThrow
            
            # Assert
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Invoke-WithErrorHandling 関数 - リトライ機能" {
        
        It "External カテゴリでエラーが発生した場合、設定に従ってリトライする" {
            # Arrange
            $retryConfig = $script:DefaultErrorConfig.Clone()
            $retryConfig.retry_settings.max_attempts = 3
            $retryConfig.retry_settings.delay_seconds = @(0, 0, 0)  # 待機時間を0にしてテストを高速化
            New-MockErrorHandling -ErrorConfig $retryConfig
            
            $attemptCount = 0
            $retryScript = {
                $script:attemptCount++
                if ($script:attemptCount -lt 3) {
                    throw "リトライテスト"
                }
                return "成功"
            }
            
            # Act
            $result = Invoke-WithErrorHandling -ScriptBlock $retryScript -Category External -Operation "リトライテスト"
            
            # Assert
            $result | Should -Be "成功"
            $attemptCount | Should -Be 3
        }
        
        It "リトライ対象外カテゴリ（System）の場合、リトライしない" {
            # Arrange
            New-MockErrorHandling -ErrorConfig $script:DefaultErrorConfig
            
            $attemptCount = 0
            $noRetryScript = {
                $script:attemptCount++
                throw "Systemエラー"
            }
            
            # Act & Assert
            { Invoke-WithErrorHandling -ScriptBlock $noRetryScript -Category System -Operation "リトライなしテスト" } | Should -Throw
            $attemptCount | Should -Be 1
        }
        
        It "最大試行回数に達した場合、最終的にエラーをスローする" {
            # Arrange
            $retryConfig = $script:DefaultErrorConfig.Clone()
            $retryConfig.retry_settings.max_attempts = 2
            $retryConfig.retry_settings.delay_seconds = @(0, 0)
            New-MockErrorHandling -ErrorConfig $retryConfig
            
            $alwaysFailScript = { throw "常に失敗" }
            
            # Act & Assert
            { Invoke-WithErrorHandling -ScriptBlock $alwaysFailScript -Category External -Operation "最大試行テスト" } | Should -Throw
        }
    }

    Context "Invoke-WithErrorHandling 関数 - クリーンアップ機能" {
        
        It "エラー時にクリーンアップスクリプトが実行される" {
            # Arrange
            New-MockErrorHandling -ErrorConfig $script:DefaultErrorConfig
            
            $cleanupExecuted = $false
            $cleanupScript = { $script:cleanupExecuted = $true }
            $errorScript = { throw "クリーンアップテスト" }
            
            # Act
            try {
                Invoke-WithErrorHandling -ScriptBlock $errorScript -Category System -Operation "クリーンアップテスト" -CleanupScript $cleanupScript
            }
            catch {
                # エラーは予期される
            }
            
            # Assert
            $cleanupExecuted | Should -Be $true
        }
        
        It "クリーンアップスクリプトでエラーが発生しても、元のエラーが優先される" {
            # Arrange
            New-MockErrorHandling -ErrorConfig $script:DefaultErrorConfig
            
            $cleanupScript = { throw "クリーンアップエラー" }
            $originalErrorScript = { throw "元のエラー" }
            
            # Act & Assert
            { Invoke-WithErrorHandling -ScriptBlock $originalErrorScript -Category System -Operation "クリーンアップエラーテスト" -CleanupScript $cleanupScript } | Should -Throw "*元のエラー*"
        }
        
        It "cleanup_on_error設定がfalseの場合、クリーンアップが実行されない" {
            # Arrange
            $noCleanupConfig = $script:DefaultErrorConfig.Clone()
            $noCleanupConfig.cleanup_on_error = $false
            New-MockErrorHandling -ErrorConfig $noCleanupConfig
            
            $cleanupExecuted = $false
            $cleanupScript = { $script:cleanupExecuted = $true }
            $errorScript = { throw "クリーンアップなしテスト" }
            
            # Act
            try {
                Invoke-WithErrorHandling -ScriptBlock $errorScript -Category System -Operation "クリーンアップなしテスト" -CleanupScript $cleanupScript
            }
            catch {
                # エラーは予期される
            }
            
            # Assert
            $cleanupExecuted | Should -Be $false
        }
    }

    Context "Invoke-WithErrorHandling 関数 - 継続設定" {
        
        It "Data カテゴリでcontinue_on_errorがtrueの場合、エラーでも継続する" {
            # Arrange
            $continueConfig = $script:DefaultErrorConfig.Clone()
            $continueConfig.continue_on_error.Data = $true
            New-MockErrorHandling -ErrorConfig $continueConfig
            
            $errorScript = { throw "Dataエラー" }
            
            # Act
            $result = Invoke-WithErrorHandling -ScriptBlock $errorScript -Category Data -Operation "継続テスト"
            
            # Assert
            $result | Should -BeNullOrEmpty
        }
        
        It "System カテゴリでcontinue_on_errorがfalseの場合、エラーで停止する" {
            # Arrange
            New-MockErrorHandling -ErrorConfig $script:DefaultErrorConfig
            
            $errorScript = { throw "Systemエラー" }
            
            # Act & Assert
            { Invoke-WithErrorHandling -ScriptBlock $errorScript -Category System -Operation "停止テスト" } | Should -Throw
        }
    }

    Context "Get-ErrorLevel 関数" {
        
        It "設定されたエラーレベルを正しく返す" {
            # Arrange
            $errorConfig = @{
                error_levels = @{
                    System = "Error"
                    Data = "Warning"
                    External = "Error"
                }
            }
            
            # Act & Assert
            Get-ErrorLevel -Category System -ErrorConfig $errorConfig | Should -Be "Error"
            Get-ErrorLevel -Category Data -ErrorConfig $errorConfig | Should -Be "Warning"
            Get-ErrorLevel -Category External -ErrorConfig $errorConfig | Should -Be "Error"
        }
        
        It "設定されていないカテゴリの場合、デフォルトレベルを返す" {
            # Arrange
            $emptyErrorConfig = @{ error_levels = @{} }
            
            # Act & Assert
            Get-ErrorLevel -Category System -ErrorConfig $emptyErrorConfig | Should -Be "Error"
            Get-ErrorLevel -Category Data -ErrorConfig $emptyErrorConfig | Should -Be "Warning"
            Get-ErrorLevel -Category External -ErrorConfig $emptyErrorConfig | Should -Be "Error"
        }
    }

    Context "Get-ShouldContinueOnError 関数" {
        
        It "設定された継続フラグを正しく返す" {
            # Arrange
            $errorConfig = @{
                continue_on_error = @{
                    System = $false
                    Data = $true
                    External = $false
                }
            }
            
            # Act & Assert
            Get-ShouldContinueOnError -Category System -ErrorConfig $errorConfig | Should -Be $false
            Get-ShouldContinueOnError -Category Data -ErrorConfig $errorConfig | Should -Be $true
            Get-ShouldContinueOnError -Category External -ErrorConfig $errorConfig | Should -Be $false
        }
        
        It "設定されていないカテゴリの場合、デフォルト（false）を返す" {
            # Arrange
            $emptyErrorConfig = @{ continue_on_error = @{} }
            
            # Act & Assert
            Get-ShouldContinueOnError -Category System -ErrorConfig $emptyErrorConfig | Should -Be $false
            Get-ShouldContinueOnError -Category Data -ErrorConfig $emptyErrorConfig | Should -Be $false
            Get-ShouldContinueOnError -Category External -ErrorConfig $emptyErrorConfig | Should -Be $false
        }
    }

    Context "Write-ErrorDetails 関数" {
        
        It "基本的なエラー情報をログ出力する" {
            # Arrange
            $testException = try { throw "テストエラー" } catch { $_ }
            $errorConfig = $script:DefaultErrorConfig
            
            # Act
            Write-ErrorDetails -Exception $testException -Category System -Operation "テスト操作" -ErrorConfig $errorConfig
            
            # Assert
            $logMessages = Get-CapturedLogMessages
            $logMessages | Should -Not -BeNullOrEmpty
            ($logMessages | Where-Object { $_.Message -match "テストエラー" }) | Should -Not -BeNullOrEmpty
        }
        
        It "スタックトレースが設定されている場合、スタックトレースを出力する" {
            # Arrange
            $testException = try { 
                function Test-Function { throw "スタックトレーステスト" }
                Test-Function
            } catch { $_ }
            $errorConfig = @{ log_stack_trace = $true; error_levels = @{ System = "Error" } }
            
            # Act
            Write-ErrorDetails -Exception $testException -Category System -Operation "スタックトレーステスト" -ErrorConfig $errorConfig
            
            # Assert
            $logMessages = Get-CapturedLogMessages
            ($logMessages | Where-Object { $_.Message -match "スタックトレース" }) | Should -Not -BeNullOrEmpty
        }
        
        It "コンテキスト情報が提供された場合、コンテキストを出力する" {
            # Arrange
            $testException = try { throw "コンテキストテスト" } catch { $_ }
            $errorConfig = @{ error_levels = @{ System = "Error" } }
            $context = @{ "ファイルパス" = "/test/file.txt"; "操作種別" = "読み込み" }
            
            # Act
            Write-ErrorDetails -Exception $testException -Category System -Operation "コンテキストテスト" -Context $context -ErrorConfig $errorConfig
            
            # Assert
            $logMessages = Get-CapturedLogMessages
            ($logMessages | Where-Object { $_.Message -match "エラーコンテキスト" }) | Should -Not -BeNullOrEmpty
            ($logMessages | Where-Object { $_.Message -match "ファイルパス" }) | Should -Not -BeNullOrEmpty
        }
        
        It "カテゴリ別の対処方法メッセージを出力する" {
            # Arrange
            $testException = try { throw "カテゴリテスト" } catch { $_ }
            $errorConfig = @{ error_levels = @{ Data = "Warning" } }
            
            # Act
            Write-ErrorDetails -Exception $testException -Category Data -Operation "カテゴリテスト" -ErrorConfig $errorConfig
            
            # Assert
            $logMessages = Get-CapturedLogMessages
            ($logMessages | Where-Object { $_.Message -match "データエラーの対処方法" }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Invoke-FileOperationWithErrorHandling 関数" {
        
        It "ファイル操作が正常な場合、結果を返す" {
            # Arrange
            New-MockErrorHandling -ErrorConfig $script:DefaultErrorConfig
            $fileOperation = { return "ファイル操作成功" }
            $filePath = "/test/file.txt"
            
            # Act
            $result = Invoke-FileOperationWithErrorHandling -FileOperation $fileOperation -FilePath $filePath -OperationType "読み込み"
            
            # Assert
            $result | Should -Be "ファイル操作成功"
        }
        
        It "ファイル操作でエラーが発生した場合、External カテゴリでエラーハンドリングされる" {
            # Arrange
            $retryConfig = $script:DefaultErrorConfig.Clone()
            $retryConfig.retry_settings.max_attempts = 2
            $retryConfig.retry_settings.delay_seconds = @(0, 0)
            New-MockErrorHandling -ErrorConfig $retryConfig
            
            $attemptCount = 0
            $fileOperation = {
                $script:attemptCount++
                if ($script:attemptCount -eq 1) {
                    throw "ファイルアクセスエラー"
                }
                return "リトライ成功"
            }
            $filePath = "/test/file.txt"
            
            # Act
            $result = Invoke-FileOperationWithErrorHandling -FileOperation $fileOperation -FilePath $filePath -OperationType "書き込み"
            
            # Assert
            $result | Should -Be "リトライ成功"
            $attemptCount | Should -Be 2
        }
        
        It "適切なコンテキスト情報が設定される" {
            # Arrange
            New-MockErrorHandling -ErrorConfig $script:DefaultErrorConfig
            $fileOperation = { throw "ファイルエラー" }
            $filePath = "/test/file.txt"
            $operationType = "削除"
            
            # Invoke-WithErrorHandlingの呼び出しをモック化してコンテキストを確認
            $capturedContext = $null
            New-MockCommand -CommandName "Invoke-WithErrorHandling" -MockScript {
                param($ScriptBlock, $Category, $Operation, $Context, $CleanupScript)
                $script:capturedContext = $Context
                throw "テストエラー"
            }
            
            # Act
            try {
                Invoke-FileOperationWithErrorHandling -FileOperation $fileOperation -FilePath $filePath -OperationType $operationType
            }
            catch {
                # エラーは予期される
            }
            
            # Assert
            $capturedContext | Should -Not -BeNullOrEmpty
            $capturedContext["ファイルパス"] | Should -Be $filePath
            $capturedContext["操作種別"] | Should -Be $operationType
        }
    }

    Context "関数のエクスポート確認" {
        
        It "すべての期待される関数がエクスポートされている" {
            # Arrange
            $expectedFunctions = @(
                'Invoke-WithErrorHandling',
                'Invoke-FileOperationWithErrorHandling'
            )
            
            # Act
            $module = Get-Module -Name ErrorHandlingUtils
            $exportedFunctions = $module.ExportedFunctions.Keys
            
            # Assert
            foreach ($expectedFunction in $expectedFunctions) {
                $exportedFunctions | Should -Contain $expectedFunction
            }
        }
    }

    Context "エラーカテゴリ列挙型" {
        
        It "ErrorCategory 列挙型が正しく定義されている" {
            # Act & Assert
            [ErrorCategory]::System | Should -Be "System"
            [ErrorCategory]::Data | Should -Be "Data"
            [ErrorCategory]::External | Should -Be "External"
        }
        
        It "ErrorCategory を文字列として正しく変換できる" {
            # Act & Assert
            [ErrorCategory]::System.ToString() | Should -Be "System"
            [ErrorCategory]::Data.ToString() | Should -Be "Data"
            [ErrorCategory]::External.ToString() | Should -Be "External"
        }
    }

    Context "統合テストとエッジケース" {
        
        It "複雑なネストしたエラーハンドリング" {
            # Arrange
            New-MockErrorHandling -ErrorConfig $script:DefaultErrorConfig
            
            $nestedScript = {
                Invoke-WithErrorHandling -ScriptBlock {
                    throw "ネストしたエラー"
                } -Category Data -Operation "ネスト内操作"
            }
            
            # Act
            $result = Invoke-WithErrorHandling -ScriptBlock $nestedScript -Category System -Operation "ネスト外操作"
            
            # Assert
            # Data カテゴリは継続するため、ネスト内で処理され、外側では正常終了
            $result | Should -BeNullOrEmpty
        }
        
        It "長時間実行されるリトライ処理のタイムアウト" {
            # Arrange
            $timeoutConfig = $script:DefaultErrorConfig.Clone()
            $timeoutConfig.retry_settings.max_attempts = 3
            $timeoutConfig.retry_settings.delay_seconds = @(0.1, 0.1, 0.1)  # 短い間隔
            New-MockErrorHandling -ErrorConfig $timeoutConfig
            
            $startTime = Get-Date
            $timeoutScript = { throw "タイムアウトテスト" }
            
            # Act
            try {
                Invoke-WithErrorHandling -ScriptBlock $timeoutScript -Category External -Operation "タイムアウトテスト"
            }
            catch {
                # エラーは予期される
            }
            $endTime = Get-Date
            
            # Assert
            $duration = ($endTime - $startTime).TotalSeconds
            $duration | Should -BeGreaterThan 0.2  # 最低限のリトライ間隔は確保される
            $duration | Should -BeLessThan 2.0     # 過度に長時間かからない
        }
        
        It "メモリ使用量の大きなエラーコンテキスト処理" {
            # Arrange
            New-MockErrorHandling -ErrorConfig $script:DefaultErrorConfig
            
            # 大きなコンテキストデータを作成
            $largeContext = @{}
            for ($i = 1; $i -le 1000; $i++) {
                $largeContext["key_$i"] = "value_$i" * 100  # 長い文字列
            }
            
            $errorScript = { throw "大容量コンテキストテスト" }
            
            # Act & Assert
            { Invoke-WithErrorHandling -ScriptBlock $errorScript -Category System -Operation "大容量テスト" -Context $largeContext } | Should -Throw
            
            # メモリリークがないことを暗黙的に確認（例外処理が正常に完了すれば良い）
        }
    }
}