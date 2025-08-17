# PowerShell & SQLite データ同期システム
# データ整合性チェックモジュール

using module ”../Utils/Foundation/CoreUtils.psm1"
using module ”../Utils/Infrastructure/LoggingUtils.psm1"
using module ”../Utils/Infrastructure/ConfigurationUtils.psm1"
using module ”../Utils/Infrastructure/ErrorHandlingUtils.psm1"
using module ”../Utils/DataAccess/DatabaseUtils.psm1"

# データの整合性チェック（安全な操作）
function Test-DataConsistency {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    Invoke-WithErrorHandling -ScriptBlock {
        # 複合キー対応のGROUP BY句生成
        $groupByClause = New-GroupByClause -TableName "sync_result"
        $syncResultKeys = Get-TableKeyColumns -TableName "sync_result"
        
        Write-SystemLog "データ整合性をチェック中..." -Level "Info"
        
        # 重複チェック
        $duplicateQuery = @"
SELECT $groupByClause, COUNT(*) as count
FROM sync_result
GROUP BY $groupByClause
HAVING COUNT(*) > 1;
"@
        
        $duplicates = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $duplicateQuery
        
        if ($duplicates -and $duplicates.Count -gt 0) {
            Write-Warning "重複したキー（$($syncResultKeys -join ', ')）が見つかりました:"
            foreach ($dup in $duplicates) {
                $keyValues = @()
                foreach ($key in $syncResultKeys) {
                    $keyValues += $dup.$key
                }
                $keyString = $keyValues -join ', '
                Write-Warning "  ($keyString): $($dup.count)件"
            }
            throw "重複したキー（$($syncResultKeys -join ', ')）が見つかりました:"
        }
        
        Write-SystemLog "データ整合性チェック完了: 問題なし" -Level "Success"
        
    } -Operation "データ整合性チェック" -Category External -SuppressThrow:$true
}

Export-ModuleMember -Function 'Test-DataConsistency'
