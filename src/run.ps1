
$DebugPreference = 'SilentlyContinue'
# $DebugPreference = 'Continue'


function put-xml() {
    # localPath must be based on root of work - is a little complex to figure out I think.
    # will figure it out at some point
    param (
    # Set environment variables for username and password
        $USERNAME,
        $PASSWORD,
        $FileList=@()
    )

    $FileList | format-table -AutoSize | write-debug
    # Define the WebDAV server URL and the file to update
    $SERVER_URL = "https://webdav.opendrive.com"

    # Create a WebClient object
    $webclient = New-Object System.Net.WebClient
    $webclient.Credentials = New-Object System.Net.NetworkCredential($USERNAME, $PASSWORD)

    # Upload the file
    $FileList | ForEach-Object {
        $remotePath="$($SERVER_URL)$($_.remotePath)"
        write-debug "Upload $($_.localPath) to $($remotePath)"
        # get-item $_.localPath
        $webclient.UploadFile("$remotePath", "PUT", $_.localPath)
    }
    # Clean up
    $webclient.Dispose()
}

function close-session() {
    param (
        [Parameter(Mandatory=$true)]
        [string]$sessionId
    )

    $body=@{
        session_id = $sessionId
    } | convertto-json

    $response = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/session/logout.json" -Method Post -Body $body -ContentType "application/json"

    write-debug $response
    if ( ("$($response)" | convertfrom-json).result -eq $True ) {
        Write-Output "Session closed successfully."
    } else {
        Write-Output "Failed to close session."
    }


}

function open-session() {
    param (
        [Parameter(Mandatory=$true)]
        [string]$UserName,
        [Parameter(Mandatory=$true)]
        [string]$Password
    )
    # Step 1: Open a session
    $body=@{
        username = $UserName
        passwd = $Password
    } | convertto-json

    $loginResponse = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/session/login.json" -Method Post `
        -Body $body -ContentType "application/json"

    write-debug $loginResponse
    $sessionId = ( "$($loginResponse)" | convertfrom-json).SessionID
    return $sessionId
}

function get-filelist() {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$SessionId
    )

    # Get directory id
    $body=@{
        session_id = $SessionId
        path = $Path
    } | convertto-json

    write-debug $body
    $searchResponse = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/folder/idbypath.json" -Method Post -Body $body -ContentType "application/json"

    write-debug $searchResponse
    # Extract directory ID
    $directoryId = ($searchResponse | convertfrom-json).FolderId
    write-debug "Directory ID: $($directoryId)"

    # Get & Structure FileList
    $fileList = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/folder/list.json/$sessionId/$directoryId" -Method Get

    write-debug "FileList: $($fileList)"
    # Extract file IDs and download links
    $fileDetails = ($fileList | convertfrom-json).Files | ForEach-Object {
        [PSCustomObject]@{
            FileID = $_.FileId
            Name = $_.Name
            DownloadLink = $_.DownloadLink
        }
    }

    $retObject=[PSCustomObject]@{
        FolderId=$directoryId
        fileList=$fileDetails
    }

    return $retObject
}




function main() {
    param (
        $UserName,
        $Password
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
    $fileListMedia.fileList | Format-Table -AutoSize | write-debug
    $fileListPlan.fileList | Format-Table -AutoSize | write-debug

    close-session $sessionId | write-debug

    generate-rss-xml -plan "./bibleListenPlan.csv" -links $fileListMedia.fileList
    # $fileListPlan.fileList[0]

    # $PutFiles | format-table -AutoSize
    put-xml -USERNAME $UserName -PASSWORD $Password -fileList $PutFiles
}

$GbBaseURL="https://www.opendrive.com"


function generate-rss-xml() {
    param (
        $plan,
        $links
    )

    function xml-header() {
        param (
            $vSection
        )

            Write-Output @"
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
<channel>

    <atom:link href="$($GbBaseURL)/bible_pod" rel="self" type="application/rss+xml" />
    <title>Bible Zondervan TNIV$($vSection)</title>
    <link>$($GbBaseURL)/podcast.xml</link>
    <description>This is a Zondervan TNIV$($vSection)</description>
    <lastBuildDate>Sun, 01 Jan 2017 17:16:55 GMT</lastBuildDate>
    <language>en-us</language>
    <copyright>Copyright 2017 ©Jared Church</copyright>
    <itunes:subtitle></itunes:subtitle>
    <itunes:author>Jared Church</itunes:author>
    <itunes:summary>Bible$($vSection)</itunes:summary>
    <itunes:owner>
        <itunes:name>Jared Church</itunes:name>
        <itunes:email>pjaredchurch@gmail.com</itunes:email>
    </itunes:owner>
    <itunes:image href="$($GbBaseURL)" />
    <itunes:category text="Category1" />
    <itunes:category text="Category2">
        <itunes:category text="Subcategory" />
    </itunes:category>

"@
    }


    function xml-Body () {
        param (
            $data
        )
        # vDay=$(echo "${item}" | cut -d, -f1)
        # if [ ${vDay} -ne ${vPrevDay} ]
        # then
        #         j=0
        #         vPrevDay=${vDay}
        # fi

        # j=$(expr ${j} + 1)
        # i=$(expr ${i} + 1)
        # vBook=$(echo "${item}" | cut -d, -f2 | sed "s/{space}/ /g")
        # vD1=$(date -d ${gbYear}-01-01 +%s)
        # vD2=$(echo "${vD1} + (${vTimeAdjust} * 60 * 60) + 1 + (${j} * 60) + (60 * 60 * 24 * ${vDay})" | bc)
        # vDate=$(date -d @${vD2} -R)
        # vURL=$(find /var/www/html/bible/media2 -name "${vBook}" -print | cut -d/ -f 6-)

        # $links | format-table
        $link = ($links | Where-Object Name -eq $data.Chapter).DownloadLink

        write-debug "$($data)"
        write-output @"
    <item>
        <title>$($data.Chapter)</title>
        <link>$($link)</link>
        <itunes:author>Zondervan</itunes:author>
        <description>$($data.Chapter)</description>
        <itunes:summary>$($data.Chapter)</itunes:summary>
        <enclosure url="$($link)" length="filesize-in-bites" type="audio/mpeg" />
        <guid>$((get-date).Year)-$($data.current)-$($data.Chapter)</guid>
        <pubDate>$(get-date)</pubDate>
        <itunes:keywords>$($data.Chapter)</itunes:keywords>
        <category>Podcasts</category>
        <itunes:explicit>no</itunes:explicit>
    </item>
"@
    }



    function xml-footer () {
        write-output @"

    <itunes:explicit>no</itunes:explicit>
    </channel>
</rss>
"@
    }


    $data=(import-csv $plan | Where-Object current -ne '' | select-object Chapter,Category,current)

    # $data[0..10] | format-table

    $data.Category | Select-Object -Unique | ForEach-Object {
        & {
            xml-header
            ($data | where-object Category -eq $_) | ForEach-Object {
                xml-body -data $_
            }
            xml-footer
        } | out-file -encoding ascii "./tniv_$($_).xml"
    }

}


main -UserName $env:OPENDRIVE_USERNAME -Password $env:OPENDRIVE_PASSWORD



### End of File
