#!/usr/bin/pwsh
#######################################################################
#
#   FileName: run-cloudflare.ps1
#
#   Purpose:
#       Cloudflare R2 backed equivalent of run.ps1.
#       Retrieves the listening plan from the repo and the media/cover art
#       listing from the R2 bucket, then generates the RSS XML files that
#       GitHub Pages publishes.
#
#   Usage:
#       source ./.env.sh     # only necessary for dev
#       pwsh ./src/run-cloudflare.ps1
#
#######################################################################

param (
    [switch]$allYear = $false,    # Generate RSS for entire year (366 days)
    [int]$linkExpireHours = 36,    # Lifetime of the generated enclosure links
    # Empty means use the default in cloudflare.ps1, so the bucket name has a
    # single definition rather than one per script.
    [string]$bucket,
    # Channel and self link emitted into every feed. rss.ps1 still defaults to
    # the retired OpenDrive location, so this overrides it with the GitHub
    # Pages site that actually serves the feeds. No trailing slash, since
    # rss.ps1 appends the path itself.
    [string]$feedBaseURL = "https://jaredchurch.github.io",
    [ValidateSet("SilentlyContinue","Continue","Inquire","Stop")]
    [string]$DebugPreference = $global:DebugPreference    # Debug output level
)

# Include required modules

. $PSScriptRoot/cloudflare.ps1
. $PSScriptRoot/rss.ps1
. $PSScriptRoot/whole_bible.ps1

# Reapplied after dot-sourcing because rss.ps1 assigns this at source time,
# which would otherwise overwrite the parameter value. The path part needs no
# override: rss.ps1 defaults to /bible_pod/rss, which is where
# update_rss.yml publishes these feeds (./public/rss, served under /bible_pod).
$webBaseURL=$feedBaseURL

# Global counter for generating publication dates in RSS items
# there is some tech-debt around this global for handling pubDate generation - ideally this would be handled in a more robust way
$global:i=0

# Bucket layout. The media and cover art sit a folder deeper than these
# prefixes, which is why the listing matches on file name rather than key.
$r2MediaPrefix="media"
$r2ImagesPrefix="coverart"

# Retrieves file metadata from Cloudflare R2, and the listening plan from the repo
function Get-PlanData() {
    param (
        [int]$LinkExpireHours,
        [string]$Bucket
    )

    # Anchored to the script location rather than the working directory, so a
    # plan edit behaves the same whether this runs from the repo root (CI) or
    # from test/
    $planCSV="$PSScriptRoot/../bibleListenPlan.csv"

    # Fail loudly and specifically: an absent or empty plan would otherwise
    # generate a feed with no items, which publishes as a silently valid RSS
    # document pointing at an empty podcast
    if ( -not (test-path $planCSV) ) {
        throw "Listening plan not found at $planCSV"
    }

    # Retrieve file listings from the R2 bucket. Each call is a paginated
    # ListObjectsV2; the links attached to the results are signed locally.
    $fileListMedia=get-r2-filelist -Prefix $r2MediaPrefix -LinkExpireHours $LinkExpireHours -Bucket $Bucket
    $fileListImages=get-r2-filelist -Prefix $r2ImagesPrefix -LinkExpireHours $LinkExpireHours -Bucket $Bucket

    # A missing cover art would emit an empty href into every item of that
    # feed, which podcast clients reject silently rather than visibly.
    if ( $fileListImages.fileList.Count -eq 0 ) {
        throw "No objects found under '$r2ImagesPrefix' in bucket $Bucket; cover art links would be empty"
    }

    # Import the CSV plan file and filter for rows with a current day value
    $plan=(import-csv $planCSV | where-object current -ne '' | select-object Chapter,Category,current,'Length Seconds')

    # Convert numeric fields to integers for proper sorting/comparison
    $plan | ForEach-Object {
        $_.current = [int]$_.current
        $_.'Length Seconds' = [int]$_.'Length Seconds'
    }

    # Return structured data object containing plan, media links, and image references
    return @{
        plan=$plan
        links=$fileListMedia.fileList
        images=$fileListImages.fileList
    }
}


# Main execution function - coordinates the RSS generation workflow
function main() {
    param (
        $LinkExpireHours,
        $Bucket
    )

    # Fetch plan data and file listings from Cloudflare R2
    $data = Get-PlanData -LinkExpireHours $LinkExpireHours -Bucket $Bucket

    # Debug: output entire data structure
    $data | out-string | write-debug

    # Every chapter in the plan must resolve to a bucket object, otherwise the
    # feed publishes an item whose enclosure URL is empty and the client
    # silently drops the episode. Compared case-insensitively to match the
    # -eq match rss.ps1 performs when it looks the file up.
    $available=[System.Collections.Generic.HashSet[string]]::new([string[]]$data.links.Name,[System.StringComparer]::OrdinalIgnoreCase)
    $missing=$data.plan.Chapter | Sort-Object -Unique | Where-Object { -not $available.Contains($_) }
    if ( $missing ) {
        throw "$($missing.Count) chapter(s) in the plan have no object under '$r2MediaPrefix' in bucket $Bucket, e.g. $(($missing | Select-Object -First 5) -join ', ')"
    }

    # Determine day of year filter
    # By default, only process entries up to today's day of year
    # With -allYear flag, process all days (day of year is always < 367)
    if ( $allYear -eq $false ) {
        $dayOfYearToday=(get-date).DayOfYear
    } else {
        $dayOfYearToday=367
    }


    # Get unique categories from the plan
    $data.plan.Category | Select-Object -Unique | write-debug

    # Process each category separately to generate individual RSS feeds
    $data.plan.Category | Select-Object -Unique | where-object { $_ -ne "" } | ForEach-Object {
        # Filter plan entries for current category that have already passed
        $plan=$data.plan | where-object { $_.current -le $dayOfYearToday } | where-object Category -eq $_
        $image=get-cover-art -Images $data.images -Category $_

        # An unmatched pattern yields no object at all, which would emit an
        # empty href into the channel image rather than failing
        if ( -not $image ) {
            throw "No cover art matching '*$($_).jpg' under '$r2ImagesPrefix' in bucket $Bucket"
        }

        # Create data object for this category's RSS generation
        $data2=@{
            category=$_
            plan=$plan | sort-object current,Chapter
            links=$data.links
            image=$image
        }
        "Number of Chapters: $($data2.plan.Length)" | write-debug
        "{0,10} {1,-10}" -f "$($data2.category):","$($data2.plan.count)"

        # Generate RSS XML file for this category
        generate-rss-xml -data $data2  | out-file -encoding ascii "./$(get-feed-filename $_)"
    }

    # Collapse the whole plan into a single feed per testament. Deliberately
    # ignores $dayOfYearToday: these are always the complete year, so a
    # subscriber starting mid-year gets the full sequence rather than a
    # partial feed that silently refills over the following days.
    generate-xml-whole-bible -plan "$PSScriptRoot/../bibleListenPlan.csv" -links $data.links -images $data.images

    # Deliberately no upload: the feeds are published by copying *.xml into
    # ./public, which .github/workflows/update_rss.yml then deploys to GitHub
    # Pages. Nothing is written back to Cloudflare.
}

################################# SCRIPT #################################
# Script entry point - executed when script is run directly
write-output "Date: $(get-date)"

# Retrieve credentials from environment variables and execute main function
try {
    main -LinkExpireHours $linkExpireHours -Bucket $bucket
} catch {
    # Surfaces the reason before exiting: a silent exit 1 leaves CI showing only
    # a failed run with no indication of what actually went wrong
    write-error $_
    # Exit with error code 1 if main function throws an exception
    exit 1
}


### End of File
