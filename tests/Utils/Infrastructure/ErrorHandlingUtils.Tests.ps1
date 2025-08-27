# PowerShell & SQLite データ同期システム
# Infrastructure/ErrorHandlingUtils.psm1 ユニットテスト

# テスト環境の設定
$ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.Parent.FullName
$ModulePath = Join-Path $ProjectRoot "scripts" "modules" "Utils" "Infrastructure" "ErrorHandlingUtils.psm1"
$TestHelpersPath = Join-Path $ProjectRoot "tests" "TestHelpers"

# レイヤアーキテクチャに従った依存モジュールの読み込み
# Layer 1: Foundation（基盤層）
Import-Module (Join-Path $ProjectRoot "scripts" "modules" "Utils" "Foundation" "CoreUtils.psm1") -Force

# Layer 2: Infrastructure（インフラ層）
Import-Module (Join-Path $ProjectRoot "scripts" "modules" "Utils" "Infrastructure" "ConfigurationUtils.psm1") -Force
Import-Module (Join-Path $ProjectRoot "scripts" "modules" "Utils" "Infrastructure" "LoggingUtils.psm1") -Force

# テストヘルパーの読み込み
Import-Module (Join-Path $TestHelpersPath "TestEnvironmentHelpers.psm1") -Force
Import-Module (Join-Path $TestHelpersPath "MockHelpers.psm1") -Force

# テスト対象モジュールの読み込み
Import-Module $ModulePath -Force

Describe "ErrorHandlingUtils モジュール" {
    
    BeforeAll {
        # TestEnvironmentクラスを使用したテスト環境の初期化
        $script:TestEnv = New-TestEnvironment -TestName "ErrorHandlingUtils"
        $script:OriginalErrorActionPreference = $ErrorActionPreference
        
        # テスト用エラーハンドリング設定
        $script:DefaultErrorConfig = @{
            enabled           = $true
            log_stack_trace   = $true
            retry_settings    = @{
                enabled              = $true
                max_attempts         = 3
                delay_seconds        = @(1, 2, 5)
                retryable_categories = @("External")
            }
            error_levels      = @{
                System   = "Error"
                Data     = "Warning"
                External = "Error"
            }
            continue_on_error = @{
                System   = $false
                Data     = $true
                External = $false
            }
            cleanup_on_error  = $true
        }
        
        # テスト用設定ファイルの作成
        $script:TestEnv.CreateConfigFile(@{
                error_handling = $script:DefaultErrorConfig
            }, "error-handling-test")
    }
    
    AfterAll {
        # TestEnvironmentのクリーンアップ
        if ($script:TestEnv) {
            $script:TestEnv.Dispose()
        }
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
            Mock Get-DataSyncConfig { return $testConfig } -ModuleName ErrorHandlingUtils
            
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
            Mock Get-DataSyncConfig { return $configWithoutErrorHandling } -ModuleName ErrorHandlingUtils
            
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
            Mock Get-DataSyncConfig { throw "設定取得エラー" } -ModuleName ErrorHandlingUtils
            
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
            $testScript = { return "成功" }
            
            # Act
            $result = Invoke-WithErrorHandling -ScriptBlock $testScript -Category System -Operation "テスト操作"
            
            # Assert
            $result | Should -Be "成功"
        }
        
        It "エラーハンドリングが無効の場合、直接実行する" {
            # Arrange
            $disabledErrorConfig = @{ enabled = $false }
            Mock Get-DataSyncConfig { return @{ error_handling = $disabledErrorConfig } } -ModuleName ErrorHandlingUtils
            $testScript = { return "直接実行" }
            
            # Act
            $result = Invoke-WithErrorHandling -ScriptBlock $testScript -Category System -Operation "テスト操作"
            
            # Assert
            $result | Should -Be "直接実行"
        }
        
        It "スクリプトブロックでエラーが発生した場合、例外を再スローする" {
            # Arrange
            Mock Get-DataSyncConfig { return @{ error_handling = $script:DefaultErrorConfig } } -ModuleName ErrorHandlingUtils
            $errorScript = { throw "テストエラー" }
            
            # Act & Assert
            { Invoke-WithErrorHandling -ScriptBlock $errorScript -Category System -Operation "エラーテスト" } | Should -Throw "*テストエラー*"
        }
        
        It "SuppressThrowスイッチが有効な場合、エラーでもnullを返す" {
            # Arrange
            Mock Get-DataSyncConfig { return @{ error_handling = $script:DefaultErrorConfig } } -ModuleName ErrorHandlingUtils
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
            Mock Get-DataSyncConfig { return @{ error_handling = $retryConfig } } -ModuleName ErrorHandlingUtils
            
            $script:attemptCount = 0
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
            $script:attemptCount | Should -Be 3
        }
        
        It "リトライ対象外カテゴリ（System）の場合、リトライしない" {
            # Arrange
            Mock Get-DataSyncConfig { return @{ error_handling = $script:DefaultErrorConfig } } -ModuleName ErrorHandlingUtils
            
            $script:attemptCount = 0
            $noRetryScript = {
                $script:attemptCount++
                throw "Systemエラー"
            }
            
            # Act & Assert
            { Invoke-WithErrorHandling -ScriptBlock $noRetryScript -Category System -Operation "リトライなしテスト" } | Should -Throw
            $script:attemptCount | Should -Be 1
        }
        
        It "最大試行回数に達した場合、最終的にエラーをスローする" {
            # Arrange
            $retryConfig = $script:DefaultErrorConfig.Clone()
            $retryConfig.retry_settings.max_attempts = 2
            $retryConfig.retry_settings.delay_seconds = @(0, 0)
            Mock Get-DataSyncConfig { return @{ error_handling = $retryConfig } } -ModuleName ErrorHandlingUtils
            
            $alwaysFailScript = { throw "常に失敗" }
            
            # Act & Assert
            { Invoke-WithErrorHandling -ScriptBlock $alwaysFailScript -Category External -Operation "最大試行テスト" } | Should -Throw
        }
    }

    Context "Invoke-WithErrorHandling 関数 - クリーンアップ機能" {
        
        It "エラー時にクリーンアップスクリプトが実行される" {
            # Arrange
            Mock Get-DataSyncConfig { return @{ error_handling = $script:DefaultErrorConfig } } -ModuleName ErrorHandlingUtils
            
            $script:cleanupExecuted = $false
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
            $script:cleanupExecuted | Should -Be $true
        }
        
        It "クリーンアップスクリプトでエラーが発生しても、元のエラーが優先される" {
            # Arrange
            Mock Get-DataSyncConfig { return @{ error_handling = $script:DefaultErrorConfig } } -ModuleName ErrorHandlingUtils
            
            $cleanupScript = { throw "クリーンアップエラー" }
            $originalErrorScript = { throw "元のエラー" }
            
            # Act & Assert
            { Invoke-WithErrorHandling -ScriptBlock $originalErrorScript -Category System -Operation "クリーンアップエラーテスト" -CleanupScript $cleanupScript } | Should -Throw "*元のエラー*"
        }
        
        It "cleanup_on_error設定がfalseの場合、クリーンアップが実行されない" {
            # Arrange
            $noCleanupConfig = $script:DefaultErrorConfig.Clone()
            $noCleanupConfig.cleanup_on_error = $false
            Mock Get-DataSyncConfig { return @{ error_handling = $noCleanupConfig } } -ModuleName ErrorHandlingUtils
            
            $script:cleanupExecuted = $false
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
            $script:cleanupExecuted | Should -Be $false
        }
    }

    Context "Invoke-WithErrorHandling 関数 - 継続設定" {
        
        It "Data カテゴリでcontinue_on_errorがtrueの場合、エラーでも継続する" {
            # Arrange
            $continueConfig = $script:DefaultErrorConfig.Clone()
            $continueConfig.continue_on_error.Data = $true
            Mock Get-DataSyncConfig { return @{ error_handling = $continueConfig } } -ModuleName ErrorHandlingUtils
            
            $errorScript = { throw "Dataエラー" }
            
            # Act
            $result = Invoke-WithErrorHandling -ScriptBlock $errorScript -Category Data -Operation "継続テスト"
            
            # Assert
            $result | Should -BeNullOrEmpty
        }
        
        It "System カテゴリでcontinue_on_errorがfalseの場合、エラーで停止する" {
            # Arrange
            Mock Get-DataSyncConfig { return @{ error_handling = $script:DefaultErrorConfig } } -ModuleName ErrorHandlingUtils
            
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
                    System   = "Error"
                    Data     = "Warning"
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
                    System   = $false
                    Data     = $true
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
            
            # Mock Write-SystemLog to capture messages 
            $script:capturedMessages = @() # Reset array
            Mock Write-SystemLog {
                param($Message, $Level)
                $script:capturedMessages += [PSCustomObject]@{ Message = $Message; Level = $Level }
            } -ModuleName ErrorHandlingUtils
            
            # Act
            Write-ErrorDetails -Exception $testException -Category System -Operation "テスト操作" -ErrorConfig $errorConfig
            
            # Assert
            $script:capturedMessages | Should -Not -BeNullOrEmpty
            ($script:capturedMessages | Where-Object { $_.Message -match "テストエラー" }) | Should -Not -BeNullOrEmpty
        }
        
        It "スタックトレースが設定されている場合、スタックトレースを出力する" {
            # Arrange
            $testException = try { 
                function Test-Function { throw "スタックトレーステスト" }
                Test-Function
            }
            catch { $_ }
            $errorConfig = @{ log_stack_trace = $true; error_levels = @{ System = "Error" } }
            
            # Mock Write-SystemLog to capture messages 
            $script:capturedMessages = @() # Reset array
            Mock Write-SystemLog {
                param($Message, $Level)
                $script:capturedMessages += [PSCustomObject]@{ Message = $Message; Level = $Level }
            } -ModuleName ErrorHandlingUtils
            
            # Act
            Write-ErrorDetails -Exception $testException -Category System -Operation "スタックトレーステスト" -ErrorConfig $errorConfig
            
            # Assert
            ($script:capturedMessages | Where-Object { $_.Message -match "スタックトレース" }) | Should -Not -BeNullOrEmpty
        }
        
        It "コンテキスト情報が提供された場合、コンテキストを出力する" {
            # Arrange
            $testException = try { throw "コンテキストテスト" } catch { $_ }
            $errorConfig = @{ error_levels = @{ System = "Error" } }
            $context = @{ "ファイルパス" = "/test/file.txt"; "操作種別" = "読み込み" }
            
            # Mock Write-SystemLog to capture messages 
            $script:capturedMessages = @() # Reset array
            Mock Write-SystemLog {
                param($Message, $Level)
                $script:capturedMessages += [PSCustomObject]@{ Message = $Message; Level = $Level }
            } -ModuleName ErrorHandlingUtils
            
            # Act
            Write-ErrorDetails -Exception $testException -Category System -Operation "コンテキストテスト" -Context $context -ErrorConfig $errorConfig
            
            # Assert
            ($script:capturedMessages | Where-Object { $_.Message -match "エラーコンテキスト" }) | Should -Not -BeNullOrEmpty
            ($script:capturedMessages | Where-Object { $_.Message -match "ファイルパス" }) | Should -Not -BeNullOrEmpty
        }
        
        It "カテゴリ別の対処方法メッセージを出力する" {
            # Arrange
            $testException = try { throw "カテゴリテスト" } catch { $_ }
            $errorConfig = @{ error_levels = @{ Data = "Warning" } }
            
            # Mock Write-SystemLog to capture messages 
            $script:capturedMessages = @() # Reset array
            Mock Write-SystemLog {
                param($Message, $Level)
                $script:capturedMessages += [PSCustomObject]@{ Message = $Message; Level = $Level }
            } -ModuleName ErrorHandlingUtils
            
            # Act
            Write-ErrorDetails -Exception $testException -Category Data -Operation "カテゴリテスト" -ErrorConfig $errorConfig
            
            # Assert
            ($script:capturedMessages | Where-Object { $_.Message -match "データエラーの対処方法" }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Invoke-FileOperationWithErrorHandling 関数" {
        
        It "ファイル操作が正常な場合、結果を返す" {
            # Arrange
            Mock Get-DataSyncConfig { return @{ error_handling = $script:DefaultErrorConfig } } -ModuleName ErrorHandlingUtils
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
            Mock Get-DataSyncConfig { return @{ error_handling = $retryConfig } } -ModuleName ErrorHandlingUtils
            
            $script:attemptCount = 0
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
            $script:attemptCount | Should -Be 2
        }
        
        It "適切なコンテキスト情報が設定される" {
            # Arrange
            Mock Get-DataSyncConfig { return @{ error_handling = $script:DefaultErrorConfig } } -ModuleName ErrorHandlingUtils
            $fileOperation = { throw "ファイルエラー" }
            $filePath = "/test/file.txt"
            $operationType = "削除"
            
            # Invoke-WithErrorHandlingの呼び出しをモック化してコンテキストを確認
            $global:capturedContext = $null
            Mock Invoke-WithErrorHandling {
                param($ScriptBlock, $Category, $Operation, $Context, $CleanupScript)
                $global:capturedContext = $Context
                throw "テストエラー"
            } -ModuleName ErrorHandlingUtils
            
            # Act
            try {
                Invoke-FileOperationWithErrorHandling -FileOperation $fileOperation -FilePath $filePath -OperationType $operationType
            }
            catch {
                # エラーは予期される
            }
            
            # Assert
            $global:capturedContext | Should -Not -BeNullOrEmpty
            $global:capturedContext["ファイルパス"] | Should -Be $filePath
            $global:capturedContext["操作種別"] | Should -Be $operationType
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
            # ErrorCategory enum should be available in the module
            # Test by calling a function that uses the enum
            $systemLevel = Get-ErrorLevel -Category System -ErrorConfig @{error_levels = @{System = "Error" } }
            $systemLevel | Should -Be "Error"
            
            $dataLevel = Get-ErrorLevel -Category Data -ErrorConfig @{error_levels = @{Data = "Warning" } }
            $dataLevel | Should -Be "Warning"
            
            $externalLevel = Get-ErrorLevel -Category External -ErrorConfig @{error_levels = @{External = "Error" } }
            $externalLevel | Should -Be "Error"
        }
        
        It "ErrorCategory を文字列として正しく変換できる" {
            # Test the enum by using functions that accept ErrorCategory parameters
            $systemContinue = Get-ShouldContinueOnError -Category System -ErrorConfig @{continue_on_error = @{System = $false } }
            $systemContinue | Should -Be $false
            
            $dataContinue = Get-ShouldContinueOnError -Category Data -ErrorConfig @{continue_on_error = @{Data = $true } }
            $dataContinue | Should -Be $true
            
            $externalContinue = Get-ShouldContinueOnError -Category External -ErrorConfig @{continue_on_error = @{External = $false } }
            $externalContinue | Should -Be $false
        }
    }

    Context "統合テストとエッジケース" {
        
        It "複雑なネストしたエラーハンドリング" {
            # Arrange
            Mock Get-DataSyncConfig { return @{ error_handling = $script:DefaultErrorConfig } } -ModuleName ErrorHandlingUtils
            
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
            Mock Get-DataSyncConfig { return @{ error_handling = $timeoutConfig } } -ModuleName ErrorHandlingUtils
            
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
            Mock Get-DataSyncConfig { return @{ error_handling = $script:DefaultErrorConfig } } -ModuleName ErrorHandlingUtils
            
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