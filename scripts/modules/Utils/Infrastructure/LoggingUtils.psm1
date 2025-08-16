# PowerShell & SQLite データ同期システム
# Layer 2: Logging ユーティリティライブラリ（高度なログ機能）

# Layer 1, 2への依存は実行時にImport-Moduleで解決


# ログファイルのローテーション（ユーティリティ関数）
function Move-LogFileToRotate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        
        [int]$MaxFiles = 5
    )
    
    $logDir = Split-Path -Path $LogPath -Parent
    $logBaseName = [System.IO.Path]::GetFileNameWithoutExtension($LogPath)
    $logExt = [System.IO.Path]::GetExtension($LogPath)
    
    # 現在のログファイルをタイムスタンプ付きでリネーム
    if (Test-Path $LogPath) {
        $timestamp = Get-Timestamp -Format "yyyyMMdd_HHmmss"
        $rotatedFile = Join-Path $logDir "$logBaseName.$timestamp$logExt"
        Move-Item $LogPath $rotatedFile -Force -ErrorAction SilentlyContinue
    }
    
    # 古いログファイルを削除（MaxFiles数を超える場合）
    $existingLogs = Get-ChildItem -Path $logDir -Filter "$logBaseName.*$logExt" |
        Where-Object { $_.Name -match "$logBaseName\.(\d{8}_\d{6})$logExt" } |
        Sort-Object LastWriteTime -Descending
    
    if ($existingLogs.Count -gt $MaxFiles) {
        $filesToDelete = $existingLogs | Select-Object -Skip $MaxFiles
        foreach ($file in $filesToDelete) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
        }
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
    $logConfig = Get-LoggingConfig
        
    if (-not $logConfig.enabled) {
        # ログ設定が無効の場合何もしない
        return
    }
    if ($Level -notin $logConfig.levels) {
        Write-Warning "ログ記録機能で想定しないレベルが指定されています：$Level"
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
            Move-LogFileToRotate -LogPath $logPath -MaxFiles $logConfig.max_files
        }
    }
        
    $timestamp = Get-Timestamp -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
        
    Add-Content -Path $logPath -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ログ出力
function Write-SystemLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    # コンソール出力
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
        # ※設定読込前やファイルシステムエラー時のフォールバック
    }
}

Export-ModuleMember -Function @(
    'Move-LogFileToRotate',
    'Write-LogToFile',
    'Write-SystemLog'
)