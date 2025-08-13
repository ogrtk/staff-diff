# PowerShell & SQLite データ同期システム
# 同期統計表示モジュール

# 同期統計情報の表示
function Show-SyncStatistics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    $result = Invoke-WithErrorHandling -ScriptBlock {
        $statsQuery = @"
SELECT 
    sync_action,
    COUNT(*) as count
FROM sync_result
GROUP BY sync_action;
"@
        
        # SQLite CSV形式で結果を取得
        $result = Invoke-SqliteCsvQuery -DatabasePath $DatabasePath -Query $statsQuery
        
        Write-SystemLog "=== 同期処理統計 ===" -Level "Info"
        if ($result -and $result.Count -gt 0) {
            foreach ($line in $result) {
                if ($line) {
                    $parts = $line -split ','
                    if ($parts.Count -eq 2) {
                        Write-SystemLog "$($parts[0]): $($parts[1])件" -Level "Info"
                    }
                }
            }
        }
        else {
            Write-SystemLog "統計データがありません" -Level "Info"
        }
        Write-SystemLog "=====================" -Level "Info"
        
        return $result
        
    } -Operation "同期統計情報表示" -Category Data -SuppressThrow:$true

    if ($null -eq $result) {
        return @()
    }
    return $result
}

Export-ModuleMember -Function 'Show-SyncStatistics'
