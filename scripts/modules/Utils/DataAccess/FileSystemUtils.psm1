# PowerShell & SQLite データ同期システム
# Layer 3: FileSystem ユーティリティライブラリ（ファイル操作・履歴管理）

# Layer 1, 2への依存は実行時に解決

# 日本時間でタイムスタンプを取得

# 履歴用ファイル名の生成
function New-HistoryFileName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseFileName,
        
        [string]$Extension = ".csv"
    )
    
    $timestamp = Get-Timestamp
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
    
    if (-not (Test-Path $SourceFilePath)) {
        throw "ソースファイルが存在しません: $SourceFilePath"
    }
    
    # 履歴ディレクトリの作成
    if (-not (Test-Path $HistoryDirectory)) {
        New-Item -ItemType Directory -Path $HistoryDirectory -Force | Out-Null
        Write-SystemLog "履歴ディレクトリを作成しました: $HistoryDirectory" -Level "Success"
    }
    
    # 履歴ファイル名の生成
    $sourceFileName = [System.IO.Path]::GetFileName($SourceFilePath)
    $historyFileName = New-HistoryFileName -BaseFileName $sourceFileName
    $historyFilePath = Join-Path $HistoryDirectory $historyFileName
    
    # ファイルのコピー
    Copy-Item -Path $SourceFilePath -Destination $historyFilePath -Force
    
    Write-SystemLog "ファイルを履歴に保存しました: $historyFilePath" -Level "Success"

    return $historyFilePath
}

# ファイルパス解決（パラメータ優先、設定ファイル）
function Resolve-FilePath {
    param(
        [string]$ParameterPath = "",
        
        [string]$ConfigKey = "",
        
        [string]$Description = "ファイル"
    )
    
    $resolvedPath = ""
    
    # 1. パラメータ指定を優先
    if (-not [string]::IsNullOrEmpty($ParameterPath)) {
        $resolvedPath = $ParameterPath
        Write-SystemLog "$Description パス（パラメータ指定）: $resolvedPath" -Level "Warning"
    }
    # 2. 設定ファイルから取得
    elseif (-not [string]::IsNullOrEmpty($ConfigKey)) {
        $config = Get-FilePathConfig
        
        if ($config.$ConfigKey -and -not [string]::IsNullOrEmpty($config.$ConfigKey)) {
            $resolvedPath = $config.$ConfigKey
            Write-SystemLog "$Description パス（設定ファイル）: $resolvedPath" -Level "Info"
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

# ディレクトリ作成（存在チェック付き）
function New-DirectoryIfNotExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath,
        
        [string]$Description = "ディレクトリ"
    )
    
    if (-not (Test-Path $DirectoryPath)) {
        try {
            New-Item -ItemType Directory -Path $DirectoryPath -Force | Out-Null
            Write-SystemLog "$Description を作成しました: $DirectoryPath" -Level "Success"
        }
        catch {
            throw "$Description の作成に失敗しました: $DirectoryPath - $($_.Exception.Message)"
        }
    }
    else {
        Write-SystemLog "$Description は既に存在します: $DirectoryPath" -Level "Info"
    }
    
    return $DirectoryPath
}

# ファイル存在確認（詳細情報付き）
function Test-FileExistsWithInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [string]$Description = "ファイル"
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-SystemLog "$Description が見つかりません: $FilePath" -Level "Error"
        return $false
    }
    
    $fileInfo = Get-Item $FilePath
    $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
    
    Write-SystemLog "$Description が見つかりました: $FilePath (サイズ: ${fileSizeMB}MB, 更新日時: $($fileInfo.LastWriteTime))" -Level "Info"
    
    return $true
}

# 出力ファイルの保存（履歴付き）
function Save-OutputFileWithHistory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $true)]
        [string]$HistoryDirectory,
        
        [string]$Description = "出力ファイル",
        
        [string]$Encoding = "UTF8"
    )
    
    try {
        # メインの出力ファイルに保存
        $Content | Out-File -FilePath $OutputPath -Encoding $Encoding -Force
        Write-SystemLog "$Description を保存しました: $OutputPath" -Level "Success"
        
        # 履歴ディレクトリの作成
        New-DirectoryIfNotExists -DirectoryPath $HistoryDirectory -Description "履歴ディレクトリ"
        
        # 履歴ファイル名の生成
        $outputFileName = [System.IO.Path]::GetFileName($OutputPath)
        $historyFileName = New-HistoryFileName -BaseFileName $outputFileName
        $historyFilePath = Join-Path $HistoryDirectory $historyFileName
        
        # 履歴ファイルに保存
        $Content | Out-File -FilePath $historyFilePath -Encoding $Encoding -Force
        Write-SystemLog "$Description の履歴を保存しました: $historyFilePath" -Level "Success"
        
        return @{
            OutputPath = $OutputPath
            HistoryPath = $historyFilePath
        }
    }
    catch {
        throw "$Description の保存に失敗しました: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function @(
    'New-HistoryFileName',
    'Copy-InputFileToHistory',
    'Resolve-FilePath',
    'ConvertTo-UnifiedLineEndings',
    'New-DirectoryIfNotExists',
    'Test-FileExistsWithInfo',
    'Save-OutputFileWithHistory'
)