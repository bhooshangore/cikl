#!/bin/bash -x
set -e
source $TRAVIS_BUILD_DIR/travis/error_handler.sh
wget https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-1.2.4.deb 
sudo dpkg -i --force-confnew elasticsearch-1.2.4.deb
sudo service elasticsearch restart
sudo apt-get install libunbound2 unbound libxml2-dev
