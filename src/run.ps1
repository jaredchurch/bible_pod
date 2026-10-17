#!/opt/microsoft/powershell/7-lts/pwsh
#######################################################################
#
#   FileName: run.ps1
#
#   Purpose:
#       Main entry point for Bible Podcast RSS feed generation.
#       Connects to OpenDrive, retrieves plan data, filters by day of year,
#       groups by category, generates RSS XML files, and uploads to server.
#
#######################################################################

# Command-line parameters
param (
    [switch]$noUpload,    # Skip uploading XML files to server
    [switch]$allYear = $false,    # Generate RSS for entire year (366 days)
    [ValidateSet("SilentlyContinue","Continue","Inquire","Stop")]
    [string]$DebugPreference = $global:DebugPreference    # Debug output level
)

# Include required modules
. $PSScriptRoot/opendrive.ps1
. $PSScriptRoot/rss.ps1
. $PSScriptRoot/whole_bible.ps1

# Global counter for generating publication dates in RSS items
# there is some tech-debt around this global for handling pubDate generation - ideally this would be handled in a more robust way
$global:i=0

# Retrieves file metadata from OpenDrive, and the listening plan from the repo
function Get-PlanData() {
    param(
        [string]$UserName,
        [string]$Password
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

    # Open session with OpenDrive API using provided credentials
    $sessionId=open-session -UserName $UserName -Password $Password

    # Retrieve file listings from media and images directories
    $fileListMedia=get-filelist -Path '/bible_pod/media' -SessionId $sessionId
    $fileListImages=get-filelist -Path '/bible_pod/images' -SessionId $sessionId

    # Close the OpenDrive session
    close-session $sessionId | write-debug

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
        $UserName,
        $Password,
        $NoUpload
    )

    # Define files to upload to OpenDrive after RSS generation
    # Each entry maps local file to remote path
    $PutFiles=@(
        @{
            localPath='./tniv_NT.xml'
            remotePath='/bible_pod/rss/tniv_NT.xml'
        },
        @{
            localPath='./tniv_OT.xml'
            remotePath='/bible_pod/rss/tniv_OT.xml'
        },
        @{
            localPath='./tniv_Proverbs.xml'
            remotePath='/bible_pod/rss/tniv_Proverbs.xml'
        },
        @{
            localPath='./tniv_Psalms.xml'
            remotePath='/bible_pod/rss/tniv_Psalms.xml'
        }
    )

    # Fetch plan data and file listings from OpenDrive
    $data = Get-PlanData -UserName $UserName -Password $Password

    # Debug: output entire data structure
    $data | out-string | write-debug

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
        $image=$data.images | where-object Name -like "*$($_).jpg"

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

    # Upload generated RSS XML files to OpenDrive server
    if ( -not $NoUpload ) {
        write-debug "Uploading xml"
        put-xml -USERNAME $UserName -PASSWORD $Password -fileList $PutFiles
    }
}

################################# SCRIPT #################################
# Script entry point - executed when script is run directly
write-output "Date: $(get-date)"

# Retrieve credentials from environment variables and execute main function
try {
    main -UserName $env:OPENDRIVE_USERNAME -Password $env:OPENDRIVE_PASSWORD -NoUpload $noUpload
} catch {
    # Surfaces the reason before exiting: a silent exit 1 leaves CI showing only
    # a failed run with no indication of what actually went wrong
    write-error $_
    # Exit with error code 1 if main function throws an exception
    exit 1
}


### End of File
