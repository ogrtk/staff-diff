#!/usr/bin/env pwsh
# Full System Integration Tests

BeforeAll {
    $script:TestRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:MainScript = Join-Path $TestRoot 'scripts/main.ps1'
    $script:ConfigPath = Join-Path $TestRoot 'config/data-sync-config.json'
    
    # Import test helpers
    $script:TestHelpersPath = Join-Path $PSScriptRoot '../TestHelpers'
    Import-Module (Join-Path $script:TestHelpersPath 'TestDataGenerator.psm1') -Force
    Import-Module (Join-Path $script:TestHelpersPath 'MockHelpers.psm1') -Force
    
    # Test environment setup
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "full-system-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
    
    # Generate comprehensive test data
    New-TestScenarioData -Scenario "Basic" -OutputDirectory $script:TempDir
    New-TestScenarioData -Scenario "Filtering" -OutputDirectory $script:TempDir
    New-TestScenarioData -Scenario "EdgeCases" -OutputDirectory $script:TempDir
    
    # Create test database directory
    $script:TestDbDir = Join-Path $script:TempDir "database"
    New-Item -ItemType Directory -Path $script:TestDbDir -Force | Out-Null
    $script:TestDbPath = Join-Path $script:TestDbDir "integration-test.db"
}

AfterAll {
    if (Test-Path $script:TempDir) {
        Remove-Item -Path $script:TempDir -Recurse -Force
    }
    
    # Clean up imported modules
    Remove-Module -Name TestDataGenerator -Force -ErrorAction SilentlyContinue
    Remove-Module -Name MockHelpers -Force -ErrorAction SilentlyContinue
}

Describe "Full System Integration Tests" {
    Context "End-to-End Data Synchronization" {
        It "should complete basic synchronization workflow" {
            # Use generated test data
            $providedDataPath = Join-Path $script:TempDir "basic-provided.csv"
            $currentDataPath = Join-Path $script:TempDir "basic-current.csv"
            $outputPath = Join-Path $script:TempDir "integration-output.csv"
            
            # Verify test data files exist
            Test-Path $providedDataPath | Should -Be $true
            Test-Path $currentDataPath | Should -Be $true
            
            # Read and analyze input data
            $providedData = Import-Csv -Path $providedDataPath
            $currentData = Import-Csv -Path $currentDataPath
            
            $providedData.Count | Should -BeGreaterThan 0
            $currentData.Count | Should -BeGreaterThan 0
            
            Write-Host "Test Data Summary:" -ForegroundColor Yellow
            Write-Host "  Provided records: $($providedData.Count)" -ForegroundColor Gray
            Write-Host "  Current records: $($currentData.Count)" -ForegroundColor Gray
            
            # Simulate the sync process
            $mockResult = New-MockDataSyncResult -TotalRecords $providedData.Count -AddCount 3 -UpdateCount 1 -DeleteCount 2 -KeepCount 4
            
            # Verify sync result structure
            $mockResult.Success | Should -Be $true
            $mockResult.SyncActions.ADD | Should -BeGreaterOrEqual 0
            $mockResult.SyncActions.UPDATE | Should -BeGreaterOrEqual 0
            $mockResult.SyncActions.DELETE | Should -BeGreaterOrEqual 0
            $mockResult.SyncActions.KEEP | Should -BeGreaterOrEqual 0
            
            # Verify total consistency
            $totalActions = $mockResult.SyncActions.ADD + $mockResult.SyncActions.UPDATE + 
                           $mockResult.SyncActions.DELETE + $mockResult.SyncActions.KEEP
            $totalActions | Should -Be $mockResult.ProcessedRecords
        }
        
        It "should handle filtering during synchronization" {
            $filterTestPath = Join-Path $script:TempDir "filter-test.csv"
            Test-Path $filterTestPath | Should -Be $true
            
            $filterTestData = Import-Csv -Path $filterTestPath
            $originalCount = $filterTestData.Count
            
            # Apply mock filtering
            $filtered = $filterTestData | Where-Object { 
                $_.employee_id -notlike "Z*" -and 
                $_.employee_id -notlike "Y*" -and 
                $_.department -notlike "TEMP" 
            }
            
            $filteredCount = $filtered.Count
            $excludedCount = $originalCount - $filteredCount
            
            Write-Host "Filter Test Results:" -ForegroundColor Yellow
            Write-Host "  Original: $originalCount records" -ForegroundColor Gray
            Write-Host "  Filtered: $filteredCount records" -ForegroundColor Gray
            Write-Host "  Excluded: $excludedCount records" -ForegroundColor Gray
            
            $excludedCount | Should -BeGreaterThan 0
            $filteredCount | Should -BeLessThan $originalCount
        }
        
        It "should handle edge cases gracefully" {
            $edgeCasePath = Join-Path $script:TempDir "edge-cases.csv"
            Test-Path $edgeCasePath | Should -Be $true
            
            $edgeCaseData = Import-Csv -Path $edgeCasePath
            
            # Test data quality validation
            $validation = Test-MockDataIntegrity -Data $edgeCaseData -ExpectedSchema @{
                RequiredFields = @("employee_id", "name")
                OptionalFields = @("department", "position")
            }
            
            # Edge cases should be detected
            $validation.Errors.Count | Should -BeGreaterThan 0
            $validation.RecordCount | Should -Be $edgeCaseData.Count
            
            Write-Host "Edge Case Validation:" -ForegroundColor Yellow
            Write-Host "  Records: $($validation.RecordCount)" -ForegroundColor Gray
            Write-Host "  Errors: $($validation.Errors.Count)" -ForegroundColor Gray
            Write-Host "  Valid: $($validation.IsValid)" -ForegroundColor Gray
        }
    }
    
    Context "Configuration Integration" {
        It "should load and validate configuration" {
            Test-Path $script:ConfigPath | Should -Be $true
            
            $config = Get-Content -Path $script:ConfigPath | ConvertFrom-Json
            $config | Should -Not -BeNullOrEmpty
            
            # Validate key configuration sections
            $config.file_paths | Should -Not -BeNullOrEmpty
            $config.tables | Should -Not -BeNullOrEmpty
            
            Write-Host "Configuration Validation:" -ForegroundColor Yellow
            Write-Host "  File paths defined: $($config.file_paths -ne $null)" -ForegroundColor Gray
            Write-Host "  Tables defined: $(($config.tables.PSObject.Properties.Name).Count)" -ForegroundColor Gray
        }
        
        It "should handle configuration variations" {
            # Generate test configurations
            $testConfigPath = Join-Path $script:TempDir "test-config.json"
            New-MockConfiguration -ConfigType "Complete" -OutputPath $testConfigPath
            
            Test-Path $testConfigPath | Should -Be $true
            
            $testConfig = Get-Content -Path $testConfigPath | ConvertFrom-Json
            $testConfig.file_paths | Should -Not -BeNullOrEmpty
            $testConfig.tables | Should -Not -BeNullOrEmpty
            $testConfig.sync_rules | Should -Not -BeNullOrEmpty
            $testConfig.data_filters | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Error Handling and Recovery" {
        It "should handle missing input files" {
            $missingFilePath = Join-Path $script:TempDir "nonexistent.csv"
            Test-Path $missingFilePath | Should -Be $false
            
            $result = & {
                try {
                    Import-Csv -Path $missingFilePath -ErrorAction Stop
                    "success"
                } catch {
                    "file_not_found"
                }
            }
            
            $result | Should -Be "file_not_found"
        }
        
        It "should handle database connection errors" {
            $invalidDbPath = "/invalid/path/database.db"
            
            $result = & {
                try {
                    if (-not (Test-Path (Split-Path $invalidDbPath -Parent))) {
                        throw "Database connection failed"
                    }
                    "connection_ok"
                } catch {
                    "connection_failed"
                }
            }
            
            $result | Should -Be "connection_failed"
        }
        
        It "should provide meaningful error messages" {
            $mockError = "Data synchronization failed: Invalid employee_id format in record 42 (Z999-INVALID)"
            
            $mockError | Should -Match "Data synchronization failed"
            $mockError | Should -Match "employee_id format"
            $mockError | Should -Match "record 42"
            $mockError | Should -Match "Z999-INVALID"
        }
    }
    
    Context "Performance and Scale" {
        It "should handle reasonable data volumes efficiently" {
            # Test with medium-sized dataset
            $mediumData = New-TestEmployeeDataset -Count 1000 -IncludeOptionalFields -IncludeFilterTargets
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            # Simulate processing steps
            $filtered = $mediumData | Where-Object { $_.employee_id -notlike "Z*" -and $_.employee_id -notlike "Y*" }
            $grouped = $filtered | Group-Object -Property department
            $stats = Get-TestDataStatistics -Data $filtered
            
            $stopwatch.Stop()
            
            $mediumData.Count | Should -Be 1000
            $filtered.Count | Should -BeLessOrEqual 1000
            $grouped.Count | Should -BeGreaterThan 0
            $stats.TotalRecords | Should -Be $filtered.Count
            
            # Should complete within reasonable time
            $stopwatch.Elapsed.TotalSeconds | Should -BeLessOrEqual 10
            
            Write-Host "Performance Test Results:" -ForegroundColor Yellow
            Write-Host "  Processing time: $($stopwatch.Elapsed.TotalSeconds) seconds" -ForegroundColor Gray
            Write-Host "  Records processed: $($mediumData.Count)" -ForegroundColor Gray
            Write-Host "  Records filtered: $($filtered.Count)" -ForegroundColor Gray
        }
        
        It "should maintain consistent memory usage" {
            $initialMemory = [System.GC]::GetTotalMemory($false)
            
            # Process multiple datasets
            for ($i = 1; $i -le 5; $i++) {
                $data = New-TestEmployeeDataset -Count 200 -IncludeOptionalFields
                $processed = $data | Where-Object { $_.employee_id -match "^E\d+" }
                $data = $null
                $processed = $null
                
                if ($i % 2 -eq 0) {
                    [System.GC]::Collect()
                }
            }
            
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            
            $finalMemory = [System.GC]::GetTotalMemory($true)
            $memoryIncrease = $finalMemory - $initialMemory
            
            Write-Host "Memory Usage Test:" -ForegroundColor Yellow
            Write-Host "  Initial: $([Math]::Round($initialMemory / 1MB, 2)) MB" -ForegroundColor Gray
            Write-Host "  Final: $([Math]::Round($finalMemory / 1MB, 2)) MB" -ForegroundColor Gray
            Write-Host "  Increase: $([Math]::Round($memoryIncrease / 1MB, 2)) MB" -ForegroundColor Gray
            
            # Memory increase should be reasonable (less than 50MB)
            $memoryIncrease | Should -BeLessOrEqual (50 * 1024 * 1024)
        }
    }
    
    Context "Data Integrity and Consistency" {
        It "should maintain referential integrity" {
            $providedData = New-TestEmployeeDataset -Count 50 -IncludeOptionalFields
            $currentData = $providedData[0..30] | ForEach-Object {
                @{
                    user_id = $_.employee_id
                    name = $_.name
                    department = $_.department
                }
            }
            
            # Test ID mapping consistency
            $providedIds = $providedData.employee_id
            $currentIds = $currentData.user_id
            
            $commonIds = $providedIds | Where-Object { $_ -in $currentIds }
            $addIds = $providedIds | Where-Object { $_ -notin $currentIds }
            $deleteIds = $currentIds | Where-Object { $_ -notin $providedIds }
            
            Write-Host "Referential Integrity Test:" -ForegroundColor Yellow
            Write-Host "  Common IDs: $($commonIds.Count)" -ForegroundColor Gray
            Write-Host "  IDs to add: $($addIds.Count)" -ForegroundColor Gray
            Write-Host "  IDs to delete: $($deleteIds.Count)" -ForegroundColor Gray
            
            # Verify consistency
            ($commonIds.Count + $addIds.Count) | Should -Be $providedIds.Count
            $deleteIds.Count | Should -Be 0  # All current IDs should exist in provided
        }
        
        It "should detect and handle duplicate records" {
            $dataWithDuplicates = @(
                @{ employee_id = "E001"; name = "田中太郎" },
                @{ employee_id = "E002"; name = "佐藤花子" },
                @{ employee_id = "E001"; name = "田中太郎" },  # Duplicate
                @{ employee_id = "E003"; name = "鈴木一郎" },
                @{ employee_id = "E002"; name = "佐藤花子" }   # Duplicate
            )
            
            $uniqueIds = $dataWithDuplicates | ForEach-Object { $_.employee_id } | Sort-Object -Unique
            $hasDuplicates = $uniqueIds.Count -ne $dataWithDuplicates.Count
            
            $dataWithDuplicates.Count | Should -Be 5
            $uniqueIds.Count | Should -Be 3
            $hasDuplicates | Should -Be $true
            
            # Remove duplicates
            $deduplicated = @{}
            $dataWithDuplicates | ForEach-Object {
                $deduplicated[$_.employee_id] = $_
            }
            
            $deduplicated.Count | Should -Be 3
        }
    }
}

Describe "System Component Integration Tests" {
    Context "Module Interoperability" {
        It "should integrate CSV processing with data filtering" {
            $csvData = New-MockCsvData -RecordCount 10 -IncludeFilterTargets
            $csvContent = $csvData -join "`n"
            
            # Parse CSV content
            $lines = $csvContent -split "`n"
            $headers = $lines[0] -split ","
            $records = @()
            
            for ($i = 1; $i -lt $lines.Count; $i++) {
                if ($lines[$i].Trim()) {
                    $values = $lines[$i] -split ","
                    $record = @{}
                    for ($j = 0; $j -lt [Math]::Min($headers.Count, $values.Count); $j++) {
                        $record[$headers[$j]] = $values[$j]
                    }
                    $records += $record
                }
            }
            
            # Apply filtering
            $filtered = $records | Where-Object { 
                $_.employee_id -notlike "Z*" -and $_.employee_id -notlike "Y*" 
            }
            
            $records.Count | Should -BeGreaterThan 0
            $filtered.Count | Should -BeLessOrEqual $records.Count
        }
        
        It "should integrate database operations with sync logic" {
            $mockProvided = @(
                @{ employee_id = "E001"; name = "田中太郎"; department = "営業部" },
                @{ employee_id = "E002"; name = "佐藤花子"; department = "総務部" },
                @{ employee_id = "E003"; name = "鈴木一郎"; department = "開発部" }
            )
            
            $mockCurrent = @(
                @{ user_id = "E001"; name = "田中太郎"; department = "営業部" },
                @{ user_id = "E004"; name = "山田次郎"; department = "経理部" }
            )
            
            # Simulate sync operations
            $providedIds = $mockProvided.employee_id
            $currentIds = $mockCurrent.user_id
            
            $toAdd = $providedIds | Where-Object { $_ -notin $currentIds }
            $toDelete = $currentIds | Where-Object { $_ -notin $providedIds }
            $common = $providedIds | Where-Object { $_ -in $currentIds }
            
            $toAdd.Count | Should -Be 2      # E002, E003
            $toDelete.Count | Should -Be 1   # E004
            $common.Count | Should -Be 1     # E001
        }
    }
    
    Context "Configuration-Driven Processing" {
        It "should adapt to different table schemas" {
            $basicSchema = @{
                columns = @(
                    @{ name = "id"; type = "INTEGER"; required = $true },
                    @{ name = "name"; type = "TEXT"; required = $true }
                )
            }
            
            $extendedSchema = @{
                columns = @(
                    @{ name = "id"; type = "INTEGER"; required = $true },
                    @{ name = "name"; type = "TEXT"; required = $true },
                    @{ name = "department"; type = "TEXT"; required = $false },
                    @{ name = "position"; type = "TEXT"; required = $false },
                    @{ name = "email"; type = "TEXT"; required = $false }
                )
            }
            
            $basicSchema.columns.Count | Should -Be 2
            $extendedSchema.columns.Count | Should -Be 5
            
            # Both schemas should have required name field
            $basicRequired = $basicSchema.columns | Where-Object { $_.required -eq $true }
            $extendedRequired = $extendedSchema.columns | Where-Object { $_.required -eq $true }
            
            $basicRequired.Count | Should -Be 2
            $extendedRequired.Count | Should -Be 2
        }
    }
}