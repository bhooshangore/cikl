# -*- mode: ruby -*-
# vi: set ft=ruby :
 
# Load up our vagrant config files -- vagrantconfig.yaml, and then 
# vagrantconfig_local.yaml (if found)
CONF = lambda do
  require 'yaml'
  require 'pathname'
  my_dir = Pathname.new(__FILE__).expand_path.dirname
  configfile = my_dir.join("vagrantconfig.yaml")
  configfile_local = my_dir.join("vagrantconfig_local.yaml")
  config = YAML.load(configfile.read)
  config_local = YAML.load(configfile_local.read) rescue {}
  config.merge(config_local)
end.call()

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

# Vagrant 1.6.0 fixed issues with Ubuntu/debian's hostname setting properly
Vagrant.require_version ">= 1.6.0" 

require_relative 'vagrant/ubuntu_trusty'

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|

  use_nfs = (CONF['nfs'] == true) && !  Vagrant::Util::Platform.windows?

  synced_folder_opts = {
    :nfs => use_nfs,
    :create => true
  }

  path_cikl_worker  = "/vagrant/src/ruby/cikl-worker"
  path_cikl_api     = "/vagrant/src/ruby/cikl-api"
  path_threatinator = "/vagrant/src/ruby/threatinator"
  path_ui           = "/vagrant/ui"

  config.vm.synced_folder ".",                  '/vagrant', synced_folder_opts
#  config.vm.synced_folder './cikl-worker',   path_cikl_worker, synced_folder_opts
#  config.vm.synced_folder './cikl-api',      path_cikl_api, synced_folder_opts
#  config.vm.synced_folder './ui',       path_ui, synced_folder_opts

  puppet_facts = {
    :environment        => 'development',
    :path_cikl_worker   => path_cikl_worker,
    :path_cikl_api      => path_cikl_api,
    :path_threatinator  => path_threatinator,
    :path_ui            => path_ui
  }

  config.vm.define "cikl" do |cikl|
    # Every Vagrant virtual environment requires a box to build off of.
    cikl.vm.box = CONF['virtual_box_name']
    cikl.vm.hostname = "cikl.private"

    cikl.vm.network :private_network, 
      :ip      => CONF['eth1_ip_address'], 
      :netmask => CONF['eth1_netmask'],
      :adapter => 2, 
      :auto_config => true


    # Route using the bridged network so that our DNS resolver doesn't nuke 
    # the NAT tables. 
    if CONF['bridge_networking'] == true
      cikl.vm.network :public_network, :adapter => 3, :auto_config => true,
        :use_dhcp_assigned_default_route => true
    end

    cikl.vm.provider "virtualbox" do |v|
      v.customize ["modifyvm", :id, "--cpus", CONF['number_cpus']]
      v.customize ["modifyvm", :id, "--memory", CONF['memory_size']]
    end

    cikl.vm.network :forwarded_port, guest: 80, host: 8080 
    cikl.vm.network :forwarded_port, guest: 9200, host: 9200
    
    cikl.vm.provision :puppet do |puppet|
      puppet.manifests_path     = "puppet/manifests"
      puppet.manifest_file      = "default.pp"
      puppet.module_path        = ['puppet/private_modules', 'puppet/modules']
      puppet.hiera_config_path  = "puppet/hiera.yaml"
      puppet.working_directory  = "/vagrant/puppet"
      puppet.facter             = puppet_facts
      if (use_nfs == true) 
        puppet.synced_folder_type = 'nfs'
      end
    end
  end
end
