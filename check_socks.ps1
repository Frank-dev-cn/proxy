# windows下，powershell 检测 socks.frankwong.dpdns.org 配置

$domain = "socks.frankwong.dpdns.org"

Write-Host "🔍 正在查询 $domain 的 DNS 记录..." -ForegroundColor Cyan
$dns = Resolve-DnsName $domain -ErrorAction SilentlyContinue

if ($dns) {
    foreach ($record in $dns) {
        Write-Host "✔️ 解析到：" $record.IPAddress $record.NameHost
    }
} else {
    Write-Host "❌ 无法解析 $domain，请检查 DNS 设置！" -ForegroundColor Red
    exit
}

Write-Host "`n🔍 正在测试 HTTP 响应..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "https://$domain" -UseBasicParsing -TimeoutSec 10
    Write-Host "✔️ HTTP 状态码：" $response.StatusCode
} catch {
    Write-Host "❌ 访问失败：" $_.Exception.Message -ForegroundColor Red
}
