# PowerShell & SQLite データ同期システム

# SQL識別子エスケープ関数（基盤機能）
function Protect-SqliteIdentifier {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Identifier
    )
    
    # SQLite識別子エスケープ：角括弧または二重引用符を含む場合は二重引用符で囲む
    if ($Identifier -match '[\[\]"]') {
        # 二重引用符を二重にエスケープしてから、全体を二重引用符で囲む
        return "`"$($Identifier.Replace('`"', '`"`"'))`""
    }
    
    return $Identifier
}

function Find-ProjectRoot {
    [CmdletBinding()]
    param(
        [string[]]$MarkerFiles = @("run.bat"),
        [string]$StartPath = $PSScriptRoot
    )
    
    $currentPath = $StartPath
    
    while ($currentPath -and (Split-Path $currentPath -Parent)) {
        foreach ($marker in $MarkerFiles) {
            if (Get-ChildItem -Path $currentPath -Filter $marker -File | Select-Object -First 1) {
                return $currentPath
            }
        }
        $currentPath = Split-Path $currentPath -Parent
    }
    
    # マーカーファイルが見つからない場合
    return $StartPath
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


# 安全なTest-Path（null値チェック付き）
function Test-PathSafe {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )
    
    if ([string]::IsNullOrEmpty($Path)) {
        return $false
    }
    
    return Test-Path $Path
}

# タイムスタンプ取得（タイムゾーン対応・設定非依存・Layer 1）
function Get-Timestamp {
    param(
        [string]$Format = "yyyyMMdd_HHmmss",
        [string]$TimeZone = "Asia/Tokyo"
    )
    
    try {
        # .NET TimeZoneInfo を使用して指定タイムゾーンの時間を取得
        $targetTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZone)
        $targetTime = [System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $targetTimeZone)
        return $targetTime.ToString($Format)
    }
    catch {
        # タイムゾーン取得に失敗した場合はUTC+9時間で計算（Asia/Tokyoのフォールバック）
        $fallbackTime = [DateTime]::UtcNow.AddHours(9)
        return $fallbackTime.ToString($Format)
    }
}

# SQLite3コマンドラッパー（テスト容易性のため）
function Invoke-Sqlite3 {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Arguments
    )
    
    & sqlite3 @Arguments
}

# SQLiteコマンド実行（汎用・設定非依存）
function Invoke-SqliteCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Query
    )
    
    # SQLite3コマンドをファイルに格納して実行
    # (複数行のコマンドはファイルから実行する必要あり)
    try {
        $tempFile = [System.IO.Path]::GetTempFileName()
        $encoding = Get-CrossPlatformEncoding
        $Query | Out-File -FilePath $tempFile -Encoding $encoding
                    
        $result = Invoke-Sqlite3 $DatabasePath ".read $tempFile" 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "sqlite3コマンドエラー (終了コード: $LASTEXITCODE ,クエリ：$Query ,結果：$result ）"
        }
                    
        return $result
    }
    catch {
        throw "SQLite3の実行に失敗しました: $($_.Exception.Message)"
    }
    finally {
        # クリーンアップ
        if (Test-Path $tempFile) {
            Remove-Item -Path $tempFile -Force
        }
    }
}

# SQLite CSV クエリ実行（ユーティリティ関数・設定非依存）
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
        
        $output = Invoke-Sqlite3 @sqlite3Args 2>&1
        
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

# SQLite CSV出力専用関数（設定非依存）
function Invoke-SqliteCsvExport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Query,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )
    
    try {
        # SQLite3で直接CSV出力（ヘッダー付き）
        $csvArgs = @($DatabasePath, "-csv", "-header", $Query)
        $result = Invoke-Sqlite3 @csvArgs 2>&1
                
        if ($LASTEXITCODE -ne 0) {
            throw "sqlite3 CSV出力エラー (終了コード: $LASTEXITCODE): $result"
        }
                
        # 結果を指定されたファイルに書き込み
        $encoding = Get-CrossPlatformEncoding
        $result | Out-File -FilePath $OutputPath -Encoding $encoding
                
        $recordCount = if ($result -is [array]) { $result.Count - 1 } else { 0 }  # ヘッダー行を除いた件数
        
        return $recordCount
    }
    catch {
        throw "SQLite3 CSV出力の実行に失敗しました: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function @(
    'Protect-SqliteIdentifier',
    'Get-Sqlite3Path',
    'Get-CrossPlatformEncoding',
    'Test-PathSafe',
    'Get-Timestamp',
    'Invoke-Sqlite3',
    'Invoke-SqliteCommand',
    'Invoke-SqliteCsvQuery',
    'Invoke-SqliteCsvExport',
    'Find-ProjectRoot'
)