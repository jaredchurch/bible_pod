param(
    [ValidateSet("SilentlyContinue","Continue","Inquire","Stop")]
    [string]$DebugPreference = $global:DebugPreference
)

# Helper: convert duration string to TimeSpan
function Convert-ToTimeSpan {
    param($duration)

    # if ($duration -match "^\d+$") {
        # Duration is in seconds
        return [TimeSpan]::FromSeconds([int]$duration)
    # }

    # Duration is in HH:MM:SS or MM:SS
    # $parts = $duration.Split(":")
    # switch ($parts.Count) {
    #     3 { return New-TimeSpan -Hours $parts[0] -Minutes $parts[1] -Seconds $parts[2] }
    #     2 { return New-TimeSpan -Minutes $parts[0] -Seconds $parts[1] }
    #     default { return [TimeSpan]::Zero }
    # }
}

$allResults = @()

$files = Get-ChildItem -Filter *.xml

if ($files.Count -eq 0) {
    & "$($PSScriptRoot)/src/run.ps1" -allYear -noUpload
}

$RssPath = (get-childitem *.xml).FullName

foreach ($path in $RssPath) {

    # Load RSS as raw text
    $rssRaw = Get-Content $path -Raw

    # Decode HTML entities like &copy;
    Add-Type -AssemblyName System.Web
    $rssDecoded = [System.Web.HttpUtility]::HtmlDecode($rssRaw)

    # Parse XML
    [xml]$rss = $rssDecoded

    $items = $rss.rss.channel.item

    $items | Format-Table -Property title, pubDate, duration -AutoSize | out-string | write-debug

    foreach ($item in $items) {
        $date = Get-Date $item.pubDate
        $duration = $item.duration

        if (-not $duration) { continue }

        $allResults += [PSCustomObject]@{
            Date     = $date.Date
            Duration = Convert-ToTimeSpan $duration
            Count = 1
        }
    }
}


# Group by date and sum durations
$summary = $allResults |
    Group-Object Date |
    ForEach-Object {
        $totalTicks = ($_.Group.Duration | Measure-Object -Property Ticks -Sum).Sum

        [PSCustomObject]@{
            Date          = $_.Name
            DOY           = (get-date $_.Name).DayOfYear
            TotalDuration = [TimeSpan]::FromTicks($totalTicks)
            Count         = ($_.Group | Measure-Object).Count
            Flag          = if ([TimeSpan]::FromTicks($totalTicks) -gt [TimeSpan]::FromMinutes(30)) { "Long" } else { "" }
        }
    }

# Output
$summary | Format-Table -AutoSize
