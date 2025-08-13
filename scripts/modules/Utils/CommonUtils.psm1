# PowerShell & SQLite データ同期システム
# 共通ユーティリティライブラリ（基盤機能）

# 必要な場合のみファイルユーティリティを読み込み
# 循環参照回避のため、config-utils.ps1のインポートを削除

# 循環参照回避のための最小限の設定取得（内部使用のみ）
function script:Get-MinimalLoggingConfig {
    # 最小限のデフォルト設定（ハードコーディング）
    return @{
        enabled          = $true
        log_directory    = "./logs/"
        log_file_name    = "data-sync-system.log"
        max_file_size_mb = 10
        max_files        = 5
        levels           = @("Info", "Warning", "Error", "Success")
    }
}

# 循環参照回避のための最小限の日本時間取得（内部使用のみ）
function script:Get-MinimalJapanTimestamp {
    param([string]$Format = "yyyy-MM-dd HH:mm:ss")
    
    # 簡単なUTC+9時間計算
    $japanTime = [DateTime]::UtcNow.AddHours(9)
    return $japanTime.ToString($Format)
}

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

# ログファイルの初期化（ユーティリティ関数）
function Initialize-LogFile {
    $logConfig = Get-MinimalLoggingConfig
    
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
    $timestamp = Get-MinimalJapanTimestamp -Format "yyyy-MM-dd HH:mm:ss"
    $initMessage = "[$timestamp] [SYSTEM] ログファイルを初期化しました"
    Add-Content -Path $logPath -Value $initMessage -Encoding UTF8 -ErrorAction SilentlyContinue
}

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
    
    $logConfig = Get-MinimalLoggingConfig
    
    if (-not $logConfig.enabled -or $Level -notin $logConfig.levels) {
        return
    }
    
    $logDir = $logConfig.log_directory
    $logFileName = $logConfig.log_file_name
    $logPath = Join-Path $logDir $logFileName
    
    $timestamp = Get-MinimalJapanTimestamp -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    Add-Content -Path $logPath -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
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

# SQLite CSV クエリ実行（ユーティリティ関数）
function Invoke-SqliteCsvQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Query
    )
    
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
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# SQLiteコマンド実行（汎用）
function Invoke-SqliteCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Query,
        
        [hashtable]$Parameters = @{},
        
        [string]$CsvOutputPath = "",
        
        [switch]$CsvOutput
    )
    
    $context = @{
        "コマンド名" = "sqlite3"
        "操作種別"  = "SQLiteコマンド実行"
    }
    
    $cleanupScript = {
        Write-SystemLog "外部コマンドの終了コード: $LASTEXITCODE" -Level "Info"
        
        $commandPath = Get-Command "sqlite3" -ErrorAction SilentlyContinue
        if ($commandPath) {
            Write-SystemLog "コマンドパス: $($commandPath.Source)" -Level "Info"
        }
        else {
            Write-SystemLog "コマンドが見つかりません: sqlite3" -Level "Warning"
        }
    }
    
    return Invoke-WithErrorHandling -ScriptBlock {
        try {
            $sqlite3Path = Get-Sqlite3Path
            # CSV出力モードの処理
            if ($CsvOutput -and -not [string]::IsNullOrEmpty($CsvOutputPath)) {
                $csvResult = Invoke-WithErrorHandling -ScriptBlock {
                    # SQLite3で直接CSV出力（ヘッダー付き）
                    $csvArgs = @($DatabasePath, "-csv", "-header", $Query)
                    $result = & sqlite3 @csvArgs 2>&1
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "sqlite3 CSV出力エラー (終了コード: $LASTEXITCODE): $result"
                    }
                    
                    # 結果を指定されたファイルに書き込み
                    $encoding = Get-CrossPlatformEncoding
                    $result | Out-File -FilePath $CsvOutputPath -Encoding $encoding
                    
                    Write-SystemLog "SQLite直接CSV出力完了: $CsvOutputPath ($(if ($result -is [array]) { $result.Count - 1 } else { 0 })件)" -Level "Success"
                    return $result.Count - 1  # ヘッダー行を除いた件数を返す
                } -Category External -Operation "SQLite CSV出力" -SuppressThrow
                
                if ($null -ne $csvResult) {
                    return $csvResult
                }
                else {
                    Write-SystemLog "SQLite直接CSV出力に失敗しました。通常処理を続行します。" -Level "Warning"
                }
            }
            
            # 通常のSQLite3コマンド実行
            return Invoke-WithErrorHandling -ScriptBlock {
                $tempFile = [System.IO.Path]::GetTempFileName()
                try {
                    $encoding = Get-CrossPlatformEncoding
                    $Query | Out-File -FilePath $tempFile -Encoding $encoding
                    
                    $result = & sqlite3 $DatabasePath ".read $tempFile" 2>&1
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "sqlite3コマンドエラー (終了コード: $LASTEXITCODE): $result"
                    }
                    
                    return $result
                }
                finally {
                    if (Test-Path $tempFile) {
                        Remove-Item -Path $tempFile -Force
                    }
                }
            } -Category External -Operation "SQLite一時ファイル処理"
        }
        catch {
            throw "SQLite3の実行に失敗しました: $($_.Exception.Message)"
        }
    } -Category External -Operation "SQLiteコマンド実行" -Context $context -CleanupScript $cleanupScript
}

Export-ModuleMember -Function @(
    'Get-Sqlite3Path',
    'Get-CrossPlatformEncoding',
    'Clear-Table',
    'Initialize-LogFile',
    'Move-LogFile',
    'Write-LogToFile',
    'Write-SystemLog',
    'Invoke-SqliteCsvQuery',
    'Invoke-SqliteCommand'
)