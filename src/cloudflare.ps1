#######################################################################
#
#   FileName: cloudflare.ps1
#
#   Purpose:
#       Cloudflare R2 client functions (S3 compatible API, SigV4 signed).
#       Provides bucket connection from environment variables, object
#       listing, and expiring pre-signed URL generation.
#       Object records are shaped like the OpenDrive records so rss.ps1
#       can consume either backend unchanged.
#
#######################################################################

# R2 only accepts "auto" as the SigV4 region, and "s3" as the service name.
# Both are fixed rather than configurable so a call site cannot accidentally
# produce a signature R2 rejects with an opaque 403.
$script:r2Region="auto"
$script:r2Service="s3"

# Bucket holding the TNIV media and cover art.
$script:r2DefaultBucket="zondervan-tniv"

# Default lifetime of a pre-signed link. The feeds are regenerated daily, so
# links only need to outlive one podcast client refresh cycle; anything longer
# just widens the window in which a leaked URL stays usable.
$script:r2DefaultLinkExpireHours=36

# R2 rejects a pre-signed URL asking for more than 7 days.
$script:r2MaxLinkExpireSeconds=604800

$script:r2UnsignedPayload="UNSIGNED-PAYLOAD"


# Hex encodes a byte array. Used for every digest and signature so they can go
# into the lower-case hex form AWS SigV4 specifies.
function convert-to-hex() {
    param (
        [byte[]]$Bytes
    )

    return -join ($Bytes | ForEach-Object { $_.ToString("x2") })
}

# Returns the lower-case hex SHA256 of a UTF-8 string
function get-sha256() {
    param (
        [string]$Text
    )

    $sha=[System.Security.Cryptography.SHA256]::Create()
    try {
        return convert-to-hex ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))
    } finally {
        $sha.Dispose()
    }
}

# HMAC-SHA256 returning raw bytes, since chaining the key derivation needs the
# unencoded result rather than hex
function get-hmac() {
    param (
        [byte[]]$Key,
        [string]$Text
    )

    $hmac=[System.Security.Cryptography.HMACSHA256]::new($Key)
    try {
        return $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
    } finally {
        $hmac.Dispose()
    }
}

# Derives the date/region/service scoped signing key described by the SigV4
# specification
function get-signing-key() {
    param (
        [string]$SecretKey,
        [string]$DateStamp
    )

    $key=[System.Text.Encoding]::UTF8.GetBytes("AWS4$($SecretKey)")
    $key=get-hmac -Key $key -Text $DateStamp
    $key=get-hmac -Key $key -Text $script:r2Region
    $key=get-hmac -Key $key -Text $script:r2Service
    $key=get-hmac -Key $key -Text "aws4_request"
    return $key
}

# Returns a map's keys sorted the way SigV4 requires: ordinal, not the
# culture-aware ordering Sort-Object applies by default. Culture ordering can
# disagree on where punctuation sorts relative to letters, which would produce a
# different canonical string from every other SigV4 implementation.
function get-sorted-keys() {
    param (
        [hashtable]$Map
    )

    $keys=[string[]]@($Map.Keys)
    [Array]::Sort($keys,[System.StringComparer]::Ordinal)
    return $keys
}

# Builds a SigV4 canonical request from a header map
function get-canonical-request() {
    param (
        [string]$Method,
        [string]$Path,
        [string]$Query,
        [hashtable]$Headers,
        [string]$PayloadHash
    )

    $names=get-sorted-keys $Headers
    $canonicalHeaders=($names | ForEach-Object { "$_`:$($Headers[$_])`n" }) -join ''

    # Uppercased because SigV4 signs the verb literally: PowerShell hands a
    # bareword Get through as "Get", which would silently change the digest.
    return @(
        $Method.ToUpperInvariant()
        $Path
        $Query
        $canonicalHeaders
        ($names -join ';')
        $PayloadHash
    ) -join "`n"
}

# Percent encodes a value for use in a canonical URI path or query string,
# matching the RFC 3986 encoding SigV4 requires
function convert-to-uri-encode() {
    param (
        [string]$Text
    )

    return [System.Uri]::EscapeDataString($Text)
}

# Percent encodes an object key into a canonical URI path. Slashes are kept
# literal because SigV4 signs the path with its structure intact.
function convert-to-uri-path() {
    param (
        [string]$Key
    )

    return ((convert-to-uri-encode $Key) -replace '%2F','/')
}

# Serialises a parameter map into a canonical query string: percent encoded,
# sorted by name, joined with bare '&'
function get-canonical-query() {
    param (
        [hashtable]$Parameters
    )

    $names=get-sorted-keys $Parameters
    return ($names | ForEach-Object { "$_=$(convert-to-uri-encode $Parameters[$_])" }) -join '&'
}

# Produces the "AWS4-HMAC-SHA256 ..." Authorization header for a signed request.
# The date is read from $Headers rather than generated here, so the value that
# gets signed is guaranteed to be the value that goes on the wire.
function get-authorization-header() {
    param (
        $Connection,
        [string]$Method,
        [string]$Path,
        [string]$Query,
        [hashtable]$Headers,
        [string]$PayloadHash
    )

    if ( -not $Headers.ContainsKey("x-amz-date") ) {
        throw "Cannot sign request: x-amz-date is missing from the signed headers"
    }

    $amzDate=$Headers["x-amz-date"]
    $dateStamp=$amzDate.Substring(0,8)

    $canonicalRequest=get-canonical-request -Method $Method -Path $Path -Query $Query -Headers $Headers -PayloadHash $PayloadHash
    $scope="$dateStamp/$($script:r2Region)/$($script:r2Service)/aws4_request"
    $stringToSign="AWS4-HMAC-SHA256`n$($amzDate)`n$($scope)`n$(get-sha256 $canonicalRequest)"
    $signature=convert-to-hex (get-hmac -Key (get-signing-key -SecretKey $Connection.SecretKey -DateStamp $dateStamp) -Text $stringToSign)
    $signedHeaders=(get-sorted-keys $Headers) -join ';'

    return "AWS4-HMAC-SHA256 Credential=$($Connection.AccessKeyId)/$($scope), SignedHeaders=$($signedHeaders), Signature=$($signature)"
}

# Validates credentials and endpoint, returning a connection object used by the
# other functions. Every variable is checked up front with the name of the
# missing variable in the error, because an empty access key surfaces from R2 as
# an unhelpful 403 rather than as a missing configuration problem.
function get-r2-connection() {
    param (
        [string]$Bucket,
        [string]$Endpoint
    )

    if ( [string]::IsNullOrWhiteSpace($Bucket) ) {
        $Bucket=$script:r2DefaultBucket
    }
    if ( [string]::IsNullOrWhiteSpace($Endpoint) ) {
        $Endpoint=$env:CLOUDFLARE_R2_URL
    }

    $missing=@()
    if ( [string]::IsNullOrWhiteSpace($env:CLOUDFLARE_BIBLE_POD_ACCESS_KEY_ID) ) {
        $missing+="CLOUDFLARE_BIBLE_POD_ACCESS_KEY_ID"
    }
    if ( [string]::IsNullOrWhiteSpace($env:CLOUDFLARE_BIBLE_POD_SECRET_ACCESS_KEY) ) {
        $missing+="CLOUDFLARE_BIBLE_POD_SECRET_ACCESS_KEY"
    }
    if ( [string]::IsNullOrWhiteSpace($Endpoint) ) {
        $missing+="CLOUDFLARE_R2_URL"
    }

    if ( $missing.Length -gt 0 ) {
        throw "Cloudflare R2 is not configured; missing: $($missing -join ', '). Populate them with: source ./.env.sh"
    }

    $uri=[uri]$Endpoint
    if ( -not $uri.IsAbsoluteUri -or $uri.Scheme -ne "https" ) {
        throw "CLOUDFLARE_R2_URL must be an absolute https URL, got '$Endpoint'"
    }

    # Tolerates the bucket already being present in the supplied URL, so either
    # form of the secret works without the caller having to know which was set.
    $path=$uri.AbsolutePath.TrimEnd('/')
    if ( $path -notmatch "/$([regex]::Escape($Bucket))/?$" ) {
        $path="$path/$($Bucket)"
    }

    return [PSCustomObject]@{
        AccessKeyId=$env:CLOUDFLARE_BIBLE_POD_ACCESS_KEY_ID
        SecretKey=$env:CLOUDFLARE_BIBLE_POD_SECRET_ACCESS_KEY
        Bucket=$Bucket
        BaseURL="$($uri.Scheme)://$($uri.Authority)$($path)"
        Host=$uri.Authority
        # SigV4 signs the canonical URI of the request, which in path style
        # includes the bucket. Kept separately so signing cannot accidentally
        # omit it, which R2 would reject as SignatureDoesNotMatch.
        PathPrefix=$path
    }
}

# Issues a SigV4 signed request against the bucket and returns the status code
# and body.
#
# HttpClient rather than Invoke-WebRequest: PowerShell parses the Authorization
# header as an auth scheme plus token and rejects the SigV4 value, which
# legitimately contains '=', ',', ';' and '/'. TryAddWithoutValidation sends it
# verbatim, which is what a signed request requires.
function invoke-r2-request() {
    param (
        $Connection,
        [string]$Method="GET",
        [string]$Path,
        [hashtable]$Query
    )

    $canonicalQuery=get-canonical-query $Query
    $requestPath="$($Connection.PathPrefix)$($Path)"

    # x-amz-date is included in the signed headers so the value that is signed
    # is the value sent, rather than one regenerated during serialisation.
    $headers=@{
        "host"=$Connection.Host
        "x-amz-content-sha256"=$script:r2UnsignedPayload
        "x-amz-date"=(Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    }

    $authorization=get-authorization-header -Connection $Connection -Method $Method -Path $requestPath -Query $canonicalQuery -Headers $headers -PayloadHash $script:r2UnsignedPayload

    $uri="$($Connection.BaseURL)$($Path)"
    if ( $canonicalQuery ) {
        $uri="$uri`?$($canonicalQuery)"
    }

    $client=[System.Net.Http.HttpClient]::new()
    try {
        $request=[System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $uri)
        foreach ( $name in get-sorted-keys $headers ) {
            $request.Headers.TryAddWithoutValidation($name, $headers[$name]) | Out-Null
        }
        $request.Headers.TryAddWithoutValidation("Authorization", $authorization) | Out-Null

        $response=$client.Send($request)
        $body=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

        if ( -not $response.IsSuccessStatusCode ) {
            # The S3 error body names the failing element (SignatureDoesNotMatch,
            # InvalidAccessKeyId, ...), which is far more useful than the status
            # code alone, so it is surfaced rather than discarded.
            throw "R2 request $Method $requestPath failed with HTTP $([int]$response.StatusCode): $body"
        }

        return [PSCustomObject]@{
            StatusCode=[int]$response.StatusCode
            Content=$body
        }
    } finally {
        $client.Dispose()
    }
}

# Lists every object under a prefix, following continuation tokens so buckets
# larger than a single 1000 key page are fully enumerated. Returns records
# shaped like the OpenDrive file list: Name, StreamingLink, DownloadLink, Size.
function get-r2-filelist() {
    param (
        [string]$Prefix,
        [int]$LinkExpireHours=$script:r2DefaultLinkExpireHours,
        [string]$Bucket,
        [string]$Endpoint
    )

    $connection=get-r2-connection -Bucket $Bucket -Endpoint $Endpoint

    if ( $LinkExpireHours -gt 0 ) {
        $expireSeconds=$LinkExpireHours * 3600
        if ( $expireSeconds -gt $script:r2MaxLinkExpireSeconds ) {
            write-warning "Requested link lifetime of $LinkExpireHours h exceeds the R2 maximum; clamped to 7 days"
            $expireSeconds=$script:r2MaxLinkExpireSeconds
        }
    } else {
        # Zero or negative means non-expiring, which R2 rejects, so fall back
        # to the default rather than emitting links that 403 an hour later.
        $expireSeconds=$script:r2DefaultLinkExpireHours * 3600
    }

    $contents=@()
    $token=$null
    do {
        $query=@{
            "list-type"="2"
            "max-keys"="1000"
        }
        if ( $Prefix ) {
            $query["prefix"]=$Prefix
        }
        if ( $token ) {
            $query["continuation-token"]=$token
        }

        $response=invoke-r2-request -Connection $connection -Method GET -Path "/" -Query $query
        $xml=[xml]$response.Content

        # Namespace-qualified so local-name() is used throughout: the S3
        # response namespace is not something callers should have to know, and
        # it is omitted by some S3-compatible implementations.
        $contents+=@($xml.SelectNodes("//*[local-name()='Contents']") | ForEach-Object {
            $node=$_
            # A key ending in '/' is a directory placeholder, not an object
            $key=($node.SelectSingleNode("./*[local-name()='Key']")).InnerText
            $size=($node.SelectSingleNode("./*[local-name()='Size']")).InnerText
            [PSCustomObject]@{
                Key=$key
                Size=[long]$size
                Modified=($node.SelectSingleNode("./*[local-name()='LastModified']")).InnerText
            }
        })

        $truncated=($xml.SelectSingleNode("//*[local-name()='IsTruncated']")).InnerText
        $nextNode=$xml.SelectSingleNode("//*[local-name()='NextContinuationToken']")
        $token=if ( $truncated -eq "true" -and $nextNode ) { $nextNode.InnerText } else { $null }
    } while ( $token )

    $files=$contents | Where-Object { -not $_.Key.EndsWith('/') } | Sort-Object Key | ForEach-Object {
        $slash=$_.Key.LastIndexOf('/')
        $name=if ( $slash -ge 0 ) { $_.Key.Substring($slash + 1) } else { $_.Key }

        $link=get-r2-presigned-url -Connection $connection -Key $_.Key -ExpireSeconds $expireSeconds

        [PSCustomObject]@{
            Name=$name
            Path=$_.Key
            Size=$_.Size
            Modified=$_.Modified
            # Both are the same pre-signed URL: OpenDrive offered distinct
            # streaming and download links, but a pre-signed R2 URL serves both
            # roles, and rss.ps1 consumes StreamingLink for enclosures and
            # DownloadLink for the channel image.
            StreamingLink=$link
            DownloadLink=$link
        }
    }

    # rss.ps1 matches objects by file name alone, so a name appearing under two
    # different folders would make the chosen file depend on listing order.
    $duplicates=$files | Group-Object Name | Where-Object Count -gt 1
    foreach ( $duplicate in $duplicates ) {
        write-warning "Bucket $($connection.Bucket) has $($duplicate.Count) objects named '$($duplicate.Name)': $($duplicate.Group.Path -join ', '). Using the first."
    }

    $retObject=[PSCustomObject]@{
        FolderId=$Prefix
        Bucket=$connection.Bucket
        fileList=@($files | Group-Object Name | ForEach-Object { $_.Group[0] })
    }

    "$($retObject.fileList.Count) objects under '$Prefix' in $($retObject.Bucket)" | write-debug
    $retObject.fileList | out-string | write-debug

    return $retObject
}

# Builds a pre-signed GET URL for an object. The signature is pure local HMAC
# arithmetic, so generating a link costs no network round trip; only the
# listing above talks to R2.
function get-r2-presigned-url() {
    param (
        $Connection,
        [string]$Key,
        [int]$ExpireSeconds=($script:r2DefaultLinkExpireHours * 3600)
    )

    $timestamp=(Get-Date).ToUniversalTime()
    $amzDate=$timestamp.ToString("yyyyMMddTHHmmssZ")
    $dateStamp=$amzDate.Substring(0,8)
    $scope="$dateStamp/$($script:r2Region)/$($script:r2Service)/aws4_request"

    $query=@{
        "X-Amz-Algorithm"="AWS4-HMAC-SHA256"
        "X-Amz-Credential"="$($Connection.AccessKeyId)/$($scope)"
        "X-Amz-Date"=$amzDate
        "X-Amz-Expires"=$ExpireSeconds
        "X-Amz-SignedHeaders"="host"
    }
    $canonicalQuery=get-canonical-query $query

    $canonicalRequest=get-canonical-request `
        -Method GET `
        -Path "$($Connection.PathPrefix)/$(convert-to-uri-path $Key)" `
        -Query $canonicalQuery `
        -Headers @{ "host"=$Connection.Host } `
        -PayloadHash $script:r2UnsignedPayload

    $stringToSign="AWS4-HMAC-SHA256`n$($amzDate)`n$($scope)`n$(get-sha256 $canonicalRequest)"
    $signature=convert-to-hex (get-hmac -Key (get-signing-key -SecretKey $Connection.SecretKey -DateStamp $dateStamp) -Text $stringToSign)

    # Signature appended after signing: it must not appear in the string that
    # was signed.
    return "$($Connection.BaseURL)/$(convert-to-uri-path $Key)?$($canonicalQuery)&X-Amz-Signature=$($signature)"
}

# Returns a pre-signed URL for downloading an object to a local file
function get-r2-file() {
    param (
        [string]$Name,
        [string]$Path,
        [string]$Bucket,
        [string]$Endpoint,
        [int]$LinkExpireHours=$script:r2DefaultLinkExpireHours
    )

    $connection=get-r2-connection -Bucket $Bucket -Endpoint $Endpoint
    if ( -not $Path ) {
        $Path=$Name
    }

    $url=get-r2-presigned-url -Connection $connection -Key $Path -ExpireSeconds ($LinkExpireHours * 3600)
    Invoke-WebRequest -Uri $url -OutFile $Name
}



### End of File