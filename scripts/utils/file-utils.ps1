# PowerShell & SQLite データ同期システム
# ファイル・CSV操作ユーティリティライブラリ

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "config-utils.ps1")

# 日本時間でタイムスタンプを取得
function Get-JapanTimestamp {
    param(
        [string]$Format = "yyyyMMdd_HHmmss"
    )
    
    $config = Get-DataSyncConfig
    $timezone = if ($config.file_paths.timezone) { $config.file_paths.timezone } else { "Asia/Tokyo" }
    
    try {
        # .NET TimeZoneInfo を使用して日本時間を取得
        $japanTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($timezone)
        $japanTime = [System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $japanTimeZone)
        return $japanTime.ToString($Format)
    }
    catch {
        # タイムゾーン取得に失敗した場合はUTC+9時間で計算
        $japanTime = [DateTime]::UtcNow.AddHours(9)
        return $japanTime.ToString($Format)
    }
}

# 履歴用ファイル名の生成
function New-HistoryFileName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseFileName,
        
        [string]$Extension = ".csv"
    )
    
    $timestamp = Get-JapanTimestamp
    $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($BaseFileName)
    return "${nameWithoutExt}_${timestamp}${Extension}"
}

# 入力ファイルの履歴保存
function Copy-InputFileToHistory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$HistoryDirectory
    )
    
    try {
        if (-not (Test-Path $SourceFilePath)) {
            throw "ソースファイルが存在しません: $SourceFilePath"
        }
        
        # 履歴ディレクトリの作成
        if (-not (Test-Path $HistoryDirectory)) {
            New-Item -ItemType Directory -Path $HistoryDirectory -Force | Out-Null
            Write-Host "履歴ディレクトリを作成しました: $HistoryDirectory" -ForegroundColor Green
        }
        
        # 履歴ファイル名の生成
        $sourceFileName = [System.IO.Path]::GetFileName($SourceFilePath)
        $historyFileName = New-HistoryFileName -BaseFileName $sourceFileName
        $historyFilePath = Join-Path $HistoryDirectory $historyFileName
        
        # ファイルのコピー
        Copy-Item -Path $SourceFilePath -Destination $historyFilePath -Force
        
        Write-Host "ファイルを履歴に保存しました: $historyFilePath" -ForegroundColor Green
        
        return $historyFilePath
        
    }
    catch {
        Write-Error "履歴保存に失敗しました: $($_.Exception.Message)"
        throw
    }
}

# ファイルパス解決（パラメータ優先、設定ファイル）
function Resolve-FilePath {
    param(
        [string]$ParameterPath = "",
        
        [string]$ConfigKey = "",
        
        [string]$Description = "ファイル"
    )
    
    try {
        $resolvedPath = ""
        
        # 1. パラメータ指定を優先
        if (-not [string]::IsNullOrEmpty($ParameterPath)) {
            $resolvedPath = $ParameterPath
            Write-Host "$Description パス（パラメータ指定）: $resolvedPath" -ForegroundColor Yellow
        }
        # 2. 設定ファイルから取得
        elseif (-not [string]::IsNullOrEmpty($ConfigKey)) {
            $config = Get-FilePathConfig
            
            if ($config.$ConfigKey -and -not [string]::IsNullOrEmpty($config.$ConfigKey)) {
                $resolvedPath = $config.$ConfigKey
                Write-Host "$Description パス（設定ファイル）: $resolvedPath" -ForegroundColor Cyan
            }
        }
        
        # パスが解決できない場合
        if ([string]::IsNullOrEmpty($resolvedPath)) {
            throw "$Description のパスが指定されていません（パラメータまたは設定ファイルで指定してください）"
        }
        
        # 相対パスを絶対パスに変換
        if (-not [System.IO.Path]::IsPathRooted($resolvedPath)) {
            $resolvedPath = [System.IO.Path]::GetFullPath($resolvedPath)
        }
        
        return $resolvedPath
        
    }
    catch {
        Write-Error "ファイルパス解決に失敗しました: $($_.Exception.Message)"
        throw
    }
}

# クロスプラットフォーム対応エンコーディング取得
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

# 改行コードの統一
function ConvertTo-UnifiedLineEndings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [string]$LineEnding = "`n"
    )
    
    # すべての改行コードを統一
    $unifiedContent = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    
    # 指定された改行コードに変換
    if ($LineEnding -ne "`n") {
        $unifiedContent = $unifiedContent -replace "`n", $LineEnding
    }
    
    return $unifiedContent
}

# クロスプラットフォーム対応CSV読み込み
function Import-CsvCrossPlatform {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [string]$Delimiter = ",",
        
        [System.Text.Encoding]$Encoding = $null
    )
    
    if (-not $Encoding) {
        $Encoding = Get-CrossPlatformEncoding
    }
    
    try {
        $content = Get-Content -Path $Path -Raw -Encoding $Encoding.WebName
        $unifiedContent = ConvertTo-UnifiedLineEndings -Content $content
        
        # 一時ファイルに書き込んでImport-Csvで読み込み
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            Out-File -FilePath $tempFile -InputObject $unifiedContent -Encoding UTF8 -NoNewline
            return Import-Csv -Path $tempFile -Delimiter $Delimiter
        }
        finally {
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force
            }
        }
    }
    catch {
        Write-Error "CSV読み込みに失敗しました: $($_.Exception.Message)"
        throw
    }
}

# クロスプラットフォーム対応CSV出力
function Export-CsvCrossPlatform {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$InputObject,
        
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [string]$Delimiter = ",",
        
        [System.Text.Encoding]$Encoding = $null,
        
        [bool]$NoTypeInformation = $true
    )
    
    if (-not $Encoding) {
        $Encoding = Get-CrossPlatformEncoding
    }
    
    try {
        # 一時ファイルに出力
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            $InputObject | Export-Csv -Path $tempFile -Delimiter $Delimiter -NoTypeInformation:$NoTypeInformation -Encoding UTF8
            
            # 内容を読み込んで改行コードを統一し、指定されたエンコーディングで出力
            $content = Get-Content -Path $tempFile -Raw -Encoding UTF8
            $unifiedContent = ConvertTo-UnifiedLineEndings -Content $content
            
            Out-FileCrossPlatform -FilePath $Path -Content $unifiedContent -Encoding $Encoding
        }
        finally {
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force
            }
        }
    }
    catch {
        Write-Error "CSV出力に失敗しました: $($_.Exception.Message)"
        throw
    }
}

# クロスプラットフォーム対応ファイル出力
function Out-FileCrossPlatform {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [System.Text.Encoding]$Encoding = $null,
        
        [switch]$NoNewline,
        
        [switch]$Append
    )
    
    if (-not $Encoding) {
        $Encoding = Get-CrossPlatformEncoding
    }
    
    try {
        $directoryPath = [System.IO.Path]::GetDirectoryName($FilePath)
        if (-not (Test-Path $directoryPath)) {
            New-Item -ItemType Directory -Path $directoryPath -Force | Out-Null
        }
        
        if ($Append) {
            # 追記モード
            if ($NoNewline) {
                [System.IO.File]::AppendAllText($FilePath, $Content, $Encoding)
            }
            else {
                # 改行を追加
                $contentWithNewline = $Content
                if (-not $Content.EndsWith("`n") -and -not $Content.EndsWith("`r`n")) {
                    $contentWithNewline += "`n"
                }
                [System.IO.File]::AppendAllText($FilePath, $contentWithNewline, $Encoding)
            }
        }
        else {
            # 通常の書き込みモード
            if ($NoNewline) {
                [System.IO.File]::WriteAllText($FilePath, $Content, $Encoding)
            }
            else {
                # 改行を追加
                $contentWithNewline = $Content
                if (-not $Content.EndsWith("`n") -and -not $Content.EndsWith("`r`n")) {
                    $contentWithNewline += "`n"
                }
                [System.IO.File]::WriteAllText($FilePath, $contentWithNewline, $Encoding)
            }
        }
    }
    catch {
        Write-Error "ファイル出力に失敗しました: $($_.Exception.Message)"
        throw
    }
}