#######################################################################
#
#   FileName: rss.ps1
#
#   Purpose:
#       Updates RSS Feed
#
#######################################################################

$apiBaseURL="https://dev.opendrive.com/api/v1"
$webBaseURL="https://www.opendrive.com"
$webDavBaseURL="https://webdav.opendrive.com"

$rssFooter=@"

        <itunes:explicit>no</itunes:explicit>
    </channel>
</rss>
"@

$rssHeader=@"
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
    <channel>

        <atom:link href="{{webBaseURL}}/bible_pod/rss" rel="self" type="application/rss+xml" />
        <title>Bible - Zondervan TNIV {{section}}</title>
        <link>{{webBaseURL}}/bible_pod/rss</link>
        <description>This is a Zondervan TNIV {{section}}</description>
        <lastBuildDate>Sun, 01 Jan 2017 17:16:55 GMT</lastBuildDate>
        <language>en-us</language>
        <copyright>Audio Copyright &copy; Zondervan</copyright>
        <itunes:subtitle></itunes:subtitle>
        <itunes:author>Jared Church</itunes:author>
        <itunes:summary>Bible {{section}}</itunes:summary>
        <itunes:owner>
            <itunes:name>Jared Church</itunes:name>
            <itunes:email>pjaredchurch@gmail.com</itunes:email>
        </itunes:owner>
        <itunes:image href="{{image}}" />
"@
# <itunes:category text="Category1" />
# <itunes:category text="Category2">
#     <itunes:category text="Subcategory" />
# </itunes:category>


$rssItem=@"
            <item>
                <title>{{title}}</title>
                <link>{{link}}</link>
                <itunes:author>Zondervan</itunes:author>
                <description><![CDATA[{{description}} <br /><br /><br />&copy; 2005 Zondervan]]></description>
                <itunes:summary>{{summary}}</itunes:summary>
                <enclosure url="{{link}}" length="{{size-bytes}}" type="audio/mpeg" />
                <guid>{{guid}}</guid>
                <pubDate>{{pubDate}}</pubDate>
                <itunes:keywords>{{keywords}}</itunes:keywords>
                <category>Podcasts</category>
                <itunes:explicit>no</itunes:explicit>
                <itunes:duration>{{duration}}</itunes:duration>
            </item>
"@



function get-publication-date() {
    param (
        $DayOfYear,
        $seconds
    )

    $date = ([datetime]::new(((get-date).Year),1,1).AddDays($DayOfYear -1).AddSeconds($seconds)).ToString("ddd, dd MMMM yyyy HH:mm:ss zzz")

    return $date
}

function xml-header() {
    param (
        $vSection,
        $image
    )

        write-output ("$($rssHeader)" `
            -replace '{{webBaseURL}}',$webBaseURL `
            -replace '{{section}}',$vSection `
            -replace '{{image}}',$image
        )

}


function xml-footer () {
    write-output $rssFooter
}

function xml-Body () {
    param (
        $data,
        [Int]$count,
        $links
    )

    $fileInfo = ($links | Where-Object Name -eq $data.Chapter)
    $fileInfo | format-table | out-string | write-debug

    $string=(
        "$($rssItem)" `
            -replace '{{title}}',$data.Chapter `
            -replace '{{link}}',$fileInfo.DownloadLink `
            -replace '{{description}}',$data.Chapter `
            -replace '{{summary}}',$data.Chapter `
            -replace '{{size-bytes}}',$fileInfo.Size `
            -replace '{{guid}}', "$((get-date).Year)-$($data.current)-$($data.Chapter)" `
            -replace '{{pubDate}}',(get-publication-date -DayOfYear $data.current -seconds $count) `
            -replace '{{keywords}}',$data.Chapter `
            -replace '{{duration}}',$data.'Length Seconds'
    )

    write-output "$($string)"

}



function generate-rss-xml() {
    param (
        $plan,
        $links,
        $images
    )


    $data=(import-csv $plan | Where-Object current -ne '' | select-object Chapter,Category,current,'Length Seconds')
    $data[0..5] | format-table | out-string | write-debug
    $data | ForEach-Object {
        $_.current = [int]$_.current
        $_.'Length Seconds' = [int]$_.'Length Seconds'
    }

    $global:i=0

    $data.Category | Select-Object -Unique | where-object { $_ -ne "" }| ForEach-Object {
        $image=$images | where-object Name -like "*$($_).jpg"

        $allInCategory=$data | where-object Category -eq $_
        $dataFilterSort = $allInCategory | where-object current -le ((get-date).DayOfYear) | sort-object current,Chapter
        $dataFilterSort[-10..-1] | write-debug
        write-output "$($_):$($dataFilterSort.count)/$($allInCategory.count)"

        & {
            xml-header -vSection $_ -image $image.DownloadLink
            $dataFilterSort | ForEach-Object {
                $global:i++
                xml-body -data $_ -count $i -links $links
            }
            xml-footer
        } | out-file -encoding ascii "./tniv_$($_).xml"
    }

    $data.Category | Select-Object -Unique | write-debug

}


### End of File
