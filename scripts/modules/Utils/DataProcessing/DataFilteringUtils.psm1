# PowerShell & SQLite データ同期システム
# Layer 4: Data Filtering ユーティリティライブラリ（データフィルタ処理専用）

# Layer 1, 2への依存は実行時に解決

# フィルタ設定の表示
function Show-FilterConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $filterConfig = Get-DataFilterConfig -TableName $TableName
    
    if (-not $filterConfig) {
        Write-SystemLog "テーブル '$TableName' にフィルタ設定がありません" -Level "Warning"
        return
    }
    
    Write-SystemLog "=== フィルタ設定: $TableName ===" -Level "Info"
    Write-SystemLog "有効: $($filterConfig.enabled)" -Level "Info"
    
    if ($filterConfig.rules -and $filterConfig.rules.Count -gt 0) {
        Write-SystemLog "ルール数: $($filterConfig.rules.Count)" -Level "Info"
        
        for ($i = 0; $i -lt $filterConfig.rules.Count; $i++) {
            $rule = $filterConfig.rules[$i]
            Write-SystemLog "  [$($i + 1)] フィールド: $($rule.field)" -Level "Info"
            Write-SystemLog "       タイプ: $($rule.type)" -Level "Info"
            
            if ($rule.pattern) {
                Write-SystemLog "       パターン: $($rule.pattern)" -Level "Info"
            }
            if ($rule.value) {
                Write-SystemLog "       値: $($rule.value)" -Level "Info"
            }
            if ($rule.glob) {
                Write-SystemLog "       GLOBパターン: $($rule.glob)" -Level "Info"
            }
            
            if ($rule.description) {
                Write-SystemLog "       説明: $($rule.description)" -Level "Info"
            }
        }
    }
    else {
        Write-SystemLog "ルールが設定されていません" -Level "Warning"
    }
}

# 一時テーブル名の生成（utils関数）
function New-TempTableName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseTableName
    )
    
    return "${BaseTableName}_temp"
}

# フィルタリング統計の表示（utils関数）
function Show-FilteringStatistics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [int]$TotalCount,
        
        [Parameter(Mandatory = $true)]
        [int]$FilteredCount,
        
        [string]$WhereClause = ""
    )
    
    $excludedCount = $TotalCount - $FilteredCount
    $filterRate = if ($TotalCount -gt 0) { [math]::Round(($FilteredCount / $TotalCount) * 100, 1) } else { 0 }
    
    Write-SystemLog "----------------------------------" -Level "Info"
    Write-SystemLog "データフィルタ処理結果: $TableName" -Level "Info"
    
    if ($WhereClause) {
        Write-SystemLog "適用フィルタ: $WhereClause" -Level "Info"
        Write-SystemLog "総件数: $TotalCount" -Level "Info"
        Write-SystemLog "通過件数: $FilteredCount (通過率: ${filterRate}%)" -Level "Info"
        Write-SystemLog "除外件数: $excludedCount" -Level "Info"
        
        if ($excludedCount -gt 0) {
            Write-SystemLog "フィルタにより $excludedCount 件のデータが除外されました" -Level "Warning"
        }
    }
    else {
        Write-SystemLog "適用フィルタ: なし（全件通過）" -Level "Info"
        Write-SystemLog "処理件数: $TotalCount" -Level "Info"
    }
    
    Write-SystemLog "----------------------------------" -Level "Info"
}

# フィルタルールの詳細分析
function Get-FilterRuleAnalysis {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $filterConfig = Get-DataFilterConfig -TableName $TableName
    
    if (-not $filterConfig -or -not $filterConfig.enabled) {
        return @{
            Enabled      = $false
            RuleCount    = 0
            IncludeRules = 0
            ExcludeRules = 0
            Fields       = @()
        }
    }
    
    $analysis = @{
        Enabled      = $true
        RuleCount    = $filterConfig.rules.Count
        IncludeRules = 0
        ExcludeRules = 0
        Fields       = @()
    }
    
    foreach ($rule in $filterConfig.rules) {
        switch ($rule.type) {
            "include" { $analysis.IncludeRules++ }
            "exclude" { $analysis.ExcludeRules++ }
        }
        
        if ($rule.field -notin $analysis.Fields) {
            $analysis.Fields += $rule.field
        }
    }
    
    return $analysis
}

# フィルタ有効性の確認
function Test-FilterEffectiveness {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [int]$TotalRecords,
        
        [Parameter(Mandatory = $true)]
        [int]$FilteredRecords
    )
    
    $filterAnalysis = Get-FilterRuleAnalysis -TableName $TableName
    
    if (-not $filterAnalysis.Enabled) {
        Write-SystemLog "テーブル '$TableName' のフィルタは無効です" -Level "Info"
        return $true
    }
    
    $exclusionRate = if ($TotalRecords -gt 0) { 
        [math]::Round((($TotalRecords - $FilteredRecords) / $TotalRecords) * 100, 1) 
    }
    else { 
        0 
    }
    
    Write-SystemLog "フィルタ有効性分析: $TableName" -Level "Info"
    Write-SystemLog "  設定ルール数: $($filterAnalysis.RuleCount)" -Level "Info"
    Write-SystemLog "  除外ルール: $($filterAnalysis.ExcludeRules), 包含ルール: $($filterAnalysis.IncludeRules)" -Level "Info"
    Write-SystemLog "  対象フィールド: $($filterAnalysis.Fields -join ', ')" -Level "Info"
    Write-SystemLog "  除外率: ${exclusionRate}%" -Level "Info"
    
    # 警告の出力
    if ($exclusionRate -gt 50) {
        Write-SystemLog "警告: フィルタにより50%以上のデータが除外されています。フィルタ設定を確認してください。" -Level "Warning"
        return $false
    }
    elseif ($exclusionRate -eq 0 -and $filterAnalysis.ExcludeRules -gt 0) {
        Write-SystemLog "情報: 除外ルールが設定されていますが、データは除外されませんでした。" -Level "Info"
    }
    
    return $true
}

# フィルタ性能メトリクスの収集
function Get-FilterPerformanceMetrics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [int]$TotalRecords,
        
        [Parameter(Mandatory = $true)]
        [int]$FilteredRecords,
        
        [Parameter(Mandatory = $true)]
        [timespan]$ProcessingTime
    )
    
    $filterAnalysis = Get-FilterRuleAnalysis -TableName $TableName
    
    return @{
        TableName        = $TableName
        FilterEnabled    = $filterAnalysis.Enabled
        RuleCount        = $filterAnalysis.RuleCount
        TotalRecords     = $TotalRecords
        FilteredRecords  = $FilteredRecords
        ExcludedRecords  = $TotalRecords - $FilteredRecords
        ExclusionRate    = if ($TotalRecords -gt 0) { 
            [math]::Round((($TotalRecords - $FilteredRecords) / $TotalRecords) * 100, 2) 
        }
        else { 
            0 
        }
        ProcessingTimeMs = $ProcessingTime.TotalMilliseconds
        RecordsPerSecond = if ($ProcessingTime.TotalSeconds -gt 0) { 
            [math]::Round($TotalRecords / $ProcessingTime.TotalSeconds, 0) 
        }
        else { 
            $TotalRecords 
        }
    }
}

Export-ModuleMember -Function @(
    'Show-FilterConfig',
    'New-TempTableName',
    'Show-FilteringStatistics',
    'Get-FilterRuleAnalysis',
    'Test-FilterEffectiveness',
    'Get-FilterPerformanceMetrics'
)