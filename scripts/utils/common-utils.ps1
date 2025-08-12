# PowerShell & SQLite データ同期システム
# 共通ユーティリティライブラリ（基盤機能）

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "config-utils.ps1")
. (Join-Path $PSScriptRoot "file-utils.ps1")

# クロスプラットフォーム対応エンコーディング取得（DRY原則による統一関数）
function Get-CrossPlatformEncoding {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PowerShell Core (6+) では UTF8 (BOM なし) がデフォルト
        return [System.Text.Encoding]::UTF8
    }
    else {
        # Windows PowerShell (5.1) では UTF8 (BOM あり)
        return [System.Text.UTF8Encoding]::new($true)
    }
}

# ログファイルの初期化
function Initialize-LogFile {
    try {
        $logConfig = Get-LoggingConfig
        
        if (-not $logConfig.enabled) {
            return
        }
        
        $logDir = $logConfig.log_directory
        $logFileName = $logConfig.log_file_name
        
        # ログディレクトリの作成
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        
        $logPath = Join-Path $logDir $logFileName
        
        # ログローテーション
        if (Test-Path $logPath) {
            $logInfo = Get-Item $logPath
            $maxSizeMB = $logConfig.max_file_size_mb
            $maxFiles = $logConfig.max_files
            
            if ($logInfo.Length -gt ($maxSizeMB * 1MB)) {
                Move-LogFile -LogPath $logPath -MaxFiles $maxFiles
            }
        }
        
        # ログファイルの初期化メッセージ
        $timestamp = Get-JapanTimestamp -Format "yyyy-MM-dd HH:mm:ss"
        $initMessage = "[$timestamp] [SYSTEM] ログファイルを初期化しました"
        Add-Content -Path $logPath -Value $initMessage -Encoding UTF8
        
    }
    catch {
        Write-Warning "ログファイルの初期化に失敗しました: $($_.Exception.Message)"
    }
}

# ログファイルのローテーション
function Move-LogFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        
        [int]$MaxFiles = 5
    )
    
    try {
        $logDir = Split-Path -Path $LogPath -Parent
        $logBaseName = [System.IO.Path]::GetFileNameWithoutExtension($LogPath)
        $logExt = [System.IO.Path]::GetExtension($LogPath)
        
        # 既存のローテーションファイルをリネーム
        for ($i = $MaxFiles - 1; $i -ge 1; $i--) {
            $currentFile = Join-Path $logDir "$logBaseName.$i$logExt"
            $nextFile = Join-Path $logDir "$logBaseName.$($i + 1)$logExt"
            
            if (Test-Path $currentFile) {
                if ($i + 1 -le $MaxFiles) {
                    Move-Item $currentFile $nextFile -Force
                }
                else {
                    Remove-Item $currentFile -Force
                }
            }
        }
        
        # 現在のログファイルを .1 にリネーム
        if (Test-Path $LogPath) {
            $rotatedFile = Join-Path $logDir "$logBaseName.1$logExt"
            Move-Item $LogPath $rotatedFile -Force
        }
        
    }
    catch {
        Write-Warning "ログファイルのローテーションに失敗しました: $($_.Exception.Message)"
    }
}

# ログファイルへの書き込み
function Write-LogToFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [string]$Level = "Info"
    )
    
    try {
        $logConfig = Get-LoggingConfig
        
        if (-not $logConfig.enabled -or $Level -notin $logConfig.levels) {
            return
        }
        
        $logDir = $logConfig.log_directory
        $logFileName = $logConfig.log_file_name
        $logPath = Join-Path $logDir $logFileName
        
        $timestamp = Get-JapanTimestamp -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
        
        Add-Content -Path $logPath -Value $logEntry -Encoding UTF8
        
    }
    catch {
        # ログ書き込み失敗時は標準出力に出力
        Write-Host "ログ書き込み失敗: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "メッセージ: $Message" -ForegroundColor Yellow
    }
}

# 統一ログ出力（コンソール + ファイル）
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
    
    # ファイル出力
    Write-LogToFile -Message $Message -Level $Level
}

# ハッシュテーブル変換（データ処理用）
function ConvertTo-DataHashtable {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$InputObject
    )
    
    $hashtable = @{}
    
    foreach ($property in $InputObject.PSObject.Properties) {
        $hashtable[$property.Name] = $property.Value
    }
    
    return $hashtable
}

# 同期アクション件数の取得
function Get-SyncActionCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [string]$TableName = "sync_result"
    )
    
    try {
        $countSql = @"
SELECT 
    sync_action,
    COUNT(*) as count
FROM $TableName 
GROUP BY sync_action
ORDER BY sync_action;
"@
        
        $results = Invoke-SqliteCsvQuery -DatabasePath $DatabasePath -Query $countSql
        
        $counts = @{
            ADD    = 0
            UPDATE = 0
            DELETE = 0
            KEEP   = 0
        }
        
        foreach ($result in $results) {
            if ($counts.ContainsKey($result.sync_action)) {
                $counts[$result.sync_action] = [int]$result.count
            }
        }
        
        return $counts
        
    }
    catch {
        Write-Error "同期アクション件数の取得に失敗しました: $($_.Exception.Message)"
        return @{ ADD = 0; UPDATE = 0; DELETE = 0; KEEP = 0 }
    }
}

# SQLite CSV クエリ実行
function Invoke-SqliteCsvQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Query
    )
    
    try {
        # 一時ファイルパス
        $tempFile = [System.IO.Path]::GetTempFileName() + ".csv"
        
        try {
            # sqlite3コマンドを実行してCSVで出力
            $sqlite3Args = @(
                $DatabasePath
                "-header"
                "-csv"
                $Query
            )
            
            $output = & sqlite3 @sqlite3Args 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                throw "SQLiteコマンド実行エラー: $output"
            }
            
            # CSV内容を一時ファイルに保存
            $output | Out-File -FilePath $tempFile -Encoding UTF8
            
            # CSVとして読み込み
            if (Test-Path $tempFile) {
                $fileInfo = Get-Item $tempFile
                if ($fileInfo.Length -gt 0) {
                    return Import-Csv $tempFile -Encoding UTF8
                }
                else {
                    return @()
                }
            }
            else {
                return @()
            }
            
        }
        finally {
            # 一時ファイルのクリーンアップ
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force
            }
        }
        
    }
    catch {
        Write-Error "SQLiteクエリの実行に失敗しました: $($_.Exception.Message)"
        throw
    }
}