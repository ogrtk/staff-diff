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
        
        Write-SystemLog "設定を読み込みました: $ConfigPath" -Level "Success"
        
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
        Write-SystemLog "file_paths設定が見つかりません。デフォルト値を使用します。" -Level "Warning"
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
            
            # table_constraints の検証
            if ($table.table_constraints) {
                Test-TableConstraintsConfig -TableName $tableName -TableConstraints $table.table_constraints -TableColumns $table.columns
            }
        }
        
        # 必須テーブル存在確認
        $requiredTables = @("provided_data", "current_data", "sync_result")
        foreach ($requiredTable in $requiredTables) {
            if (-not $config.tables.$requiredTable) {
                throw "必須テーブル '$requiredTable' の定義が見つかりません"
            }
        }
        Write-SystemLog "必須テーブル定義確認完了" -Level "Info"
        
        # 同期ルールの基本検証
        if ($config.sync_rules) {
            if (-not $config.sync_rules.column_mappings -or -not $config.sync_rules.column_mappings.mappings) {
                throw "column_mappings の設定が必要です"
            }
            
            # 同期ルール整合性検証
            Test-SyncRulesConsistency -Config $config
            
            # sync_result_mappingの検証
            if ($config.sync_rules.sync_result_mapping) {
                Test-SyncResultMappingConfig -SyncResultMappingConfig $config.sync_rules.sync_result_mapping
            }
        } else {
            throw "sync_rules セクションが見つかりません"
        }
        
        # キーカラム検証
        Test-KeyColumnsValidation -Config $config
        
        # データフィルタ設定検証
        if ($config.data_filters) {
            Test-DataFilterConsistency -Config $config
        }
        
        # CSVフォーマット設定の検証
        if ($config.csv_format) {
            Test-CsvFormatConfig -CsvFormatConfig $config.csv_format
        }
        
        # ログ設定の検証
        try {
            $loggingConfig = Get-LoggingConfig
            Test-LoggingConfigInternal -LoggingConfig $loggingConfig
        }
        catch {
            Write-Warning "ログ設定の検証で問題が発生しました: $($_.Exception.Message)"
        }
        
        Write-SystemLog "設定の検証が完了しました: 問題なし" -Level "Success"
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
        Write-SystemLog "ログ設定が見つかりません。デフォルト値を使用します。" -Level "Warning"
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
    
    Write-SystemLog "sync_result_mapping設定の検証が完了しました" -Level "Success"
}

# sync_result_mappingの取得
function Get-SyncResultMappingConfig {
    $config = Get-DataSyncConfig
    
    if (-not $config.sync_rules -or -not $config.sync_rules.sync_result_mapping) {
        throw "sync_result_mapping設定が見つかりません"
    }
    
    return $config.sync_rules.sync_result_mapping
}

# テーブル制約設定の検証
function Test-TableConstraintsConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [array]$TableConstraints,
        
        [Parameter(Mandatory = $true)]
        [array]$TableColumns
    )
    
    $validConstraintTypes = @("UNIQUE", "PRIMARY KEY", "CHECK", "FOREIGN KEY")
    $columnNames = $TableColumns | ForEach-Object { $_.name }
    
    foreach ($constraint in $TableConstraints) {
        # 必須項目の検証
        if (-not $constraint.name) {
            throw "テーブル '$TableName' の制約に名前が設定されていません"
        }
        
        if (-not $constraint.type) {
            throw "テーブル '$TableName' の制約 '$($constraint.name)' にタイプが設定されていません"
        }
        
        # 制約タイプの検証
        if ($constraint.type -notin $validConstraintTypes) {
            throw "テーブル '$TableName' の制約 '$($constraint.name)' に無効なタイプが設定されています: $($constraint.type). 有効な値: $($validConstraintTypes -join ', ')"
        }
        
        # enabled プロパティの検証（設定されている場合）
        if ($constraint.PSObject.Properties.Name -contains "enabled" -and $constraint.enabled -isnot [bool]) {
            throw "テーブル '$TableName' の制約 '$($constraint.name)' のenabledプロパティはbool型である必要があります"
        }
        
        # 制約タイプ別の詳細検証
        switch ($constraint.type) {
            "UNIQUE" {
                Test-UniqueConstraintConfig -TableName $TableName -Constraint $constraint -ColumnNames $columnNames
            }
            "PRIMARY KEY" {
                Test-PrimaryKeyConstraintConfig -TableName $TableName -Constraint $constraint -ColumnNames $columnNames
            }
            "CHECK" {
                Test-CheckConstraintConfig -TableName $TableName -Constraint $constraint
            }
            "FOREIGN KEY" {
                Test-ForeignKeyConstraintConfig -TableName $TableName -Constraint $constraint -ColumnNames $columnNames
            }
        }
    }
    
    Write-SystemLog "テーブル '$TableName' の制約設定の検証が完了しました" -Level "Info"
}

# UNIQUE制約の検証
function Test-UniqueConstraintConfig {
    param(
        [string]$TableName,
        [object]$Constraint,
        [array]$ColumnNames
    )
    
    if (-not $Constraint.columns -or $Constraint.columns.Count -eq 0) {
        throw "テーブル '$TableName' のUNIQUE制約 '$($Constraint.name)' にカラムが設定されていません"
    }
    
    foreach ($columnName in $Constraint.columns) {
        if ($columnName -notin $ColumnNames) {
            throw "テーブル '$TableName' のUNIQUE制約 '$($Constraint.name)' に存在しないカラムが指定されています: $columnName"
        }
    }
}

# PRIMARY KEY制約の検証
function Test-PrimaryKeyConstraintConfig {
    param(
        [string]$TableName,
        [object]$Constraint,
        [array]$ColumnNames
    )
    
    if (-not $Constraint.columns -or $Constraint.columns.Count -eq 0) {
        throw "テーブル '$TableName' のPRIMARY KEY制約 '$($Constraint.name)' にカラムが設定されていません"
    }
    
    foreach ($columnName in $Constraint.columns) {
        if ($columnName -notin $ColumnNames) {
            throw "テーブル '$TableName' のPRIMARY KEY制約 '$($Constraint.name)' に存在しないカラムが指定されています: $columnName"
        }
    }
}

# CHECK制約の検証
function Test-CheckConstraintConfig {
    param(
        [string]$TableName,
        [object]$Constraint
    )
    
    if (-not $Constraint.check_expression -or [string]::IsNullOrWhiteSpace($Constraint.check_expression)) {
        throw "テーブル '$TableName' のCHECK制約 '$($Constraint.name)' にcheck_expressionが設定されていません"
    }
}

# FOREIGN KEY制約の検証
function Test-ForeignKeyConstraintConfig {
    param(
        [string]$TableName,
        [object]$Constraint,
        [array]$ColumnNames
    )
    
    if (-not $Constraint.columns -or $Constraint.columns.Count -eq 0) {
        throw "テーブル '$TableName' のFOREIGN KEY制約 '$($Constraint.name)' にカラムが設定されていません"
    }
    
    if (-not $Constraint.foreign_key) {
        throw "テーブル '$TableName' のFOREIGN KEY制約 '$($Constraint.name)' にforeign_key設定が必要です"
    }
    
    $foreignKey = $Constraint.foreign_key
    
    # 参照テーブルの検証
    if (-not $foreignKey.reference_table) {
        throw "テーブル '$TableName' のFOREIGN KEY制約 '$($Constraint.name)' にreference_tableが設定されていません"
    }
    
    # 参照カラムの検証
    if (-not $foreignKey.reference_columns -or $foreignKey.reference_columns.Count -eq 0) {
        throw "テーブル '$TableName' のFOREIGN KEY制約 '$($Constraint.name)' にreference_columnsが設定されていません"
    }
    
    # カラム数の一致確認
    if ($Constraint.columns.Count -ne $foreignKey.reference_columns.Count) {
        throw "テーブル '$TableName' のFOREIGN KEY制約 '$($Constraint.name)' で、カラム数と参照カラム数が一致しません"
    }
    
    # 制約対象カラムの存在確認
    foreach ($columnName in $Constraint.columns) {
        if ($columnName -notin $ColumnNames) {
            throw "テーブル '$TableName' のFOREIGN KEY制約 '$($Constraint.name)' に存在しないカラムが指定されています: $columnName"
        }
    }
    
    # オプション設定の検証
    if ($foreignKey.PSObject.Properties.Name -contains "on_delete") {
        $validActions = @("CASCADE", "SET NULL", "SET DEFAULT", "RESTRICT", "NO ACTION")
        if ($foreignKey.on_delete -notin $validActions) {
            throw "テーブル '$TableName' のFOREIGN KEY制約 '$($Constraint.name)' の無効なon_deleteアクション: $($foreignKey.on_delete). 有効な値: $($validActions -join ', ')"
        }
    }
    
    if ($foreignKey.PSObject.Properties.Name -contains "on_update") {
        $validActions = @("CASCADE", "SET NULL", "SET DEFAULT", "RESTRICT", "NO ACTION")
        if ($foreignKey.on_update -notin $validActions) {
            throw "テーブル '$TableName' のFOREIGN KEY制約 '$($Constraint.name)' の無効なon_updateアクション: $($foreignKey.on_update). 有効な値: $($validActions -join ', ')"
        }
    }
}

# 同期ルール整合性検証
function Test-SyncRulesConsistency {
    param(
        [Parameter(Mandatory = $true)]
        $Config
    )
    
    $mappings = $Config.sync_rules.column_mappings.mappings
    $providedColumns = $Config.tables.provided_data.columns | ForEach-Object { $_.name }
    $currentColumns = $Config.tables.current_data.columns | ForEach-Object { $_.name }
    
    # column_mappingsのキー（provided_data側）の存在確認
    foreach ($providedColumn in $mappings.PSObject.Properties.Name) {
        if ($providedColumn -notin $providedColumns) {
            throw "column_mappings のキー '$providedColumn' がprovided_dataテーブルに存在しません"
        }
    }
    
    # column_mappingsの値（current_data側）の存在確認
    foreach ($property in $mappings.PSObject.Properties) {
        $currentColumn = $property.Value
        if ($currentColumn -notin $currentColumns) {
            throw "column_mappings の値 '$currentColumn' がcurrent_dataテーブルに存在しません (キー: $($property.Name))"
        }
    }
    
    Write-SystemLog "同期ルール整合性検証完了" -Level "Info"
}

# キーカラム検証
function Test-KeyColumnsValidation {
    param(
        [Parameter(Mandatory = $true)]
        $Config
    )
    
    if (-not $Config.sync_rules.key_columns) {
        throw "key_columns の設定が見つかりません"
    }
    
    $keyColumns = $Config.sync_rules.key_columns
    
    # 各テーブルのキーカラム存在確認
    foreach ($tableName in @("provided_data", "current_data", "sync_result")) {
        if (-not $keyColumns.$tableName) {
            throw "テーブル '$tableName' のkey_columnsが設定されていません"
        }
        
        $tableColumns = $Config.tables.$tableName.columns | ForEach-Object { $_.name }
        
        foreach ($keyColumn in $keyColumns.$tableName) {
            if ($keyColumn -notin $tableColumns) {
                throw "テーブル '$tableName' にキーカラム '$keyColumn' が存在しません"
            }
            
            # UNIQUE制約の確認（推奨）
            $column = $Config.tables.$tableName.columns | Where-Object { $_.name -eq $keyColumn }
            $hasUniqueInColumn = $column.constraints -like "*UNIQUE*" -or $column.constraints -like "*PRIMARY KEY*"
            
            # テーブル制約からUNIQUE制約をチェック
            $hasUniqueInTableConstraints = $false
            if ($Config.tables.$tableName.table_constraints) {
                foreach ($constraint in $Config.tables.$tableName.table_constraints) {
                    if ($constraint.type -eq "UNIQUE" -and $keyColumn -in $constraint.columns -and $constraint.enabled -ne $false) {
                        $hasUniqueInTableConstraints = $true
                        break
                    }
                }
            }
            
            if (-not $hasUniqueInColumn -and -not $hasUniqueInTableConstraints) {
                Write-Warning "キーカラム '$keyColumn' (テーブル: $tableName) にUNIQUE制約がありません。データ整合性のためUNIQUE制約を推奨します"
            }
        }
    }
    
    Write-SystemLog "キーカラム検証完了" -Level "Info"
}

# データフィルタ設定整合性検証
function Test-DataFilterConsistency {
    param(
        [Parameter(Mandatory = $true)]
        $Config
    )
    
    foreach ($tableName in @("provided_data", "current_data")) {
        if ($Config.data_filters.$tableName -and $Config.data_filters.$tableName.enabled) {
            $tableColumns = $Config.tables.$tableName.columns | ForEach-Object { $_.name }
            $filterRules = $Config.data_filters.$tableName.rules
            
            foreach ($rule in $filterRules) {
                # フィルタ対象フィールドの存在確認
                if ($rule.field -notin $tableColumns) {
                    throw "テーブル '$tableName' のデータフィルタで、存在しないフィールド '$($rule.field)' が指定されています"
                }
                
                # フィルタタイプの妥当性確認
                if ($rule.type -notin @("include", "exclude")) {
                    throw "テーブル '$tableName' のデータフィルタで、無効なフィルタタイプ '$($rule.type)' が指定されています。有効な値: include, exclude"
                }
                
                # GLOBパターンの基本的な妥当性確認
                if ([string]::IsNullOrWhiteSpace($rule.glob)) {
                    Write-Warning "テーブル '$tableName' のデータフィルタでGLOBパターンが空です (フィールド: $($rule.field))"
                }
                
                # 危険なパターンの警告
                if ($rule.glob -eq "*") {
                    Write-Warning "テーブル '$tableName' のデータフィルタで全件一致パターン '*' が使用されています (フィールド: $($rule.field))"
                }
            }
        }
    }
    
    Write-SystemLog "データフィルタ整合性検証完了" -Level "Info"
}

# ログ設定の内部検証（循環参照回避）
function Test-LoggingConfigInternal {
    param(
        [Parameter(Mandatory = $true)]
        $LoggingConfig
    )
    
    # ログレベルの妥当性確認
    $validLevels = @("Info", "Warning", "Error", "Success")
    foreach ($level in $LoggingConfig.levels) {
        if ($level -notin $validLevels) {
            Write-Warning "無効なログレベルが指定されています: $level. 有効な値: $($validLevels -join ', ')"
        }
    }
    
    # ファイルサイズとファイル数の妥当性確認
    if ($LoggingConfig.max_file_size_mb -le 0) {
        Write-Warning "ログファイルの最大サイズが無効です: $($LoggingConfig.max_file_size_mb)MB. 正の数値を指定してください"
    }
    
    if ($LoggingConfig.max_files -le 0) {
        Write-Warning "ログファイルの保持数が無効です: $($LoggingConfig.max_files). 正の数値を指定してください"
    }
    
    # ログディレクトリパスの検証
    if ([string]::IsNullOrWhiteSpace($LoggingConfig.log_directory)) {
        Write-Warning "ログディレクトリパスが空です"
    }
    
    # ログファイル名の検証
    if ([string]::IsNullOrWhiteSpace($LoggingConfig.log_file_name)) {
        Write-Warning "ログファイル名が空です"
    }
    
    Write-SystemLog "ログ設定検証完了" -Level "Info"
}

Export-ModuleMember -Function @(
    'Get-DataSyncConfig',
    'Get-FilePathConfig',
    'Test-DataSyncConfig',
    'Test-CsvFormatConfig',
    'Get-LoggingConfig',
    'Get-DataFilterConfig',
    'Test-SyncResultMappingConfig',
    'Get-SyncResultMappingConfig',
    'Test-TableConstraintsConfig',
    'Test-SyncRulesConsistency',
    'Test-KeyColumnsValidation',
    'Test-DataFilterConsistency'
)