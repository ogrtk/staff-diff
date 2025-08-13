# PowerShell & SQLite データ同期システム
# 同期レポート生成モジュール

# 同期処理の詳細レポート生成（安全な操作）
function Get-SyncReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    $result = Invoke-WithErrorHandling -ScriptBlock {
        $reportQuery = @"
SELECT 
    'PROVIDED_DATA_TOTAL' as category,
    COUNT(*) as count
FROM provided_data
UNION ALL
SELECT 
    'CURRENT_DATA_TOTAL' as category,
    COUNT(*) as count
FROM current_data
UNION ALL
SELECT 
    'SYNC_' || sync_action as category,
    COUNT(*) as count
FROM sync_result
GROUP BY sync_action;
"@
        
        # SQLite CSV形式で結果を取得
        $result = Invoke-SqliteCsvQuery -DatabasePath $DatabasePath -Query $reportQuery
        
        # Log to file
        Write-SystemLog "=== 詳細同期レポート ===" -Level "Info"
        if ($result -and $result.Count -gt 0) {
            foreach ($line in $result) {
                if ($line) {
                    $parts = $line -split ','
                    if ($parts.Count -eq 2) {
                        Write-SystemLog "$($parts[0]): $($parts[1])" -Level "Info"
                    }
                }
            }
        }
        else {
            Write-SystemLog "レポートデータがありません" -Level "Info"
        }
        
        return $result
        
    } -Operation "同期レポート生成" -Category External -SuppressThrow:$true

    if ($null -eq $result) {
        return @()
    }
    return $result
}

Export-ModuleMember -Function 'Get-SyncReport'
Export-ModuleMember -Function 'Get-SyncReport'