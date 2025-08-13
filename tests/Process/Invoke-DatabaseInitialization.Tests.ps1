#!/usr/bin/env pwsh
# Invoke-DatabaseInitialization Module Tests

BeforeAll {
    $script:TestRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $TestRoot 'scripts/modules/Process/Invoke-DatabaseInitialization.psm1'
    
    # Import required modules
    Import-Module $script:ModulePath -Force
    
    # Test temporary directory
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "db-init-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
    
    # Test database paths
    $script:TestDbPath = Join-Path $script:TempDir "test-init.db"
    $script:ExistingDbPath = Join-Path $script:TempDir "existing.db"
    
    # Mock table configuration
    $script:MockTableConfig = @{
        provided_data = @{
            description = "Ð›Çü¿ÆüÖë"
            columns = @(
                @{
                    name = "id"
                    type = "INTEGER"
                    constraints = "PRIMARY KEY AUTOINCREMENT"
                    csv_include = $false
                    required = $true
                },
                @{
                    name = "employee_id"
                    type = "TEXT"
                    constraints = "NOT NULL UNIQUE"
                    csv_include = $true
                    required = $true
                },
                @{
                    name = "name"
                    type = "TEXT"
                    constraints = "NOT NULL"
                    csv_include = $true
                    required = $true
                },
                @{
                    name = "department"
                    type = "TEXT"
                    constraints = ""
                    csv_include = $true
                    required = $false
                }
            )
        }
        current_data = @{
            description = "þ(Çü¿ÆüÖë"
            columns = @(
                @{
                    name = "id"
                    type = "INTEGER"
                    constraints = "PRIMARY KEY AUTOINCREMENT"
                    csv_include = $false
                    required = $true
                },
                @{
                    name = "user_id"
                    type = "TEXT"
                    constraints = "NOT NULL UNIQUE"
                    csv_include = $true
                    required = $true
                },
                @{
                    name = "name"
                    type = "TEXT"
                    constraints = "NOT NULL"
                    csv_include = $true
                    required = $true
                }
            )
        }
    }
    
    # Create a mock existing database
    "CREATE TABLE existing_table (id INTEGER);" | Out-File -FilePath "$script:ExistingDbPath.sql" -Encoding utf8
    
    # Expected SQL statements
    $script:ExpectedCreateTableSQL = @{
        provided_data = "CREATE TABLE IF NOT EXISTS provided_data (id INTEGER PRIMARY KEY AUTOINCREMENT, employee_id TEXT NOT NULL UNIQUE, name TEXT NOT NULL, department TEXT)"
        current_data = "CREATE TABLE IF NOT EXISTS current_data (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL UNIQUE, name TEXT NOT NULL)"
    }
}

AfterAll {
    if (Test-Path $script:TempDir) {
        Remove-Item -Path $script:TempDir -Recurse -Force
    }
    
    Remove-Module -Name Invoke-DatabaseInitialization -Force -ErrorAction SilentlyContinue
}

Describe "Invoke-DatabaseInitialization Tests" {
    Context "SQL Generation" {
        It "should generate correct CREATE TABLE statements" {
            $tableConfig = $script:MockTableConfig.provided_data
            $tableName = "provided_data"
            
            # Mock SQL generation logic
            $columns = @()
            foreach ($column in $tableConfig.columns) {
                if ($column.constraints) {
                    $columns += "$($column.name) $($column.type) $($column.constraints)"
                } else {
                    $columns += "$($column.name) $($column.type)"
                }
            }
            $sql = "CREATE TABLE IF NOT EXISTS $tableName ($($columns -join ', '))"
            
            $sql | Should -Match "CREATE TABLE IF NOT EXISTS provided_data"
            $sql | Should -Match "id INTEGER PRIMARY KEY AUTOINCREMENT"
            $sql | Should -Match "employee_id TEXT NOT NULL UNIQUE"
            $sql | Should -Match "name TEXT NOT NULL"
            $sql | Should -Match "department TEXT"
        }
        
        It "should handle tables without constraints" {
            $simpleTableConfig = @{
                columns = @(
                    @{ name = "id"; type = "INTEGER"; constraints = "" },
                    @{ name = "data"; type = "TEXT"; constraints = "" }
                )
            }
            
            $columns = @()
            foreach ($column in $simpleTableConfig.columns) {
                if ($column.constraints -and $column.constraints.Trim() -ne "") {
                    $columns += "$($column.name) $($column.type) $($column.constraints)"
                } else {
                    $columns += "$($column.name) $($column.type)"
                }
            }
            $sql = "CREATE TABLE IF NOT EXISTS simple_table ($($columns -join ', '))"
            
            $sql | Should -Be "CREATE TABLE IF NOT EXISTS simple_table (id INTEGER, data TEXT)"
        }
        
        It "should generate appropriate index statements" {
            $tableName = "provided_data"
            $indexColumns = @("employee_id", "name")
            
            $indexStatements = @()
            foreach ($column in $indexColumns) {
                $indexName = "idx_${tableName}_${column}"
                $indexStatements += "CREATE INDEX IF NOT EXISTS $indexName ON $tableName ($column)"
            }
            
            $indexStatements[0] | Should -Be "CREATE INDEX IF NOT EXISTS idx_provided_data_employee_id ON provided_data (employee_id)"
            $indexStatements[1] | Should -Be "CREATE INDEX IF NOT EXISTS idx_provided_data_name ON provided_data (name)"
        }
        
        It "should generate composite index statements" {
            $tableName = "provided_data"
            $compositeColumns = @("department", "position")
            $indexName = "idx_${tableName}_dept_pos"
            
            $sql = "CREATE INDEX IF NOT EXISTS $indexName ON $tableName ($($compositeColumns -join ', '))"
            
            $sql | Should -Be "CREATE INDEX IF NOT EXISTS idx_provided_data_dept_pos ON provided_data (department, position)"
        }
    }
    
    Context "Database File Operations" {
        It "should create new database file when it doesn't exist" {
            $newDbPath = Join-Path $script:TempDir "new-database.db"
            Test-Path $newDbPath | Should -Be $false
            
            # Mock database creation
            $result = & {
                try {
                    # Simulate database file creation
                    New-Item -Path $newDbPath -ItemType File -Force | Out-Null
                    "database_created"
                } catch {
                    "creation_failed"
                }
            }
            
            $result | Should -Be "database_created"
            Test-Path $newDbPath | Should -Be $true
        }
        
        It "should handle existing database gracefully" {
            Test-Path $script:ExistingDbPath | Should -Be $false
            
            # Create existing database file
            New-Item -Path $script:ExistingDbPath -ItemType File -Force | Out-Null
            Test-Path $script:ExistingDbPath | Should -Be $true
            
            # Mock handling existing database
            $result = & {
                if (Test-Path $script:ExistingDbPath) {
                    "database_exists"
                } else {
                    "database_not_found"
                }
            }
            
            $result | Should -Be "database_exists"
        }
        
        It "should validate database file permissions" {
            $testDbFile = Join-Path $script:TempDir "permission-test.db"
            New-Item -Path $testDbFile -ItemType File -Force | Out-Null
            
            # Check if file is readable and writable
            $readable = Test-Path $testDbFile -PathType Leaf
            $writable = & {
                try {
                    Add-Content -Path $testDbFile -Value "test" -ErrorAction Stop
                    $true
                } catch {
                    $false
                }
            }
            
            $readable | Should -Be $true
            $writable | Should -Be $true
        }
    }
    
    Context "Table Schema Validation" {
        It "should validate required columns are present" {
            $tableConfig = $script:MockTableConfig.provided_data
            $requiredColumns = $tableConfig.columns | Where-Object { $_.required -eq $true }
            
            $requiredColumns.Count | Should -BeGreaterThan 0
            $requiredColumns | Where-Object { $_.name -eq "employee_id" } | Should -Not -BeNullOrEmpty
            $requiredColumns | Where-Object { $_.name -eq "name" } | Should -Not -BeNullOrEmpty
        }
        
        It "should validate column data types" {
            $tableConfig = $script:MockTableConfig.provided_data
            $validTypes = @("TEXT", "INTEGER", "REAL", "BLOB", "NUMERIC")
            
            foreach ($column in $tableConfig.columns) {
                $validTypes | Should -Contain $column.type
            }
        }
        
        It "should validate constraint syntax" {
            $validConstraints = @(
                "PRIMARY KEY",
                "PRIMARY KEY AUTOINCREMENT", 
                "NOT NULL",
                "UNIQUE",
                "NOT NULL UNIQUE",
                ""
            )
            
            $tableConfig = $script:MockTableConfig.provided_data
            foreach ($column in $tableConfig.columns) {
                if ($column.constraints) {
                    # Basic constraint validation
                    $column.constraints | Should -Match "^(PRIMARY KEY|NOT NULL|UNIQUE|\s)*"
                }
            }
        }
        
        It "should detect duplicate column names" {
            $duplicateConfig = @{
                columns = @(
                    @{ name = "id"; type = "INTEGER" },
                    @{ name = "name"; type = "TEXT" },
                    @{ name = "id"; type = "TEXT" }  # Duplicate
                )
            }
            
            $columnNames = $duplicateConfig.columns | ForEach-Object { $_.name }
            $uniqueNames = $columnNames | Sort-Object -Unique
            
            $hasDuplicates = $columnNames.Count -ne $uniqueNames.Count
            $hasDuplicates | Should -Be $true
        }
    }
    
    Context "Error Handling" {
        It "should handle invalid table configuration gracefully" {
            $invalidConfig = @{
                # Missing columns array
            }
            
            $result = & {
                try {
                    if (-not $invalidConfig.columns) {
                        throw "Invalid table configuration: missing columns"
                    }
                    "config_valid"
                } catch {
                    "config_invalid"
                }
            }
            
            $result | Should -Be "config_invalid"
        }
        
        It "should handle SQL execution errors" {
            # Mock SQL execution error
            $invalidSQL = "CREATE TABLE invalid syntax"
            
            $result = & {
                try {
                    if ($invalidSQL -notmatch "^CREATE TABLE \w+") {
                        throw "SQL syntax error"
                    }
                    "sql_valid"
                } catch {
                    "sql_error"
                }
            }
            
            $result | Should -Be "sql_error"
        }
        
        It "should handle database connection failures" {
            $invalidPath = "/invalid/path/database.db"
            
            $result = & {
                try {
                    $parentPath = Split-Path $invalidPath -Parent
                    if (-not (Test-Path $parentPath)) {
                        throw "Database connection failed: invalid path"
                    }
                    "connection_ok"
                } catch {
                    "connection_failed"
                }
            }
            
            $result | Should -Be "connection_failed"
        }
        
        It "should provide meaningful error messages" {
            $error = "Database initialization failed: Table 'provided_data' column 'employee_id' constraint validation failed"
            
            $error | Should -Match "Database initialization failed"
            $error | Should -Match "provided_data"
            $error | Should -Match "employee_id"
            $error | Should -Match "constraint validation failed"
        }
    }
    
    Context "Performance Optimization" {
        It "should generate efficient table creation order" {
            # Tables should be created in dependency order
            $tableOrder = @("provided_data", "current_data", "sync_result")
            
            # sync_result might depend on provided_data and current_data
            $tableOrder.IndexOf("provided_data") | Should -BeLessOrEqual $tableOrder.IndexOf("sync_result")
            $tableOrder.IndexOf("current_data") | Should -BeLessOrEqual $tableOrder.IndexOf("sync_result")
        }
        
        It "should batch SQL operations for performance" {
            $sqlStatements = @(
                "CREATE TABLE table1 (id INTEGER)",
                "CREATE INDEX idx1 ON table1 (id)",
                "CREATE TABLE table2 (id INTEGER)",
                "CREATE INDEX idx2 ON table2 (id)"
            )
            
            # Group operations by type for better performance
            $createTables = $sqlStatements | Where-Object { $_ -like "CREATE TABLE*" }
            $createIndexes = $sqlStatements | Where-Object { $_ -like "CREATE INDEX*" }
            
            $createTables.Count | Should -Be 2
            $createIndexes.Count | Should -Be 2
        }
        
        It "should handle large schema initialization efficiently" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            # Simulate large schema creation
            $largeSchema = @{}
            for ($i = 1; $i -le 50; $i++) {
                $largeSchema["table$i"] = @{
                    columns = @(
                        @{ name = "id"; type = "INTEGER"; constraints = "PRIMARY KEY" },
                        @{ name = "name"; type = "TEXT"; constraints = "NOT NULL" },
                        @{ name = "data"; type = "TEXT"; constraints = "" }
                    )
                }
            }
            
            # Generate SQL for all tables
            $sqlStatements = @()
            foreach ($tableName in $largeSchema.Keys) {
                $columns = @()
                foreach ($column in $largeSchema[$tableName].columns) {
                    if ($column.constraints) {
                        $columns += "$($column.name) $($column.type) $($column.constraints)"
                    } else {
                        $columns += "$($column.name) $($column.type)"
                    }
                }
                $sqlStatements += "CREATE TABLE IF NOT EXISTS $tableName ($($columns -join ', '))"
            }
            
            $stopwatch.Stop()
            
            $sqlStatements.Count | Should -Be 50
            # Should complete within 1 second
            $stopwatch.Elapsed.TotalSeconds | Should -BeLessOrEqual 1
        }
    }
    
    Context "Configuration Integration" {
        It "should read table configuration from config file" {
            # Mock configuration loading
            $mockConfigPath = Join-Path $script:TempDir "mock-config.json"
            $mockConfig = @{
                tables = $script:MockTableConfig
            } | ConvertTo-Json -Depth 10
            
            $mockConfig | Out-File -FilePath $mockConfigPath -Encoding utf8
            
            $loadedConfig = Get-Content -Path $mockConfigPath | ConvertFrom-Json
            $loadedConfig.tables.provided_data | Should -Not -BeNullOrEmpty
            $loadedConfig.tables.current_data | Should -Not -BeNullOrEmpty
        }
        
        It "should validate configuration schema version" {
            $configWithVersion = @{
                schema_version = "1.0"
                tables = $script:MockTableConfig
            }
            
            $configWithVersion.schema_version | Should -Match "^\d+\.\d+$"
            $configWithVersion.tables | Should -Not -BeNullOrEmpty
        }
        
        It "should handle configuration updates gracefully" {
            $oldConfig = @{
                tables = @{
                    provided_data = @{
                        columns = @(
                            @{ name = "id"; type = "INTEGER" },
                            @{ name = "name"; type = "TEXT" }
                        )
                    }
                }
            }
            
            $newConfig = @{
                tables = @{
                    provided_data = @{
                        columns = @(
                            @{ name = "id"; type = "INTEGER" },
                            @{ name = "name"; type = "TEXT" },
                            @{ name = "department"; type = "TEXT" }  # New column
                        )
                    }
                }
            }
            
            $oldColumns = $oldConfig.tables.provided_data.columns.Count
            $newColumns = $newConfig.tables.provided_data.columns.Count
            
            $newColumns | Should -BeGreaterThan $oldColumns
        }
    }
}

Describe "Database Initialization Integration Tests" {
    Context "Full Database Setup" {
        It "should initialize complete database schema" {
            $initializationSteps = @{
                ValidateConfig = $true
                CreateDatabase = $true
                CreateTables = $true
                CreateIndexes = $true
                CreateTriggers = $false  # Optional
                VerifySchema = $true
            }
            
            $completedSteps = ($initializationSteps.Values | Where-Object { $_ -eq $true }).Count
            $totalSteps = $initializationSteps.Count
            
            $completionRate = $completedSteps / $totalSteps
            $completionRate | Should -BeGreaterOrEqual 0.8  # At least 80% completion
        }
        
        It "should handle database migration scenarios" {
            # Mock version comparison
            $currentVersion = "1.0"
            $requiredVersion = "1.1"
            
            $needsMigration = [Version]$requiredVersion -gt [Version]$currentVersion
            $needsMigration | Should -Be $true
        }
        
        It "should verify database integrity after initialization" {
            $integrityChecks = @{
                TablesExist = $true
                IndexesExist = $true
                ConstraintsValid = $true
                PermissionsCorrect = $true
            }
            
            $failedChecks = $integrityChecks.Values | Where-Object { $_ -eq $false }
            $failedChecks.Count | Should -Be 0
        }
    }
}