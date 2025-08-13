# PowerShell & SQLite データ同期システム
# 共通ユーティリティライブラリ（基盤機能）

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "config-utils.ps1")
. (Join-Path $PSScriptRoot "file-utils.ps1")

# SQLite3コマンドパス取得（DRY原則による統一関数）
function Get-Sqlite3Path {
    try {
        $sqlite3Path = Get-Command sqlite3 -ErrorAction SilentlyContinue
        if (-not $sqlite3Path) {
            throw "sqlite3コマンドが見つかりません。sqlite3をインストールしてPATHに追加してください。"
        }
        return $sqlite3Path
    }
    catch {
        throw "SQLite3コマンドの取得に失敗しました: $($_.Exception.Message)"
    }
}

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

# テーブルクリア（汎用・リトライ対応）
function Clear-Table {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [switch]$ShowStatistics = $true
    )
    
    try {
        # テーブルの存在確認
        $checkTableQuery = @"
SELECT name FROM sqlite_master 
WHERE type='table' AND name='$TableName';
"@
        
        $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $checkTableQuery
        
        if ($result -and $result.Count -gt 0) {
            # レコード数を事前に取得（統計表示用）
            if ($ShowStatistics) {
                $countQuery = "SELECT COUNT(*) as count FROM $TableName;"
                $countResult = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $countQuery
                $existingCount = if ($countResult -and $countResult[0]) { $countResult[0].count } else { 0 }
                
                Write-SystemLog "テーブル '$TableName' をクリア中（既存件数: $existingCount）..." -Level "Info"
            }
            else {
                Write-SystemLog "テーブル '$TableName' をクリア中..." -Level "Info"
            }
            
            # テーブル内容を削除
            $deleteQuery = "DELETE FROM $TableName;"
            Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $deleteQuery
            
            Write-SystemLog "テーブル '$TableName' のクリアが完了しました" -Level "Success"
        }
        else {
            Write-SystemLog "テーブル '$TableName' は存在しないため、スキップします" -Level "Info"
        }
        
    }
    catch {
        Write-SystemLog "テーブルクリア処理に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
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