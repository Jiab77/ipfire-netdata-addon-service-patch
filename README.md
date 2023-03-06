# Netdata add-on service patch for IPFire <!-- omit from toc -->

Simple patch for adding Netdata add-on service to the IPFire web interface.

## Content <!-- omit from toc -->

* [Current version](#current-version)
* [Features](#features)
* [Installation](#installation)
* [Update](#update)
* [Uninstall](#uninstall)
* [Service](#service)
* [Roadmap](#roadmap)
* [Community](#community)
* [Thanks](#thanks)
* [Author](#author)

---

## Current version

The current version is __`0.1.0`__.

## Features

The installer script will allow you to do the following:

* Install / Update / Remove the add-on
* Add / Remove the patch on the __services__ page (__not implemented yet__)
* Test the Netdata service

## Installation

1. Install `git` with __Pakfire__
2. Clone the project and run the patch:

```console
# pakfire install -y git
# git clone https://github.com/Jiab77/ipfire-netdata-addon-service-patch.git
# cd ipfire-netdata-addon-service-patch
# ./install.sh -h
```

Once done, simply reload the page(s).

> You can remove `git` right after from __Pakfire__ once installed. `git` is just required for downloading and updating the project to get the latest versions.

## Update

```console
# cd ipfire-netdata-addon-service-patch
# ./install.sh -u
```

> You can also use `--update` if you prefer the long version.

## Uninstall

```console
# cd ipfire-netdata-addon-service-patch
# ./install.sh -r
```

> You can also use `--remove` if you prefer the long version.

## Service

The Netdata service will be added to the IPFire services page by injecting a custom line inside the `CGI` file.

Here is how it works:

* Install the patch

```console
# cd ipfire-netdata-addon-service-patch
# ./install.sh -s add
```

> You can also use `--service` if you prefer the long version.

* Remove the patch

```console
# cd ipfire-netdata-addon-service-patch
# ./install.sh -s remove
```

> You can also use `--service` if you prefer the long version.

* Test the service

```console
# cd ipfire-netdata-addon-service-patch
# ./install.sh -s test
```

> You can also use `--service` if you prefer the long version.

## Roadmap

* [X] Create initial version
* [X] Make the script better
* [ ] See if the _kickstart_ method can be supported

## Community

You can find the discussion around this project [here](https://community.ipfire.org/t/netdata-addon-by-ummeegge/5318).

## Thanks

Huge thanks to __siosios__ for his work on the Netdata package for IPFire!

## Author

* __Jiab77__