#######################################################################
#
#   FileName: opendrive.ps1
#
#   Purpose:
#       Updates RSS Feed
#
#######################################################################



function put-xml() {
    # localPath must be based on root of work - is a little complex to figure out I think.
    # will figure it out at some point
    param (
    # Set environment variables for username and password
        $USERNAME,
        $PASSWORD,
        $FileList=@()
    )

    $FileList | format-table -AutoSize | out-string | write-debug

    # Create a WebClient object
    $webclient = New-Object System.Net.WebClient
    $webclient.Credentials = New-Object System.Net.NetworkCredential($USERNAME, $PASSWORD)

    # Upload the file
    $FileList | ForEach-Object {
        $remotePath="$($webDavBaseURL)$($_.remotePath)"
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

    $response = Invoke-WebRequest -Uri "$($apiBaseURL)/session/logout.json" -Method Post -Body $body -ContentType "application/json"

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

    $loginResponse = Invoke-WebRequest -Uri "$($apiBaseURL)/session/login.json" -Method Post `
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
    $searchResponse = Invoke-WebRequest -Uri "$($apiBaseURL)/folder/idbypath.json" -Method Post -Body $body -ContentType "application/json"

    write-debug $searchResponse
    # Extract directory ID
    $directoryId = ($searchResponse | convertfrom-json).FolderId
    write-debug "Directory ID: $($directoryId)"

    # Get & Structure FileList
    $fileList = Invoke-WebRequest -Uri "$($apiBaseURL)/folder/list.json/$sessionId/$directoryId" -Method Get

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


function get-file() {
    param (
        [PSCustomObject]$file
    )

    wget $file.DownloadLink --output-document="$($file.Name)" --quiet
}




### End of File
