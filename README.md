# Cloudflare as a Dynamic DNS Provider

## Introduction
If you run a server from your home network, or perhaps simply want to access your home computer when you are away from home, one challenge is determining what your IP address is as most domestic internet connections have a dynamic IP address that changes from time to time. To get over this issue you will need to use a Dynamic DNS provider.

I use Cloudflare as my DNS provider but I was unable to find any dynamic DNS client that supported the new V4 API, and some of the scripts I found on GitHub did not contain enough error checking for my liking. I therefore decided to build upon their concepts and create my own script which is currently running on ac[Raspberry Pi](https://www.raspberrypi.org/) running [Raspbian](https://www.raspbian.org/) and also on server that is running [Ubuntu](https://ubuntu.com/server). This script should also be able to run on most Linux systems as long as the pre-requisites are met.

## Prerequisites

This script makes use of a couple of tools that are not necessarily installed by default on your computer. 

- [jq](https://stedolan.github.io/jq/) - A lightweight and flexible command-line JSON processor.
- [dig](https://www.commandlinux.com/man-page/man1/dig.1.html) - A DNS lookup utility.

On Debian/Ubuntu you should be able to install these as follows:

```shell
sudo apt install jq dnsutils
```
## Installation

The easiest way to install this script is by cloning the git repository. From the directory you wish to install the cloudflare-ddns script, simply run:

```shell
git clone https://github.com/paulgit/cloudflare-ddns.git .
```
This will clone the repository into the current directory.

The next step is to create a configuration file. The configuration file **must** be called ```cloudflare-ddns.conf``` and be created in the same directory as the script. It's contents should be as follows. Don't forget to update the values with those applicable to you. If you are not sure how to get these values then this [this article](https://letswp.io/cloudflare-as-dynamic-dns-raspberry-pi/) will show you what to do.

```shell
# Update these with your values
AUTH_EMAIL="YOUR_CLOUDFLARE_AUTH_EMAIL" 
AUTH_KEY="YOUR_CLOUDFLARE_AUTH_KEY"
ZONE_NAME="example.com" 
RECORD_NAME="site.example.com"

# This can be any IP checking site that returns the IP as plain text
IP_CHECK_URL="http://ipv4.icanhazip.com" 

```
You can either create this file manually using your favourite text editor or have the script create a template for you by running the script without a configuration file in the script directory.
``` shell
./cloudflare-ddns.conf
```

## Running the Script
Once you have created your configuration file you can run the script. On first execution it must obtain a Zone and Record Identifier from Cloudflare. If your credentials are correct then this should just work, if not then an error will be displayed.

Once the identifiers have been obtained. The current IP address for your record is looked up directly using the 1.1.1.1 Cloudflare DNS server. If this differs from the detected external IP address then the DNS record will be updated and a message output as follows:

```shell
[Fri 01 May 2020 02:29:54 PM CEST] IP of site.example.com has been changed to x.x.x.x (was y.y.y.y)
```

## Running the Script From CRON
You will most likely want to run this script periodically from a cron job, an example cron task to check every 5 minutes is as follows:

```shell
*/5 * * * * /bin/bash /path_to_script/cloudflare-ddns.sh
```
