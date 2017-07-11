# FortiADC hook for `dehydrated`

This is a hook for the [Let's Encrypt](https://letsencrypt.org/) ACME client [dehydrated](https://github.com/lukas2511/dehydrated) (previously known as `letsencrypt.sh`) that allows you to use [Fortinet FortiADC](https://cloud.google.com/dns/docs/) records to respond to `dns-01` challenges.

Tested on FortiADC 5.8.0

## Requirements

```
$ sudo apt-get update
$ sudo apt-get install jq
```

## Installation

```
$ cd ~
$ git clone https://github.com/lukas2511/dehydrated
$ cd dehydrated
$ mkdir hooks
$ git clone https://github.com/lenoxys/dns-01-fortiadc hooks/dns-01-fortiadc
```

## Configuration

This hook uses the gcloud command-line tool and fascilitates the default project and account information. Check ```gcloud info``` to see, what this is set to. Also, your account needs to have "editor" permissions in the current project. This project needs to host your DNS zone for the domain (or a subdomain) you want to get a Let's Encrypt certificate for. Also, if you use the Google Cloud HTTPS load balancers, these have to be in the same project as well. Only required if you wish this hook to update the created certificates automatically. 

Also you need to change the following settings in your dehydrated config (original value commented out):
```
# Which challenge should be used? Currently http-01 and dns-01 are supported
#CHALLENGETYPE="http-01"
CHALLENGETYPE="dns-01"
``` 

If you use Google Cloud HTTPS load balancers, you need to align your setup of target proxies with how you create the certificates. All domains served by a target proxy have to be in the same certificate. If that is more than one, you cannot use the -d command line option of dehydrated. Instead you have to create a domains.txt file. The following example assumes you have two target proxies; one serving requests for example.com and www.example.com. And the second one serving wwwtest.example.com:

domains.txt
``` 
example.com www.example.com
wwwtest.example.com
``` 


## Usage

```
$ ./dehydrated -c -t dns-01 -k 'hooks/dns-01-fortiadc/hook.sh'
```

The ```-t dns-01``` part can be skipped, if you have set this challenge type in your config already. Same goes for the ```-k 'hooks/dns-01-fortiadc/hook.sh'``` part, when set in the config as well.

## More info

More hooks: https://github.com/lukas2511/dehydrated/wiki/Examples-for-DNS-01-hooks

Dehydrated: https://github.com/lukas2511/dehydrated
