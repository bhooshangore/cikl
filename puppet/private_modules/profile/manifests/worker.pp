class profile::worker (
  $root          = '/opt/worker',
  $user          = 'cikl_worker',
  $group         = 'cikl_worker',
  $rabbitmq_host = 'localhost',
  $rabbitmq_port = 5672,
  $rabbitmq_username = 'guest',
  $rabbitmq_password = 'guest',
  $rabbitmq_vhost = '/',
) inherits profile::base {
  $gems = "$root/gems"

  ensure_packages(['bundler', 'libunbound2'])

  file { $root: 
    ensure => "directory"
  } ->
  exec { 'profile::worker::install':
    cwd         => $root,
    command     => "/usr/bin/bundle install --path=${$gems} --gemfile=/vagrant/cikl-worker/Gemfile",
    require => [
      Package['libunbound2', 'bundler']
    ],
    unless => '/usr/bin/bundle check --gemfile=/vagrant/cikl-worker/Gemfile'
  }


  group { 'profile::worker::group':
    name => $group,
    ensure => 'present'
  } ->
  user { 'profile::worker::user':
    name    => $user,
    ensure  => 'present',
    gid     => $group,
    shell   => '/usr/sbin/nologin'
  }

  file { 'profile::worker::config': 
    path    => "/etc/cikl-dns-worker.yaml",
    owner   => "root",
    group   => "root",
    mode    => '0644',
    content => template('profile/worker/cikl-dns-worker.yaml.erb')
  }

  file { 'profile::worker::upstart': 
    path    => "/etc/init/cikl-dns-worker.conf",
    owner   => "root",
    group   => "root",
    mode    => '0644',
    content => template('profile/worker/cikl-dns-worker-upstart.conf.erb'),
    require => [
      User['profile::worker::user'],
      Group['profile::worker::group']
    ]
  }

  service { 'cikl_worker::service': 
    name       => 'cikl-dns-worker',
    ensure     => 'running',
    provider   => 'upstart',
    hasstatus  => true,
    hasrestart => true,
    pattern    => 'dns_worker',
    subscribe  => [
      File['profile::worker::upstart', 'profile::worker::config']
    ]
  }

}

