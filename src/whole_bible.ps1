

function generate-xml-whole-bible() {
    param (
        $plan,
        $links,
        $images
    )

    $data=(import-csv $plan | Where-Object current -ne '' | select-object Chapter,current,Category,'Book Number','Length Seconds')

    $data | foreach {
        $_.current=1
        $_.'Book Number' = [int]($_.'Book Number')
        $_.'Length Seconds' = [int]$_.'Length Seconds'
        if ( @('Psalms','Proverbs','OT') -contains $_.Category ) {
            $_.Category='WOT'
        } else {
            $_.Category='WNT'
        }
    }
    $data=$data | sort-object -Property 'Book Number','Chapter' -Unique
    $data[0..60] | out-string | write-debug

    $data.Category | Select-Object -Unique | where-object { $_ -ne "" } | foreach-object {
        $allInCategory=$data | where-object Category -eq $_

        & {
            xml-header -vSection $_ -image $image.DownloadLink
            $allInCategory | ForEach-Object {
                $global:i++
                xml-body -data $_ -count $i -links $links
            }
            xml-footer
        } | out-file -encoding ascii "./tniv_$($_).xml"
    }

    $PutFiles=@(
        @{
            localPath='./tniv_WNT.xml'
            remotePath='/bible_pod/rss/tniv_WNT.xml'
        },
        @{
            localPath='./tniv_WOT.xml'
            remotePath='/bible_pod/rss/tniv_WOT.xml'
        }
    )

    $UserName=$env:OPENDRIVE_USERNAME
    $Password=$env:OPENDRIVE_PASSWORD

    # put-xml -USERNAME $UserName -PASSWORD $Password -fileList $PutFiles

}

### End of File
