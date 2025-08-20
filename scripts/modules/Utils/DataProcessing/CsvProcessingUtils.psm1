# PowerShell & SQLite データ同期システム
# Layer 4: CSV Processing ユーティリティライブラリ（CSV処理専用）

using module "../Foundation/CoreUtils.psm1"
using module "../Infrastructure/LoggingUtils.psm1"
using module "../Infrastructure/ConfigurationUtils.psm1"

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
            Write-SystemLog "CSVファイルが空です: $(Split-Path -Leaf $CsvPath)" -Level "Info"
            
            # 空ファイル許可設定をチェック
            $allowEmpty = $formatConfig.allow_empty_file
            if ($null -eq $allowEmpty) {
                $allowEmpty = $true  # デフォルトは許可
            }
            
            if (-not $allowEmpty) {
                Write-SystemLog "空のCSVファイルは許可されていません (allow_empty_file=false): $(Split-Path -Leaf $CsvPath)" -Level "Error"
                return $false
            }
            
            Write-SystemLog "空のCSVファイルが許可されています (allow_empty_file=true): $(Split-Path -Leaf $CsvPath)" -Level "Info"
            return $true
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

# 設定からCSVカラム取得
function Get-CsvColumns {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    try {
        $config = Get-DataSyncConfig
        
        # テーブル設定を直接参照
        if (-not $config.tables -or -not $config.tables.$TableName) {
            throw "テーブル設定が見つかりません: $TableName"
        }
        
        $tableConfig = $config.tables.$TableName
        return $tableConfig.columns | Where-Object { $_.csv_include -eq $true } | ForEach-Object { $_.name }
        
    }
    catch {
        Write-SystemLog "CSVカラム情報の取得に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 設定から必須カラム取得
function Get-RequiredColumns {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    try {
        $config = Get-DataSyncConfig
        
        # テーブル設定を直接参照
        if (-not $config.tables -or -not $config.tables.$TableName) {
            throw "テーブル設定が見つかりません: $TableName"
        }
        
        $tableConfig = $config.tables.$TableName
        return $tableConfig.columns | Where-Object { $_.csv_include -eq $true -and $_.required -eq $true } | ForEach-Object { $_.name }
        
    }
    catch {
        Write-SystemLog "必須カラム情報の取得に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

Export-ModuleMember -Function @(
    'Get-CsvFormatConfig',
    'ConvertTo-PowerShellEncoding',
    'Import-CsvWithFormat',
    'Test-CsvFormat',
    'ConvertFrom-CsvData',
    'Get-CsvColumns',
    'Get-RequiredColumns'
)