# PowerShell & SQLite データ同期システム
# データフィルタリングユーティリティライブラリ

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "config-utils.ps1")


# フィルタ設定の表示
function Show-FilterConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $filterConfig = Get-DataFilterConfig -TableName $TableName
    
    if (-not $filterConfig) {
        Write-Host "テーブル '$TableName' にフィルタ設定がありません" -ForegroundColor Yellow
        return
    }
    
    Write-Host "=== フィルタ設定: $TableName ===" -ForegroundColor Cyan
    Write-Host "有効: $($filterConfig.enabled)" -ForegroundColor Green
    
    if ($filterConfig.rules -and $filterConfig.rules.Count -gt 0) {
        Write-Host "ルール数: $($filterConfig.rules.Count)" -ForegroundColor Green
        
        for ($i = 0; $i -lt $filterConfig.rules.Count; $i++) {
            $rule = $filterConfig.rules[$i]
            Write-Host "  [$($i + 1)] フィールド: $($rule.field)" -ForegroundColor White
            Write-Host "       タイプ: $($rule.type)" -ForegroundColor White
            
            if ($rule.pattern) {
                Write-Host "       パターン: $($rule.pattern)" -ForegroundColor White
            }
            if ($rule.value) {
                Write-Host "       値: $($rule.value)" -ForegroundColor White
            }
            
            Write-Host "       説明: $($rule.description)" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "ルールが設定されていません" -ForegroundColor Yellow
    }
}

# データフィルタリング
function Invoke-Filtering {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [string]$CsvFilePath,
        
        [bool]$ShowStatistics = $true,
        
        [switch]$ShowConfig = $false
    )
    
    if ($ShowConfig) {
        Show-FilterConfig -TableName $TableName
    }
    
    try {
        Write-SystemLog "フィルタリング用に一時テーブルへCSVをインポートする: $TableName ($CsvFilePath)" -Level "Info"

        # 一時テーブル名
        $tempTableName = "${TableName}_temp"

        # リトライ対応: 既存データをクリア
        Clear-Table -DatabasePath $DatabasePath -TableName $TableName

        # CSVファイルの件数を事前に取得
        $csvData = Import-Csv -Path $CsvFilePath
        $totalRecords = $csvData.Count
        
        Write-Host "CSVファイル読み込み完了: $totalRecords 件" -ForegroundColor Green
        
        # 1. 一時テーブル作成
        $createTempTableSql = New-CreateTempTableSql -BaseTableName $TableName -TempTableName $tempTableName
        Write-SystemLog "一時テーブル作成: $tempTableName" -Level "Info"
        # 一時テーブルを事前に作成
        $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $createTempTableSql
        
        # 2. CSVデータを一時テーブルに直接インポート（SQLite .import使用）
        Write-Host "CSVデータを一時テーブルに直接インポート中..." -ForegroundColor Cyan
        $importResult = Import-CsvToSqliteTable -CsvFilePath $CsvFilePath -DatabasePath $DatabasePath -TableName $tempTableName
        if (-not $importResult) {
            throw "CSVファイルの一時テーブルへのインポートに失敗しました"
        }
        
        # 3. フィルタ用WHERE句生成
        $whereClause = New-FilterWhereClause -TableName $TableName
        
        # 4-6. フィルタ済みデータ移行、統計取得、クリーンアップ
        $filteredInsertSql = New-FilteredInsertSql -TargetTableName $TableName -SourceTableName $tempTableName -WhereClause $whereClause
        $statisticsSql = "SELECT COUNT(*) as filtered_count FROM $TableName;"
        $dropTempTableSql = "DROP TABLE $tempTableName;"
        
        $filteringAndCleanupSql = @"
BEGIN TRANSACTION;
$filteredInsertSql
$statisticsSql
$dropTempTableSql
COMMIT;
"@
        
        Write-SystemLog "フィルタリングとクリーンアップ実行中..." -Level "Info"
        $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $filteringAndCleanupSql
        
        # 結果から件数を取得
        $filteredCount = if ($result -is [array] -and $result.Count -gt 0) { 
            # 最後の統計クエリの結果を取得
            [int]($result | Select-Object -Last 1)
        }
        else { 
            [int]$result 
        }
        
        # 動的インデックス作成（レコード数に基づく判定）
        $indexSqls = New-CreateIndexSql -TableName $TableName -RecordCount $filteredCount
        foreach ($indexSql in $indexSqls) {
            Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $indexSql
        }
        
        # 統計表示
        if ($ShowStatistics) {
            $excludedCount = $totalRecords - $filteredCount
            $exclusionRate = if ($totalRecords -gt 0) { [Math]::Round(($excludedCount / $totalRecords) * 100, 2) } else { 0 }
            
            Write-Host "`n=== SQLフィルタリング統計: $TableName ===" -ForegroundColor Green
            Write-Host "総件数: $totalRecords" -ForegroundColor White
            Write-Host "通過件数: $filteredCount" -ForegroundColor Green
            Write-Host "除外件数: $excludedCount" -ForegroundColor Red
            Write-Host "除外率: $exclusionRate%" -ForegroundColor Yellow
            Write-Host "処理方式: SQLベースフィルタリング（高速）" -ForegroundColor Cyan
            
            if ($whereClause) {
                Write-Host "適用フィルタ: $whereClause" -ForegroundColor Gray
            }
            else {
                Write-Host "適用フィルタ: なし（全件通過）" -ForegroundColor Gray
            }
        }
        
        Write-SystemLog "SQLベースフィルタリング完了: $filteredCount 件を $TableName に挿入" -Level "Success"
        
        return @{
            TotalCount    = $totalRecords
            FilteredCount = $filteredCount
            ExcludedCount = $excludedCount
            ExclusionRate = $exclusionRate
        }
        
    }
    catch {
        Write-SystemLog "SQLベースフィルタリングに失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}
