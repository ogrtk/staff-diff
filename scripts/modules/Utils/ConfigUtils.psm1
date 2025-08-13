# PowerShell & SQLite データ同期システム
# 設定管理ライブラリ

# モジュールスコープの変数で設定をキャッシュ
$script:DataSyncConfig = $null

# クロスプラットフォーム対応エンコーディング取得（内部関数）
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

# データ同期設定の読み込み（初回はパス指定が必須）
function Get-DataSyncConfig {
    param(
        [string]$ConfigPath
    )

    if ($null -ne $script:DataSyncConfig) {
        return $script:DataSyncConfig
    }

    if ([string]::IsNullOrEmpty($ConfigPath)) {
        throw "設定がまだ読み込まれていません。最初にConfigPathを指定して呼び出す必要があります。"
    }

    try {
        if (-not (Test-Path $ConfigPath)) {
            throw "設定ファイルが見つかりません: $ConfigPath"
        }
        
        $encoding = Get-CrossPlatformEncoding
        $configContent = Get-Content -Path $ConfigPath -Raw -Encoding $encoding
        $script:DataSyncConfig = $configContent | ConvertFrom-Json
        
        Write-Host "設定を読み込みました: $ConfigPath" -ForegroundColor Green
        
        return $script:DataSyncConfig
    }
    catch {
        Write-Error "設定の読み込みに失敗しました: $($_.Exception.Message)"
        throw
    }
}

# ファイルパス設定の取得
function Get-FilePathConfig {
    $config = Get-DataSyncConfig
    
    # file_pathsセクションが存在しない場合、デフォルト値を生成（内部動作）
    if (-not $config.file_paths) {
        # Write-SystemLogを使うと無限ループの可能性があるため、直接出力
        Write-Host "file_paths設定が見つかりません。デフォルト値を使用します。" -ForegroundColor Yellow
        $defaultPaths = @{
            provided_data_history_directory = "./data/provided-data/"
            current_data_history_directory  = "./data/current-data/"
            output_history_directory        = "./data/output/"
            timezone                        = "Asia/Tokyo"
        }
        
        # 設定オブジェクトにデフォルト値を追加
        $config | Add-Member -MemberType NoteProperty -Name "file_paths" -Value $defaultPaths -Force
    }
    
    # 個別項目のデフォルト値設定（内部動作）
    $paths = $config.file_paths
    if (-not $paths.provided_data_history_directory) {
        $paths | Add-Member -MemberType NoteProperty -Name "provided_data_history_directory" -Value "./data/provided-data/" -Force
    }
    if (-not $paths.current_data_history_directory) {
        $paths | Add-Member -MemberType NoteProperty -Name "current_data_history_directory" -Value "./data/current-data/" -Force
    }
    if (-not $paths.output_history_directory) {
        $paths | Add-Member -MemberType NoteProperty -Name "output_history_directory" -Value "./data/output/" -Force
    }
    if (-not $paths.timezone) {
        $paths | Add-Member -MemberType NoteProperty -Name "timezone" -Value "Asia/Tokyo" -Force
    }
    
    return $paths
}

# 設定の検証
function Test-DataSyncConfig {
    try {
        $config = Get-DataSyncConfig

        # 基本構造の検証
        if (-not $config.tables) {
            throw "テーブル定義が見つかりません"
        }
        
        # 各テーブルの検証
        foreach ($tableName in $config.tables.PSObject.Properties.Name) {
            $table = $config.tables.$tableName
            
            if (-not $table.columns -or $table.columns.Count -eq 0) {
                throw "テーブル '$tableName' のカラム定義が不正です"
            }
            
            # 必須カラムの存在確認
            $idColumn = $table.columns | Where-Object { $_.name -eq "id" }
            if (-not $idColumn) {
                Write-Warning "テーブル '$tableName' にidカラムがありません"
            }
        }
        
        # 同期ルールの基本検証
        if ($config.sync_rules) {
            if (-not $config.sync_rules.column_mappings -or -not $config.sync_rules.column_mappings.mappings) {
                Write-Warning "column_mappings が設定されていません"
            }
            
            # sync_result_mappingの検証
            if ($config.sync_rules.sync_result_mapping) {
                Test-SyncResultMappingConfig -SyncResultMappingConfig $config.sync_rules.sync_result_mapping
            }
        }
        
        # CSVフォーマット設定の検証
        if ($config.csv_format) {
            Test-CsvFormatConfig -CsvFormatConfig $config.csv_format
        }
        
        Write-Host "設定の検証が完了しました: 問題なし" -ForegroundColor Green
        return $true
        
    }
    catch {
        Write-Error "設定の検証に失敗しました: $($_.Exception.Message)"
        return $false
    }
}

# CSVフォーマット設定の検証
function Test-CsvFormatConfig {
    param(
        [Parameter(Mandatory = $true)]
        $CsvFormatConfig
    )
    
    $validEncodings = @("UTF-8", "UTF-16", "UTF-16BE", "UTF-32", "SHIFT_JIS", "EUC-JP", "ASCII", "ISO-8859-1")
    $validNewlines = @("CRLF", "LF", "CR")
    
    foreach ($configType in @("provided_data", "current_data", "output")) {
        if ($CsvFormatConfig.$configType) {
            $config = $CsvFormatConfig.$configType
            
            # エンコーディング検証
            if ($config.encoding -and $config.encoding -notin $validEncodings) {
                Write-Warning "無効なエンコーディングが指定されています ($configType): $($config.encoding)"
            }
            
            # 改行コード検証
            if ($config.newline -and $config.newline -notin $validNewlines) {
                Write-Warning "無効な改行コードが指定されています ($configType): $($config.newline)"
            }
            
            # 区切り文字の長さチェック
            if ($config.delimiter -and $config.delimiter.Length -gt 1) {
                Write-Warning "区切り文字は1文字である必要があります ($configType): '$($config.delimiter)'"
            }
            
            # 実装されていない設定項目の警告
            if ($config.PSObject.Properties.Name -contains "quote_char") {
                Write-Warning "[$configType] 'quote_char' 設定は PowerShell の Import-Csv/Export-Csv では使用できません。設定から削除することを推奨します。"
            }
            
            if ($config.PSObject.Properties.Name -contains "escape_char") {
                Write-Warning "[$configType] 'escape_char' 設定は PowerShell の Import-Csv/Export-Csv では使用できません。設定から削除することを推奨します。"
            }
            
            if ($config.PSObject.Properties.Name -contains "quote_all") {
                throw "[$configType] 'quote_all' 設定は PowerShell の Export-Csv では使用できません。設定から削除してください。"
            }
            
            # ヘッダー設定の必須チェック
            if ($configType -in @("provided_data", "current_data")) {
                if (-not ($config.PSObject.Properties.Name -contains "has_header")) {
                    throw "[$configType] 'has_header' 設定が必要です。設定ファイルに追加してください。"
                }
            }
            
            if ($configType -eq "output") {
                if (-not ($config.PSObject.Properties.Name -contains "include_header")) {
                    throw "[$configType] 'include_header' 設定が必要です。設定ファイルに追加してください。"
                }
            }
        }
    }
}

# ログ設定の取得
function Get-LoggingConfig {
    $config = Get-DataSyncConfig
    
    if (-not $config.logging) {
        # Write-SystemLogを使うと無限ループするため、直接出力
        Write-Host "ログ設定が見つかりません。デフォルト値を使用します。" -ForegroundColor Yellow
        # デフォルトログ設定を生成（内部動作）
        $defaultLogging = @{
            enabled          = $true
            log_directory    = "./logs/"
            log_file_name    = "data-sync-system.log"
            max_file_size_mb = 10
            max_files        = 5
            levels           = @("Info", "Warning", "Error", "Success")
        }
        
        # 設定オブジェクトにデフォルト値を追加
        $config | Add-Member -MemberType NoteProperty -Name "logging" -Value $defaultLogging -Force
    }
    
    return $config.logging
}

# データフィルタ設定の取得
function Get-DataFilterConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $config = Get-DataSyncConfig
    
    if (-not $config.data_filters -or -not $config.data_filters.$TableName) {
        return $null
    }
    
    return $config.data_filters.$TableName
}

# sync_result_mapping設定の検証
function Test-SyncResultMappingConfig {
    param(
        [Parameter(Mandatory = $true)]
        $SyncResultMappingConfig
    )
    
    if (-not $SyncResultMappingConfig.mappings) {
        throw "sync_result_mappingにmappingsが設定されていません"
    }
    
    $validTypes = @("provided_data", "current_data", "fixed_value")
    
    foreach ($fieldName in $SyncResultMappingConfig.mappings.PSObject.Properties.Name) {
        $fieldConfig = $SyncResultMappingConfig.mappings.$fieldName
        
        if (-not $fieldConfig.sources -or $fieldConfig.sources.Count -eq 0) {
            throw "フィールド '$fieldName' にsourcesが設定されていません"
        }
        
        $priorities = @()
        
        foreach ($source in $fieldConfig.sources) {
            # type検証
            if (-not $source.type -or $source.type -notin $validTypes) {
                throw "フィールド '$fieldName' の無効なtype: $($source.type). 有効な値: $($validTypes -join ', ')"
            }
            
            # priority検証
            if (-not $source.priority -or $source.priority -lt 1) {
                throw "フィールド '$fieldName' のpriorityは1以上の整数である必要があります: $($source.priority)"
            }
            
            # priority重複チェック
            if ($source.priority -in $priorities) {
                throw "フィールド '$fieldName' でpriorityが重複しています: $($source.priority)"
            }
            $priorities += $source.priority
            
            # type別の必須項目検証
            switch ($source.type) {
                "provided_data" {
                    if (-not $source.field) {
                        throw "フィールド '$fieldName' のprovided_dataタイプにfieldが設定されていません"
                    }
                }
                "current_data" {
                    if (-not $source.field) {
                        throw "フィールド '$fieldName' のcurrent_dataタイプにfieldが設定されていません"
                    }
                }
                "fixed_value" {
                    if (-not ($source.PSObject.Properties.Name -contains "value")) {
                        throw "フィールド '$fieldName' のfixed_valueタイプにvalueが設定されていません"
                    }
                }
            }
        }
        
        # priority連続性チェック（1から始まる連続した番号であるか）
        $sortedPriorities = $priorities | Sort-Object
        for ($i = 0; $i -lt $sortedPriorities.Count; $i++) {
            if ($sortedPriorities[$i] -ne ($i + 1)) {
                Write-Warning "フィールド '$fieldName' のpriorityが連続していません。$($i + 1)が期待されますが$($sortedPriorities[$i])が設定されています"
                break
            }
        }
    }
    
    Write-Host "sync_result_mapping設定の検証が完了しました" -ForegroundColor Green
}

# sync_result_mappingの取得
function Get-SyncResultMappingConfig {
    $config = Get-DataSyncConfig
    
    if (-not $config.sync_rules -or -not $config.sync_rules.sync_result_mapping) {
        throw "sync_result_mapping設定が見つかりません"
    }
    
    return $config.sync_rules.sync_result_mapping
}

Export-ModuleMember -Function @(
    'Get-DataSyncConfig',
    'Get-FilePathConfig',
    'Test-DataSyncConfig',
    'Test-CsvFormatConfig',
    'Get-LoggingConfig',
    'Get-DataFilterConfig',
    'Test-SyncResultMappingConfig',
    'Get-SyncResultMappingConfig'
)