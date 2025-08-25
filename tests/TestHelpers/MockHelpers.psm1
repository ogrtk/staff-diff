# PowerShell & SQLite データ同期システム
# モック機能テストヘルパーモジュール

# グローバルモック状態管理
$script:MockedCommands = @{}
$script:MockCallHistory = @{}

# コマンドのモック化
function New-MockCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        
        [scriptblock]$MockScript = { Write-Host "Mocked: $CommandName" },
        
        [object]$ReturnValue = $null,
        
        [switch]$PassThru
    )
    
    # 元のコマンドの保存
    if (-not $script:MockedCommands.ContainsKey($CommandName)) {
        $originalCommand = Get-Command $CommandName -ErrorAction SilentlyContinue
        $script:MockedCommands[$CommandName] = $originalCommand
        $script:MockCallHistory[$CommandName] = @()
    }
    
    # Pesterのネイティブモック機能を使用
    if (Get-Command "Mock" -ErrorAction SilentlyContinue) {
        if ($null -ne $ReturnValue) {
            Mock $CommandName { return $ReturnValue }
        }
        else {
            Mock $CommandName $MockScript
        }
    }
    else {
        # Pesterが利用できない場合のフォールバック
        throw "Mock機能が利用できません。Pesterが正しくインストールされているか確認してください。"
    }
    
    Write-Verbose "コマンドをモック化しました: $CommandName"
    
    if ($PassThru) {
        return $CommandName
    }
}

# SQLiteコマンドのモック化
function New-MockSqliteCommand {
    param(
        [string]$ReturnValue = "",
        [int]$ExitCode = 0,
        [switch]$ThrowError
    )
    
    if ($ThrowError) {
        New-MockCommand -CommandName "sqlite3" -MockScript {
            $global:LASTEXITCODE = 1
            throw "モック化されたSQLiteエラー"
        }
    }
    else {
        New-MockCommand -CommandName "sqlite3" -MockScript {
            $global:LASTEXITCODE = $ExitCode
            return $ReturnValue
        }
    }
}

# ファイルシステム操作のモック化
function New-MockFileSystemOperations {
    param(
        [hashtable]$FileExists = @{},
        [hashtable]$FileContent = @{},
        [bool]$AllowWrite = $true
    )
    
    # Test-Pathのモック
    New-MockCommand -CommandName "Test-Path" -MockScript {
        param($Path)
        
        if ($FileExists.ContainsKey($Path)) {
            return $FileExists[$Path]
        }
        
        return $false
    }
    
    # Get-Contentのモック
    New-MockCommand -CommandName "Get-Content" -MockScript {
        param($Path, $Raw, $Encoding)
        
        if ($FileContent.ContainsKey($Path)) {
            $content = $FileContent[$Path]
            if ($Raw) {
                return $content
            }
            else {
                return $content -split "`n"
            }
        }
        
        throw "モックファイルが見つかりません: $Path"
    }
    
    # Out-Fileのモック
    if ($AllowWrite) {
        New-MockCommand -CommandName "Out-File" -MockScript {
            Write-Verbose "モックファイル出力実行"
        }
    }
}

# ログ機能のモック化
function New-MockLoggingSystem {
    param(
        [switch]$CaptureMessages,
        [switch]$SuppressOutput
    )
    
    if ($CaptureMessages) {
        $script:CapturedLogMessages = @()
    }
    
    if (Get-Command "Mock" -ErrorAction SilentlyContinue) {
        Mock Write-SystemLog {
            param($Message, $Level = "Info")
            
            if ($CaptureMessages) {
                $script:CapturedLogMessages += @{
                    Message   = $Message
                    Level     = $Level
                    Timestamp = Get-Date
                }
            }
            
            if (-not $SuppressOutput) {
                Write-Host "[$Level] $Message" -ForegroundColor Green
            }
        }
    }
}

# エラーハンドリングのモック化
function New-MockErrorHandling {
    param(
        [hashtable]$ErrorConfig = @{},
        [switch]$BypassErrorHandling
    )
    
    if (Get-Command "Mock" -ErrorAction SilentlyContinue) {
        if ($BypassErrorHandling) {
            Mock Invoke-WithErrorHandling {
                param($ScriptBlock, $Category, $Operation, $Context, $CleanupScript)
                
                # エラーハンドリングをバイパスして直接実行
                & $ScriptBlock
            }
            return
        }
        
        # Get-ErrorHandlingConfigのモック - 最初に実行される
        Mock Get-ErrorHandlingConfig { return $ErrorConfig } -ModuleName ErrorHandlingUtils
        
        # Get-ErrorLevelのモック
        Mock Get-ErrorLevel {
            param($Category, $ErrorConfig)
            
            if ($ErrorConfig.ContainsKey("error_levels") -and $ErrorConfig.error_levels.ContainsKey($Category)) {
                return $ErrorConfig.error_levels[$Category]
            }
            
            # デフォルト値
            switch ($Category) {
                "System" { return "Error" }
                "Data" { return "Warning" }
                "External" { return "Error" }
                default { return "Error" }
            }
        } -ModuleName ErrorHandlingUtils
        
        # Get-ShouldContinueOnErrorのモック
        Mock Get-ShouldContinueOnError {
            param($Category, $ErrorConfig)
            
            if ($ErrorConfig.ContainsKey("continue_on_error") -and $ErrorConfig.continue_on_error.ContainsKey($Category)) {
                return $ErrorConfig.continue_on_error[$Category]
            }
            
            # デフォルト値
            switch ($Category) {
                "Data" { return $true }
                default { return $false }
            }
        } -ModuleName ErrorHandlingUtils
        
        # Write-ErrorDetailsのモック
        Mock Write-ErrorDetails {
            param($Exception, $Category, $Operation, $Context, $ErrorConfig)
            # ログメッセージをキャプチャ
            if ($null -ne $script:CapturedLogMessages) {
                $script:CapturedLogMessages += @{
                    Message   = $Exception.Message
                    Level     = "Error"
                    Category  = $Category
                    Operation = $Operation
                    Timestamp = Get-Date
                }
            }
        } -ModuleName ErrorHandlingUtils
    }
}

# キャプチャされたログメッセージの取得
function Get-CapturedLogMessages {
    param(
        [string]$Level = ""
    )
    
    if (-not (Get-Variable -Name "CapturedLogMessages" -Scope Script -ErrorAction SilentlyContinue)) {
        return @()
    }
    
    $messages = $script:CapturedLogMessages
    
    if (-not [string]::IsNullOrEmpty($Level)) {
        $messages = $messages | Where-Object { $_.Level -eq $Level }
    }
    
    return $messages
}


Export-ModuleMember -Function @(
    'New-MockCommand',
    'New-MockSqliteCommand', 
    'New-MockFileSystemOperations',
    'New-MockLoggingSystem',
    'New-MockErrorHandling',
    'Mock-ConfigurationSystem',
    'Get-CapturedLogMessages'
) 
