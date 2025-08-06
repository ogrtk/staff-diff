# PowerShell & SQLite データ同期システム
# SQL生成・テーブル定義ユーティリティライブラリ

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "config-utils.ps1")

# テーブル定義の取得
function Get-TableDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $config = Get-DataSyncConfig
    
    if (-not $config.tables.$TableName) {
        throw "テーブル定義が見つかりません: $TableName"
    }
    
    return $config.tables.$TableName
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

# CREATE TABLE SQL生成
function New-CreateTableSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $tableDefinition = Get-TableDefinition -TableName $TableName
    
    $columns = @()
    foreach ($column in $tableDefinition.columns) {
        $columnDef = "$($column.name) $($column.type)"
        if (-not [string]::IsNullOrWhiteSpace($column.constraints)) {
            $columnDef += " $($column.constraints)"
        }
        $columns += $columnDef
    }
    
    $sql = "CREATE TABLE IF NOT EXISTS $TableName (`n"
    $sql += "    " + ($columns -join ",`n    ") + "`n"
    $sql += ");"
    
    return $sql
}

# SQL値の保護（SQLインジェクション対策）
function Protect-SqlValue {
    param(
        [string]$Value
    )
    
    if ([string]::IsNullOrEmpty($Value)) {
        return "NULL"
    }
    
    # シングルクォートをエスケープ
    $escapedValue = $Value -replace "'", "''"
    return "'$escapedValue'"
}

# INSERT SQL生成
function New-InsertSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Data
    )
    
    $csvColumns = Get-CsvColumns -TableName $TableName
    
    $columns = @()
    $values = @()
    
    foreach ($column in $csvColumns) {
        if ($Data.ContainsKey($column) -and -not [string]::IsNullOrWhiteSpace($Data[$column])) {
            $columns += $column
            $values += Protect-SqlValue -Value $Data[$column]
        }
    }
    
    if ($columns.Count -eq 0) {
        throw "挿入するデータがありません"
    }
    
    $columnsStr = $columns -join ", "
    $valuesStr = $values -join ", "
    
    return "INSERT INTO $TableName ($columnsStr) VALUES ($valuesStr);"
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

# CSVヘッダー生成
function New-CsvHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    return Get-CsvColumns -TableName $TableName
}

# 同期結果用カラムマッピングの取得
function Get-SyncResultColumnMapping {
    $config = Get-DataSyncConfig
    
    if (-not $config.sync_rules.sync_result_mapping -or -not $config.sync_rules.sync_result_mapping.mappings) {
        throw "sync_result_mapping が設定されていません。設定ファイルを確認してください。"
    }
    
    return $config.sync_rules.sync_result_mapping.mappings
}

# 同期結果用INSERT文のカラムリスト取得
function Get-SyncResultInsertColumns {
    $csvColumns = Get-CsvColumns -TableName "sync_result"
    
    # sync_actionカラムを含める（SQLで値を指定するため）
    return $csvColumns
}

# CREATE INDEX SQL生成
function New-CreateIndexSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $tableDefinition = Get-TableDefinition -TableName $TableName
    
    if (-not $tableDefinition.indexes) {
        return @()
    }
    
    $indexSqls = @()
    
    foreach ($index in $tableDefinition.indexes) {
        $columnsStr = $index.columns -join ", "
        $indexSql = "CREATE INDEX IF NOT EXISTS $($index.name) ON $TableName ($columnsStr);"
        $indexSqls += $indexSql
    }
    
    return $indexSqls
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
    
    return @{}
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

# NOT IN条件生成
function New-NotInCondition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Column,
        
        [Parameter(Mandatory = $true)]
        [string]$SubQuery
    )
    
    return "$Column NOT IN ($SubQuery)"
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
    
    $syncResultMapping = Get-SyncResultColumnMapping
    $selectClauses = @()
    
    foreach ($syncResultColumn in (Get-CsvColumns -TableName "sync_result")) {
        if ($syncResultColumn -eq "sync_action") {
            $selectClauses += "'$SyncAction'"
        }
        else {
            $mapping = $syncResultMapping.$syncResultColumn
            if ($mapping) {
                # ソーステーブル名に基づいてフィールドを選択
                $sourceField = $null
                if ($SourceTableName -eq "provided_data" -and $mapping.provided_data_field) {
                    $sourceField = $mapping.provided_data_field
                }
                elseif ($SourceTableName -eq "current_data" -and $mapping.current_data_field) {
                    $sourceField = $mapping.current_data_field
                }
                
                if ($sourceField) {
                    $selectClauses += "$SourceTableAlias.$sourceField"
                }
                else {
                    # フォールバック: 同名カラムを使用
                    $selectClauses += "$SourceTableAlias.$syncResultColumn"
                }
            }
            else {
                # フォールバック: 同名カラムを使用
                $selectClauses += "$SourceTableAlias.$syncResultColumn"
            }
        }
    }
    
    return $selectClauses -join ", "
}