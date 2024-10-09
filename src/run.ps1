

function put-xml() {
    # Set environment variables for username and password
    $USERNAME = $env:WEBDAV_USERNAME
    $PASSWORD = $env:WEBDAV_PASSWORD

    # Define the WebDAV server URL and the file to update
    $SERVER_URL = "https://webdav.opendrive.com"
    $LOCAL_FILE_PATH = "./test3.xml"
    $REMOTE_FILE_PATH = "/bible_pod/rss/test2.xml"

    # Create a WebClient object
    $webclient = New-Object System.Net.WebClient
    $webclient.Credentials = New-Object System.Net.NetworkCredential($USERNAME, $PASSWORD)

    # Upload the file
    $webclient.UploadFile("$SERVER_URL$REMOTE_FILE_PATH", "PUT", $LOCAL_FILE_PATH)

    # Clean up
    $webclient.Dispose()
}

function write-xml() {


    # WebDAV interaction within a runner/codespace
    # this is probably a good method to avoid the issue with API upload that
    # I've had trouble working out.
    # name: WebDAV Interaction

    # on: [push]

    # jobs:
    #   webdav:
    #     runs-on: ubuntu-latest

    #     steps:
    #       - name: Checkout code
    #         uses: actions/checkout@v2

    #       - name: Install WebDAV client
    #         run: sudo apt-get install -y cadaver

    #       - name: Upload file to WebDAV
    #         run: |
    #           echo "Hello, WebDAV!" > hello.txt
    #           cadaver <<EOF
    #           open https://your-webdav-server.com
    #           put hello.txt
    #           EOF
    #         env:
    #           WEBDAV_USERNAME: ${{ secrets.WEBDAV_USERNAME }}
    #           WEBDAV_PASSWORD: ${{ secrets.WEBDAV_PASSWORD }}



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

    function test() {
    # Step 2: Find the file ID and get direct download links
    $folderId = "your_folder_id"
    $fileList = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/folder/list.json/$sessionId/$folderId" -Method Get

    # Extract file IDs and download links
    $fileDetails = $fileList | ForEach-Object {
        [PSCustomObject]@{
            FileID = $_.FileID
            Name = $_.Name
            DownloadLink = $_.DownloadLink
        }
    }

    # Display file details
    $fileDetails | Format-Table -AutoSize

    # Step 3: Update the file
    $fileId = ($fileDetails | Where-Object { $_.Name -eq "file_name" }).FileID
    $form = @{
        session_id = $sessionId
        file_id = $fileId
        file = Get-Item -Path "path_to_new_file"
    }

    Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/upload/file.json" -Method Post -Form $form


    # Get file by path
    $filePath = "path/to/your/file.txt"
    $searchResponse = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/file/search.json" -Method Post -Body @{
        session_id = $sessionId
        query = $filePath
    } -ContentType "application/json"

    $fileId = $searchResponse.FileID
    $downloadLink = $searchResponse.DownloadLink

    Write-Output "File ID: $fileId"
    Write-Output "Download Link: $downloadLink"



    # Get directory by path
    $directoryPath = "path/to/your/directory"
    $searchResponse = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/folder/search.json" -Method Post -Body @{
        session_id = $sessionId
        query = $directoryPath
    } -ContentType "application/json"

    # Extract directory ID
    $directoryId = $searchResponse.FolderID

    Write-Output "Directory ID: $directoryId"
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

        $directoryPath = "path/to/your/directory"
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


    function upload-file() {
        param (
            $SessionId,
            $FolderId,
            $SourceFile,
            $TargetFileName
        )

        if ( -not $TargetFileName ) {
            $TargetFileName=(get-item $SourceFile).PSChildName
        }
        
        $body=@{
            session_id = $sessionId 
            folder_id = $FolderId
            file_name = $TargetFileName
            open_if_exists = 1
        } | convertto-json

        $result = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/upload/create_file.json" -Method Post `
            -Body $body  -ContentType "application/json"

        write-debug "Create File: $($result)"
        $openFileRes="$($result)" | convertfrom-json




        $chunkSize = 10MB
        $fileStream = [System.IO.File]::OpenRead($SourceFile)
        $buffer = New-Object byte[] $chunkSize
        $chunkNumber = 0
        $totalBytesRead=0
        while (($bytesRead = $fileStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $prevChunkNum=$chunkNumber
            $chunkNumber++
            $chunk = [System.IO.MemoryStream]::new($buffer, 0, $bytesRead)
            $chunkBinary=[System.IO.StreamReader]::new($chunk)
            $byteArray = [System.Text.Encoding]::UTF8.GetBytes($chunkBinary)
            write-debug "Bytes Read Length: $($byteArray.Length)"
            $form = @{
                session_id = $sessionId
                file_data = $byteArray
                chunk_number = $chunkNumber
                temp_location = $openFileRes.TempLocation
                chunk_offset = $totalBytesRead
                chunk_size = $byteArray.Length
            }

            # $chunkBinary | select-object *
            write-debug "Upload form: $($form | convertto-json -depth 10)"
            $response = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/upload/upload_file_chunk2.json/$($sessionId)/$($openFileRes.FileId)" `
                -Method Post -Form $form
            Write-Output "Uploaded chunk $chunkNumber"
            $totalBytesRead+=$bytesRead.Length
        }

        $fileStream.Close()


        $body=@{
            session_id = $sessionId 
            file_id = $openFileRes.FileId
            file_size = (get-item $SourceFile).Length
            temp_location = $openFileRes.TempLocation
        } | convertto-json

        $result = Invoke-WebRequest -Uri "https://dev.opendrive.com/api/v1/upload/close_file_upload.json" -Method Post `
            -Body $body  -ContentType "application/json"

        write-debug "Close File Upload: $($result)"


    }


    ################################ SCRIPT ################################
    $DebugPreference = 'SilentlyContinue'
    # $DebugPreference = 'Continue'


    $sessionId=open-session -UserName $env:UserName -Password $env:Password

    # Get file listings for the two directories of interest (xml storage and media storage)
    $fileListRSS=get-filelist -Path 'bible_pod/rss' -SessionId $sessionId
    $fileListMedia=get-filelist -Path 'bible_pod/media' -SessionId $sessionId
    $fileListRSS.fileList | Format-Table -AutoSize | write-debug
    $fileListMedia.fileList | Format-Table -AutoSize | write-debug

    $DebugPreference = 'Continue'
    # Prep new xml files
    write-output "$(get-date)" | out-file test2.xml

    # create/update xml files on opendrive
    upload-file -SessionId $sessionId -FolderId $fileListRSS.FolderId -SourceFile "./test2.xml"

    $DebugPreference = 'SilentlyContinue'
    close-session $sessionId
}