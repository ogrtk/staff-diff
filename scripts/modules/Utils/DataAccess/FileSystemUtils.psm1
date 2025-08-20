# PowerShell & SQLite データ同期システム
# Layer 3: FileSystem ユーティリティライブラリ（ファイル操作・履歴管理）
using module "../Foundation/CoreUtils.psm1"
using module "../Infrastructure/LoggingUtils.psm1"
using module "../Infrastructure/ConfigurationUtils.psm1"

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

Export-ModuleMember -Function @(
    'New-HistoryFileName',
    'Copy-InputFileToHistory',
    'Resolve-FilePath'
)