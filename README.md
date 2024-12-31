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

## How To Run in Testing
* ```run.ps1 -noUpload``` will prevent results being written to opendrive.
* ```run.ps1 -DebugPreference Continue``` will give debug outputs
* ```n/a``` A way to get necessary files from opendrive once rather than on every run.
* ```n/a``` A way to fix a set date to run as.
