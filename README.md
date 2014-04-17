# Cikl
Cikl is a cyber threat intelligence management system. It is a fork of the [Collective Intelligence Framework (CIF)](https://code.google.com/p/collective-intelligence-framework/), which aims for the same goal. The primary goals of this (currently experimental) fork is to improve speed, scalability, functionality, and ease of installation. 

The codebase will be evolved over time from Perl to Ruby (likely with an emphasis on JRuby). In the meantime, the project will likely consist of some hybrid of the two languages until we stabilize features. 

## Documentation
Currently? We haven't got much in the way of documentation. Please accept my appologies.

## Setting up the development environment

- Install [VirtualBox](https://www.virtualbox.org/wiki/Downloads)
- Install [Vagrant](http://www.vagrantup.com/downloads.html)
- Clone and start up the Vagrant VM:
```
git clone https://github.com/cikl/cikl.git
cd cikl
git submodule update --init
vagrant up
```
- Open up http://localhost:8080/
- When you're done playing around, shutdown the VM:
```vagrant halt```

## Roadmap
You can find our roadmap [here](https://github.com/cikl/cikl/wiki/Roadmap).

## Issues and Pull Requests

All issues are managed within the primary repository: [cikl/cikl/issues](https://github.com/cikl/cikl/issues). Pull requests should be sent to their respective reposirotires, referencing some issue within the main project repository.

## Repositories

Cikl consists of many different sub-projects. The main ones are:

### p5-Cikl
[cikl/p5-Cikl](https://github.com/cikl/p5-Cikl) - the current core of Cikl. This began as a fork of https://github.com/collectiveintel/cif-v1 and has evolved quite a bit over time. The code is available on CPAN as Cikl. 

