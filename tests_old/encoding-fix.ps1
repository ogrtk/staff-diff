#!/usr/bin/env pwsh
# UTF-8 Encoding Fix Script

# Force UTF-8 without BOM for cross-platform compatibility
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
} else {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
}

Write-Host "=== UTF-8 Encoding Test ===" -ForegroundColor Cyan
Write-Host "Testing Japanese characters: データ管理システム" -ForegroundColor Green
Write-Host "Testing Chinese characters: 数据管理系统" -ForegroundColor Green  
Write-Host "Testing Korean characters: 데이터 관리 시스템" -ForegroundColor Green
Write-Host "=== Test Complete ===" -ForegroundColor Cyan