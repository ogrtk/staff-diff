# PowerShell & SQLite データ同期システム
# Layer 2: Error Handling ユーティリティライブラリ（エラーハンドリング専用）

# Layer 1, 2への依存は実行時に解決（Import-Module不要、直接関数呼び出し）

# エラー分類の定義
enum ErrorCategory {
    System       # システム関連エラー（設定ファイル不正、プログラムロジックエラーなど）- リトライ不可・継続不可
    Data         # データ関連エラー（個別レコードのCSV不正、フィルタリング失敗など）- リトライ不可・継続可能
    External     # 外部依存エラー（ファイルアクセス、DB接続、外部コマンドなど）- リトライ可能・継続不可
}

# エラーハンドリング設定取得
function Get-ErrorHandlingConfig {
    try {
        $config = Get-DataSyncConfig
        
        if (-not $config.error_handling) {
            # デフォルト設定を生成
            Write-SystemLog "エラーハンドリング設定が見つかりません。デフォルト値を使用します。" -Level "Warning"
            $defaultErrorHandling = @{
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
            
            # 設定オブジェクトにデフォルト値を追加
            $config | Add-Member -MemberType NoteProperty -Name "error_handling" -Value $defaultErrorHandling -Force
        }
        
        return $config.error_handling
    }
    catch {
        Write-SystemLog "エラーハンドリング設定の取得に失敗しました: $($_.Exception.Message)" -Level "Error"
        # 最低限のフォールバック設定
        return @{
            enabled           = $true
            log_stack_trace   = $true
            retry_settings    = @{ enabled = $false }
            error_levels      = @{}
            continue_on_error = @{}
            cleanup_on_error  = $false
        }
    }
}

# 統合エラーハンドリング関数
function Invoke-WithErrorHandling {
    param(
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$ScriptBlock,
        
        [ErrorCategory]$Category = [ErrorCategory]::System,
        
        [string]$Operation = "",
        
        [ScriptBlock]$CleanupScript = $null,
        
        [hashtable]$Context = @{},
        
        [switch]$SuppressThrow
    )
    
    $errorConfig = Get-ErrorHandlingConfig
    
    if (-not $errorConfig.enabled) {
        # エラーハンドリングが無効の場合は直接実行
        return & $ScriptBlock
    }
    
    $attempt = 1
    $maxAttempts = 1 # Default to no retries
    $retryDelays = @() # Default to no delays

    # リトライ設定を適用 (リトライが有効かつ、現在のカテゴリがリトライ対象の場合のみ)
    if ($errorConfig.retry_settings.enabled -and ($errorConfig.retry_settings.retryable_categories -contains $Category.ToString())) {
        $maxAttempts = $errorConfig.retry_settings.max_attempts
        $retryDelays = $errorConfig.retry_settings.delay_seconds
    }

    $lastException = $null
    
    while ($attempt -le $maxAttempts) {
        try {
            # リトライ対象の場合のみ試行回数を表示
            if ($maxAttempts -gt 1) {
                Write-SystemLog "$Operation を実行中... (試行 $attempt/$maxAttempts)" -Level "Info"
            }
            else {
                Write-SystemLog "$Operation を実行中..." -Level "Info"
            }
            
            # スクリプトブロック実行
            $result = & $ScriptBlock
            
            if ($attempt -gt 1) {
                Write-SystemLog "$Operation が成功しました (試行 $attempt/$maxAttempts)" -Level "Success"
            }
            
            return $result
        }
        catch {
            $lastException = $_
            
            # エラー情報のログ出力
            Write-ErrorDetails -Exception $_ -Category $Category -Operation $Operation -Context $Context -ErrorConfig $errorConfig
            
            # リトライ判定
            if ($errorConfig.retry_settings.enabled -and ($errorConfig.retry_settings.retryable_categories -contains $Category.ToString()) -and $attempt -lt $maxAttempts) {
                $delay = if ($attempt - 1 -lt $retryDelays.Count) { $retryDelays[$attempt - 1] } else { 5 }
                Write-SystemLog "$Operation を $delay 秒後にリトライします... (試行 $($attempt + 1)/$maxAttempts)" -Level "Warning"
                Start-Sleep -Seconds $delay
                $attempt++
                continue
            }
            
            # 最終失敗時の処理
            if ($maxAttempts -gt 1) {
                Write-SystemLog "$Operation が最終的に失敗しました (試行 $attempt/$maxAttempts)" -Level "Error"
            }
            else {
                Write-SystemLog "$Operation が失敗しました" -Level "Error"
            }
            
            # クリーンアップ実行
            if ($CleanupScript -and $errorConfig.cleanup_on_error) {
                try {
                    Write-SystemLog "クリーンアップ処理を実行中..." -Level "Info"
                    & $CleanupScript
                    Write-SystemLog "クリーンアップ処理が完了しました" -Level "Info"
                }
                catch {
                    Write-SystemLog "クリーンアップ処理に失敗しました: $($_.Exception.Message)" -Level "Error"
                }
            }
            
            # 継続判定
            if ($SuppressThrow -or (Get-ShouldContinueOnError -Category $Category -ErrorConfig $errorConfig)) {
                Write-SystemLog "$Operation のエラーを無視して処理を継続します" -Level "Warning"
                return $null
            }
            
            # エラーの再スロー
            throw $lastException
        }
    }
}

# エラーレベル取得
function Get-ErrorLevel {
    param(
        [Parameter(Mandatory = $true)]
        [ErrorCategory]$Category,
        
        [Parameter(Mandatory = $true)]
        $ErrorConfig
    )
    
    $categoryString = $Category.ToString()
    if ($ErrorConfig.error_levels -and $ErrorConfig.error_levels.$categoryString) {
        return $ErrorConfig.error_levels.$categoryString
    }
    
    # デフォルトレベル
    switch ($Category) {
        "System" { return "Error" }
        "Data" { return "Warning" }
        "External" { return "Error" }
        default { return "Error" }
    }
}

# 継続判定
function Get-ShouldContinueOnError {
    param(
        [Parameter(Mandatory = $true)]
        [ErrorCategory]$Category,
        
        [Parameter(Mandatory = $true)]
        $ErrorConfig
    )
    
    $categoryString = $Category.ToString()
    if ($ErrorConfig.continue_on_error -and $null -ne $ErrorConfig.continue_on_error.$categoryString) {
        return $ErrorConfig.continue_on_error.$categoryString
    }
    
    # デフォルトは継続しない
    return $false
}

# エラー詳細ログ出力
function Write-ErrorDetails {
    param(
        [Parameter(Mandatory = $true)]
        $Exception,
        
        [Parameter(Mandatory = $true)]
        [ErrorCategory]$Category,
        
        [string]$Operation = "処理",
        
        [hashtable]$Context = @{},
        
        [Parameter(Mandatory = $true)]
        $ErrorConfig
    )
    
    $level = Get-ErrorLevel -Category $Category -ErrorConfig $ErrorConfig
    
    # 基本エラー情報
    Write-SystemLog "[$Category] $Operation でエラーが発生しました: $($Exception.Exception.Message)" -Level $level
    
    # スタックトレース出力
    if ($ErrorConfig.log_stack_trace -and $Exception.ScriptStackTrace) {
        Write-SystemLog "スタックトレース:`n$($Exception.ScriptStackTrace)" -Level $level
    }
    
    # コンテキスト情報出力
    if ($Context.Count -gt 0) {
        $contextInfo = $Context.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }
        Write-SystemLog "エラーコンテキスト:`n$($contextInfo -join "`n")" -Level $level
    }
    
    # エラーカテゴリ別の追加情報
    switch ($Category) {
        "System" {
            Write-SystemLog "システムエラーの対処方法: 設定ファイル（config/data-sync-config.json）の内容、プログラムロジックを確認してください" -Level $level
        }
        "Data" {
            Write-SystemLog "データエラーの対処方法: 入力データの形式、個別レコードの内容を確認してください" -Level $level
        }
        "External" {
            Write-SystemLog "外部依存エラーの対処方法: ファイルアクセス権限、DB接続、必要なツール（sqlite3など）を確認してください" -Level $level
        }
    }
}

Export-ModuleMember -Function @(
    'Invoke-WithErrorHandling'
)