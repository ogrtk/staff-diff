#!/usr/bin/env pwsh
# Layered Architecture Test Support Utilities

<#
.SYNOPSIS
レイヤアーキテクチャ対応テストヘルパー

.DESCRIPTION
4層アーキテクチャに対応したテストサポート機能：
- Layer 1: Foundation（基盤層）- 設定非依存
- Layer 2: Infrastructure（インフラ層）- 設定依存
- Layer 3: DataAccess（データアクセス層）
- Layer 4: DataProcessing（データ処理層）

各層の依存関係とモックを適切に管理します。
#>

# レイヤー定義と依存関係マップ
$script:LayerArchitecture = @{
    "Foundation" = @{
        Order = 1
        Description = "基盤層（設定非依存）"
        Modules = @("CoreUtils")
        Dependencies = @()  # 依存なし
    }
    "Infrastructure" = @{
        Order = 2
        Description = "インフラ層（設定依存）"
        Modules = @("ConfigurationUtils", "LoggingUtils", "ErrorHandlingUtils")
        Dependencies = @("Foundation")
    }
    "DataAccess" = @{
        Order = 3
        Description = "データアクセス層"
        Modules = @("DatabaseUtils", "FileSystemUtils")
        Dependencies = @("Foundation", "Infrastructure")
    }
    "DataProcessing" = @{
        Order = 4
        Description = "データ処理層"
        Modules = @("CsvProcessingUtils", "DataFilteringUtils")
        Dependencies = @("Foundation", "Infrastructure", "DataAccess")
    }
    "Process" = @{
        Order = 5
        Description = "プロセス層（ビジネスロジック）"
        Modules = @("Show-SyncResult", "Invoke-CsvImport", "Invoke-CsvExport", "Invoke-DataSync", "Invoke-DatabaseInitialization", "Invoke-ConfigValidation", "Test-DataConsistency")
        Dependencies = @("Foundation", "Infrastructure", "DataAccess", "DataProcessing")
    }
}

function Initialize-LayeredTestEnvironment {
    <#
    .SYNOPSIS
    レイヤード テスト環境の初期化
    
    .PARAMETER LayerName
    テスト対象のレイヤー名
    
    .PARAMETER ModuleName
    テスト対象のモジュール名
    
    .PARAMETER MockDependencies
    依存関係をモックするかどうか
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Foundation", "Infrastructure", "DataAccess", "DataProcessing", "Process")]
        [string]$LayerName,
        
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        
        [switch]$MockDependencies = $true
    )
    
    # Pesterヘルパー関数の定義
    if (-not (Get-Command "Set-TestInconclusive" -ErrorAction SilentlyContinue)) {
        function Global:Set-TestInconclusive {
            param([string]$Message)
            Write-Warning "Test Inconclusive: $Message"
            return
        }
    }
    
    $layer = $script:LayerArchitecture[$LayerName]
    
    if (-not $layer.Modules.Contains($ModuleName)) {
        throw "モジュール '$ModuleName' は Layer '$LayerName' に属していません。"
    }
    
    $testEnv = @{
        LayerName = $LayerName
        ModuleName = $ModuleName
        LayerOrder = $layer.Order
        Dependencies = $layer.Dependencies
        MockedFunctions = @{}
        TempDirectory = $null
        ConfigurationMock = $null
    }
    
    # 一時ディレクトリの作成
    $testEnv.TempDirectory = New-MockTemporaryDirectory -Prefix "layered-test-$LayerName-$ModuleName"
    
    # モック化を先に実行（実際のモジュール読み込み前）
    if ($MockDependencies) {
        # 依存関係のモック化
        foreach ($dependencyLayer in $layer.Dependencies) {
            Initialize-LayerMocks -LayerName $dependencyLayer -TestEnvironment $testEnv
        }
        # 現在のレイヤーもモック化対象の場合
        Initialize-LayerMocks -LayerName $LayerName -TestEnvironment $testEnv
    }
    
    # モジュールの読み込み
    Import-LayeredModule -LayerName $LayerName -ModuleName $ModuleName -TestEnvironment $testEnv
    
    # 設定の初期化（Infrastructure層以上の場合）
    if ($layer.Order -ge 2) {
        try {
            Initialize-TestConfiguration
        }
        catch {
            Write-Warning "Test configuration initialization failed: $_"
        }
    }
    
    return $testEnv
}

function Import-LayeredModule {
    <#
    .SYNOPSIS
    レイヤードモジュールのインポート（依存関係を適切な順序で読み込み）
    #>
    [CmdletBinding()]
    param(
        [string]$LayerName,
        [string]$ModuleName,
        [hashtable]$TestEnvironment
    )
    
    # 依存関係を先に読み込み
    Import-LayerDependencies -LayerName $LayerName
    
    # 対象モジュールを読み込み
    if ($LayerName -eq "Process") {
        $modulePath = Join-Path (Get-ProjectRoot) "scripts/modules/Process/$ModuleName.psm1"
    } else {
        $modulePath = Join-Path (Get-ProjectRoot) "scripts/modules/Utils/$LayerName/$ModuleName.psm1"
    }
    
    if (-not (Test-Path $modulePath)) {
        throw "モジュールファイルが見つかりません: $modulePath"
    }
    
    try {
        Import-Module $modulePath -Force -Global
        Write-Verbose "モジュールをインポートしました: $ModuleName ($LayerName)"
    }
    catch {
        throw "モジュールのインポートに失敗しました: $ModuleName - $($_.Exception.Message)"
    }
}

function Import-LayerDependencies {
    <#
    .SYNOPSIS
    指定レイヤーの依存関係を適切な順序でインポート
    #>
    [CmdletBinding()]
    param(
        [string]$LayerName
    )
    
    $layer = $script:LayerArchitecture[$LayerName]
    if (-not $layer) {
        throw "不明なレイヤー: $LayerName"
    }
    
    # 依存関係を順序に従って読み込み（再帰的に依存関係を解決）
    foreach ($dependencyLayer in $layer.Dependencies) {
        # 再帰的に依存関係を解決
        Import-LayerDependencies -LayerName $dependencyLayer
        
        $dependencyLayerInfo = $script:LayerArchitecture[$dependencyLayer]
        
        # 依存レイヤーのすべてのモジュールを読み込み
        foreach ($depModuleName in $dependencyLayerInfo.Modules) {
            # Process層は別ディレクトリ構造
            if ($dependencyLayer -eq "Process") {
                $depModulePath = Join-Path (Get-ProjectRoot) "scripts/modules/Process/$depModuleName.psm1"
            } else {
                $depModulePath = Join-Path (Get-ProjectRoot) "scripts/modules/Utils/$dependencyLayer/$depModuleName.psm1"
            }
            
            if (Test-Path $depModulePath) {
                try {
                    # モジュールが既に読み込まれているかチェック
                    if (-not (Get-Module -Name $depModuleName -ErrorAction SilentlyContinue)) {
                        Import-Module $depModulePath -Force -Global
                        Write-Verbose "依存モジュールをインポートしました: $depModuleName ($dependencyLayer)"
                    }
                }
                catch {
                    Write-Warning "依存モジュールのインポートに失敗しました: $depModuleName - $($_.Exception.Message)"
                }
            }
        }
    }
}

function Initialize-LayerMocks {
    <#
    .SYNOPSIS
    指定レイヤーの関数をモック化
    #>
    [CmdletBinding()]
    param(
        [string]$LayerName,
        [hashtable]$TestEnvironment
    )
    
    switch ($LayerName) {
        "Foundation" {
            Mock-FoundationFunctions -TestEnvironment $TestEnvironment
        }
        "Infrastructure" {
            Mock-InfrastructureFunctions -TestEnvironment $TestEnvironment
        }
        "DataAccess" {
            Mock-DataAccessFunctions -TestEnvironment $TestEnvironment
        }
        "DataProcessing" {
            Mock-DataProcessingFunctions -TestEnvironment $TestEnvironment
        }
        "Process" {
            Mock-ProcessFunctions -TestEnvironment $TestEnvironment
        }
    }
}

function Mock-FoundationFunctions {
    <#
    .SYNOPSIS
    Foundation層関数のモック化
    #>
    [CmdletBinding()]
    param([hashtable]$TestEnvironment)
    
    # CoreUtils functions
    if (-not (Get-Command "Get-Sqlite3Path" -ErrorAction SilentlyContinue)) {
        function Global:Get-Sqlite3Path {
            return @{ Source = "C:\mock\sqlite3.exe" }
        }
        $TestEnvironment.MockedFunctions["Get-Sqlite3Path"] = $true
    }
    
    if (-not (Get-Command "Get-CrossPlatformEncoding" -ErrorAction SilentlyContinue)) {
        function Global:Get-CrossPlatformEncoding {
            return [System.Text.Encoding]::UTF8
        }
        $TestEnvironment.MockedFunctions["Get-CrossPlatformEncoding"] = $true
    }
    
    if (-not (Get-Command "Get-Timestamp" -ErrorAction SilentlyContinue)) {
        function Global:Get-Timestamp {
            param($Format = "yyyyMMdd_HHmmss", $TimeZone = "Asia/Tokyo")
            return (Get-Date).ToString($Format)
        }
        $TestEnvironment.MockedFunctions["Get-Timestamp"] = $true
    }
}

function Mock-InfrastructureFunctions {
    <#
    .SYNOPSIS
    Infrastructure層関数のモック化
    #>
    [CmdletBinding()]
    param([hashtable]$TestEnvironment)
    
    # ConfigurationUtils functions
    if (-not (Get-Command "Get-DataSyncConfig" -ErrorAction SilentlyContinue)) {
        function Global:Get-DataSyncConfig {
            param($ConfigPath, [switch]$Force)
            return $TestEnvironment.ConfigurationMock ?? (New-MockConfiguration)
        }
        $TestEnvironment.MockedFunctions["Get-DataSyncConfig"] = $true
    }
    
    # 設定が実際にロードされていない場合のためのヘルパー関数
    if (-not (Get-Command "Initialize-TestConfiguration" -ErrorAction SilentlyContinue)) {
        function Global:Initialize-TestConfiguration {
            param([string]$ConfigPath)
            
            if (-not $ConfigPath) {
                # デフォルトテスト設定を作成
                $tempConfig = Join-Path ([System.IO.Path]::GetTempPath()) "temp-test-config-$(Get-Random).json"
                $mockConfig = New-MockConfiguration
                $mockConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $tempConfig -Encoding UTF8
                $ConfigPath = $tempConfig
            }
            
            try {
                if (Get-Command "Get-DataSyncConfig" -ErrorAction SilentlyContinue) {
                    Get-DataSyncConfig -ConfigPath $ConfigPath -Force | Out-Null
                }
            }
            catch {
                Write-Warning "Failed to initialize test configuration: $_"
            }
        }
        $TestEnvironment.MockedFunctions["Initialize-TestConfiguration"] = $true
    }
    
    # LoggingUtils functions
    if (-not (Get-Command "Write-SystemLog" -ErrorAction SilentlyContinue)) {
        function Global:Write-SystemLog {
            param($Message, $Level = "Info", $Component = "Test")
            Write-Host "Mock Log [$Level][$Component]: $Message"
        }
        $TestEnvironment.MockedFunctions["Write-SystemLog"] = $true
    }
    
    # ErrorHandlingUtils functions
    if (-not (Get-Command "Invoke-WithErrorHandling" -ErrorAction SilentlyContinue)) {
        function Global:Invoke-WithErrorHandling {
            param(
                [scriptblock]$ScriptBlock,
                [string]$Category = "System",
                [string]$Operation = "Operation",
                [hashtable]$Context = @{},
                [scriptblock]$CleanupScript = {}
            )
            try {
                return & $ScriptBlock
            } catch {
                Write-Warning "Mock error handling: $($_.Exception.Message)"
                throw
            }
        }
        $TestEnvironment.MockedFunctions["Invoke-WithErrorHandling"] = $true
    }
    
    if (-not (Get-Command "Invoke-FileOperationWithErrorHandling" -ErrorAction SilentlyContinue)) {
        function Global:Invoke-FileOperationWithErrorHandling {
            param(
                [scriptblock]$FileOperation,
                [string]$FilePath,
                [string]$OperationType = "FileOperation"
            )
            try {
                return & $FileOperation
            } catch {
                Write-Warning "Mock file operation error: $($_.Exception.Message)"
                throw
            }
        }
        $TestEnvironment.MockedFunctions["Invoke-FileOperationWithErrorHandling"] = $true
    }
    
    # LoggingUtils additional functions
    if (-not (Get-Command "Initialize-LoggingSystem" -ErrorAction SilentlyContinue)) {
        function Global:Initialize-LoggingSystem {
            param($LogDirectory = "logs", $ConfigSection = @{})
            Write-Verbose "Mock: Logging system initialized"
            return $true
        }
        $TestEnvironment.MockedFunctions["Initialize-LoggingSystem"] = $true
    }
    
    if (-not (Get-Command "Write-ProcessLog" -ErrorAction SilentlyContinue)) {
        function Global:Write-ProcessLog {
            param($Message, $Level = "Info", $Component = "Process")
            Write-Host "Mock Process Log [$Level][$Component]: $Message"
        }
        $TestEnvironment.MockedFunctions["Write-ProcessLog"] = $true
    }
    
    if (-not (Get-Command "Write-ErrorLog" -ErrorAction SilentlyContinue)) {
        function Global:Write-ErrorLog {
            param($ErrorRecord, $Context = @{}, $Component = "Error")
            Write-Host "Mock Error Log [$Component]: $($ErrorRecord.Exception.Message)"
        }
        $TestEnvironment.MockedFunctions["Write-ErrorLog"] = $true
    }
}

function Mock-DataAccessFunctions {
    <#
    .SYNOPSIS
    DataAccess層関数のモック化
    #>
    [CmdletBinding()]
    param([hashtable]$TestEnvironment)
    
    # DatabaseUtils functions
    if (-not (Get-Command "Get-TableDefinition" -ErrorAction SilentlyContinue)) {
        function Global:Get-TableDefinition {
            param($TableName)
            return @{
                columns = @{
                    employee_id = @{ type = "TEXT"; primary_key = $true }
                    name = @{ type = "TEXT"; nullable = $false }
                }
            }
        }
        $TestEnvironment.MockedFunctions["Get-TableDefinition"] = $true
    }
    
    # FileSystemUtils functions
    if (-not (Get-Command "Save-WithHistory" -ErrorAction SilentlyContinue)) {
        function Global:Save-WithHistory {
            param($Content, $OutputPath, $HistoryDir)
            $tempFile = Join-Path $TestEnvironment.TempDirectory.Path "mock-output.csv"
            $Content | Out-File -FilePath $tempFile -Encoding UTF8
            return @{ OutputPath = $tempFile; HistoryPath = $tempFile }
        }
        $TestEnvironment.MockedFunctions["Save-WithHistory"] = $true
    }
    
    # DatabaseUtils additional functions
    if (-not (Get-Command "Invoke-SqliteCsvQuery" -ErrorAction SilentlyContinue)) {
        function Global:Invoke-SqliteCsvQuery {
            param($DatabasePath, $Query, $Headers = $true)
            # Show-SyncResultテスト用のモックデータ
            return @(
                @{ sync_action = "1"; count = "5" },
                @{ sync_action = "2"; count = "3" },
                @{ sync_action = "3"; count = "1" },
                @{ sync_action = "9"; count = "10" }
            )
        }
        $TestEnvironment.MockedFunctions["Invoke-SqliteCsvQuery"] = $true
    }
    
    if (-not (Get-Command "Initialize-Database" -ErrorAction SilentlyContinue)) {
        function Global:Initialize-Database {
            param($DatabasePath, $ConfigData)
            Write-Verbose "Mock: Database initialized at $DatabasePath"
            return $true
        }
        $TestEnvironment.MockedFunctions["Initialize-Database"] = $true
    }
}

function Mock-DataProcessingFunctions {
    <#
    .SYNOPSIS
    DataProcessing層関数のモック化
    #>
    [CmdletBinding()]
    param([hashtable]$TestEnvironment)
    
    # CsvProcessingUtils functions
    if (-not (Get-Command "ConvertFrom-CsvData" -ErrorAction SilentlyContinue)) {
        function Global:ConvertFrom-CsvData {
            param($CsvContent, $TableName)
            return @(
                @{ employee_id = "E001"; name = "テスト太郎" },
                @{ employee_id = "E002"; name = "テスト花子" }
            )
        }
        $TestEnvironment.MockedFunctions["ConvertFrom-CsvData"] = $true
    }
    
    # DataFilteringUtils functions
    if (-not (Get-Command "Invoke-DataFiltering" -ErrorAction SilentlyContinue)) {
        function Global:Invoke-DataFiltering {
            param($Data, $FilterConfig, $TableName)
            
            if (-not $Data -or $Data.Count -eq 0) {
                return @{
                    FilteredData = @()
                    Statistics = @{ 
                        OriginalCount = 0; 
                        FilteredCount = 0; 
                        ExcludedCount = 0; 
                        ProcessingTime = "0.001s"
                        Timestamp = Get-Timestamp
                    }
                }
            }
            
            $filteredData = @()
            $excludedCount = 0
            
            # フィルタ設定がある場合の実際のフィルタリング
            if ($FilterConfig -and $FilterConfig.exclude) {
                foreach ($item in $Data) {
                    $shouldExclude = $false
                    
                    foreach ($excludePattern in $FilterConfig.exclude) {
                        # 主要なフィールドでパターンマッチ
                        $itemValues = @($item.employee_id, $item.user_id, $item.id, $item.name) | Where-Object { $_ }
                        
                        foreach ($value in $itemValues) {
                            if ($value -like $excludePattern) {
                                $shouldExclude = $true
                                break
                            }
                        }
                        if ($shouldExclude) { break }
                    }
                    
                    if (-not $shouldExclude) {
                        $filteredData += $item
                    } else {
                        $excludedCount++
                    }
                }
            } else {
                $filteredData = $Data
            }
            
            return @{
                FilteredData = $filteredData
                Statistics = @{ 
                    OriginalCount = $Data.Count; 
                    FilteredCount = $filteredData.Count; 
                    ExcludedCount = $excludedCount;
                    ProcessingTime = "0.001s"
                    Timestamp = Get-Timestamp
                }
            }
        }
        $TestEnvironment.MockedFunctions["Invoke-DataFiltering"] = $true
    }
}

function Mock-ProcessFunctions {
    <#
    .SYNOPSIS
    Process層関数のモック化
    #>
    [CmdletBinding()]
    param([hashtable]$TestEnvironment)
    
    # Show-SyncResult functions (Process層はテスト対象なので通常はモックしない)
    # 他のProcess層モジュールで必要な場合のみ追加
    
    Write-Verbose "Mock: Process layer mock functions initialized"
}

function New-MockConfiguration {
    <#
    .SYNOPSIS
    モック設定オブジェクトの作成
    #>
    return @{
        file_paths = @{
            provided_data_file_path = "test-data/provided.csv"
            current_data_file_path = "test-data/current.csv"
            output_file_path = "test-data/output.csv"
            timezone = "Asia/Tokyo"
        }
        tables = @{
            provided_data = @{
                columns = @{
                    employee_id = @{ type = "TEXT"; primary_key = $true; nullable = $false }
                    card_number = @{ type = "TEXT"; nullable = $true }
                    name = @{ type = "TEXT"; nullable = $false }
                    department = @{ type = "TEXT"; nullable = $true }
                    position = @{ type = "TEXT"; nullable = $true }
                    email = @{ type = "TEXT"; nullable = $true }
                    phone = @{ type = "TEXT"; nullable = $true }
                    hire_date = @{ type = "TEXT"; nullable = $true }
                }
                csv_mapping = @{
                    delimiter = ","
                    header_row = 1
                    encoding = "utf8"
                }
                filter = @{
                    exclude = @("Z*")
                    output_excluded_as_keep = $true
                }
            }
            current_data = @{
                columns = @{
                    employee_id = @{ type = "TEXT"; primary_key = $true; nullable = $false }
                    card_number = @{ type = "TEXT"; nullable = $true }
                    name = @{ type = "TEXT"; nullable = $false }
                    department = @{ type = "TEXT"; nullable = $true }
                    position = @{ type = "TEXT"; nullable = $true }
                    email = @{ type = "TEXT"; nullable = $true }
                    phone = @{ type = "TEXT"; nullable = $true }
                    hire_date = @{ type = "TEXT"; nullable = $true }
                }
            }
        }
        sync_config = @{
            key_columns = @("employee_id")
            comparison_columns = @("card_number", "name", "department", "position", "email", "phone", "hire_date")
        }
    }
}

function Get-ProjectRoot {
    <#
    .SYNOPSIS
    プロジェクトルートディレクトリの取得
    #>
    # 複数の可能な起点を試行
    $possibleStartPaths = @(
        $PSScriptRoot,
        (Get-Location).Path,
        $MyInvocation.PSScriptRoot,
        (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
    )
    
    foreach ($startPath in $possibleStartPaths) {
        if (-not $startPath) { continue }
        
        $currentPath = $startPath
        
        # 最大10レベルまで上位ディレクトリを探索
        for ($i = 0; $i -lt 10; $i++) {
            if (Test-Path (Join-Path $currentPath "CLAUDE.md")) {
                return $currentPath
            }
            $parentPath = Split-Path $currentPath -Parent
            if (-not $parentPath -or $parentPath -eq $currentPath) { break }
            $currentPath = $parentPath
        }
    }
    
    # フォールバック: 既知のワーキングディレクトリから推測
    if ($PWD.Path -like "*/ps-sqlite*") {
        $currentPath = $PWD.Path
        while ($currentPath -and -not (Test-Path (Join-Path $currentPath "CLAUDE.md"))) {
            $currentPath = Split-Path $currentPath -Parent
        }
        if ($currentPath) { return $currentPath }
    }
    
    throw "プロジェクトルートが見つかりません（CLAUDE.mdを基準）。起動パス: $($possibleStartPaths -join ', ')"
}

function Cleanup-LayeredTestEnvironment {
    <#
    .SYNOPSIS
    レイヤードテスト環境のクリーンアップ
    #>
    [CmdletBinding()]
    param([hashtable]$TestEnvironment)
    
    # 一時ディレクトリのクリーンアップ
    if ($TestEnvironment.TempDirectory -and $TestEnvironment.TempDirectory.Cleanup) {
        & $TestEnvironment.TempDirectory.Cleanup
    }
    
    # モックされた関数の削除
    foreach ($functionName in $TestEnvironment.MockedFunctions.Keys) {
        if (Get-Command $functionName -ErrorAction SilentlyContinue) {
            Remove-Item -Path "Function:\$functionName" -Force -ErrorAction SilentlyContinue
        }
    }
    
    # モジュールのアンロード
    $moduleName = $TestEnvironment.ModuleName
    Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
}

function Assert-LayeredModuleDependencies {
    <#
    .SYNOPSIS
    レイヤード依存関係のアサーション
    #>
    [CmdletBinding()]
    param(
        [string]$LayerName,
        [string]$ModuleName
    )
    
    $layer = $script:LayerArchitecture[$LayerName]
    $result = @{
        LayerName = $LayerName
        ModuleName = $ModuleName
        Dependencies = $layer.Dependencies
        ValidDependencies = @()
        InvalidDependencies = @()
        CircularDependencies = @()
    }
    
    # 依存関係の検証
    foreach ($depLayer in $layer.Dependencies) {
        $depLayerInfo = $script:LayerArchitecture[$depLayer]
        if ($depLayerInfo.Order -lt $layer.Order) {
            $result.ValidDependencies += $depLayer
        } else {
            $result.InvalidDependencies += $depLayer
        }
    }
    
    return $result
}

function New-LayeredTestData {
    <#
    .SYNOPSIS
    レイヤードテスト用のサンプルデータ作成
    #>
    [CmdletBinding()]
    param(
        [string]$DataType = "Employee",
        [int]$RecordCount = 5,
        [switch]$IncludeHeaders,
        [switch]$IncludeProblematicData
    )
    
    switch ($DataType) {
        "Employee" {
            return New-MockEmployeeData -RecordCount $RecordCount -IncludeHeaders:$IncludeHeaders -IncludeProblematicData:$IncludeProblematicData
        }
        "Configuration" {
            return New-MockConfiguration
        }
        "SyncResult" {
            return New-MockDataSyncResult
        }
        default {
            throw "サポートされていないデータタイプ: $DataType"
        }
    }
}

function New-MockEmployeeData {
    <#
    .SYNOPSIS
    モック従業員データの作成
    #>
    [CmdletBinding()]
    param(
        [int]$RecordCount = 5,
        [switch]$IncludeHeaders,
        [switch]$IncludeProblematicData
    )
    
    $headers = @("employee_id", "card_number", "name", "department", "position", "email", "phone", "hire_date")
    $records = @()
    
    if ($IncludeHeaders) {
        $records += $headers -join ","
    }
    
    for ($i = 1; $i -le $RecordCount; $i++) {
        $employeeId = "E{0:D3}" -f $i
        $cardNumber = "C{0:D3}" -f $i
        $name = "テスト{0:D3}" -f $i
        $department = "部署{0}" -f ($i % 3)
        $position = "役職{0}" -f ($i % 2)
        $email = "test{0:D3}@example.com" -f $i
        $phone = "090-{0:D4}-{1:D4}" -f ($i % 10000), (($i * 2) % 10000)
        $hireDate = (Get-Date).AddDays(-($i * 30)).ToString("yyyy-MM-dd")
        
        if ($IncludeProblematicData -and $i -eq 3) {
            $name = "エラー,データ"  # Comma in name causes CSV parsing issues
            $email = ""  # Empty required field
        }
        
        $record = @($employeeId, $cardNumber, $name, $department, $position, $email, $phone, $hireDate)
        $records += $record -join ","
    }
    
    return $records
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-LayeredTestEnvironment',
    'Import-LayeredModule',
    'Initialize-LayerMocks',
    'Mock-FoundationFunctions',
    'Mock-InfrastructureFunctions',
    'Mock-DataAccessFunctions',
    'Mock-DataProcessingFunctions',
    'New-MockConfiguration',
    'Get-ProjectRoot',
    'Cleanup-LayeredTestEnvironment',
    'Assert-LayeredModuleDependencies',
    'New-LayeredTestData',
    'New-MockEmployeeData'
)