# PowerShell & SQLite データ同期システム
# データベース情報表示モジュール

# データベース情報の表示（安全な操作）
function Show-DatabaseInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    $result = Invoke-WithErrorHandling -ScriptBlock {
        Write-SystemLog "データベース情報を取得中..." -Level "Info"
        
        $config = Get-DataSyncConfig
        
        Write-SystemLog "=== データベース情報 ===" -Level "Info"
        Write-SystemLog "データベースファイル: $DatabasePath" -Level "Info"
        Write-SystemLog "設定バージョン: $($config.version)" -Level "Info"
        
        foreach ($tableName in $config.tables.PSObject.Properties.Name) {
            $countQuery = "SELECT COUNT(*) as count FROM $tableName;"
            
            $tableResult = Invoke-WithErrorHandling -ScriptBlock {
                $result = Invoke-SqliteCsvQuery -DatabasePath $DatabasePath -Query $countQuery
                $count = if ($result -and $result.Count -gt 0) { [int]$result[0].count } else { 0 }
                return $count
            } -Operation "テーブル件数取得 ($tableName)" -Category External -SuppressThrow:$true

            if ($null -eq $tableResult) {
                $tableResult = "取得エラー"
            }
            
            Write-SystemLog "$tableName : $tableResult" -Level "Info"
        }
        
        Write-SystemLog "========================" -Level "Info"
        
        return "データベース情報表示完了"
        
    } -Operation "データベース情報表示" -Category External -SuppressThrow:$true

    if ($null -eq $result) {
        return "表示スキップ"
    }
    return $result
}

Export-ModuleMember -Function 'Show-DatabaseInfo'
