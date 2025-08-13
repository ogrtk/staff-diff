#!/usr/bin/env pwsh
# Test Data Generation Utilities

<#
.SYNOPSIS
Test data generation utilities for PowerShell & SQLite data management system tests

.DESCRIPTION
This module provides functions to generate consistent test data for various test scenarios:
- Employee/user data with Japanese names
- CSV files with different formats and edge cases
- Large datasets for performance testing
- Error scenarios for robustness testing
#>

# Japanese name components for realistic test data
$script:JapaneseLastNames = @(
    "田中", "佐藤", "鈴木", "高橋", "渡辺", "伊藤", "山本", "中村", "小林", "加藤",
    "吉田", "山田", "佐々木", "山口", "松本", "井上", "木村", "林", "斎藤", "清水"
)

$script:JapaneseFirstNames = @(
    "太郎", "花子", "一郎", "次郎", "三郎", "洋子", "美佳", "健太", "翔太", "愛子",
    "智子", "直樹", "雅人", "恵子", "幸子", "和也", "麻衣", "香織", "隆", "真理"
)

$script:JapaneseDepartments = @(
    "営業部", "総務部", "開発部", "経理部", "人事部", "企画部", "製造部", "品質保証部",
    "マーケティング部", "情報システム部", "法務部", "広報部", "購買部", "物流部", "研究開発部"
)

$script:JapanesePositions = @(
    "部長", "課長", "係長", "主任", "担当者", "チームリーダー", "スペシャリスト",
    "エキスパート", "アナリスト", "コーディネーター", "アシスタント"
)

function New-TestEmployeeRecord {
    <#
    .SYNOPSIS
    Generate a single test employee record
    
    .PARAMETER EmployeeId
    Employee ID (e.g., "E001")
    
    .PARAMETER IncludeOptionalFields
    Include optional fields like email, phone, hire_date
    
    .PARAMETER UseRealisticData
    Use realistic Japanese names and departments
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EmployeeId,
        
        [switch]$IncludeOptionalFields,
        
        [switch]$UseRealisticData
    )
    
    if ($UseRealisticData) {
        $lastName = Get-Random -InputObject $script:JapaneseLastNames
        $firstName = Get-Random -InputObject $script:JapaneseFirstNames
        $name = $lastName + $firstName
        $department = Get-Random -InputObject $script:JapaneseDepartments
        $position = Get-Random -InputObject $script:JapanesePositions
    } else {
        $name = "テスト{0}" -f ($EmployeeId -replace '\D', '')
        $department = "部署{0}" -f ((Get-Random -Maximum 10) + 1)
        $position = "役職{0}" -f ((Get-Random -Maximum 5) + 1)
    }
    
    $record = @{
        employee_id = $EmployeeId
        name = $name
        department = $department
        position = $position
    }
    
    if ($IncludeOptionalFields) {
        $record.card_number = "C{0:D3}" -f ($EmployeeId -replace '\D', '')
        $record.email = "{0}@example.com" -f $EmployeeId.ToLower()
        $record.phone = "090-{0:D4}-{1:D4}" -f (Get-Random -Maximum 9999), (Get-Random -Maximum 9999)
        $record.hire_date = (Get-Date).AddDays(-((Get-Random -Maximum 3650))).ToString("yyyy-MM-dd")
    }
    
    return $record
}

function New-TestEmployeeDataset {
    <#
    .SYNOPSIS
    Generate a dataset of test employee records
    
    .PARAMETER Count
    Number of records to generate
    
    .PARAMETER IncludeFilterTargets
    Include records that match filter criteria (Z*, Y*, TEMP, etc.)
    
    .PARAMETER FilterTargetRatio
    Ratio of filter targets to include (0.0-1.0)
    
    .PARAMETER IncludeOptionalFields
    Include optional fields like email, phone, hire_date
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Count,
        
        [switch]$IncludeFilterTargets,
        
        [ValidateRange(0.0, 1.0)]
        [double]$FilterTargetRatio = 0.2,
        
        [switch]$IncludeOptionalFields
    )
    
    $dataset = @()
    $filterTargetCount = if ($IncludeFilterTargets) { [Math]::Floor($Count * $FilterTargetRatio) } else { 0 }
    $regularCount = $Count - $filterTargetCount
    
    # Generate regular employee records
    for ($i = 1; $i -le $regularCount; $i++) {
        $employeeId = "E{0:D3}" -f $i
        $record = New-TestEmployeeRecord -EmployeeId $employeeId -IncludeOptionalFields:$IncludeOptionalFields -UseRealisticData
        $dataset += $record
    }
    
    # Generate filter target records
    if ($IncludeFilterTargets) {
        $zCount = [Math]::Floor($filterTargetCount * 0.4)
        $yCount = [Math]::Floor($filterTargetCount * 0.4)
        $tempCount = $filterTargetCount - $zCount - $yCount
        
        # Z-prefixed records
        for ($i = 1; $i -le $zCount; $i++) {
            $employeeId = "Z{0:D3}" -f $i
            $record = New-TestEmployeeRecord -EmployeeId $employeeId -IncludeOptionalFields:$IncludeOptionalFields
            $record.name = "テスト{0:D3}" -f $i
            $record.department = "テスト部"
            $dataset += $record
        }
        
        # Y-prefixed records
        for ($i = 1; $i -le $yCount; $i++) {
            $employeeId = "Y{0:D3}" -f $i
            $record = New-TestEmployeeRecord -EmployeeId $employeeId -IncludeOptionalFields:$IncludeOptionalFields
            $record.name = "削除{0:D3}" -f $i
            $record.department = "削除部"
            $dataset += $record
        }
        
        # TEMP department records
        for ($i = 1; $i -le $tempCount; $i++) {
            $employeeId = "TEMP{0:D3}" -f $i
            $record = New-TestEmployeeRecord -EmployeeId $employeeId -IncludeOptionalFields:$IncludeOptionalFields
            $record.name = "一時{0:D3}" -f $i
            $record.department = "TEMP"
            $dataset += $record
        }
    }
    
    # Shuffle the dataset to randomize order
    return $dataset | Sort-Object { Get-Random }
}

function New-TestCsvFile {
    <#
    .SYNOPSIS
    Create a test CSV file with specified data
    
    .PARAMETER FilePath
    Path where the CSV file should be created
    
    .PARAMETER Data
    Array of hashtables representing the data
    
    .PARAMETER IncludeHeaders
    Include header row in CSV
    
    .PARAMETER Encoding
    File encoding (default: utf8)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [array]$Data,
        
        [switch]$IncludeHeaders = $true,
        
        [string]$Encoding = "utf8"
    )
    
    if ($Data.Count -eq 0) {
        Write-Warning "No data provided for CSV file: $FilePath"
        return
    }
    
    # Get all unique keys from all records
    $allKeys = @()
    foreach ($record in $Data) {
        foreach ($key in $record.Keys) {
            if ($allKeys -notcontains $key) {
                $allKeys += $key
            }
        }
    }
    
    $csvContent = @()
    
    # Add headers if requested
    if ($IncludeHeaders) {
        $csvContent += $allKeys -join ","
    }
    
    # Add data rows
    foreach ($record in $Data) {
        $row = @()
        foreach ($key in $allKeys) {
            $value = $record[$key]
            if ($value -eq $null) {
                $row += ""
            } else {
                # Escape commas and quotes in values
                $value = $value.ToString()
                if ($value.Contains(",") -or $value.Contains("`"") -or $value.Contains("`n")) {
                    $value = "`"$($value.Replace('`"', '`"`"'))`""
                }
                $row += $value
            }
        }
        $csvContent += $row -join ","
    }
    
    # Ensure directory exists
    $directory = Split-Path -Path $FilePath -Parent
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
    
    # Write to file
    $csvContent | Out-File -FilePath $FilePath -Encoding $Encoding
}

function New-TestScenarioData {
    <#
    .SYNOPSIS
    Generate test data for specific scenarios
    
    .PARAMETER Scenario
    Test scenario type
    
    .PARAMETER OutputDirectory
    Directory to save generated files
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Basic", "Large", "Filtering", "EdgeCases", "Performance")]
        [string]$Scenario,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )
    
    if (-not (Test-Path $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }
    
    switch ($Scenario) {
        "Basic" {
            # Small dataset for basic functionality testing
            $providedData = New-TestEmployeeDataset -Count 10 -IncludeOptionalFields -IncludeFilterTargets
            $currentData = $providedData[0..7] | ForEach-Object { 
                $record = $_.Clone()
                $record.user_id = $record.employee_id
                $record.Remove("employee_id")
                $record
            }
            
            New-TestCsvFile -FilePath (Join-Path $OutputDirectory "basic-provided.csv") -Data $providedData
            New-TestCsvFile -FilePath (Join-Path $OutputDirectory "basic-current.csv") -Data $currentData
        }
        
        "Large" {
            # Large dataset for performance testing
            $providedData = New-TestEmployeeDataset -Count 10000 -IncludeOptionalFields -IncludeFilterTargets -FilterTargetRatio 0.15
            $currentData = $providedData[0..7999] | ForEach-Object { 
                $record = $_.Clone()
                $record.user_id = $record.employee_id
                $record.Remove("employee_id")
                $record
            }
            
            New-TestCsvFile -FilePath (Join-Path $OutputDirectory "large-provided.csv") -Data $providedData
            New-TestCsvFile -FilePath (Join-Path $OutputDirectory "large-current.csv") -Data $currentData
        }
        
        "Filtering" {
            # Dataset focused on filter testing
            $providedData = @()
            
            # Add normal records
            $providedData += New-TestEmployeeRecord -EmployeeId "E001" -UseRealisticData -IncludeOptionalFields
            $providedData += New-TestEmployeeRecord -EmployeeId "E002" -UseRealisticData -IncludeOptionalFields
            $providedData += New-TestEmployeeRecord -EmployeeId "E003" -UseRealisticData -IncludeOptionalFields
            
            # Add filter targets
            $zRecord = New-TestEmployeeRecord -EmployeeId "Z001" -IncludeOptionalFields
            $zRecord.name = "テスト太郎"
            $zRecord.department = "テスト部"
            $providedData += $zRecord
            
            $yRecord = New-TestEmployeeRecord -EmployeeId "Y001" -IncludeOptionalFields
            $yRecord.name = "削除花子"
            $yRecord.department = "削除部"
            $providedData += $yRecord
            
            $tempRecord = New-TestEmployeeRecord -EmployeeId "TEMP001" -IncludeOptionalFields
            $tempRecord.name = "一時太郎"
            $tempRecord.department = "TEMP"
            $providedData += $tempRecord
            
            New-TestCsvFile -FilePath (Join-Path $OutputDirectory "filter-test.csv") -Data $providedData
        }
        
        "EdgeCases" {
            # Dataset with edge cases and potential problems
            $edgeCaseData = @(
                @{ employee_id = "E001"; name = "田中太郎"; department = "営業部"; position = "主任" },
                @{ employee_id = "E002"; name = ""; department = "総務部"; position = "係長" },  # Empty name
                @{ employee_id = ""; name = "鈴木一郎"; department = "開発部"; position = "部長" },  # Empty ID
                @{ employee_id = "E004"; name = $null; department = $null; position = $null },  # Null values
                @{ employee_id = "E005"; name = "山田,次郎"; department = "経理部"; position = "主任" },  # Comma in name
                @{ employee_id = "E006"; name = "佐藤`"花子`""; department = "人事部"; position = "係長" },  # Quotes in name
                @{ employee_id = "E007"; name = "田中太郎`n改行"; department = "企画部"; position = "担当者" }  # Newline in name
            )
            
            New-TestCsvFile -FilePath (Join-Path $OutputDirectory "edge-cases.csv") -Data $edgeCaseData
            
            # Also create invalid CSV structure
            $invalidContent = @(
                "employee_id,name,department",
                "E001,田中太郎,営業部",
                "E002,佐藤花子",  # Missing field
                "E003,鈴木一郎,開発部,部長,extra_field"  # Extra field
            )
            $invalidContent | Out-File -FilePath (Join-Path $OutputDirectory "invalid-structure.csv") -Encoding utf8
        }
        
        "Performance" {
            # Multiple files for performance testing
            $sizes = @(100, 1000, 5000, 10000)
            
            foreach ($size in $sizes) {
                $data = New-TestEmployeeDataset -Count $size -IncludeOptionalFields -IncludeFilterTargets -FilterTargetRatio 0.1
                New-TestCsvFile -FilePath (Join-Path $OutputDirectory "performance-${size}.csv") -Data $data
            }
        }
    }
    
    Write-Host "Generated test data for scenario '$Scenario' in: $OutputDirectory" -ForegroundColor Green
}

function New-MockConfiguration {
    <#
    .SYNOPSIS
    Generate mock configuration for testing
    
    .PARAMETER ConfigType
    Type of configuration to generate
    
    .PARAMETER OutputPath
    Path where configuration file should be saved
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Complete", "Minimal", "Invalid", "FilterOnly")]
        [string]$ConfigType,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )
    
    $config = @{}
    
    switch ($ConfigType) {
        "Complete" {
            $config = @{
                file_paths = @{
                    provided_data_file_path = "./test-data/provided.csv"
                    current_data_file_path = "./test-data/current.csv"
                    output_file_path = "./test-data/sync-result.csv"
                    provided_data_history_directory = "./data/provided-data/"
                    current_data_history_directory = "./data/current-data/"
                    output_history_directory = "./data/output/"
                    timezone = "Asia/Tokyo"
                }
                tables = @{
                    provided_data = @{
                        description = "提供データテーブル"
                        columns = @(
                            @{ name = "id"; type = "INTEGER"; constraints = "PRIMARY KEY AUTOINCREMENT"; csv_include = $false; required = $true },
                            @{ name = "employee_id"; type = "TEXT"; constraints = "NOT NULL UNIQUE"; csv_include = $true; required = $true },
                            @{ name = "card_number"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false },
                            @{ name = "name"; type = "TEXT"; constraints = "NOT NULL"; csv_include = $true; required = $true },
                            @{ name = "department"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false },
                            @{ name = "position"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false }
                        )
                    }
                    current_data = @{
                        description = "現在データテーブル"
                        columns = @(
                            @{ name = "id"; type = "INTEGER"; constraints = "PRIMARY KEY AUTOINCREMENT"; csv_include = $false; required = $true },
                            @{ name = "user_id"; type = "TEXT"; constraints = "NOT NULL UNIQUE"; csv_include = $true; required = $true },
                            @{ name = "name"; type = "TEXT"; constraints = "NOT NULL"; csv_include = $true; required = $true },
                            @{ name = "department"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false }
                        )
                    }
                }
                sync_rules = @{
                    key_columns = @{
                        provided_data = @("employee_id")
                        current_data = @("user_id")
                        sync_result = @("syokuin_no")
                    }
                    column_mappings = @{
                        mappings = @{
                            employee_id = "user_id"
                            name = "name"
                            department = "department"
                            position = "position"
                        }
                    }
                }
                data_filters = @{
                    provided_data = @{
                        enabled = $true
                        rules = @(
                            @{ field = "employee_id"; type = "exclude"; glob = "Z*"; description = "Z始まりの職員番号を除外" },
                            @{ field = "employee_id"; type = "exclude"; glob = "Y*"; description = "Y始まりの職員番号を除外" }
                        )
                    }
                    current_data = @{
                        enabled = $true
                        rules = @(
                            @{ field = "user_id"; type = "exclude"; glob = "Z*"; description = "Z始まりの利用者IDを除外" }
                        )
                    }
                }
            }
        }
        
        "Minimal" {
            $config = @{
                file_paths = @{
                    provided_data_file_path = "./test-data/provided.csv"
                    current_data_file_path = "./test-data/current.csv"
                    output_file_path = "./test-data/sync-result.csv"
                }
                tables = @{
                    provided_data = @{
                        columns = @(
                            @{ name = "employee_id"; type = "TEXT"; csv_include = $true; required = $true },
                            @{ name = "name"; type = "TEXT"; csv_include = $true; required = $true }
                        )
                    }
                }
            }
        }
        
        "Invalid" {
            $config = @{
                # Missing required file_paths section
                tables = "invalid_structure"  # Should be object, not string
                invalid_section = @{
                    test = $true
                }
            }
        }
        
        "FilterOnly" {
            $config = @{
                data_filters = @{
                    provided_data = @{
                        enabled = $true
                        rules = @(
                            @{ field = "employee_id"; type = "exclude"; glob = "Z*"; description = "Test filter" },
                            @{ field = "department"; type = "exclude"; glob = "TEMP"; description = "Exclude temp data" },
                            @{ field = "employee_id"; type = "include"; glob = "E*"; description = "Include E-prefixed only" }
                        )
                    }
                }
            }
        }
    }
    
    # Ensure directory exists
    $directory = Split-Path -Path $OutputPath -Parent
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
    
    # Save configuration
    $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding utf8
    
    Write-Host "Generated $ConfigType configuration: $OutputPath" -ForegroundColor Green
}

function Get-TestDataStatistics {
    <#
    .SYNOPSIS
    Generate statistics about test data
    
    .PARAMETER Data
    Array of data records
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Data
    )
    
    if ($Data.Count -eq 0) {
        return @{ TotalRecords = 0; Message = "No data provided" }
    }
    
    $stats = @{
        TotalRecords = $Data.Count
        FieldStatistics = @{}
        FilterTargets = @{
            ZPrefixed = 0
            YPrefixed = 0
            TempDepartment = 0
            InactiveDepartment = 0
        }
        DataQuality = @{
            EmptyFields = 0
            NullFields = 0
            ValidRecords = 0
        }
    }
    
    # Analyze each record
    foreach ($record in $Data) {
        $isValid = $true
        
        foreach ($key in $record.Keys) {
            # Initialize field statistics
            if (-not $stats.FieldStatistics.ContainsKey($key)) {
                $stats.FieldStatistics[$key] = @{
                    PopulatedCount = 0
                    EmptyCount = 0
                    NullCount = 0
                    UniqueValues = @()
                }
            }
            
            $value = $record[$key]
            
            if ($value -eq $null) {
                $stats.FieldStatistics[$key].NullCount++
                $stats.DataQuality.NullFields++
                $isValid = $false
            } elseif ($value -eq "" -or $value.ToString().Trim() -eq "") {
                $stats.FieldStatistics[$key].EmptyCount++
                $stats.DataQuality.EmptyFields++
                $isValid = $false
            } else {
                $stats.FieldStatistics[$key].PopulatedCount++
                if ($stats.FieldStatistics[$key].UniqueValues -notcontains $value) {
                    $stats.FieldStatistics[$key].UniqueValues += $value
                }
            }
        }
        
        # Check for filter targets
        $id = $record.employee_id ?? $record.user_id
        if ($id) {
            if ($id -like "Z*") { $stats.FilterTargets.ZPrefixed++ }
            if ($id -like "Y*") { $stats.FilterTargets.YPrefixed++ }
        }
        
        if ($record.department) {
            if ($record.department -like "TEMP") { $stats.FilterTargets.TempDepartment++ }
            if ($record.department -like "INACTIVE") { $stats.FilterTargets.InactiveDepartment++ }
        }
        
        if ($isValid) { $stats.DataQuality.ValidRecords++ }
    }
    
    return $stats
}

# Export functions
Export-ModuleMember -Function @(
    'New-TestEmployeeRecord',
    'New-TestEmployeeDataset',
    'New-TestCsvFile',
    'New-TestScenarioData',
    'New-MockConfiguration',
    'Get-TestDataStatistics'
)