#######################################################################
#
#   FileName: opendrive.ps1
#
#   Purpose:
#       OpenDrive API client functions for file operations.
#       Provides functions for session management, file listing,
#       file downloads, and file uploads via OpenDrive's REST API
#       and WebDAV interface.
#
#######################################################################

# Upload local XML files to OpenDrive server via WebDAV
# Takes username, password, and list of files with local and remote paths
function put-xml() {
    param (
        $USERNAME,
        $PASSWORD,
        $FileList=@()
    )

    # Debug: display the file list being uploaded
    $FileList | format-table -AutoSize | out-string | write-debug

    # Create WebClient with network credentials for authentication
    $webclient = New-Object System.Net.WebClient
    $webclient.Credentials = New-Object System.Net.NetworkCredential($USERNAME, $PASSWORD)

    # Upload each file in the list to its specified remote path
    $FileList | ForEach-Object {
        $remotePath="$($webDavBaseURL)$($_.remotePath)"
        write-debug "Upload $($_.localPath) to $($remotePath)"
        $webclient.UploadFile("$remotePath", "PUT", $_.localPath)
    }
    # Clean up WebClient resources
    $webclient.Dispose()
}

# Closes an active OpenDrive session
# Required to properly clean up server-side session state
function close-session() {
    param (
        [Parameter(Mandatory=$true)]
        [string]$sessionId
    )

    # Build request body with session ID
    $body=@{
        session_id = $sessionId
    } | convertto-json

    # Call logout endpoint to close session
    $response = Invoke-WebRequest -Uri "$($apiBaseURL)/session/logout.json" -Method Post -Body $body -ContentType "application/json"

    write-debug $response
    if ( ("$($response)" | convertfrom-json).result -eq $True ) {
        Write-Output "Session closed successfully."
    } else {
        Write-Output "Failed to close session."
    }

}

# Opens a new session with OpenDrive using username and password
# Returns the session ID needed for subsequent API calls
function open-session() {
    param (
        [Parameter(Mandatory=$true)]
        [string]$UserName,
        [Parameter(Mandatory=$true)]
        [string]$Password
    )

    # Build login request body with credentials
    $body=@{
        username = $UserName
        passwd = $Password
    } | convertto-json

    # Call login API endpoint
    $loginResponse = Invoke-WebRequest -Uri "$($apiBaseURL)/session/login.json" -Method Post `
        -Body $body -ContentType "application/json"

    write-debug $loginResponse
    # Extract and return the session ID from the response
    $sessionId = ( "$($loginResponse)" | convertfrom-json).SessionID
    return $sessionId
}

# Lists files in a specified directory on OpenDrive
# Returns folder ID and list of files with metadata (ID, name, links, size)
function get-filelist() {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$SessionId
    )

    # First, get the directory ID by path
    $body=@{
        session_id = $SessionId
        path = $Path
    } | convertto-json

    write-debug $body
    $searchResponse = Invoke-WebRequest -Uri "$($apiBaseURL)/folder/idbypath.json" -Method Post -Body $body -ContentType "application/json"

    write-debug $searchResponse
    # Extract directory ID from response
    $directoryId = ($searchResponse | convertfrom-json).FolderId
    write-debug "Directory ID: $($directoryId)"

    # Get file list for the directory using the folder ID
    $fileList = Invoke-WebRequest -Uri "$($apiBaseURL)/folder/list.json/$sessionId/$directoryId" -Method Get

    # Extract relevant file metadata from the response
    $fileDetails = ($fileList | convertfrom-json).Files | select-object FileId,Name,StreamingLink,DownloadLink,Size

    # Build and return structured response object
    $retObject=[PSCustomObject]@{
        FolderId=$directoryId
        fileList=$fileDetails
    }

    $retObject.fileList | out-string | write-debug

    return $retObject
}

# Legacy function for downloading files using wget
function get-file-old() {
    param (
        [PSCustomObject]$file
    )

    wget $file.DownloadLink --output-document="$($file.Name)" --quiet
}

# Downloads a file from OpenDrive using the file ID
# Saves the file to the local filesystem with its original name
function get-file() {
    param (
        $SessionId,
        [PSCustomObject]$file
    )

    $body=@{
        session_id = $SessionId
        file_id = $Path
    } | convertto-json

    # Construct download URL and fetch the file
    $url="$($apiBaseURL)/download/file.json/$($file.FileId)"

    Invoke-WebRequest -Uri $url -Method GET -Body $body -ContentType "application/json" -OutFile $file.Name
}



### End of File
