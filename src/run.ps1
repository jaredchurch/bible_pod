#######################################################################
#
#   FileName: run.ps1
#
#   Purpose:
#       Updates RSS Feed
#
#######################################################################

param (
    [switch]$noUpload
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
    $fileListMedia.fileList | Format-Table -AutoSize | out-string | write-debug
    $fileListPlan=get-filelist -Path '/bible_pod' -SessionId $sessionId
    $fileListPlan.fileList | Format-Table -AutoSize | out-string | write-debug
    $fileListImages=get-filelist -Path '/bible_pod/images' -SessionId $sessionId
    $fileListImages.fileList | Format-Table -AutoSize | out-string | write-debug

    $fileListPlan.fileList | Where-Object Name -eq "bibleListenPlan.csv" | out-string | write-debug
    $fileListPlan.fileList | Where-Object Name -eq "bibleListenPlan.csv" | foreach {
        get-file -file $_ -SessionId $sessionId
    }

    close-session $sessionId | write-debug

    generate-rss-xml -plan "./bibleListenPlan.csv" -links $fileListMedia.fileList -images $fileListImages.fileList

    # Upload rss feeds
    if ( -not $NoUpload ) {
        write-debug "Uploading xml"
        put-xml -USERNAME $UserName -PASSWORD $Password -fileList $PutFiles
    }
}

################################# SCRIPT #################################
$DebugPreference = "Continue"
$DebugPreference = "SilentlyContinue"

write-output "Date: $(get-date)"

try {
    main -UserName $env:OPENDRIVE_USERNAME -Password $env:OPENDRIVE_PASSWORD -NoUpload $noUpload
} catch {
    exit 1
}


### End of File
