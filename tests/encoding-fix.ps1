# PowerShell & SQLite データ同期システム
# エンコーディング修正スクリプト

param(
    [string]$TargetPath = "",
    [ValidateSet("UTF8", "UTF8BOM", "ASCII", "Unicode", "UTF32")]
    [string]$TargetEncoding = "UTF8",
    [ValidateSet("Auto", "UTF8", "UTF8BOM", "ASCII", "Unicode", "UTF32", "SHIFT_JIS")]
    [string]$SourceEncoding = "Auto",
    [switch]$Recursive,
    [string[]]$FileExtensions = @("*.ps1", "*.psm1", "*.csv", "*.json", "*.txt", "*.md"),
    [switch]$Backup,
    [switch]$DryRun,
    [switch]$Force
)

# スクリプトの場所を基準にプロジェクトルートを設定
$ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.FullName

# 対象パスの設定
if ([string]::IsNullOrEmpty($TargetPath)) {
    $TargetPath = $ProjectRoot
}

# エンコーディング変換マップ
$EncodingMap = @{
    "UTF8"      = [System.Text.UTF8Encoding]::new($false)  # BOM無し
    "UTF8BOM"   = [System.Text.UTF8Encoding]::new($true)  # BOM有り
    "ASCII"     = [System.Text.ASCIIEncoding]::new()
    "Unicode"   = [System.Text.UnicodeEncoding]::new()
    "UTF32"     = [System.Text.UTF32Encoding]::new()
    "SHIFT_JIS" = [System.Text.Encoding]::GetEncoding("Shift_JIS")
}

# ファイルエンコーディングの検出
function Get-FileEncoding {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    try {
        # ファイルサイズが0の場合
        $fileInfo = Get-Item $FilePath
        if ($fileInfo.Length -eq 0) {
            return @{
                Encoding   = "Empty"
                HasBOM     = $false
                Confidence = 100
            }
        }
        
        # バイナリデータの読み込み（最初の1024バイトまたはファイル全体）
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        $maxBytesToCheck = [Math]::Min(1024, $bytes.Length)
        $sampleBytes = $bytes[0..($maxBytesToCheck - 1)]
        
        # BOM検出
        $bomInfo = Find-BOM -Bytes $bytes
        if ($bomInfo.HasBOM) {
            return $bomInfo
        }
        
        # BOMがない場合のエンコーディング推定
        $encodingGuess = Get-EstimatedEncoding -Bytes $sampleBytes
        
        return $encodingGuess
    }
    catch {
        Write-Warning "ファイル '$FilePath' のエンコーディング検出に失敗しました: $($_.Exception.Message)"
        return @{
            Encoding   = "Unknown"
            HasBOM     = $false
            Confidence = 0
        }
    }
}

# BOM検出
function Find-BOM {
    param(
        [byte[]]$Bytes
    )
    
    if ($Bytes.Length -lt 2) {
        return @{ Encoding = "Unknown"; HasBOM = $false; Confidence = 0 }
    }
    
    # UTF-8 BOM: EF BB BF
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return @{ Encoding = "UTF8BOM"; HasBOM = $true; Confidence = 100 }
    }
    
    # UTF-16 LE BOM: FF FE
    if ($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return @{ Encoding = "Unicode"; HasBOM = $true; Confidence = 100 }
    }
    
    # UTF-16 BE BOM: FE FF
    if ($Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return @{ Encoding = "UnicodeBE"; HasBOM = $true; Confidence = 100 }
    }
    
    # UTF-32 LE BOM: FF FE 00 00
    if ($Bytes.Length -ge 4 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE -and $Bytes[2] -eq 0x00 -and $Bytes[3] -eq 0x00) {
        return @{ Encoding = "UTF32"; HasBOM = $true; Confidence = 100 }
    }
    
    return @{ Encoding = "Unknown"; HasBOM = $false; Confidence = 0 }
}

# コンテンツからのエンコーディング推定
function Get-EstimatedEncoding {
    param(
        [byte[]]$Bytes
    )
    
    $utf8Score = 0
    $asciiScore = 0
    $shiftJisScore = 0
    
    # ASCII チェック
    $asciiValid = $true
    foreach ($byte in $Bytes) {
        if ($byte -gt 127) {
            $asciiValid = $false
            break
        }
    }
    
    if ($asciiValid) {
        $asciiScore = 100
    }
    
    # UTF-8 チェック
    try {
        $utf8Text = [System.Text.Encoding]::UTF8.GetString($Bytes)
        $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($utf8Text)
        
        if ($Bytes.Length -eq $utf8Bytes.Length) {
            $matchCount = 0
            for ($i = 0; $i -lt $Bytes.Length; $i++) {
                if ($Bytes[$i] -eq $utf8Bytes[$i]) {
                    $matchCount++
                }
            }
            $utf8Score = [Math]::Round(($matchCount / $Bytes.Length) * 100, 2)
        }
    }
    catch {
        $utf8Score = 0
    }
    
    # Shift_JIS チェック（日本語環境の場合）
    try {
        $shiftJisEncoding = [System.Text.Encoding]::GetEncoding("Shift_JIS")
        $shiftJisText = $shiftJisEncoding.GetString($Bytes)
        $shiftJisBytes = $shiftJisEncoding.GetBytes($shiftJisText)
        
        if ($Bytes.Length -eq $shiftJisBytes.Length) {
            $matchCount = 0
            for ($i = 0; $i -lt $Bytes.Length; $i++) {
                if ($Bytes[$i] -eq $shiftJisBytes[$i]) {
                    $matchCount++
                }
            }
            $shiftJisScore = [Math]::Round(($matchCount / $Bytes.Length) * 100, 2)
        }
    }
    catch {
        $shiftJisScore = 0
    }
    
    # 最も高いスコアのエンコーディングを選択
    $bestEncoding = "Unknown"
    $bestScore = 0
    
    if ($asciiScore -gt $bestScore) {
        $bestEncoding = "ASCII"
        $bestScore = $asciiScore
    }
    
    if ($utf8Score -gt $bestScore) {
        $bestEncoding = "UTF8"
        $bestScore = $utf8Score
    }
    
    if ($shiftJisScore -gt $bestScore) {
        $bestEncoding = "SHIFT_JIS"
        $bestScore = $shiftJisScore
    }
    
    return @{
        Encoding   = $bestEncoding
        HasBOM     = $false
        Confidence = $bestScore
    }
}

# ファイルのエンコーディング変換
function Convert-FileEncoding {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetEncoding,
        
        [string]$SourceEncoding = "Auto",
        
        [switch]$Backup,
        [switch]$DryRun
    )
    
    try {
        # 現在のエンコーディングを検出
        if ($SourceEncoding -eq "Auto") {
            $currentEncoding = Get-FileEncoding -FilePath $FilePath
            $sourceEncodingName = $currentEncoding.Encoding
        }
        else {
            $sourceEncodingName = $SourceEncoding
        }
        
        # 既に目的のエンコーディングの場合はスキップ
        if ($sourceEncodingName -eq $TargetEncoding) {
            Write-Host "  → スキップ (既に $TargetEncoding)" -ForegroundColor Gray
            return @{
                Success        = $true
                Action         = "Skipped"
                SourceEncoding = $sourceEncodingName
                TargetEncoding = $TargetEncoding
            }
        }
        
        # DryRun モードの場合
        if ($DryRun) {
            Write-Host "  → 変換予定: $sourceEncodingName → $TargetEncoding" -ForegroundColor Yellow
            return @{
                Success        = $true
                Action         = "DryRun"
                SourceEncoding = $sourceEncodingName
                TargetEncoding = $TargetEncoding
            }
        }
        
        # バックアップの作成
        if ($Backup) {
            $backupPath = "$FilePath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Copy-Item $FilePath $backupPath
            Write-Host "  → バックアップ作成: $(Split-Path $backupPath -Leaf)" -ForegroundColor Cyan
        }
        
        # ソースエンコーディングの取得
        $sourceEnc = if ($EncodingMap.ContainsKey($sourceEncodingName)) {
            $EncodingMap[$sourceEncodingName]
        }
        else {
            [System.Text.Encoding]::Default
        }
        
        # ターゲットエンコーディングの取得
        $targetEnc = $EncodingMap[$TargetEncoding]
        
        # ファイル内容の読み込みと変換
        $content = [System.IO.File]::ReadAllText($FilePath, $sourceEnc)
        [System.IO.File]::WriteAllText($FilePath, $content, $targetEnc)
        
        Write-Host "  → 変換完了: $sourceEncodingName → $TargetEncoding" -ForegroundColor Green
        
        return @{
            Success        = $true
            Action         = "Converted"
            SourceEncoding = $sourceEncodingName
            TargetEncoding = $TargetEncoding
        }
    }
    catch {
        Write-Host "  → エラー: $($_.Exception.Message)" -ForegroundColor Red
        return @{
            Success        = $false
            Action         = "Error"
            Error          = $_.Exception.Message
            SourceEncoding = $sourceEncodingName
            TargetEncoding = $TargetEncoding
        }
    }
}

# ファイル検索
function Get-TargetFiles {
    param(
        [string]$Path,
        [string[]]$Extensions,
        [switch]$Recursive
    )
    
    $files = @()
    
    foreach ($extension in $Extensions) {
        if ($Recursive) {
            $foundFiles = Get-ChildItem -Path $Path -Filter $extension -Recurse -File -ErrorAction SilentlyContinue
        }
        else {
            $foundFiles = Get-ChildItem -Path $Path -Filter $extension -File -ErrorAction SilentlyContinue
        }
        $files += $foundFiles
    }
    
    return $files | Sort-Object FullName | Get-Unique -AsString
}

# メイン処理
function Invoke-EncodingFix {
    Write-Host "=== エンコーディング修正スクリプト ===" -ForegroundColor Cyan
    Write-Host "対象パス: $TargetPath" -ForegroundColor Gray
    Write-Host "ターゲットエンコーディング: $TargetEncoding" -ForegroundColor Gray
    Write-Host "ソースエンコーディング: $SourceEncoding" -ForegroundColor Gray
    Write-Host "再帰検索: $Recursive" -ForegroundColor Gray
    Write-Host "対象拡張子: $($FileExtensions -join ', ')" -ForegroundColor Gray
    Write-Host "DryRunモード: $DryRun" -ForegroundColor Gray
    Write-Host ""
    
    # 対象パスの存在確認
    if (-not (Test-Path $TargetPath)) {
        Write-Error "対象パスが見つかりません: $TargetPath"
        exit 1
    }
    
    # 対象ファイルの検索
    Write-Host "対象ファイルを検索中..." -ForegroundColor Yellow
    $targetFiles = Get-TargetFiles -Path $TargetPath -Extensions $FileExtensions -Recursive:$Recursive
    
    if ($targetFiles.Count -eq 0) {
        Write-Host "対象ファイルが見つかりませんでした。" -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "見つかったファイル: $($targetFiles.Count) 件" -ForegroundColor Green
    Write-Host ""
    
    # 確認プロンプト
    if (-not $Force -and -not $DryRun) {
        Write-Host "以下のファイルのエンコーディングを変換します:" -ForegroundColor Yellow
        foreach ($file in $targetFiles | Select-Object -First 10) {
            Write-Host "  $($file.FullName)" -ForegroundColor Gray
        }
        if ($targetFiles.Count -gt 10) {
            Write-Host "  ... 他 $($targetFiles.Count - 10) 件" -ForegroundColor Gray
        }
        Write-Host ""
        
        $response = Read-Host "続行しますか？ (y/N)"
        if ($response -notmatch "^[yY]") {
            Write-Host "処理を中止しました。" -ForegroundColor Yellow
            exit 0
        }
    }
    
    # ファイル変換処理
    Write-Host "エンコーディング変換を開始..." -ForegroundColor Green
    Write-Host ""
    
    $results = @{
        Total     = $targetFiles.Count
        Converted = 0
        Skipped   = 0
        Errors    = 0
        DryRun    = 0
    }
    
    foreach ($file in $targetFiles) {
        $relativePath = $file.FullName.Replace($TargetPath, "").TrimStart("\", "/")
        Write-Host "$relativePath" -ForegroundColor White
        
        $result = Convert-FileEncoding -FilePath $file.FullName -TargetEncoding $TargetEncoding -SourceEncoding $SourceEncoding -Backup:$Backup -DryRun:$DryRun
        
        switch ($result.Action) {
            "Converted" { $results.Converted++ }
            "Skipped" { $results.Skipped++ }
            "Error" { $results.Errors++ }
            "DryRun" { $results.DryRun++ }
        }
    }
    
    # 結果サマリー
    Write-Host ""
    Write-Host "=== 処理結果 ===" -ForegroundColor Cyan
    Write-Host "総ファイル数: $($results.Total)" -ForegroundColor White
    
    if ($DryRun) {
        Write-Host "変換予定: $($results.DryRun)" -ForegroundColor Yellow
    }
    else {
        Write-Host "変換完了: $($results.Converted)" -ForegroundColor Green
    }
    
    Write-Host "スキップ: $($results.Skipped)" -ForegroundColor Gray
    
    if ($results.Errors -gt 0) {
        Write-Host "エラー: $($results.Errors)" -ForegroundColor Red
    }
    
    Write-Host ""
    
    if ($DryRun) {
        Write-Host "DryRunモードで実行されました。実際の変換を行うには -DryRun パラメータを外してください。" -ForegroundColor Yellow
    }
    elseif ($results.Converted -gt 0) {
        Write-Host "✓ エンコーディング変換が完了しました！" -ForegroundColor Green
    }
    else {
        Write-Host "変換が必要なファイルはありませんでした。" -ForegroundColor Yellow
    }
}

# エンコーディング情報の表示
function Show-EncodingInfo {
    param(
        [string]$FilePath
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Error "ファイルが見つかりません: $FilePath"
        return
    }
    
    $encoding = Get-FileEncoding -FilePath $FilePath
    $fileInfo = Get-Item $FilePath
    
    Write-Host "=== ファイル情報 ===" -ForegroundColor Cyan
    Write-Host "ファイル: $($fileInfo.Name)" -ForegroundColor White
    Write-Host "パス: $($fileInfo.FullName)" -ForegroundColor Gray
    Write-Host "サイズ: $($fileInfo.Length) bytes" -ForegroundColor Gray
    Write-Host "エンコーディング: $($encoding.Encoding)" -ForegroundColor Yellow
    Write-Host "BOM: $($encoding.HasBOM)" -ForegroundColor Yellow
    Write-Host "信頼度: $($encoding.Confidence)%" -ForegroundColor Yellow
    
    # バイナリダンプ（最初の16バイト）
    if ($fileInfo.Length -gt 0) {
        $bytes = [System.IO.File]::ReadAllBytes($FilePath) | Select-Object -First 16
        $hexString = ($bytes | ForEach-Object { "{0:X2}" -f $_ }) -join " "
        Write-Host "バイナリ（先頭16バイト）: $hexString" -ForegroundColor Gray
    }
}

# ヘルプの表示
function Show-Help {
    Write-Host @"
エンコーディング修正スクリプト

使用方法:
  pwsh ./tests/encoding-fix.ps1 [オプション]

オプション:
  -TargetPath <パス>           対象パス（デフォルト: プロジェクトルート）
  -TargetEncoding <エンコード>  変換先エンコーディング（UTF8, UTF8BOM, ASCII, Unicode, UTF32）
  -SourceEncoding <エンコード>  変換元エンコーディング（Auto, UTF8, UTF8BOM, ASCII, Unicode, UTF32, SHIFT_JIS）
  -Recursive                  サブディレクトリも対象にする
  -FileExtensions <拡張子>     対象ファイル拡張子（配列）
  -Backup                     変換前にバックアップを作成
  -DryRun                     実際には変換せず、変換予定を表示
  -Force                      確認プロンプトをスキップ

使用例:
  # 全てのファイルをUTF-8（BOM無し）に変換
  pwsh ./tests/encoding-fix.ps1 -TargetEncoding UTF8 -Recursive

  # PowerShellファイルのみをUTF-8 BOM付きに変換（DryRun）
  pwsh ./tests/encoding-fix.ps1 -TargetEncoding UTF8BOM -FileExtensions @("*.ps1", "*.psm1") -DryRun

  # 特定ディレクトリのCSVファイルを変換（バックアップ付き）
  pwsh ./tests/encoding-fix.ps1 -TargetPath "./test-data" -TargetEncoding UTF8 -FileExtensions @("*.csv") -Backup

  # ファイルのエンコーディング情報を表示
  pwsh ./tests/encoding-fix.ps1 -TargetPath "file.txt" -ShowInfo

追加コマンド:
  # 特定ファイルのエンコーディング情報表示
  Show-EncodingInfo -FilePath "path/to/file.txt"

注意事項:
  - 変換前には必ずバックアップを取ることを推奨します
  - DryRunモードで事前に変換対象を確認してください
  - 大量のファイルを変換する場合は時間がかかる場合があります
"@
}

# 特別なパラメータの処理
if ($args -contains "-ShowInfo") {
    $infoIndex = [Array]::IndexOf($args, "-ShowInfo")
    if ($infoIndex -ge 0 -and $infoIndex + 1 -lt $args.Length) {
        $infoFilePath = $args[$infoIndex + 1]
        Show-EncodingInfo -FilePath $infoFilePath
        exit 0
    }
    else {
        Write-Error "-ShowInfo パラメータにはファイルパスが必要です"
        exit 1
    }
}

# ヘルプが要求された場合
if ($args -contains "-h" -or $args -contains "-help" -or $args -contains "--help") {
    Show-Help
    exit 0
}

# メイン処理の実行
Invoke-EncodingFix