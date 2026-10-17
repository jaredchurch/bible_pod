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

# Path appended to the base URL for the channel and self links. Separate from the
# host because the two backends serve the feeds from different places: OpenDrive
# from /bible_pod/rss, GitHub Pages from the Pages site. A script that
# dot-sources this file can override it after the fact.
$feedPath="/bible_pod/rss"

# RSS XML footer template - closes the RSS document
$rssFooter=@"

        <itunes:explicit>no</itunes:explicit>
    </channel>
</rss>
"@

# RSS XML header template - defines channel metadata
# Uses placeholders for dynamic values: {{webBaseURL}}, {{feedPath}}, {{feedFile}}, {{section}}, {{image}}
$rssHeader=@"
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
    <channel>

        <atom:link href="{{webBaseURL}}{{feedPath}}/{{feedFile}}" rel="self" type="application/rss+xml" />
        <title>Bible - Zondervan TNIV {{section}}</title>
        <link>{{webBaseURL}}{{feedPath}}/{{feedFile}}</link>
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



# Escapes a value for use in XML element text or an attribute value.
# Required for the enclosure and cover art URLs: an R2 pre-signed URL carries
# '&' between its query parameters, and a raw '&' is a fatal parse error that
# stops a feed rendering at all. OpenDrive links contained none, which is why
# this was not needed before.
function xml-escape() {
    param (
        $Text
    )

    return "$Text" `
        -replace '&','&amp;' `
        -replace '<','&lt;' `
        -replace '>','&gt;' `
        -replace '"','&quot;' `
        -replace "'",'&apos;'
}

# Fills a template placeholder. String.Replace rather than -replace, because
# -replace interprets '$' sequences in the replacement as substitution patterns
# and would corrupt any value that happens to contain one.
function xml-fill() {
    param (
        [string]$Template,
        [string]$Placeholder,
        $Value
    )

    return $Template.Replace($Placeholder, (xml-escape $Value))
}

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

# Selects the cover art for a category.
#
# The exact name is preferred because a wildcard match cannot tell categories
# apart: '*NT.jpg' also matches logo_WNT.jpg, so the feed ended up with two URLs
# in a single href, which podcast clients resolve as neither. Falls back to the
# wildcard for buckets that name their art differently.
function get-cover-art() {
    param (
        $Images,
        $Category
    )

    $exact=$Images | Where-Object Name -eq "logo_$($Category).jpg" | Select-Object -First 1
    if ( $exact ) {
        return $exact
    }

    $candidates=@($Images | Where-Object Name -like "*$($Category).jpg")
    if ( $candidates.Count -gt 1 ) {
        write-warning "More than one cover art matches '*$($Category).jpg' ($($candidates.Name -join ', ')); using the first"
    }

    return $candidates | Select-Object -First 1
}

# Name of the generated feed file for a section. Defined once because the file
# written by each script and the URL advertised in its channel have to agree.
function get-feed-filename() {
    param (
        $Section
    )

    return "tniv_$($Section).xml"
}

# Generates the XML header for an RSS feed
# Replaces placeholders with the category section name and podcast cover image URL
function xml-header() {
    param (
        $vSection,
        $image
    )

        $xml = "$($rssHeader)"
        $xml = xml-fill -Template $xml -Placeholder '{{webBaseURL}}' -Value $webBaseURL
        $xml = xml-fill -Template $xml -Placeholder '{{feedPath}}' -Value $feedPath
        $xml = xml-fill -Template $xml -Placeholder '{{feedFile}}' -Value (get-feed-filename $vSection)
        $xml = xml-fill -Template $xml -Placeholder '{{section}}' -Value $vSection
        $xml = xml-fill -Template $xml -Placeholder '{{image}}' -Value $image

        write-output $xml
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

    # Fill the template with actual values. The description is the one field
    # left unescaped: it is interpolated inside a CDATA section, where a raw
    # '&' or '<' is legal text, and escaping it would show the entities to
    # listeners instead. Only the CDATA terminator itself needs neutralising.
    $xml = "$($rssItem)"
    $xml = xml-fill -Template $xml -Placeholder '{{title}}' -Value $data.Chapter
    $xml = xml-fill -Template $xml -Placeholder '{{link}}' -Value $fileInfo.StreamingLink
    $xml = xml-fill -Template $xml -Placeholder '{{summary}}' -Value $data.Chapter
    $xml = xml-fill -Template $xml -Placeholder '{{size-bytes}}' -Value $fileInfo.Size
    $xml = xml-fill -Template $xml -Placeholder '{{guid}}' -Value "$((get-date).Year)-$($data.current)-$($data.Chapter)"
    $xml = xml-fill -Template $xml -Placeholder '{{pubDate}}' -Value (get-publication-date -DayOfYear $data.current -seconds $count)
    $xml = xml-fill -Template $xml -Placeholder '{{keywords}}' -Value $data.Chapter
    $xml = xml-fill -Template $xml -Placeholder '{{duration}}' -Value $data.'Length Seconds'
    $xml = $xml.Replace('{{description}}', "$($data.Chapter)".Replace(']]>', ']]]]><![CDATA[>'))

    write-output "$($xml)"

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
