# upgrade-fork.ps1 — 看板娘 fork 一键升级
# 作用：拉官方 upstream 最新 → rebase 我们的 multi-city-weather 分支 →
#       版本号定为 <官方版本>+fork.<N>（tag fork-<N>）→ push GitHub →
#       npm pack 到 ~/.dsh/tools → host CLI 安装到 desktop profile。
# 用法：
#   pwsh -File tools\upgrade-fork.ps1            # 常规升级
#   pwsh -File tools\upgrade-fork.ps1 -Continue  # 手工解决 rebase 冲突后继续
param(
  [string]$Repo = "C:\Users\vincent\.dsh\workspace\dsh-whale-musume-fork",
  [string]$Branch = "multi-city-weather",
  [switch]$Continue
)
$ErrorActionPreference = "Stop"
$toolsDir = "C:/Users/vincent/.dsh/tools"
$hostExe  = "C:\Users\vincent\AppData\Local\Programs\DeepSeek Harness\DeepSeek Harness.exe"
$hostCli  = "C:\Users\vincent\AppData\Local\Programs\DeepSeek Harness\resources\app.asar\dsh\node_modules\@deepseek-ai\dsh-desktop-host\lib\cli.js"

if ($Continue) {
  $env:GIT_EDITOR = "true"
  git -C $Repo rebase --continue
  if ($LASTEXITCODE -ne 0) { Write-Error "rebase 仍有冲突，继续解决后再 -Continue"; exit 1 }
} else {
  git -C $Repo fetch upstream
  git -C $Repo checkout $Branch
  git -C $Repo rebase upstream/main
  if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️ rebase 冲突：手工解决（git status 看 UU 文件），然后重跑本脚本加 -Continue"
    exit 1
  }
}

# fork 序号 = 已有 fork-N tag 最大值 + 1
$nums = git -C $Repo tag -l "fork-*" | ForEach-Object { if ($_ -match "^fork-(\d+)$") { [int]$Matches[1] } }
$N = 1; if ($nums) { $N = ($nums | Measure-Object -Maximum).Maximum + 1 }

# 官方基版本（取 upstream/main 的 package.json）
$upVer = (git -C $Repo show upstream/main:package.json | ConvertFrom-Json).version
$ver = "$upVer+fork.$N"

# 写版本号 + 同步资源缓存尾巴
$pkg = Join-Path $Repo "package.json"
(Get-Content $pkg -Raw) -replace '"version":\s*"[^"]+"', ('"version": "' + $ver + '"') | Set-Content $pkg -Encoding utf8
$cl = Join-Path $Repo "lib\client.js"
(Get-Content $cl -Raw) -replace 'const cacheBust = "&v=fork\.\d+"', ('const cacheBust = "&v=fork.' + $N + '"') | Set-Content $cl -Encoding utf8

git -C $Repo add -A
git -C $Repo commit -m "chore(fork): $ver (upstream base $upVer)"
git -C $Repo tag "fork-$N"
git -C $Repo push origin $Branch "fork-$N"

# 打包 + 官方 host CLI 安装
Set-Location $Repo
npm pack --pack-destination $toolsDir | Out-Null
$env:ELECTRON_RUN_AS_NODE = "1"
& $hostExe --expose-internals $hostCli plugin --profile desktop add ("file:" + $toolsDir + "/dsh-whale-musume-" + $ver + ".tgz")
Write-Host "✅ $ver 已安装（upstream base $upVer），重启 DSH Desktop 生效"
