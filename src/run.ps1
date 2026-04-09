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


    $sessionId=open-session -UserName $UserName -Password $Password

    $fileListMedia=get-filelist -Path '/bible_pod/media' -SessionId $sessionId
    $fileListPlan=get-filelist -Path '/bible_pod' -SessionId $sessionId
    $fileListImages=get-filelist -Path '/bible_pod/images' -SessionId $sessionId

    $fileListPlan.fileList | Where-Object Name -eq "bibleListenPlan.csv" | out-string | write-debug
    $fileListPlan.fileList | Where-Object Name -eq "bibleListenPlan.csv" | foreach {
        get-file -file $_ -SessionId $sessionId
    }

    close-session $sessionId | write-debug

    $plan=(import-csv './bibleListenPlan.csv' | where-object current -ne '' | select-object Chapter,Category,current,'Length Seconds')

    $data=@{
        plan=$plan
        links=$fileListMedia.fileList
        images=$fileListImages.fileList
    }

    $data.plan | ForEach-Object {
        $_.current = [int]$_.current
        $_.'Length Seconds' = [int]$_.'Length Seconds'
    }

    # Filter for Day of Year
    if ( $allYear -eq $false ) {
        $dayOfYearToday=(get-date).DayOfYear
    } else {
        $dayOfYearToday=366
    }

    $data.plan = $data.plan | where-object { $_.current -le $dayOfYearToday }
    "Plan data: Day of Year: $($dayOfYearToday)" | write-debug
    $data.plan[-5..-1] | format-table | out-string | write-debug
    $data.plan[0..5] | format-table | out-string | write-debug

    generate-rss-xml -data $data

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
