# Bible Podcast
Handle podcast feed for bible listening

## Process
Script will collect info on plan and media from open drive, write xml for rss feed and then return that to open drive.
Podcast connection is to rss xml stored in opendrive and collects all media from there.

## Data Storage
All the data for this is stored in OpenDrive.
github stores the script and will execute daily on runner.

## Subscription
Uses redirhub.com as a URL redirection service that allow a nice URL to point at the opendrive xml files for podcast subscription. Also means that if the file link on opendrive has to change then redirhub.com link can be repointed to the new opendrive location.
