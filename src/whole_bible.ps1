

function generate-xml-whole-bible() {
    param (
        $plan,
        $links,
        $images
    )

    $data=(import-csv $plan | Where-Object current -ne '' | select-object Chapter,Category,'Book Number','Length Seconds')

    $data | foreach {
        $_.'Book Number' = [int]($_.'Book Number')
        $_.Category='Bible'
        $_.'Length Seconds' = [int]$_.'Length Seconds'
    }
    $data=$data | sort-object -Property 'Book Number','Chapter' -Unique
    $data[0..60] | out-string | write-debug

    "Bible" | foreach-object {
        & {
            xml-header -vSection $_ -image $image.DownloadLink
            $data | ForEach-Object {
                $global:i++
                xml-body -data $_ -count $i -links $links
            }
            xml-footer
        } | out-file -encoding ascii "./tniv_$($_).xml"
    }

    $PutFiles=@(@{
        localPath='./tniv_Bible.xml'
        remotePath='/bible_pod/rss/tniv_Bible.xml'
    })

    $UserName=$env:OPENDRIVE_USERNAME
    $Password=$env:OPENDRIVE_PASSWORD

    put-xml -USERNAME $UserName -PASSWORD $Password -fileList $PutFiles
}

### End of File
