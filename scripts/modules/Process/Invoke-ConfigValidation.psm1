# PowerShell & SQLite データ管理システム
# 設定検証・パラメータ解決処理スクリプト（レイヤー化版）

# 設定検証とパラメータ解決の統合処理
function Invoke-ConfigValidation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        
        [string]$DatabasePath = "",
        [string]$ProvidedDataFilePath = "",
        [string]$CurrentDataFilePath = "",
        [string]$OutputFilePath = ""
    )
    
    return Invoke-WithErrorHandling -Category System -Operation "設定検証・パラメータ解決処理" -Context @{
        "ProjectRoot"          = $ProjectRoot
        "DatabasePath"         = $DatabasePath
        "ProvidedDataFilePath" = $ProvidedDataFilePath
        "CurrentDataFilePath"  = $CurrentDataFilePath
        "OutputFilePath"       = $OutputFilePath
    } -ScriptBlock {
        
        # DatabasePathが未指定の場合、デフォルトを設定
        $resolvedDatabasePath = $DatabasePath
        if ([string]::IsNullOrEmpty($resolvedDatabasePath)) {
            $resolvedDatabasePath = Join-Path $ProjectRoot "database" "data-sync.db"
            Write-SystemLog "DatabasePathが未指定のため、デフォルトパスを使用します: $resolvedDatabasePath" -Level "Info"
        }
    
        # 1. 設定の検証
        Write-SystemLog "システム設定を検証中..." -Level "Info"
        Invoke-WithErrorHandling -ScriptBlock {
            if (-not (Test-DataSyncConfig)) {
                throw "設定の検証に失敗しました"
            }
        } -Category System -Operation "設定の検証" -Context @{"設定セクション" = "システム全体設定"}
        
        # 2. 入力ファイルパスの解決
        Write-SystemLog "ファイルパス解決処理を開始..." -Level "Info"
        
        $resolvedProvidedDataPath = Invoke-WithErrorHandling -Category System -Operation "提供データファイルパス解決" -ScriptBlock {
            Resolve-FilePath -ParameterPath $ProvidedDataFilePath -ConfigKey "provided_data_file_path" -Description "提供データファイル"
        }
        
        $resolvedCurrentDataPath = Invoke-WithErrorHandling -Category System -Operation "現在データファイルパス解決" -ScriptBlock {
            Resolve-FilePath -ParameterPath $CurrentDataFilePath -ConfigKey "current_data_file_path" -Description "現在データファイル"
        }
        
        $resolvedOutputPath = Invoke-WithErrorHandling -Category System -Operation "出力ファイルパス解決" -ScriptBlock {
            Resolve-FilePath -ParameterPath $OutputFilePath -ConfigKey "output_file_path" -Description "出力ファイル"
        }
        
        # 3. 処理パラメータのログ出力
        Write-SystemLog "=== 処理パラメータ ===" -Level "Info"
        Write-SystemLog "Database Path: $resolvedDatabasePath" -Level "Info"
        Write-SystemLog "Provided Data File: $resolvedProvidedDataPath" -Level "Info"
        Write-SystemLog "Current Data File: $resolvedCurrentDataPath" -Level "Info"
        Write-SystemLog "Output File: $resolvedOutputPath" -Level "Info"
        Write-SystemLog "========================" -Level "Info"
        
        # 4. 解決されたパラメータのファイル存在チェック
        $resolvedParams = @{
            DatabasePath         = $resolvedDatabasePath
            ProvidedDataFilePath = $resolvedProvidedDataPath
            CurrentDataFilePath  = $resolvedCurrentDataPath
            OutputFilePath       = $resolvedOutputPath
        }
        
        Write-SystemLog "入力ファイルの存在チェックを実行中..." -Level "Info"
        $null = Test-ResolvedFilePaths -ResolvedPaths $resolvedParams -SkipOutputFileCheck
        
        # 5. 解決されたパラメータを返す
        return $resolvedParams
    }
}

# ファイル存在チェック（設定完了後の検証）
function script:Test-ResolvedFilePaths {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ResolvedPaths,
        
        [switch]$SkipOutputFileCheck
    )
    
    return Invoke-WithErrorHandling -Category External -Operation "ファイルパス存在チェック" -Context $ResolvedPaths -ScriptBlock {
        
        Write-SystemLog "入力ファイルの存在チェックを実行中..." -Level "Info"
        
        # 提供データファイルの存在チェック
        if (-not (Test-Path $ResolvedPaths.ProvidedDataFilePath)) {
            throw "提供データファイルが見つかりません: $($ResolvedPaths.ProvidedDataFilePath)"
        }
        Write-SystemLog "提供データファイル確認済み: $($ResolvedPaths.ProvidedDataFilePath)" -Level "Info"
        
        # 現在データファイルの存在チェック
        if (-not (Test-Path $ResolvedPaths.CurrentDataFilePath)) {
            throw "現在データファイルが見つかりません: $($ResolvedPaths.CurrentDataFilePath)"
        }
        Write-SystemLog "現在データファイル確認済み: $($ResolvedPaths.CurrentDataFilePath)" -Level "Info"
        
        # 出力ファイルのディレクトリチェック（オプション）
        if (-not $SkipOutputFileCheck) {
            $outputDir = Split-Path -Path $ResolvedPaths.OutputFilePath -Parent
            if (-not (Test-Path $outputDir)) {
                Write-SystemLog "出力ディレクトリが存在しません。作成します: $outputDir" -Level "Warning"
                New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
                Write-SystemLog "出力ディレクトリを作成しました: $outputDir" -Level "Info"
            }
        }
        
        Write-SystemLog "ファイルパス存在チェックが完了しました" -Level "Success"
        return $true
    }
}

Export-ModuleMember -Function 'Invoke-ConfigValidation'
