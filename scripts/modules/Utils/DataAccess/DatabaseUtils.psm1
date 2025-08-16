# PowerShell & SQLite データ同期システム
# Layer 3: Database ユーティリティライブラリ（SQL生成・テーブル定義）

# Layer 1, 2への依存は実行時に解決

# テーブル定義の取得（一時テーブル対応）
function Get-TableDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $config = Get-DataSyncConfig
    
    # 一時テーブル（_tempサフィックス）の場合は元のテーブル定義を使用
    $baseTableName = $TableName
    if ($TableName -match "^(.+)_temp$") {
        $baseTableName = $Matches[1]
    }
    
    if (-not $config.tables.$baseTableName) {
        throw "テーブル定義が見つかりません: $TableName (ベーステーブル: $baseTableName)"
    }
    
    return $config.tables.$baseTableName
}

# CSVカラムリストの取得
function Get-CsvColumns {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $tableDefinition = Get-TableDefinition -TableName $TableName
    $csvColumns = $tableDefinition.columns | Where-Object { $_.csv_include -eq $true } | ForEach-Object { $_.name }
    
    return $csvColumns
}

# 必須カラムリストの取得
function Get-RequiredColumns {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $tableDefinition = Get-TableDefinition -TableName $TableName
    $requiredColumns = $tableDefinition.columns | Where-Object { $_.required -eq $true } | ForEach-Object { $_.name }
    
    return $requiredColumns
}

# テーブルクリア（汎用・リトライ対応）
function Clear-Table {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [bool]$ShowStatistics = $true
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

# CREATE TABLE SQL生成（table_constraints対応）
function New-CreateTableSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $tableDefinition = Get-TableDefinition -TableName $TableName
    
    # カラム定義の生成
    $columns = @()
    foreach ($column in $tableDefinition.columns) {
        $columnDef = "$($column.name) $($column.type)"
        if (-not [string]::IsNullOrWhiteSpace($column.constraints)) {
            $columnDef += " $($column.constraints)"
        }
        $columns += $columnDef
    }
    
    # テーブル制約の生成
    $tableConstraints = @()
    if ($tableDefinition.table_constraints) {
        foreach ($constraint in $tableDefinition.table_constraints) {
            # enabled プロパティが false の場合はスキップ
            if ($constraint.enabled -eq $false) {
                Write-SystemLog "テーブル制約 '$($constraint.name)' は無効のためスキップします" -Level "Info"
                continue
            }
            
            switch ($constraint.type) {
                "UNIQUE" {
                    $columnsStr = $constraint.columns -join ", "
                    $constraintDef = "CONSTRAINT $($constraint.name) UNIQUE ($columnsStr)"
                    $tableConstraints += $constraintDef
                    Write-SystemLog "UNIQUE制約を追加: $($constraint.name) ($columnsStr)" -Level "Info"
                }
                "PRIMARY KEY" {
                    $columnsStr = $constraint.columns -join ", "
                    $constraintDef = "CONSTRAINT $($constraint.name) PRIMARY KEY ($columnsStr)"
                    $tableConstraints += $constraintDef
                    Write-SystemLog "PRIMARY KEY制約を追加: $($constraint.name) ($columnsStr)" -Level "Info"
                }
                "FOREIGN KEY" {
                    if ($constraint.foreign_key) {
                        $fkColumns = $constraint.columns -join ", "
                        $refColumns = $constraint.foreign_key.reference_columns -join ", "
                        $constraintDef = "CONSTRAINT $($constraint.name) FOREIGN KEY ($fkColumns) REFERENCES $($constraint.foreign_key.reference_table) ($refColumns)"
                        
                        if ($constraint.foreign_key.on_delete) {
                            $constraintDef += " ON DELETE $($constraint.foreign_key.on_delete)"
                        }
                        if ($constraint.foreign_key.on_update) {
                            $constraintDef += " ON UPDATE $($constraint.foreign_key.on_update)"
                        }
                        
                        $tableConstraints += $constraintDef
                        Write-SystemLog "FOREIGN KEY制約を追加: $($constraint.name)" -Level "Info"
                    }
                }
                default {
                    Write-SystemLog "未対応の制約タイプです: $($constraint.type)" -Level "Warning"
                }
            }
        }
    }
    
    # SQL文の構築
    $sql = "CREATE TABLE IF NOT EXISTS $TableName (`n"
    $sql += "    " + ($columns -join ",`n    ")
    
    # テーブル制約がある場合は追加
    if ($tableConstraints.Count -gt 0) {
        $sql += ",`n    " + ($tableConstraints -join ",`n    ")
    }
    
    $sql += "`n);"
    
    return $sql
}

# SELECT SQL生成
function New-SelectSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [string[]]$Columns = @(),
        
        [string]$WhereClause = "",
        
        [string]$OrderBy = "",
        
        [int]$Limit = 0
    )
    
    if ($Columns.Count -eq 0) {
        $Columns = Get-CsvColumns -TableName $TableName
    }
    
    $columnsStr = $Columns -join ", "
    $sql = "SELECT $columnsStr FROM $TableName"
    
    if (-not [string]::IsNullOrWhiteSpace($WhereClause)) {
        $sql += " WHERE $WhereClause"
    }
    
    if (-not [string]::IsNullOrWhiteSpace($OrderBy)) {
        $sql += " ORDER BY $OrderBy"
    }
    
    if ($Limit -gt 0) {
        $sql += " LIMIT $Limit"
    }
    
    return $sql + ";"
}

# 一時テーブル作成SQL生成
function New-CreateTempTableSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseTableName,
        
        [Parameter(Mandatory = $true)]
        [string]$TempTableName
    )
    
    $tableDefinition = Get-TableDefinition -TableName $BaseTableName
    
    $columns = @()
    foreach ($column in $tableDefinition.columns) {
        if ($column.csv_include -eq $true) {
            $columnDef = "$($column.name) $($column.type)"
            $columns += $columnDef
        }
    }
    
    $sql = "CREATE TABLE $TempTableName (`n"
    $sql += "    " + ($columns -join ",`n    ") + "`n"
    $sql += ");"
    
    return $sql
}

# カラムマッピングの取得
function Get-ColumnMapping {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceTableName,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetTableName
    )
    
    $config = Get-DataSyncConfig
    
    if (-not $config.sync_rules.column_mappings -or -not $config.sync_rules.column_mappings.mappings) {
        return @{}
    }
    
    # 固定のmappingsキーを参照
    $mapping = $config.sync_rules.column_mappings.mappings
    $hashtable = @{}
    $mapping.PSObject.Properties | ForEach-Object {
        $hashtable[$_.Name] = $_.Value
    }
    return $hashtable
}

# テーブルのキーカラム取得
function Get-TableKeyColumns {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $config = Get-DataSyncConfig
    
    # key_columns設定をチェック
    if (-not $config.sync_rules.key_columns -or -not $config.sync_rules.key_columns.$TableName) {
        throw "テーブル '$TableName' のkey_columnsが設定されていません。設定ファイルを確認してください。"
    }
    
    return $config.sync_rules.key_columns.$TableName
}

# 比較カラムの取得
function Get-ComparisonColumns {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceTableName,
        
        [string]$TargetTableName = ""
    )
    
    $config = Get-DataSyncConfig
    
    # column_mappingsから比較カラムを自動生成
    if (-not $config.sync_rules.column_mappings -or -not $config.sync_rules.column_mappings.mappings) {
        Write-Warning "column_mappings が設定されていません"
        return @()
    }
    
    $mappings = $config.sync_rules.column_mappings.mappings
    $columns = @()
    
    switch ($SourceTableName) {
        "provided_data" {
            # provided_dataの比較カラム = column_mappingsのキー部分
            $mappings.PSObject.Properties | ForEach-Object {
                $columns += $_.Name
            }
        }
        "current_data" {
            # current_dataの比較カラム = column_mappingsの値部分
            $mappings.PSObject.Properties | ForEach-Object {
                $columns += $_.Value
            }
        }
        default {
            Write-Warning "未対応のテーブル名: $SourceTableName"
            return @()
        }
    }
    
    return $columns
}

# CREATE INDEX SQL生成（条件付き）
function New-CreateIndexSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [int]$RecordCount = 0
    )
    
    $tableDefinition = Get-TableDefinition -TableName $TableName
    
    if (-not $tableDefinition.indexes) {
        return @()
    }
    
    # 性能設定を取得（ハードコーディング排除）
    $config = Get-DataSyncConfig
    $threshold = $config.performance_settings.index_threshold
    $autoOptimization = $true
    
    if ($config.performance_settings) {
        $autoOptimization = $config.performance_settings.auto_optimization
    }
    
    $indexSqls = @()
    
    foreach ($index in $tableDefinition.indexes) {
        $shouldCreateIndex = $true
        
        # 自動最適化が有効な場合は件数で判定
        if ($autoOptimization -and $RecordCount -gt 0 -and $RecordCount -lt $threshold) {
            Write-SystemLog "テーブル '$TableName' は小規模データ ($RecordCount 件 < $threshold) のため、インデックス '$($index.name)' をスキップします" -Level "Info"
            $shouldCreateIndex = $false
        }
        
        if ($shouldCreateIndex) {
            $columnsStr = $index.columns -join ", "
            $indexSql = "CREATE INDEX IF NOT EXISTS $($index.name) ON $TableName ($columnsStr);"
            $indexSqls += $indexSql
            Write-SystemLog "インデックス '$($index.name)' を作成します: $TableName ($columnsStr)" -Level "Info"
        }
    }
    
    return $indexSqls
}

# SQLite最適化PRAGMA生成
function New-OptimizationPragmas {
    $config = Get-DataSyncConfig
    $pragmas = @()
    
    if ($config.performance_settings -and $config.performance_settings.sqlite_pragmas) {
        $sqlitePragmas = $config.performance_settings.sqlite_pragmas
        
        if ($sqlitePragmas.journal_mode) {
            $pragmas += "PRAGMA journal_mode = $($sqlitePragmas.journal_mode);"
        }
        
        if ($sqlitePragmas.synchronous) {
            $pragmas += "PRAGMA synchronous = $($sqlitePragmas.synchronous);"
        }
        
        if ($sqlitePragmas.temp_store) {
            $pragmas += "PRAGMA temp_store = $($sqlitePragmas.temp_store);"
        }
        
        if ($sqlitePragmas.cache_size) {
            $pragmas += "PRAGMA cache_size = $($sqlitePragmas.cache_size);"
        }
    }
    
    return $pragmas
}

# フィルタ用WHERE句生成
function New-FilterWhereClause {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    $config = Get-DataSyncConfig
    
    if (-not $config.data_filters -or -not $config.data_filters.$TableName) {
        return ""
    }
    
    $filterConfig = $config.data_filters.$TableName
    
    if (-not $filterConfig.enabled -or -not $filterConfig.rules) {
        return ""
    }
    
    $conditions = @()
    
    foreach ($rule in $filterConfig.rules) {
        switch ($rule.type) {
            "exclude" {
                if ($rule.glob) {
                    $conditions += "$($rule.field) NOT GLOB '$($rule.glob)'"
                }
            }
            "include" {
                if ($rule.glob) {
                    $conditions += "$($rule.field) GLOB '$($rule.glob)'"
                }
            }
        }
    }
    
    if ($conditions.Count -gt 0) {
        return "(" + ($conditions -join " AND ") + ")"
    }
    
    return ""
}

# フィルタ付きINSERT SQL生成
function New-FilteredInsertSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetTableName,
        
        [Parameter(Mandatory = $true)]
        [string]$SourceTableName,
        
        [string]$WhereClause = ""
    )
    
    $csvColumns = Get-CsvColumns -TableName $TargetTableName
    $columnsStr = $csvColumns -join ", "
    
    $sql = "INSERT INTO $TargetTableName ($columnsStr)`n"
    $sql += "SELECT $columnsStr FROM $SourceTableName"
    
    if (-not [string]::IsNullOrWhiteSpace($WhereClause)) {
        $sql += "`nWHERE $WhereClause"
    }
    
    return $sql + ";"
}

# JOIN条件生成
function New-JoinCondition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LeftTableName,
        
        [Parameter(Mandatory = $true)]
        [string]$RightTableName,
        
        [string[]]$JoinColumns = @(),
        
        [string]$LeftAlias = "",
        
        [string]$RightAlias = ""
    )
    
    if ($JoinColumns.Count -eq 0) {
        # 左側テーブルのキーカラムを使用
        $JoinColumns = Get-TableKeyColumns -TableName $LeftTableName
    }
    
    if ($JoinColumns.Count -eq 0) {
        throw "JOIN条件用のカラムが見つかりません: $LeftTableName"
    }
    
    $conditions = @()
    
    foreach ($column in $JoinColumns) {
        $leftColumn = $column
        $rightColumn = $column
        
        # カラムマッピングがある場合は変換（順方向と逆方向両方チェック）
        $mapping = Get-ColumnMapping -SourceTableName $LeftTableName -TargetTableName $RightTableName
        if ($mapping -and $mapping.$column) {
            $rightColumn = $mapping.$column
        }
        else {
            # 逆方向のマッピングもチェック
            $reverseMapping = Get-ReverseColumnMapping -SourceTableName $LeftTableName -TargetTableName $RightTableName
            if ($reverseMapping -and $reverseMapping.$column) {
                $rightColumn = $reverseMapping.$column
            }
        }
        
        # テーブル名またはエイリアスを使用
        $leftTable = if ($LeftAlias) { $LeftAlias } else { $LeftTableName }
        $rightTable = if ($RightAlias) { $RightAlias } else { $RightTableName }
        
        $conditions += "$leftTable.$leftColumn = $rightTable.$rightColumn"
    }
    
    return $conditions -join " AND "
}

# 逆方向カラムマッピングの取得
function Get-ReverseColumnMapping {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceTableName,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetTableName
    )
    
    $forwardMapping = Get-ColumnMapping -SourceTableName $TargetTableName -TargetTableName $SourceTableName
    
    if (-not $forwardMapping) {
        return @{}
    }
    
    $reverseMapping = @{}
    foreach ($key in $forwardMapping.Keys) {
        $value = $forwardMapping[$key]
        $reverseMapping[$value] = $key
    }
    
    return $reverseMapping
}

# 比較用WHERE句生成
function New-ComparisonWhereClause {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Table1Alias,
        
        [Parameter(Mandatory = $true)]
        [string]$Table2Alias,
        
        [Parameter(Mandatory = $true)]
        [string]$ComparisonType, # "different" or "same"
        
        [Parameter(Mandatory = $true)]
        [string]$Table1Name,
        
        [Parameter(Mandatory = $true)]
        [string]$Table2Name,
        
        [string[]]$ComparisonColumns = @()
    )
    
    # テーブルの比較対象項目を取得
    $table1Columns = Get-ComparisonColumns -SourceTableName $Table1Name
    
    # column_mappingsを取得
    $mapping = Get-ColumnMapping -SourceTableName $Table1Name -TargetTableName $Table2Name
    
    $conditions = @()
    
    # Table1の各カラムに対してTable2の対応カラムを見つけて比較条件を作成
    foreach ($table1Column in $table1Columns) {
        $table2Column = if ($mapping -and $mapping.$table1Column) { 
            $mapping.$table1Column 
        }
        else { 
            $table1Column 
        }
        
        if ($ComparisonType -eq "different") {
            $conditions += "($Table1Alias.$table1Column != $Table2Alias.$table2Column OR ($Table1Alias.$table1Column IS NULL AND $Table2Alias.$table2Column IS NOT NULL) OR ($Table1Alias.$table1Column IS NOT NULL AND $Table2Alias.$table2Column IS NULL))"
        }
        elseif ($ComparisonType -eq "same") {
            $conditions += "(($Table1Alias.$table1Column = $Table2Alias.$table2Column) OR ($Table1Alias.$table1Column IS NULL AND $Table2Alias.$table2Column IS NULL))"
        }
    }
    
    if ($conditions.Count -eq 0) {
        return ""
    }
    
    if ($ComparisonType -eq "different") {
        return "(" + ($conditions -join " OR ") + ")"
    }
    else {
        return "(" + ($conditions -join " AND ") + ")"
    }
}

# 優先度ベースSQLのCASE文生成
function New-PriorityBasedCaseStatement {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,
        
        [Parameter(Mandatory = $true)]
        [array]$Sources
    )
    
    # 優先度順にソート
    $sortedSources = $Sources | Sort-Object priority
    
    $coalesceParts = @()
    
    foreach ($source in $sortedSources) {
        switch ($source.type) {
            "provided_data" {
                $fieldRef = "pd.$($source.field)"
                # NULL と空文字をNULLとして扱う
                $coalesceParts += "NULLIF($fieldRef, '')"
            }
            "current_data" {
                $fieldRef = "cd.$($source.field)"
                # NULL と空文字をNULLとして扱う
                $coalesceParts += "NULLIF($fieldRef, '')"
            }
            "fixed_value" {
                # 固定値は最後のフォールバック
                $coalesceParts += "'$($source.value)'"
            }
        }
    }
    
    if ($coalesceParts.Count -gt 1) {
        return "COALESCE(" + ($coalesceParts -join ", ") + ")"
    }
    elseif ($coalesceParts.Count -eq 1) {
        return $coalesceParts[0]
    }
    
    return "NULL"
}

# 優先度ベースマッピングから最優先のソーステーブル項目を取得
function Get-PriorityBasedSourceField {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SyncResultField,
        
        [Parameter(Mandatory = $true)]
        [string]$SourceTableName
    )
    
    $syncResultMappingConfig = Get-SyncResultMappingConfig
    $fieldConfig = $syncResultMappingConfig.mappings.$SyncResultField
    
    if (-not $fieldConfig -or -not $fieldConfig.sources) {
        return $SyncResultField  # フォールバック: 同名フィールド
    }
    
    # 優先度順にソートして、指定されたソーステーブルの最初の項目を返す
    $sortedSources = $fieldConfig.sources | Sort-Object priority
    
    foreach ($source in $sortedSources) {
        if ($source.type -eq $SourceTableName -and $source.field) {
            return $source.field
        }
    }
    
    # 見つからない場合はフォールバック
    return $SyncResultField
}

# 同期結果用INSERT文のカラムリスト取得
function Get-SyncResultInsertColumns {
    $csvColumns = Get-CsvColumns -TableName "sync_result"
    
    # sync_actionカラムを含める（SQLで値を指定するため）
    return $csvColumns
}

# GROUP BY句生成
function New-GroupByClause {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [string[]]$GroupColumns = @(),
        
        [string]$TableAlias = ""
    )
    
    if ($GroupColumns.Count -eq 0) {
        $GroupColumns = Get-TableKeyColumns -TableName $TableName
    }
    
    if ($GroupColumns.Count -eq 0) {
        return ""
    }
    
    # テーブルエイリアスがある場合は各カラムにプレフィックスを追加
    if ($TableAlias) {
        $prefixedColumns = $GroupColumns | ForEach-Object { "$TableAlias.$_" }
        return $prefixedColumns -join ", "
    }
    else {
        return $GroupColumns -join ", "
    }
}

# sync_result用のSELECT句生成（カラムマッピング対応）
function New-SyncResultSelectClause {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceTableName,
        
        [Parameter(Mandatory = $true)]
        [string]$SourceTableAlias,
        
        [Parameter(Mandatory = $true)]
        [string]$SyncAction
    )
    
    $syncResultMappingConfig = Get-SyncResultMappingConfig
    $selectClauses = @()
    
    foreach ($syncResultColumn in (Get-CsvColumns -TableName "sync_result")) {
        if ($syncResultColumn -eq "sync_action") {
            $selectClauses += "'$SyncAction'"
        }
        else {
            $fieldConfig = $syncResultMappingConfig.mappings.$syncResultColumn
            if ($fieldConfig -and $fieldConfig.sources) {
                # 優先度ベースのCASE文を生成
                $caseStatement = New-PriorityBasedCaseStatement -FieldName $syncResultColumn -Sources $fieldConfig.sources
                $selectClauses += $caseStatement
            }
            else {
                # フォールバック: 同名カラムを使用
                $selectClauses += "$SourceTableAlias.$syncResultColumn"
            }
        }
    }
    
    return $selectClauses -join ", "
}

# 優先度ベース用の新しいSyncResultSelectClause（UPDATE専用 - provided_dataを優先）
function New-PriorityBasedSyncResultSelectClause {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SyncAction
    )
    
    $syncResultMappingConfig = Get-SyncResultMappingConfig
    $selectClauses = @()
    
    foreach ($syncResultColumn in (Get-CsvColumns -TableName "sync_result")) {
        if ($syncResultColumn -eq "sync_action") {
            $selectClauses += "'$SyncAction'"
        }
        else {
            $fieldConfig = $syncResultMappingConfig.mappings.$syncResultColumn
            if ($fieldConfig -and $fieldConfig.sources) {
                # 優先度ベースのCASE文を生成（両テーブルを考慮）
                $caseStatement = New-PriorityBasedCaseStatement -FieldName $syncResultColumn -Sources $fieldConfig.sources
                $selectClauses += $caseStatement
            }
            else {
                # フォールバック: provided_dataを優先
                $selectClauses += "COALESCE(pd.$syncResultColumn, cd.$syncResultColumn)"
            }
        }
    }
    
    return $selectClauses -join ", "
}

Export-ModuleMember -Function @(
    'Get-TableDefinition',
    'Get-CsvColumns',
    'Get-RequiredColumns',
    'Clear-Table',
    'New-CreateTableSql',
    'New-CreateTempTableSql',
    'New-SelectSql',
    'Get-ColumnMapping',
    'Get-TableKeyColumns',
    'Get-ComparisonColumns',
    'New-CreateIndexSql',
    'New-OptimizationPragmas',
    'New-FilterWhereClause',
    'New-FilteredInsertSql',
    'New-JoinCondition',
    'Get-ReverseColumnMapping',
    'New-ComparisonWhereClause',
    'New-PriorityBasedCaseStatement',
    'Get-PriorityBasedSourceField',
    'Get-SyncResultInsertColumns',
    'New-GroupByClause',
    'New-SyncResultSelectClause',
    'New-PriorityBasedSyncResultSelectClause'
)