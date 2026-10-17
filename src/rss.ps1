#######################################################################
#
#   FileName: rss.ps1
#
#   Purpose:
#       RSS XML generation for Bible Podcast feeds.
#       Defines templates and functions for creating iTunes-compatible
#       podcast RSS feeds from Bible listening plan data.
#
#######################################################################

# OpenDrive web base URLs for constructing download links
$webBaseURL="https://www.opendrive.com"

# RSS XML footer template - closes the RSS document
$rssFooter=@"

        <itunes:explicit>no</itunes:explicit>
    </channel>
</rss>
"@

# RSS XML header template - defines channel metadata
# Uses placeholders for dynamic values: {{webBaseURL}}, {{section}}, {{image}}
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
        <copyright>Audio Copyright &#169; Zondervan</copyright>
        <itunes:subtitle></itunes:subtitle>
        <itunes:author>Jared Church</itunes:author>
        <itunes:summary>Bible {{section}}</itunes:summary>
        <itunes:owner>
            <itunes:name>Jared Church</itunes:name>
            <itunes:email>pjaredchurch@gmail.com</itunes:email>
        </itunes:owner>
        <itunes:image href="{{image}}" />
"@
# Example of iTunes category hierarchy (currently commented out)
# <itunes:category text="Category1" />
# <itunes:category text="Category2">
#     <itunes:category text="Subcategory" />
# </itunes:category>

# RSS item template - represents a single podcast episode
# Placeholders: {{title}}, {{link}}, {{description}}, {{summary}},
#               {{size-bytes}}, {{guid}}, {{pubDate}}, {{keywords}}, {{duration}}
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



# Calculates the publication date for an RSS item based on day of year and seconds
# Uses the current year, starting from Jan 1, then adds the day offset and time in seconds
function get-publication-date() {
    param (
        $DayOfYear,
        $seconds
    )

    $date = ([datetime]::new(((get-date).Year),1,1).AddDays($DayOfYear -1).AddSeconds($seconds)).ToString("ddd, dd MMMM yyyy HH:mm:ss zzz")

    return $date
}

# Generates the XML header for an RSS feed
# Replaces placeholders with the category section name and podcast cover image URL
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


# Outputs the fixed RSS XML footer
function xml-footer () {
    write-output $rssFooter
}

# Generates a single RSS item entry from plan data and file information
# Matches the chapter name to find the corresponding media file details
function xml-Body () {
    param (
        $data,
        [Int]$count,
        $links
    )

    # Find the media file matching this chapter/verse
    $fileInfo = ($links | Where-Object Name -eq $data.Chapter)
    $fileInfo | format-table | out-string | write-debug

    # Replace all placeholders in the RSS item template with actual values
    $string=(
        "$($rssItem)" `
            -replace '{{title}}',$data.Chapter `
            -replace '{{link}}',$fileInfo.StreamingLink `
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



# Main function to generate RSS XML files
function generate-rss-xml() {
    param (
        $data
    )
    "generate-rss-xml: Start" | write-debug

    # Build the complete RSS XML
    xml-header -vSection $data.category -image $data.image.DownloadLink
    $data.plan | ForEach-Object {
        $global:i++
        xml-body -data $_ -count $i -links $data.links
    }
    xml-footer
}


### End of File
