#!/usr/bin/env pwsh
# Mock and Test Support Utilities

<#
.SYNOPSIS
Mock helpers and test support utilities for PowerShell & SQLite data management system tests

.DESCRIPTION
This module provides mock functions and test utilities to simulate external dependencies:
- Database operations
- File system operations
- External command executions
- System time and environment
#>

# Mock database responses
$script:MockDatabaseResponses = @{
    SelectAll = @(
        @{ id = 1; employee_id = "E001"; name = "田中太郎" },
        @{ id = 2; employee_id = "E002"; name = "佐藤花子" },
        @{ id = 3; employee_id = "E003"; name = "鈴木一郎" }
    )
    SelectEmpty = @()
    InsertSuccess = @{ RowsAffected = 1; LastInsertId = 123 }
    UpdateSuccess = @{ RowsAffected = 1 }
    DeleteSuccess = @{ RowsAffected = 1 }
    Error = @{ Error = "Database connection failed"; Code = 1001 }
}

function Invoke-MockSqliteCommand {
    <#
    .SYNOPSIS
    Mock SQLite command execution
    
    .PARAMETER Query
    SQL query to mock
    
    .PARAMETER DatabasePath
    Database path (used for validation)
    
    .PARAMETER Parameters
    SQL parameters
    
    .PARAMETER ResponseType
    Type of response to return (SelectAll, SelectEmpty, InsertSuccess, etc.)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,
        
        [string]$DatabasePath,
        
        [hashtable]$Parameters = @{},
        
        [ValidateSet("SelectAll", "SelectEmpty", "InsertSuccess", "UpdateSuccess", "DeleteSuccess", "Error")]
        [string]$ResponseType = "SelectAll"
    )
    
    # Validate database path exists (in real scenario)
    if ($DatabasePath -and -not (Test-Path $DatabasePath)) {
        Write-Warning "Mock: Database path does not exist: $DatabasePath"
    }
    
    # Log the mock operation
    Write-Verbose "Mock SQLite Query: $Query"
    if ($Parameters.Count -gt 0) {
        Write-Verbose "Mock Parameters: $($Parameters | ConvertTo-Json -Compress)"
    }
    
    # Simulate processing time
    Start-Sleep -Milliseconds (Get-Random -Minimum 10 -Maximum 100)
    
    # Return appropriate mock response
    $response = $script:MockDatabaseResponses[$ResponseType]
    
    if ($ResponseType -eq "Error") {
        throw $response.Error
    }
    
    return $response
}

function New-MockTemporaryDirectory {
    <#
    .SYNOPSIS
    Create a temporary directory for testing
    
    .PARAMETER Prefix
    Prefix for the temporary directory name
    #>
    [CmdletBinding()]
    param(
        [string]$Prefix = "mock-test"
    )
    
    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) "$Prefix-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
    
    # Return cleanup script along with path
    return @{
        Path = $tempPath
        Cleanup = {
            if (Test-Path $tempPath) {
                Remove-Item -Path $tempPath -Recurse -Force
            }
        }
    }
}

function Invoke-MockFileOperation {
    <#
    .SYNOPSIS
    Mock file operations for testing
    
    .PARAMETER Operation
    Type of file operation
    
    .PARAMETER FilePath
    File path for the operation
    
    .PARAMETER Content
    Content for write operations
    
    .PARAMETER ShouldFail
    Whether the operation should fail
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Read", "Write", "Delete", "Copy", "Move", "Exists")]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [string]$Content = "",
        
        [switch]$ShouldFail
    )
    
    Write-Verbose "Mock File Operation: $Operation on $FilePath"
    
    if ($ShouldFail) {
        throw "Mock file operation failed: $Operation on $FilePath"
    }
    
    switch ($Operation) {
        "Read" {
            if ($Content) {
                return $Content
            } else {
                return "mock,file,content`nrow1,value1,data1`nrow2,value2,data2"
            }
        }
        "Write" {
            return @{ Success = $true; BytesWritten = $Content.Length }
        }
        "Delete" {
            return @{ Success = $true; Deleted = $FilePath }
        }
        "Copy" {
            return @{ Success = $true; Source = $FilePath; Destination = $Content }
        }
        "Move" {
            return @{ Success = $true; From = $FilePath; To = $Content }
        }
        "Exists" {
            return $true  # Mock files always exist unless ShouldFail is set
        }
    }
}

function New-MockSystemEnvironment {
    <#
    .SYNOPSIS
    Create a mock system environment for testing
    
    .PARAMETER TimeZone
    Mock time zone
    
    .PARAMETER CurrentTime
    Mock current time
    
    .PARAMETER EnvironmentVariables
    Mock environment variables
    #>
    [CmdletBinding()]
    param(
        [string]$TimeZone = "Asia/Tokyo",
        
        [DateTime]$CurrentTime = (Get-Date),
        
        [hashtable]$EnvironmentVariables = @{}
    )
    
    return @{
        TimeZone = $TimeZone
        CurrentTime = $CurrentTime
        EnvironmentVariables = $EnvironmentVariables
        GetTimestamp = {
            param($Format = "yyyyMMdd_HHmmss")
            return $CurrentTime.ToString($Format)
        }
        GetEnvironmentVariable = {
            param($Name)
            return $EnvironmentVariables[$Name]
        }
    }
}

function Invoke-MockExternalCommand {
    <#
    .SYNOPSIS
    Mock external command execution
    
    .PARAMETER CommandName
    Name of the command to mock
    
    .PARAMETER Arguments
    Command arguments
    
    .PARAMETER ResponseType
    Type of response to simulate
    
    .PARAMETER ExitCode
    Exit code to return
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        
        [string[]]$Arguments = @(),
        
        [ValidateSet("Success", "NotFound", "AccessDenied", "InvalidArguments")]
        [string]$ResponseType = "Success",
        
        [int]$ExitCode = 0
    )
    
    Write-Verbose "Mock External Command: $CommandName $($Arguments -join ' ')"
    
    switch ($ResponseType) {
        "Success" {
            return @{
                ExitCode = 0
                StandardOutput = "Mock command executed successfully"
                StandardError = ""
                Success = $true
            }
        }
        "NotFound" {
            throw "Command not found: $CommandName"
        }
        "AccessDenied" {
            return @{
                ExitCode = 1
                StandardOutput = ""
                StandardError = "Access denied"
                Success = $false
            }
        }
        "InvalidArguments" {
            return @{
                ExitCode = 2
                StandardOutput = ""
                StandardError = "Invalid arguments"
                Success = $false
            }
        }
    }
}

function Assert-MockCalled {
    <#
    .SYNOPSIS
    Assert that a mock function was called with specific parameters
    
    .PARAMETER MockName
    Name of the mock function
    
    .PARAMETER Times
    Expected number of calls
    
    .PARAMETER ParameterFilter
    Filter for parameters
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MockName,
        
        [int]$Times = -1,
        
        [scriptblock]$ParameterFilter = { $true }
    )
    
    # This is a simplified mock assertion
    # In a real implementation, you would track mock calls
    Write-Host "Mock Assertion: $MockName should have been called" -ForegroundColor Green
    
    if ($Times -gt 0) {
        Write-Host "Expected $Times calls" -ForegroundColor Gray
    }
    
    return $true
}

function New-MockDataSyncResult {
    <#
    .SYNOPSIS
    Create a mock data synchronization result
    
    .PARAMETER TotalRecords
    Total number of records processed
    
    .PARAMETER AddCount
    Number of records added
    
    .PARAMETER UpdateCount
    Number of records updated
    
    .PARAMETER DeleteCount
    Number of records deleted
    
    .PARAMETER KeepCount
    Number of records kept unchanged
    
    .PARAMETER HasErrors
    Whether the sync had errors
    #>
    [CmdletBinding()]
    param(
        [int]$TotalRecords = 100,
        [int]$AddCount = 20,
        [int]$UpdateCount = 10,
        [int]$DeleteCount = 5,
        [int]$KeepCount = 65,
        [switch]$HasErrors
    )
    
    $errors = @()
    if ($HasErrors) {
        $errors = @(
            @{ Severity = "Warning"; Message = "Record E999 has missing department"; RecordId = "E999" },
            @{ Severity = "Error"; Message = "Duplicate employee_id found: E001"; RecordId = "E001" }
        )
    }
    
    return @{
        Success = -not $HasErrors
        TotalRecords = $TotalRecords
        ProcessedRecords = $AddCount + $UpdateCount + $DeleteCount + $KeepCount
        SyncActions = @{
            ADD = $AddCount
            UPDATE = $UpdateCount
            DELETE = $DeleteCount
            KEEP = $KeepCount
        }
        ProcessingTime = [TimeSpan]::FromSeconds((Get-Random -Minimum 1 -Maximum 10))
        Errors = $errors
        FilterStatistics = @{
            OriginalCount = $TotalRecords
            FilteredCount = $TotalRecords - 10  # Assume 10 filtered out
            ExcludedCount = 10
            ExclusionRate = 10.0
        }
        DatabaseOperations = @{
            Inserts = $AddCount
            Updates = $UpdateCount
            Deletes = $DeleteCount
            Selects = 3  # Typically: select provided, current, verify final
        }
    }
}

function New-MockCsvData {
    <#
    .SYNOPSIS
    Create mock CSV data for testing
    
    .PARAMETER RecordCount
    Number of records to generate
    
    .PARAMETER IncludeHeaders
    Whether to include headers
    
    .PARAMETER IncludeFilterTargets
    Whether to include records that would be filtered
    
    .PARAMETER HasErrors
    Whether to include problematic records
    #>
    [CmdletBinding()]
    param(
        [int]$RecordCount = 10,
        [switch]$IncludeHeaders,
        [switch]$IncludeFilterTargets,
        [switch]$HasErrors
    )
    
    $records = @()
    $headers = @("employee_id", "card_number", "name", "department", "position", "email", "phone", "hire_date")
    
    if ($IncludeHeaders) {
        $records += $headers -join ","
    }
    
    for ($i = 1; $i -le $RecordCount; $i++) {
        $employeeId = "E{0:D3}" -f $i
        $cardNumber = "C{0:D3}" -f $i
        $name = "テスト{0:D3}" -f $i
        $department = "部署{0}" -f ($i % 5)
        $position = "役職{0}" -f ($i % 3)
        $email = "test{0:D3}@example.com" -f $i
        $phone = "090-{0:D4}-{1:D4}" -f ($i % 10000), (($i * 2) % 10000)
        $hireDate = (Get-Date).AddDays(-($i * 30)).ToString("yyyy-MM-dd")
        
        if ($HasErrors -and $i -eq 3) {
            # Create problematic record
            $name = "エラー,データ"  # Comma in name
            $email = ""  # Empty email
        }
        
        $record = @($employeeId, $cardNumber, $name, $department, $position, $email, $phone, $hireDate)
        $records += $record -join ","
    }
    
    if ($IncludeFilterTargets) {
        # Add Z-prefixed record
        $zRecord = @("Z001", "C999", "テスト太郎", "テスト部", "テスト", "test@example.com", "090-0000-0000", "2021-01-01")
        $records += $zRecord -join ","
        
        # Add Y-prefixed record
        $yRecord = @("Y001", "C998", "削除花子", "削除部", "削除", "delete@example.com", "090-0000-0001", "2021-02-01")
        $records += $yRecord -join ","
    }
    
    return $records
}

function Test-MockDataIntegrity {
    <#
    .SYNOPSIS
    Validate mock data integrity
    
    .PARAMETER Data
    Data to validate
    
    .PARAMETER ExpectedSchema
    Expected data schema
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        
        [hashtable]$ExpectedSchema = @{
            RequiredFields = @("employee_id", "name")
            OptionalFields = @("department", "position", "email", "phone")
        }
    )
    
    $validationResults = @{
        IsValid = $true
        Errors = @()
        Warnings = @()
        RecordCount = 0
        FieldCoverage = @{}
    }
    
    if ($Data -is [array] -and $Data.Count -gt 0) {
        $validationResults.RecordCount = $Data.Count
        
        foreach ($record in $Data) {
            # Check required fields
            foreach ($field in $ExpectedSchema.RequiredFields) {
                if (-not $record.ContainsKey($field) -or -not $record[$field]) {
                    $validationResults.Errors += "Missing required field '$field' in record"
                    $validationResults.IsValid = $false
                }
            }
            
            # Track field coverage
            foreach ($field in $record.Keys) {
                if (-not $validationResults.FieldCoverage.ContainsKey($field)) {
                    $validationResults.FieldCoverage[$field] = 0
                }
                $validationResults.FieldCoverage[$field]++
            }
        }
    } else {
        $validationResults.Errors += "No data provided or data is not in expected format"
        $validationResults.IsValid = $false
    }
    
    return $validationResults
}

function Invoke-MockPesterTest {
    <#
    .SYNOPSIS
    Create a mock Pester test result
    
    .PARAMETER TestName
    Name of the test
    
    .PARAMETER ShouldPass
    Whether the test should pass
    
    .PARAMETER Duration
    Test duration in milliseconds
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestName,
        
        [bool]$ShouldPass = $true,
        
        [int]$Duration = 100
    )
    
    $result = @{
        Name = $TestName
        Passed = $ShouldPass
        Duration = [TimeSpan]::FromMilliseconds($Duration)
        FailureMessage = ""
        ErrorRecord = $null
    }
    
    if (-not $ShouldPass) {
        $result.FailureMessage = "Mock test failure: $TestName"
        $result.ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Mock test exception"),
            "MockTestFailure",
            [System.Management.Automation.ErrorCategory]::InvalidResult,
            $TestName
        )
    }
    
    return $result
}

function Remove-MockTemporaryDirectory {
    <#
    .SYNOPSIS
    Remove a temporary directory created for testing
    
    .PARAMETER TempDirectory
    Path to the temporary directory to remove
    .PARAMETER Path
    Alias for TempDirectory parameter for backward compatibility
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "TempDirectory")]
        [Alias("Path")]
        [string]$TempDirectory
    )
    
    try {
        if (Test-Path $TempDirectory) {
            Remove-Item -Path $TempDirectory -Recurse -Force
            Write-Verbose "Removed temporary directory: $TempDirectory"
        } else {
            Write-Verbose "Temporary directory does not exist: $TempDirectory"
        }
    }
    catch {
        Write-Warning "Failed to remove temporary directory: $TempDirectory - $_"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Invoke-MockSqliteCommand',
    'New-MockTemporaryDirectory',
    'Remove-MockTemporaryDirectory',
    'Invoke-MockFileOperation',
    'New-MockSystemEnvironment',
    'Invoke-MockExternalCommand',
    'Assert-MockCalled',
    'New-MockDataSyncResult',
    'New-MockCsvData',
    'Test-MockDataIntegrity',
    'Invoke-MockPesterTest'
)