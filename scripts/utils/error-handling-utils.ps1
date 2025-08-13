# PowerShell & SQLite データ同期システム
# エラーハンドリングユーティリティライブラリ

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "config-utils.ps1")
. (Join-Path $PSScriptRoot "common-utils.ps1")

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
        
        [Parameter(Mandatory = $true)]
        [ErrorCategory]$Category,
        
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
    $maxAttempts = 1
    $retryDelays = @()
    
    # リトライ設定の取得
    if ($errorConfig.retry_settings.enabled -and $Category -in $errorConfig.retry_settings.retryable_categories) {
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
            $errorLevel = Get-ErrorLevel -Category $Category -ErrorConfig $errorConfig
            
            # エラー情報のログ出力
            Write-ErrorDetails -Exception $_ -Category $Category -Operation $Operation -Context $Context -ErrorConfig $errorConfig
            
            # リトライ判定
            if ($attempt -lt $maxAttempts) {
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

# ファイル操作エラーハンドリング専用関数
function Invoke-FileOperationWithErrorHandling {
    param(
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$ScriptBlock,
        
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [string]$Operation = "ファイル操作",
        
        [switch]$SuppressThrow
    )
    
    $context = @{
        "ファイルパス" = $FilePath
        "操作種別"   = $Operation
    }
    
    $cleanupScript = {
        # ファイル操作特有のクリーンアップ
        if (Test-Path $FilePath -ErrorAction SilentlyContinue) {
            $fileInfo = Get-Item $FilePath -ErrorAction SilentlyContinue
            if ($fileInfo) {
                Write-SystemLog "ファイル情報 - サイズ: $($fileInfo.Length) bytes, 最終更新: $($fileInfo.LastWriteTime)" -Level "Info"
            }
        }
    }
    
    return Invoke-WithErrorHandling -ScriptBlock $ScriptBlock -Category External -Operation $Operation -Context $context -CleanupScript $cleanupScript -SuppressThrow:$SuppressThrow
}

# データベース操作エラーハンドリング専用関数
function Invoke-DatabaseOperationWithErrorHandling {
    param(
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$ScriptBlock,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [string]$Operation = "データベース操作",
        
        [string]$TableName = "",
        
        [switch]$SuppressThrow
    )
    
    $context = @{
        "データベースパス" = $DatabasePath
        "操作種別"     = $Operation
    }
    
    if ($TableName) {
        $context["テーブル名"] = $TableName
    }
    
    $cleanupScript = {
        # データベース操作特有のクリーンアップ
        if (Test-Path $DatabasePath -ErrorAction SilentlyContinue) {
            $dbInfo = Get-Item $DatabasePath -ErrorAction SilentlyContinue
            if ($dbInfo) {
                Write-SystemLog "データベース情報 - サイズ: $($dbInfo.Length) bytes, 最終更新: $($dbInfo.LastWriteTime)" -Level "Info"
            }
        }
    }
    
    return Invoke-WithErrorHandling -ScriptBlock $ScriptBlock -Category External -Operation $Operation -Context $context -CleanupScript $cleanupScript -SuppressThrow:$SuppressThrow
}

# 設定検証エラーハンドリング専用関数  
function Invoke-ConfigValidationWithErrorHandling {
    param(
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$ValidationOperation,
        
        [string]$ConfigSection = "全体設定",
        
        [switch]$SuppressThrow
    )
    
    $context = @{
        "設定セクション" = $ConfigSection
    }
    
    return Invoke-WithErrorHandling -ScriptBlock $ValidationOperation -Category System -Operation "設定の検証" -Context $context -SuppressThrow:$SuppressThrow
}

# 外部コマンド実行エラーハンドリング専用関数
function Invoke-ExternalCommandWithErrorHandling {
    param(
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$ScriptBlock,
        
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        
        [string]$Operation = "外部コマンド実行",
        
        [switch]$SuppressThrow
    )
    
    $context = @{
        "コマンド名" = $CommandName
        "操作種別"  = $Operation
    }
    
    $cleanupScript = {
        # 外部コマンド特有のクリーンアップ
        Write-SystemLog "外部コマンドの終了コード: $LASTEXITCODE" -Level "Info"
        
        # コマンド可用性チェック
        $commandPath = Get-Command $CommandName -ErrorAction SilentlyContinue
        if ($commandPath) {
            Write-SystemLog "コマンドパス: $($commandPath.Source)" -Level "Info"
        }
        else {
            Write-SystemLog "コマンドが見つかりません: $CommandName" -Level "Warning"
        }
    }
    
    return Invoke-WithErrorHandling -ScriptBlock $ScriptBlock -Category External -Operation $Operation -Context $context -CleanupScript $cleanupScript -SuppressThrow:$SuppressThrow
}

# 安全な関数実行（エラーを例外として再スローしない）
function Invoke-SafeOperation {
    param(
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$Operation,
        
        [string]$OperationName = "操作",
        
        [ErrorCategory]$Category = "System",
        
        $DefaultReturn = $null
    )
    
    $result = Invoke-WithErrorHandling -ScriptBlock $Operation -Category $Category -Operation $OperationName -SuppressThrow
    
    if ($null -eq $result) {
        Write-SystemLog "$OperationName の実行に失敗しましたが、デフォルト値を返します" -Level "Warning"
        return $DefaultReturn
    }
    
    return $result
}