# PowerShell & SQLite 職員データ管理システム
# CSV処理ユーティリティスクリプト（設定ベース版）

# CSVフォーマット設定取得関数
function Get-CsvFormatConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    try {
        $config = Get-DataSyncConfig
        
        # 出力用は sync_result → output にマップ
        $configKey = if ($TableName -eq "sync_result") { "output" } else { $TableName }
        
        if (-not $config.csv_format -or -not $config.csv_format.$configKey) {
            throw "CSVフォーマット設定が見つかりません: $TableName (設定キー: $configKey)"
        }
        
        return $config.csv_format.$configKey
    }
    catch {
        Write-SystemLog "CSVフォーマット設定の取得に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# エンコーディング名をPowerShell形式に変換
function ConvertTo-PowerShellEncoding {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EncodingName
    )
    
    switch ($EncodingName.ToUpper()) {
        "UTF-8" { return "UTF8" }
        "UTF-16" { return "Unicode" }
        "UTF-16BE" { return "BigEndianUnicode" }
        "UTF-32" { return "UTF32" }
        "SHIFT_JIS" { return "Shift_JIS" }
        "EUC-JP" { return "EUC-JP" }
        "ASCII" { return "ASCII" }
        "ISO-8859-1" { return "Latin1" }
        default { 
            Write-SystemLog "未サポートのエンコーディング: $EncodingName。UTF8を使用します。" -Level "Warning"
            return "UTF8" 
        }
    }
}

# 改行コード変換関数
function ConvertTo-NewlineFormat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter(Mandatory = $true)]
        [string]$NewlineFormat
    )
    
    # 一旦すべての改行を統一
    $normalized = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    
    switch ($NewlineFormat.ToUpper()) {
        "CRLF" { return $normalized -replace "`n", "`r`n" }
        "LF" { return $normalized }
        "CR" { return $normalized -replace "`n", "`r" }
        default { 
            Write-SystemLog "未サポートの改行コード: $NewlineFormat。CRLFを使用します。" -Level "Warning"
            return $normalized -replace "`n", "`r`n"
        }
    }
}

# 設定ベースCSVインポート関数
function Import-CsvWithFormat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    try {
        $formatConfig = Get-CsvFormatConfig -TableName $TableName
        
        Write-SystemLog "CSVファイルを読み込み中: $CsvPath (テーブル: $TableName)" -Level "Info"
        Write-SystemLog "使用設定 - エンコーディング: $($formatConfig.encoding), 区切り文字: '$($formatConfig.delimiter)', ヘッダー有り: $($formatConfig.has_header)" -Level "Info"
        
        # PowerShell用エンコーディング名に変換
        $encoding = ConvertTo-PowerShellEncoding -EncodingName $formatConfig.encoding
        
        # Import-Csvパラメータ準備（ヘッダー付きCSVとして処理）
        $importParams = @{
            Path     = $CsvPath
            Encoding = $encoding
        }
        
        # 区切り文字設定（PowerShellのデフォルトはカンマ）
        if ($formatConfig.delimiter -ne ",") {
            $importParams.Delimiter = $formatConfig.delimiter
        }
        
        # CSVデータインポート
        $csvData = Import-Csv @importParams
        
        # null値の変換
        if ($formatConfig.null_values -and $formatConfig.null_values.Count -gt 0) {
            foreach ($row in $csvData) {
                foreach ($prop in $row.PSObject.Properties) {
                    if ($prop.Value -in $formatConfig.null_values) {
                        $prop.Value = $null
                    }
                }
            }
        }
        
        Write-SystemLog "CSVファイル読み込み完了: $($csvData.Count)行" -Level "Success"
        return $csvData
        
    }
    catch {
        Write-SystemLog "CSVファイルの読み込みに失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# SQLite文字列結果をPSCustomObjectに変換
function ConvertFrom-SqliteStringResult {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$StringArray,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    try {
        if ($StringArray.Count -eq 0) {
            return @()
        }
        
        # SQLite3のデフォルト出力は"|"区切り
        # 最初の行をヘッダーとして扱う
        $headers = $StringArray[0] -split '\|'
        $headers = $headers | ForEach-Object { $_.Trim() }
        
        if ($StringArray.Count -eq 1) {
            # ヘッダーのみでデータなし
            return @()
        }
        
        $dataRows = $StringArray[1..($StringArray.Count - 1)]
        
        $objects = foreach ($row in $dataRows) {
            if ([string]::IsNullOrWhiteSpace($row)) { 
                continue 
            }
            
            $values = $row -split '\|'
            $obj = [PSCustomObject]@{}
            
            for ($i = 0; $i -lt $headers.Count; $i++) {
                $value = if ($i -lt $values.Count) { $values[$i].Trim() } else { "" }
                # 空文字列をnullに変換
                if ([string]::IsNullOrEmpty($value)) {
                    $value = $null
                }
                $obj | Add-Member -NotePropertyName $headers[$i] -NotePropertyValue $value
            }
            $obj
        }
        
        Write-SystemLog "SQLite結果変換完了: $($objects.Count)件のPSCustomObjectに変換" -Level "Success"
        return $objects
        
    }
    catch {
        Write-SystemLog "SQLite結果の変換に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}



# CSVファイルのバリデーション（設定ベース版）
function Test-CsvFormat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    try {
        # CSV設定を取得
        $formatConfig = Get-CsvFormatConfig -TableName $TableName
        Write-SystemLog "CSVファイルを検証中: $(Split-Path -Leaf $CsvPath) (テーブル: $TableName, ヘッダー有り: $($formatConfig.has_header))" -Level "Info"
        
        $csvData = Import-CsvWithFormat -CsvPath $CsvPath -TableName $TableName
        
        # 空のCSVファイルチェック
        if (-not $csvData -or $csvData.Count -eq 0) {
            Write-SystemLog "CSVファイルが空です: $(Split-Path -Leaf $CsvPath)" -Level "Warning"
            return $false
        }
        
        # ヘッダー取得（最初の行から）
        $headers = @()
        $firstRow = $csvData[0]
        if ($firstRow -and $firstRow.PSObject.Properties) {
            $headers = $firstRow.PSObject.Properties.Name
        }
        
        if ($headers.Count -eq 0) {
            Write-SystemLog "CSVファイルにヘッダーが見つかりません: $(Split-Path -Leaf $CsvPath)" -Level "Warning"
            return $false
        }
        
        # カラム数チェック（ヘッダー付きファイルとして処理されるため、設定ベースでチェック）
        $expectedColumns = Get-CsvColumns -TableName $TableName
        if ($headers.Count -ne $expectedColumns.Count) {
            Write-SystemLog "カラム数が一致しません。期待値: $($expectedColumns.Count), 実際: $($headers.Count)" -Level "Warning"
            Write-SystemLog "期待されるカラム: $($expectedColumns -join ', ')" -Level "Info"
            Write-SystemLog "実際のカラム: $($headers -join ', ')" -Level "Info"
            return $false
        }
        
        # 設定ベースで必要カラムを取得
        $requiredColumns = Get-RequiredColumns -TableName $TableName
        
        $missingColumns = $requiredColumns | Where-Object { $_ -notin $headers }
        
        if ($missingColumns.Count -gt 0) {
            Write-SystemLog "必要なカラムが不足しています: $($missingColumns -join ', ')" -Level "Warning"
            Write-SystemLog "実際のヘッダー: $($headers -join ', ')" -Level "Info"
            return $false
        }
        
        Write-SystemLog "CSVフォーマットの検証が完了しました: $(Split-Path -Leaf $CsvPath) (行数: $($csvData.Count))" -Level "Success"
        return $true
        
    }
    catch {
        Write-SystemLog "CSVファイルの検証に失敗しました: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}

Export-ModuleMember -Function @(
    'Import-CsvWithFormat',
    'Test-CsvFormat',
    'Get-CsvFormatConfig', 'ConvertTo-PowerShellEncoding'
)
