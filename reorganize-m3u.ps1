# M3U文件重组脚本 - 按线路分组
# 将原始按地区分组的M3U文件重组为按线路(源)分组

$sourceFile = "source/result.m3u"
$outputFile = "output/mytv.m3u"

# 确保输出目录存在
$outputDir = Split-Path $outputFile -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Write-Host "正在读取源文件: $sourceFile"

# 读取文件内容
$content = Get-Content $sourceFile -Encoding UTF8

# 存储频道信息的哈希表: 频道名 -> 源列表
$channels = [ordered]@{}
$epgUrl = ""

# 解析M3U文件
for ($i = 0; $i -lt $content.Count; $i++) {
    $line = $content[$i]
    
    # 提取EPG URL
    if ($line -match '^#EXTM3U\s+x-tvg-url="([^"]+)"') {
        $epgUrl = $matches[1]
        continue
    }
    
    # 解析频道信息
    if ($line -match '^#EXTINF:-1\s+(.+)') {
        $attributes = $matches[1]
        
        # 提取tvg-name
        if ($attributes -match 'tvg-name="([^"]+)"') {
            $channelName = $matches[1]
            
            # 跳过 CCTV5+ 频道
            if ($channelName -eq 'CCTV5+') {
                $i++ # 跳过下一行的URL
                continue
            }
            
            # 跳过"🕘️更新时间","🎵音乐频道","🎮游戏频道","🏀体育频道","🌊港·澳·台","💰央视付费频道"这些特殊频道
            # 跳过"📺央视频道","📡卫视频道","☘️上海频道","☘️河南频道","🎬电影频道","🪁动画频道","🏛经典剧场"这些特殊频道
            if ($attributes -notmatch 'group-title="📺央视频道"' -and 
            $attributes -notmatch 'group-title="📡卫视频道"' -and
            $attributes -notmatch 'group-title="☘️上海频道"') {
                $i++ # 跳过下一行的URL
                continue
            }
            
            # 提取其他属性
            $tvgLogo = if ($attributes -match 'tvg-logo="([^"]+)"') { $matches[1] } else { "" }
            $groupTitle = if ($attributes -match 'group-title="([^"]+)"') { $matches[1] } else { "" }
            
            # 提取频道显示名称(逗号后的部分)
            $displayName = if ($attributes -match ',(.+)$') { $matches[1] } else { $channelName }
            
            # 获取下一行的URL
            $i++
            if ($i -lt $content.Count) {
                $url = $content[$i].Trim()
                
                # 跳过包含 iptv.catvod.com 的链接
                if ($url -match 'iptv\.catvod\.com') {
                    continue
                }
                
                # 只处理有效的URL行
                if ($url -and -not $url.StartsWith('#')) {
                    # 初始化频道数组
                    if (-not $channels.Contains($channelName)) {
                        $channels[$channelName] = @{
                            DisplayName = $displayName
                            Logo = $tvgLogo
                            Sources = @()
                        }
                    }
                    
                    # 添加源
                    $channelInfo = $channels[$channelName]
                    $channelInfo.Sources += $url
                    $channels[$channelName] = $channelInfo
                }
            }
        }
    }
}

Write-Host "已解析 $($channels.Count) 个频道"

# 生成新的M3U文件
$output = @()

# 添加M3U头部
# if ($epgUrl) {
#     $output += "#EXTM3U x-tvg-url=`"http://epg.51zmt.top:8000/e.xml`""
# } else {
#     $output += "#EXTM3U x-tvg-url=`"http://epg.51zmt.top:8000/e.xml`""
# }

# 生成9个线路分组
for ($routeNum = 1; $routeNum -le 9; $routeNum++) {
    $routeName = "线路$routeNum"
    Write-Host "正在生成 $routeName..."
    
    $addedCount = 0
    
    # 遍历所有频道
    foreach ($channelName in $channels.Keys) {
        $channelInfo = $channels[$channelName]
        $sources = $channelInfo.Sources
        
        # 检查是否有足够的源
        if ($sources.Count -ge $routeNum) {
            $sourceUrl = $sources[$routeNum - 1]
            $displayName = $channelInfo.DisplayName
            $logo = $channelInfo.Logo
            
            # 生成EXTINF行
            $extinf = "#EXTINF:-1 tvg-name=`"$channelName`""
            if ($logo) {
                $extinf += " tvg-logo=`"$logo`""
            }
            $extinf += " group-title=`"$routeName`",$displayName"
            
            $output += $extinf
            $output += $sourceUrl
            $addedCount++
        }
    }
    
    Write-Host "  $routeName 添加了 $addedCount 个频道"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$finalContent = [string]::Join("`n", $output) + "`n" # 用 LF 拼接

Write-Host "正在写入输出文件: $outputFile"
[System.IO.File]::WriteAllText($outputFile, $finalContent, $utf8NoBom)

Write-Host "完成! 新文件已保存到: $outputFile"
Write-Host "总共生成了 $($output.Count - 1) 行内容"
