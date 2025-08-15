# PowerShell & SQLite データ同期システム
# Layer 2: Logging ユーティリティライブラリ（高度なログ機能）

# Layer 1, 2への依存は実行時にImport-Moduleで解決


# ログファイルのローテーション（ユーティリティ関数）
function Move-LogFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        
        [int]$MaxFiles = 5
    )
    
    $logDir = Split-Path -Path $LogPath -Parent
    $logBaseName = [System.IO.Path]::GetFileNameWithoutExtension($LogPath)
    $logExt = [System.IO.Path]::GetExtension($LogPath)
    
    # 既存のローテーションファイルをリネーム
    for ($i = $MaxFiles - 1; $i -ge 1; $i--) {
        $currentFile = Join-Path $logDir "$logBaseName.$i$logExt"
        $nextFile = Join-Path $logDir "$logBaseName.$($i + 1)$logExt"
        
        if (Test-Path $currentFile) {
            if ($i + 1 -le $MaxFiles) {
                Move-Item $currentFile $nextFile -Force -ErrorAction SilentlyContinue
            }
            else {
                Remove-Item $currentFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    # 現在のログファイルを .1 にリネーム
    if (Test-Path $LogPath) {
        $rotatedFile = Join-Path $logDir "$logBaseName.1$logExt"
        Move-Item $LogPath $rotatedFile -Force -ErrorAction SilentlyContinue
    }
}

# ログファイルへの書き込み（ユーティリティ関数）
function Write-LogToFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [string]$Level = "Info"
    )
    
    # 設定ファイルベースのログ設定を使用
    try {
        $logConfig = Get-LoggingConfig
        
        if (-not $logConfig.enabled -or $Level -notin $logConfig.levels) {
            return
        }
        
        $logDir = $logConfig.log_directory
        $logFileName = $logConfig.log_file_name
        $logPath = Join-Path $logDir $logFileName
        
        # ログディレクトリの確認と作成
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        
        # ログファイルサイズチェックとローテーション
        if (Test-Path $logPath) {
            $fileSizeMB = (Get-Item $logPath).Length / 1MB
            if ($fileSizeMB -gt $logConfig.max_file_size_mb) {
                Move-LogFile -LogPath $logPath -MaxFiles $logConfig.max_files
            }
        }
        
        $timestamp = Get-Timestamp -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
        
        Add-Content -Path $logPath -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch {
        # ログ設定取得に失敗した場合は何もしない（無限ループ回避）
        return
    }
}

# 統一ログ出力（コンソール + ファイル、フォールバック対応）
function Write-SystemLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    # コンソール出力（常に実行）
    switch ($Level) {
        "Info" {
            Write-Host $Message -ForegroundColor Cyan
        }
        "Warning" {
            Write-Host $Message -ForegroundColor Yellow
        }
        "Error" {
            Write-Host $Message -ForegroundColor Red
        }
        "Success" {
            Write-Host $Message -ForegroundColor Green
        }
    }
    
    # ファイル出力（設定が利用可能な場合のみ、エラー時は無視）
    try {
        Write-LogToFile -Message $Message -Level $Level
    }
    catch {
        # ファイル出力に失敗してもエラーにしない
        # 設定読み込み前やファイルシステムエラー時のフォールバック
    }
}

Export-ModuleMember -Function @(
    'Move-LogFile',
    'Write-LogToFile',
    'Write-SystemLog'
)