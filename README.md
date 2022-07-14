# vagrant-zones
Vagrant Plugin which can be used to managed Bhyve, LX and native zones on illumos (OmniOSce)

This project is still in the early stages, any feedback is much appreciated

[![Gem Version](https://badge.fury.io/rb/vagrant-zones.svg)](https://badge.fury.io/rb/vagrant-zones)

- [Status](#status)
  - [Functions](../../wiki/Status#functions)
  - [Boxes](../../wiki/Status#Box-Support)
- [Examples](https://github.com/STARTCloud/vagrant-zones-examples)
- [Installation](#installation)
- [Known Issues](../../wiki/Known-Issues-and-Workarounds)
- [Development](../../wiki/Plugin-Development-Environment)
  - [Preparing OS environment](../../wiki/Plugin-Development-Environment#setup-os-for-development)
  - [Setup vagrant-zones environment](../../wiki/Plugin-Development-Environment#setup-vagrant-zones-environment)
- [Commands](../../wiki/Commands) 
  - [Create a box](../../wiki/Commands#create-a-box)
  - [Add the box](../../wiki/Commands#add-the-box)
  - [Run the box](../../wiki/Commands#run-the-box)
  - [SSH into the box](../../wiki/Commands#ssh-into-the-box)
  - [Shutdown the box and cleanup](../../wiki/Commands#shutdown-the-box-and-cleanup)
  - [Convert the Box](../../wiki/Commands#convert)
  - [Detect existing VMs](../../wiki/Commands#detect)
  - [Create, Manage, Destroy ZFS snapshots](../../wiki/Commands#zfs-snapshots)
  - [Clone and existing zone](../../wiki/Commands#clone)
  - [Safe restart/shutdown](../../wiki/Commands#safe-control)
  - [Start/Stop console](../../wiki/Commands#console)

## Installation

Publiched Package locations:
- [rubygems.org](https://rubygems.org/gems/vagrant-zones).
- [github.com](../../packages/963217)

### Setup OS Installation

  * ooce/library/libarchive
  * system/bhyve
  * system/bhyve/firmware
  * ooce/application/vagrant
  * ruby-26
  * zadm

### Setup vagrant-zones

 To install it in a standard vagrant environment:
 
 `vagrant plugin install vagrant-zones`

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/STARTcloud/vagrant-zones/issues

## License

This project is licensed under the AGPL v3 License - see the [LICENSE](LICENSE) file for details

## Built With
* [Vagrant](https://www.vagrantup.com/) - Portable Development Environment Suite.
* [bhyve](https://omnios.org/info/bhyve) - Hypervisor.
* [zadm](https://github.com/omniosorg/zadm) -  Bhyve Management tool

## Contributing Sources and References
* [vagrant-bhyve](https://github.com/jesa7955/vagrant-bhyve) - A Vagrant plugin for FreeBSD to spin up Bhyve Guests.
* [vagrant-zone](https://github.com/skylime/vagrant-zone) - A Vagrant plugin to spin up LXZones.


## Contributing

Please read [CONTRIBUTING.md](https://www.prominic.net) for details on our code of conduct, and the process for submitting pull requests to us.

## Authors
* **Thomas Merkel** - *Initial work* - [Skylime](https://github.com/skylime)
* **Mark Gilbert** - *Takeover* - [Makr91](https://github.com/Makr91)

See also the list of [contributors](../../graphs/contributors) who participated in this project.

## Acknowledgments

* Hat tip to anyone whose code was used
