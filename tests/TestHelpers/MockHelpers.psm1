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
        [switch]$AllowWrite = $true
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
        [switch]$BypassErrorHandling
    )
    
    if ($BypassErrorHandling -and (Get-Command "Mock" -ErrorAction SilentlyContinue)) {
        Mock Invoke-WithErrorHandling {
            param($ScriptBlock, $Category, $Operation, $Context, $CleanupScript)
            
            # エラーハンドリングをバイパスして直接実行
            & $ScriptBlock
        }
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
    'Get-CapturedLogMessages'
)