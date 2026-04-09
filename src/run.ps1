#!/opt/microsoft/powershell/7-lts/pwsh
#######################################################################
#
#   FileName: run.ps1
#
#   Purpose:
#       Updates RSS Feed
#
#######################################################################

param (
    [switch]$noUpload,
    [switch]$allYear = $false,
    [ValidateSet("SilentlyContinue","Continue","Inquire","Stop")]
    [string]$DebugPreference = $global:DebugPreference
)

. $PSScriptRoot/opendrive.ps1
. $PSScriptRoot/rss.ps1

function Get-PlanData() {
    param(
        [string]$UserName,
        [string]$Password
    )

    $planCSV="bibleListenPlan.csv"

    $sessionId=open-session -UserName $UserName -Password $Password

    $fileListMedia=get-filelist -Path '/bible_pod/media' -SessionId $sessionId
    $fileListPlan=get-filelist -Path '/bible_pod' -SessionId $sessionId
    $fileListImages=get-filelist -Path '/bible_pod/images' -SessionId $sessionId

    $fileListPlan.fileList | Where-Object Name -eq $planCSV | out-string | write-debug
    $fileListPlan.fileList | Where-Object Name -eq $planCSV | foreach {
        get-file -file $_ -SessionId $sessionId
    }

    close-session $sessionId | write-debug

    $plan=(import-csv "./$($planCSV)" | where-object current -ne '' | select-object Chapter,Category,current,'Length Seconds')

    $plan | ForEach-Object {
        $_.current = [int]$_.current
        $_.'Length Seconds' = [int]$_.'Length Seconds'
    }

    return @{
        plan=$plan
        links=$fileListMedia.fileList
        images=$fileListImages.fileList
    }
}



function main() {
    param (
        $UserName,
        $Password,
        $NoUpload
    )
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


    $data = Get-PlanData -UserName $UserName -Password $Password


    $data | out-string | write-debug

    # Filter for Day of Year
    if ( $allYear -eq $false ) {
        $dayOfYearToday=(get-date).DayOfYear
    } else {
        $dayOfYearToday=366
    }

    $global:i=0

    $data.plan.Category | Select-Object -Unique | write-debug
    $data.plan.Category | Select-Object -Unique | where-object { $_ -ne "" } | ForEach-Object {
        $inCategory=$data.plan | where-object { $_.current -le $dayOfYearToday } | where-object Category -eq $_

        $data2=@{
            category=$_
            plan=$inCategory
            links=$data.links
            images=$data.images
        }
        generate-rss-xml -data $data2
    }

    # Upload rss feeds
    if ( -not $NoUpload ) {
        write-debug "Uploading xml"
        put-xml -USERNAME $UserName -PASSWORD $Password -fileList $PutFiles
    }
}

################################# SCRIPT #################################
write-output "Date: $(get-date)"

try {
    main -UserName $env:OPENDRIVE_USERNAME -Password $env:OPENDRIVE_PASSWORD -NoUpload $noUpload
} catch {
    exit 1
}


### End of File
