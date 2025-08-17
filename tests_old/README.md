# PowerShell & SQLite データ管理システム テストガイド

このドキュメントでは、レイヤアーキテクチャに対応した新しいテストシステムの使用方法について説明します。

## 📁 テスト構造

テストは4層のアーキテクチャに対応して整理されています：

```
tests/
├── Utils/
│   ├── Foundation/          # Layer 1: 基盤層（設定非依存）
│   │   └── CoreUtils.Tests.ps1
│   ├── Infrastructure/      # Layer 2: インフラ層（設定依存）
│   │   ├── ConfigurationUtils.Tests.ps1
│   │   ├── ErrorHandlingUtils.Tests.ps1
│   │   └── LoggingUtils.Tests.ps1
│   ├── DataAccess/         # Layer 3: データアクセス層
│   │   ├── DatabaseUtils.Tests.ps1
│   │   └── FileSystemUtils.Tests.ps1
│   └── DataProcessing/     # Layer 4: データ処理層
│       ├── CsvProcessingUtils.Tests.ps1
│       └── DataFilteringUtils.Tests.ps1
├── Process/                # ビジネスロジックテスト
├── Integration/            # 統合テスト
├── Feature/               # 機能テスト
└── TestHelpers/           # テストサポート
    ├── LayeredTestHelpers.psm1
    └── MockHelpers.psm1
```

## 🚀 基本的なテスト実行

### すべてのテストを実行
```bash
pwsh ./tests/run-test.ps1
```

### レイヤー別テスト実行
```bash
# Foundation層（基盤層）のテスト
pwsh ./tests/run-test.ps1 -Layer "Foundation"

# Infrastructure層（インフラ層）のテスト  
pwsh ./tests/run-test.ps1 -Layer "Infrastructure"

# DataAccess層（データアクセス層）のテスト
pwsh ./tests/run-test.ps1 -Layer "DataAccess"

# DataProcessing層（データ処理層）のテスト
pwsh ./tests/run-test.ps1 -Layer "DataProcessing"
```

### 特定のテストファイル実行
```bash
# 特定のモジュールテスト
pwsh ./tests/run-test.ps1 -TestPath "Utils/Foundation/CoreUtils.Tests.ps1"

# 統合テスト
pwsh ./tests/run-test.ps1 -TestPath "Integration/FullSystem.Tests.ps1"

# プロセステスト
pwsh ./tests/run-test.ps1 -TestPath "Process/Invoke-DataSync.Tests.ps1"
```

## 📊 レポート生成とカバレッジ

### HTMLレポート生成
```bash
# HTMLレポートでテスト結果を出力
pwsh ./tests/run-test.ps1 -OutputFormat "HTML"

# カバレッジ情報を含むHTMLレポート
pwsh ./tests/run-test.ps1 -OutputFormat "HTML" -ShowCoverage
```

### XMLレポート生成（CI/CD用）
```bash
# NUnit XML形式
pwsh ./tests/run-test.ps1 -OutputFormat "NUnitXml"

# JUnit XML形式
pwsh ./tests/run-test.ps1 -OutputFormat "JUnitXml"

# カバレッジ付きXMLレポート
pwsh ./tests/run-test.ps1 -OutputFormat "JUnitXml" -ShowCoverage
```

## 🔧 開発者向けワークフロー

### 新機能開発時のテスト実行順序

1. **関連レイヤーのテスト実行**
   ```bash
   # 例：CSVProcessingUtilsを修正した場合
   pwsh ./tests/run-test.ps1 -Layer "DataProcessing"
   ```

2. **特定モジュールのテスト実行**
   ```bash
   pwsh ./tests/run-test.ps1 -TestPath "Utils/DataProcessing/CsvProcessingUtils.Tests.ps1"
   ```

3. **依存関係のあるレイヤーのテスト**
   ```bash
   # DataProcessing層を変更した場合、上位レイヤーのテストも実行
   pwsh ./tests/run-test.ps1 -TestPath "Process"
   ```

4. **統合テストでの最終確認**
   ```bash
   pwsh ./tests/run-test.ps1 -TestPath "Integration/FullSystem.Tests.ps1"
   ```

### バグ修正時のテスト実行

1. **該当する機能テストの実行**
   ```bash
   pwsh ./tests/run-test.ps1 -TestPath "Feature/ExcludedDataKeepOutput.Tests.ps1"
   ```

2. **関連するモジュールテストの実行**
   ```bash
   pwsh ./tests/run-test.ps1 -Layer "DataProcessing"
   ```

3. **回帰テストの実行**
   ```bash
   pwsh ./tests/run-test.ps1
   ```

## 🛠️ トラブルシューティング

### よくある問題と解決方法

#### 1. モジュール不足エラー
```
エラー: Cannot find module 'ModuleName'
```

**解決方法:**
```bash
# モジュールファイルの存在確認
ls -la scripts/modules/Utils/*/

# 実際のモジュールパスの確認
find scripts/modules -name "*.psm1"
```

#### 2. 依存関係エラー
```
エラー: Cannot resolve dependency 'DependencyName'
```

**解決方法:**
```bash
# レイヤーヘルパーのデバッグモードで実行
pwsh -Command "Import-Module ./tests/TestHelpers/LayeredTestHelpers.psm1 -Verbose"
```

#### 3. 設定ファイルエラー
```
エラー: Configuration file not found or invalid
```

**解決方法:**
```bash
# 設定ファイルの確認
cat config/data-sync-config.json | jq .

# 設定ファイルの妥当性チェック
pwsh -Command "Get-Content config/data-sync-config.json | ConvertFrom-Json"
```

#### 4. UTF-8エンコーディング問題
```
エラー: Character encoding issues with Japanese text
```

**解決方法:**
```bash
# UTF-8エンコーディングの修正スクリプト実行
pwsh ./tests/encoding-fix.ps1

# UTF-8テストファイルの作成
pwsh ./tests/create-utf8-tests.ps1
```

### デバッグ用コマンド

#### テスト構造の確認
```bash
# すべてのテストファイルの一覧
find tests -name "*.Tests.ps1" -type f

# レイヤー別テストファイルの確認
ls -la tests/Utils/*/
```

#### Pesterモジュールの確認
```bash
# Pesterバージョンの確認
pwsh -Command "Get-Module -ListAvailable Pester"

# Pesterの詳細情報
pwsh -Command "Get-Module Pester -ListAvailable | Select-Object Name, Version, Path"
```

#### 個別テストのデバッグ実行
```bash
# 詳細出力でテスト実行
pwsh -Command "Invoke-Pester './tests/Utils/Foundation/CoreUtils.Tests.ps1' -Output Detailed"

# 特定のテストケースのみ実行
pwsh -Command "Invoke-Pester './tests/Utils/Foundation/CoreUtils.Tests.ps1' -TestName '*timestamp*'"
```

## 📈 継続的インテグレーション（CI/CD）

### GitHub Actions用設定例

```yaml
# .github/workflows/test.yml
name: PowerShell Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup PowerShell
        uses: actions/setup-powershell@v1
        
      - name: Install Dependencies
        run: |
          pwsh -Command "Install-Module -Name Pester -Force -SkipPublisherCheck"
          
      - name: Run Tests
        run: |
          pwsh ./tests/run-test.ps1 -OutputFormat "JUnitXml" -ShowCoverage
          
      - name: Publish Test Results
        uses: dorny/test-reporter@v1
        if: always()
        with:
          name: PowerShell Tests
          path: tests/TestResults.xml
          reporter: java-junit
```

### ローカルCI環境でのテスト
```bash
# すべてのテストを実行してレポート生成
pwsh ./tests/run-test.ps1 -OutputFormat "JUnitXml" -ShowCoverage

# 結果ファイルの確認
ls -la tests/TestResults.*

# HTMLレポートの表示（ブラウザで開く）
if [ -f "tests/TestResults.html" ]; then
    xdg-open tests/TestResults.html  # Linux
    # open tests/TestResults.html    # macOS
    # start tests/TestResults.html   # Windows
fi
```

## 🔍 パフォーマンステスト

### 大量データテスト
```bash
# 大量データでの統合テスト
pwsh ./tests/run-test.ps1 -TestPath "Integration/FullSystem.Tests.ps1" -ShowCoverage

# パフォーマンス測定付きテスト
pwsh -Command "Measure-Command { ./tests/run-test.ps1 }"
```

### メモリ使用量の監視
```bash
# メモリ使用量を監視しながらテスト実行
pwsh -Command "
\$before = [GC]::GetTotalMemory(\$false)
./tests/run-test.ps1
\$after = [GC]::GetTotalMemory(\$true)
Write-Host \"Memory used: \$((\$after - \$before) / 1MB) MB\"
"
```

## 📝 テスト結果の解釈

### 成功時の出力例
```
Tests Passed: 85, Failed: 0, Skipped: 2, Inconclusive: 0
Test execution time: 00:02:15.342
Coverage: 87.5% (245/280 lines covered)
```

### 失敗時の対応
- **Failed テスト**: 機能の問題、修正が必要
- **Skipped テスト**: プラットフォーム固有、通常は問題なし  
- **Inconclusive テスト**: 環境依存、必要に応じて調査

### カバレッジ目標
- **Foundation層**: 95%以上
- **Infrastructure層**: 90%以上
- **DataAccess層**: 85%以上
- **DataProcessing層**: 90%以上
- **統合テスト**: 80%以上

## 🤝 コントリビューション

### 新しいテストの追加
1. 適切なレイヤーディレクトリにテストファイルを配置
2. `LayeredTestHelpers`を使用してテスト環境を初期化
3. レイヤー依存関係の検証を含める
4. 日本語文字とエラーハンドリングのテストを含める

### テストの命名規則
- ファイル名: `{ModuleName}.Tests.ps1`
- テストブロック: `Describe "{ModuleName} ({LayerName}) Tests"`
- コンテキスト: `Context "{機能名} Function"`
- テストケース: `It "should {期待される動作}"`

## 📚 参考資料

- [Pester Documentation](https://pester.dev/)
- [PowerShell Testing Best Practices](https://docs.microsoft.com/en-us/powershell/scripting/dev-cross-plat/testing/)
- [プロジェクトのCLAUDE.md](../CLAUDE.md) - アーキテクチャの詳細