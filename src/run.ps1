
$DebugPreference = 'Continue'


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
    $FileList | foreach {
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

            echo @"
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
        $link = ($links | ? Name -eq $data.Chapter).DownloadLink

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


    $data=(import-csv $plan | ? current -ne '' | select-object Chapter,Category,current)

    $data[0..10] | format-table

    $category=""
    $data.Category | Select-Object -Unique | foreach {
        & {
            xml-header
            ($data | ? Category -eq $_)[0..1] | foreach {
                xml-body -data $_
            }
            xml-footer
        } | out-file -encoding ascii "./tniv_$($_).xml"
    }

}


# test
main -UserName $env:UserName -Password $env:Password




# function write-xml() {


#     # WebDAV interaction within a runner/codespace
#     # this is probably a good method to avoid the issue with API upload that
#     # I've had trouble working out.
#     # name: WebDAV Interaction

#     # on: [push]

#     # jobs:
#     #   webdav:
#     #     runs-on: ubuntu-latest

#     #     steps:
#     #       - name: Checkout code
#     #         uses: actions/checkout@v2

#     #       - name: Install WebDAV client
#     #         run: sudo apt-get install -y cadaver

#     #       - name: Upload file to WebDAV
#     #         run: |
#     #           echo "Hello, WebDAV!" > hello.txt
#     #           cadaver <<EOF
#     #           open https://your-webdav-server.com
#     #           put hello.txt
#     #           EOF
#     #         env:
#     #           WEBDAV_USERNAME: ${{ secrets.WEBDAV_USERNAME }}
#     #           WEBDAV_PASSWORD: ${{ secrets.WEBDAV_PASSWORD }}




#     function test() {
#     # Step 2: Find the file ID and get direct download links
#     $folderId = "your_folder_id"
#     $fileList = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/folder/list.json/$sessionId/$folderId" -Method Get

#     # Extract file IDs and download links
#     $fileDetails = $fileList | ForEach-Object {
#         [PSCustomObject]@{
#             FileID = $_.FileID
#             Name = $_.Name
#             DownloadLink = $_.DownloadLink
#         }
#     }

#     # Display file details
#     $fileDetails | Format-Table -AutoSize

#     # Step 3: Update the file
#     $fileId = ($fileDetails | Where-Object { $_.Name -eq "file_name" }).FileID
#     $form = @{
#         session_id = $sessionId
#         file_id = $fileId
#         file = Get-Item -Path "path_to_new_file"
#     }

#     Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/upload/file.json" -Method Post -Form $form


#     # Get file by path
#     $filePath = "path/to/your/file.txt"
#     $searchResponse = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/file/search.json" -Method Post -Body @{
#         session_id = $sessionId
#         query = $filePath
#     } -ContentType "application/json"

#     $fileId = $searchResponse.FileID
#     $downloadLink = $searchResponse.DownloadLink

#     Write-Output "File ID: $fileId"
#     Write-Output "Download Link: $downloadLink"



#     # Get directory by path
#     $directoryPath = "path/to/your/directory"
#     $searchResponse = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/folder/search.json" -Method Post -Body @{
#         session_id = $sessionId
#         query = $directoryPath
#     } -ContentType "application/json"

#     # Extract directory ID
#     $directoryId = $searchResponse.FolderID

#     Write-Output "Directory ID: $directoryId"
#     }


#     function get-filelist() {
#         param (
#             [Parameter(Mandatory=$true)]
#             [string]$Path,
#             [Parameter(Mandatory=$true)]
#             [string]$SessionId
#         )

#         # Get directory id
#         $body=@{
#             session_id = $SessionId
#             path = $Path
#         } | convertto-json

#         $directoryPath = "path/to/your/directory"
#         $searchResponse = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/folder/idbypath.json" -Method Post -Body $body -ContentType "application/json"

#         write-debug $searchResponse
#         # Extract directory ID
#         $directoryId = ($searchResponse | convertfrom-json).FolderId
#         write-debug "Directory ID: $($directoryId)"

#         # Get & Structure FileList
#         $fileList = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/folder/list.json/$sessionId/$directoryId" -Method Get

#         write-debug "FileList: $($fileList)"
#         # Extract file IDs and download links
#         $fileDetails = ($fileList | convertfrom-json).Files | ForEach-Object {
#             [PSCustomObject]@{
#                 FileID = $_.FileId
#                 Name = $_.Name
#                 DownloadLink = $_.DownloadLink
#             }
#         }

#         $retObject=[PSCustomObject]@{
#             FolderId=$directoryId
#             fileList=$fileDetails
#         }

#         return $retObject
#     }


#     function upload-file() {
#         param (
#             $SessionId,
#             $FolderId,
#             $SourceFile,
#             $TargetFileName
#         )

#         if ( -not $TargetFileName ) {
#             $TargetFileName=(get-item $SourceFile).PSChildName
#         }
        
#         $body=@{
#             session_id = $sessionId 
#             folder_id = $FolderId
#             file_name = $TargetFileName
#             open_if_exists = 1
#         } | convertto-json

#         $result = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/upload/create_file.json" -Method Post `
#             -Body $body  -ContentType "application/json"

#         write-debug "Create File: $($result)"
#         $openFileRes="$($result)" | convertfrom-json




#         $chunkSize = 10MB
#         $fileStream = [System.IO.File]::OpenRead($SourceFile)
#         $buffer = New-Object byte[] $chunkSize
#         $chunkNumber = 0
#         $totalBytesRead=0
#         while (($bytesRead = $fileStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
#             $prevChunkNum=$chunkNumber
#             $chunkNumber++
#             $chunk = [System.IO.MemoryStream]::new($buffer, 0, $bytesRead)
#             $chunkBinary=[System.IO.StreamReader]::new($chunk)
#             $byteArray = [System.Text.Encoding]::UTF8.GetBytes($chunkBinary)
#             write-debug "Bytes Read Length: $($byteArray.Length)"
#             $form = @{
#                 session_id = $sessionId
#                 file_data = $byteArray
#                 chunk_number = $chunkNumber
#                 temp_location = $openFileRes.TempLocation
#                 chunk_offset = $totalBytesRead
#                 chunk_size = $byteArray.Length
#             }

#             # $chunkBinary | select-object *
#             write-debug "Upload form: $($form | convertto-json -depth 10)"
#             $response = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/upload/upload_file_chunk2.json/$($sessionId)/$($openFileRes.FileId)" `
#                 -Method Post -Form $form
#             Write-Output "Uploaded chunk $chunkNumber"
#             $totalBytesRead+=$bytesRead.Length
#         }

#         $fileStream.Close()


#         $body=@{
#             session_id = $sessionId 
#             file_id = $openFileRes.FileId
#             file_size = (get-item $SourceFile).Length
#             temp_location = $openFileRes.TempLocation
#         } | convertto-json

#         $result = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/upload/close_file_upload.json" -Method Post `
#             -Body $body  -ContentType "application/json"

#         write-debug "Close File Upload: $($result)"


#     }


#     ################################ SCRIPT ################################
#     $DebugPreference = 'SilentlyContinue'
#     # $DebugPreference = 'Continue'


#     $sessionId=open-session -UserName $env:UserName -Password $env:Password

#     # Get file listings for the two directories of interest (xml storage and media storage)
#     $fileListRSS=get-filelist -Path 'bible_pod/rss' -SessionId $sessionId
#     $fileListMedia=get-filelist -Path 'bible_pod/media' -SessionId $sessionId
#     $fileListRSS.fileList | Format-Table -AutoSize | write-debug
#     $fileListMedia.fileList | Format-Table -AutoSize | write-debug

#     $DebugPreference = 'Continue'
#     # Prep new xml files
#     write-output "$(get-date)" | out-file test2.xml

#     # create/update xml files on opendrive
#     upload-file -SessionId $sessionId -FolderId $fileListRSS.FolderId -SourceFile "./test2.xml"

#     $DebugPreference = 'SilentlyContinue'
#     close-session $sessionId
# }

$DebugPreference = 'SilentlyContinue'

### End of File
